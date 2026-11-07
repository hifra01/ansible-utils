# Feature Specification: Percona Server for MongoDB Role (`percona_mongodb`)

**Feature Branch**: `003-percona-mongodb-role`

**Created**: 2026-11-04

**Status**: Draft

**Input**: User description: "create ansible role to install percona mongodb with the ability to create replica set even with only 1 instance"

## Clarifications

### Session 2026-11-04

- Q: What default values should the role use for `percona_mongodb_bind_ip` and `percona_mongodb_replset_advertise_host` when not explicitly overridden? (FR-003) → A: Default `percona_mongodb_bind_ip` to `"0.0.0.0"` and `percona_mongodb_replset_advertise_host` to `"{{ ansible_default_ipv4.address | default('127.0.0.1') }}"`.
- Q: How should the role handle an empty `percona_mongodb_keyfile_content` when both replica set mode and authentication are enabled? (FR-003, FR-007) → A: Auto-generate a keyfile on the host for single-instance replica sets when empty, and fail fast during validation if `percona_mongodb_keyfile_content` is empty when more than 1 member is defined in `percona_mongodb_replset_members`.
- Q: Where should admin user bootstrap and `percona_mongodb_users` provisioning run when replica set mode is enabled? (FR-007, FR-008) → A: Execute admin user bootstrap and `percona_mongodb_users` management only on the replica set initializer node (`percona_mongodb_replset_init: true`) or in standalone mode (`percona_mongodb_replset_enabled: false`), relying on MongoDB replica set replication to propagate user documents to secondary nodes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Percona Server for MongoDB with Single-Instance Replica Set (Priority: P1)

Infrastructure operators and application teams need to install Percona Server for MongoDB on a single target Linux host and automatically initialize a single-node replica set so that MongoDB features requiring an oplog (such as multi-document ACID transactions, change streams, and oplog-based backups) work immediately without requiring a multi-server cluster.

**Why this priority**: Installing Percona Server for MongoDB and initializing a functional replica set (including on a single instance) is the core capability requested by the user and the prerequisite for modern MongoDB application workloads.

**Independent Test**: Can be fully tested by provisioning a single Linux host with default replica set settings enabled, verifying that the MongoDB service is enabled and active, and confirming that the replica set is initialized with the single instance elected as `PRIMARY` and capable of executing multi-document transactions.

**Acceptance Scenarios**:

1. **Given** a clean supported Linux host (Debian/Ubuntu or RHEL/Rocky/AlmaLinux), **When** the operator applies the role with replica set mode enabled and no multi-node member list specified (single-instance mode), **Then** Percona Server for MongoDB is installed from the official Percona repository, configured with the target replica set name, enabled at boot, started, and automatically initialized as a single-node replica set whose sole member reaches `PRIMARY` state.
2. **Given** a clean supported Linux host, **When** the operator applies the role with replica set mode explicitly disabled (`percona_mongodb_replset_enabled: false`), **Then** Percona Server for MongoDB is installed, configured, and started as a standalone database instance without replica set initialization.
3. **Given** an already provisioned single-instance Percona MongoDB replica set host, **When** the operator re-runs the role with identical variables, **Then** no configuration files are rewritten, the replica set is not re-initialized, no service restarts occur, and the run completes with zero changes.

---

### User Story 2 - Initialize or Reconfigure a Multi-Instance Replica Set (Priority: P2)

Infrastructure operators deploying high-availability environments need to declare an explicit list of replica set members across multiple Percona Server for MongoDB hosts (or expand an existing single-instance replica set into a multi-node topology) and designate an initializer host to configure membership, priorities, or arbiter roles.

**Why this priority**: Once single-node replica sets are supported, operators need a declarative path to form multi-node replica sets for production high availability and automatic failover using the same role interface.

**Independent Test**: Can be independently tested by provisioning multiple Percona MongoDB instances (or reconfiguring a single-node instance with member options such as priority or custom host:port), converging the role with `percona_mongodb_replset_members` defined on the initializer node, and verifying that the replica set configuration reflects the declared members and priorities.

**Acceptance Scenarios**:

1. **Given** one or more Percona MongoDB hosts configured with the same `percona_mongodb_replset_name` and shared keyfile authentication, **When** the role is applied with a list of members in `percona_mongodb_replset_members` and `percona_mongodb_replset_init: true` on the designated primary/initializer node, **Then** the replica set is initialized (or reconfigured if already initialized) to match the declared member list and member attributes (`host`, `priority`, `arbiterOnly`, `hidden`, `votes`).
2. **Given** a secondary member node where `percona_mongodb_replset_init` is `false`, **When** the role is applied, **Then** the node starts with the replica set name and shared keyfile configured and waits to be joined by the initializer node without attempting competing `rs.initiate()` calls or user provisioning tasks.

---

### User Story 3 - Manage Authentication, Users, and Custom Server Configuration (Priority: P3)

Infrastructure operators need to secure Percona Server for MongoDB with access control (`security.authorization: enabled` and replica set `security.keyFile`), bootstrap an administrative user account, declaratively provision application database users with scoped roles, and customize storage, networking, and oplog parameters.

**Why this priority**: Production and staging MongoDB deployments require authenticated access, least-privilege application credentials, and tunable resource limits (`bindIp`, `port`, WiredTiger cache size, oplog size) without manual shell intervention.

**Independent Test**: Can be tested by applying the role with access control enabled, custom `percona_mongodb_users` entries, and custom server tuning parameters, then verifying that unauthenticated queries are rejected, the admin and application users can authenticate against their assigned databases and roles, and the active server configuration reflects the custom parameters.

**Acceptance Scenarios**:

1. **Given** `percona_mongodb_auth_enabled: true` and configured admin credentials (`percona_mongodb_admin_user` and `percona_mongodb_admin_password`), **When** the role converges on a replica set initializer (`percona_mongodb_replset_init: true`) or standalone node, **Then** the administrative user is created, access control and keyfile security (when replica set is enabled) are enforced, and unauthenticated database commands are denied.
2. **Given** one or more user definitions in `percona_mongodb_users` on a replica set initializer (`percona_mongodb_replset_init: true`) or standalone node, **When** the role is applied, **Then** each user account is created or updated in its target database with the declared roles and password, or removed when `state: "absent"`.
3. **Given** custom server settings (such as `percona_mongodb_bind_ip`, `percona_mongodb_port`, `percona_mongodb_wiredtiger_cache_size_gb`, `percona_mongodb_oplog_size_mb`, or `percona_mongodb_extra_config`), **When** the role is applied, **Then** the configuration file reflects those settings and the running instance applies them cleanly.

---

### Edge Cases

- **Unsupported operating system family**: When executed against an OS family outside `Debian` and `RedHat`, the role fails immediately with a clear, descriptive assertion message before modifying packages or files.
- **Single-node replica set hostname resolution and bind address**: When initializing a single-instance replica set where `percona_mongodb_replset_members` is empty, `percona_mongodb_bind_ip` defaults to `"0.0.0.0"` and the member host address defaults to `{{ percona_mongodb_replset_advertise_host }}:{{ percona_mongodb_port }}` (where `percona_mongodb_replset_advertise_host` defaults to `"{{ ansible_default_ipv4.address | default('127.0.0.1') }}"`) so `rs.initiate()` succeeds immediately without DNS lookup failures in containers or single-server setups.
- **Transition from unauthenticated bootstrap to enforced authorization**: On a fresh installation with `percona_mongodb_auth_enabled: true` and `percona_mongodb_replset_enabled: true`, the role handles the initial replica set initialization (`rs.initiate()`), waits for the node to become `PRIMARY`, creates the root administrative user, and ensures `security.authorization: enabled` and `security.keyFile` are active without deadlocking between replica set state and authentication enforcement.
- **Keyfile permissions, single-node auto-generation, and multi-node validation**: MongoDB refuses to start if a configured `keyFile` has overly permissive file modes or is missing. When replica set mode and authentication are enabled, if `percona_mongodb_replset_members` contains more than 1 member and `percona_mongodb_keyfile_content` is empty, the role fails fast during input validation so nodes do not generate mismatched keyfiles; for single-instance replica sets (`percona_mongodb_replset_members` empty or 1 member), the role uses `percona_mongodb_keyfile_content` if provided or auto-generates a keyfile on the host if absent, always enforcing mode `'0400'` owned by the OS-specific MongoDB service user/group.
- **Replica set member host or priority changes on subsequent runs**: When an operator updates `percona_mongodb_replset_members` on an already initialized replica set, the role compares the current replica set configuration (`rs.conf()`) with the desired members and executes `rs.reconfig()` (using `{force: true}` only when necessary or when no primary is currently elected) only when a difference exists.
- **Invalid configuration or variable inputs**: If an operator supplies an invalid port number, empty admin password when `percona_mongodb_auth_enabled: true`, or invalid replica set name when `percona_mongodb_replset_enabled: true`, the role fails fast during input validation with an actionable error message.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The role MUST validate that the target host belongs to a supported OS family (`Debian` or `RedHat`) at the beginning of execution and fail immediately with a descriptive message on unsupported platforms.
- **FR-002**: The role MUST configure the official Percona package repository (via the `percona-release` repository package and `percona-release enable` / `setup` for the configured Percona Server for MongoDB release series, defaulting to `"8.0"` / `psmdb-80`) and install Percona Server for MongoDB server, shell (`mongosh`), and client packages on Debian-family and RedHat-family systems.
- **FR-003**: The role MUST provide user-tunable, `percona_mongodb_`-prefixed variables in `defaults/main.yml` for core server, storage, networking, security, and replica set configuration, including at minimum:
  - `percona_mongodb_version` (Percona Server for MongoDB series, default `"8.0"` mapped to `psmdb-80`)
  - `percona_mongodb_bind_ip` (comma-separated bind IPs or `"0.0.0.0"`, default `"0.0.0.0"`)
  - `percona_mongodb_port` (listening TCP port, default `27017`)
  - `percona_mongodb_wiredtiger_cache_size_gb` (optional WiredTiger cache size in GB, default `null` / omitted)
  - `percona_mongodb_extra_config` (optional dictionary of extra settings merged into `mongod.conf`, default `{}`)
  - `percona_mongodb_replset_enabled` (boolean enabling replica set mode, default `true`)
  - `percona_mongodb_replset_name` (replica set name, default `"rs0"`)
  - `percona_mongodb_replset_init` (boolean controlling whether this host initializes/reconfigures the replica set and provisions users, default `true`)
  - `percona_mongodb_replset_advertise_host` (host/IP used for the local node when `percona_mongodb_replset_members` is empty in single-instance replica set mode, default `"{{ ansible_default_ipv4.address | default('127.0.0.1') }}"`)
  - `percona_mongodb_replset_members` (optional list of replica set members; when empty `[]`, defaults to a single-instance replica set containing `{{ percona_mongodb_replset_advertise_host }}:{{ percona_mongodb_port }}`)
  - `percona_mongodb_oplog_size_mb` (optional integer oplog size in MB, default `null` / omitted)
  - `percona_mongodb_auth_enabled` (boolean enabling MongoDB access control, default `true`)
  - `percona_mongodb_keyfile_path` (path to the replica set internal authentication keyfile, default `"/etc/mongod.keyfile"`)
  - `percona_mongodb_keyfile_content` (optional base64 keyfile string shared across multi-node replica set members; auto-generated on the host if empty in single-instance mode, and required when `percona_mongodb_replset_members` has more than 1 member, default `""`)
  - `percona_mongodb_admin_user` (administrative username in the `admin` database, default `"admin"`)
  - `percona_mongodb_admin_password` (administrative password, default `"changeme_admin_password"`)
  - `percona_mongodb_users` (list of application user dictionaries supporting `name`, `password`, optional `database` default `"admin"`, `roles` list, and optional `state` default `"present"`, default `[]`)
- **FR-004**: Isolate OS-specific package names, service name (`mongod`), service user/group (`mongod:mongod` across Percona DEB and RPM packages), configuration file path (`/etc/mongod.conf`), default `dbPath` (`/var/lib/mongodb` on Debian-family, `/var/lib/mongo` on RedHat-family), and log path in `vars/Debian.yml` and `vars/RedHat.yml`.
- **FR-005**: When `percona_mongodb_replset_enabled` is `true` and `percona_mongodb_replset_init` is `true`, the role MUST support initializing a **single-instance replica set** out of the box (when `percona_mongodb_replset_members` is empty or has 1 member) as well as a **multi-instance replica set** (when `percona_mongodb_replset_members` defines multiple hosts), waiting until the replica set elects a `PRIMARY` node.
- **FR-006**: When `percona_mongodb_replset_enabled` is `true` and the replica set is already initialized, the role MUST inspect the current replica set configuration (`rs.conf()`) and only execute `rs.reconfig()` if the configured member list or member attributes (`host`, `priority`, `arbiterOnly`, `hidden`, `votes`) differ from the desired state, maintaining zero changes when unchanged.
- **FR-007**: When `percona_mongodb_auth_enabled` is `true`, the role MUST validate that `percona_mongodb_keyfile_content` is non-empty whenever `percona_mongodb_replset_enabled` is `true` and `percona_mongodb_replset_members` has more than 1 member, ensure a valid replica set keyfile is present at `percona_mongodb_keyfile_path` with mode `'0400'` (auto-generating one on the host if empty in single-instance mode), bootstrap the administrative user (`percona_mongodb_admin_user`) in the `admin` database with root administrative privileges when `percona_mongodb_replset_init: true` or `percona_mongodb_replset_enabled: false`, and enforce `security.authorization: enabled`.
- **FR-008**: The role MUST provision, update, or remove database user accounts declared in `percona_mongodb_users` only when `percona_mongodb_replset_init: true` (in replica set mode) or `percona_mongodb_replset_enabled: false` (in standalone mode) idempotently using `mongosh` without requiring external Python MongoDB drivers (`pymongo`) on the target host.
- **FR-009**: When `percona_mongodb_replset_enabled` is `false`, the role MUST omit the `replication` section (and `security.keyFile`) from `/etc/mongod.conf` so the instance runs in standalone mode.
- **FR-010**: All tasks in the role MUST be strictly idempotent, producing zero changes on a second consecutive run with unchanged variables across all supported distributions.

### Key Entities

- **Percona MongoDB Instance**: Represents the `mongod` server daemon managed on a target host. Key attributes include release series (default `8.0` / `psmdb-80`), network binding (`bindIp`, `port`), storage path (`dbPath`), WiredTiger cache limit, access control state, and replica set membership mode.
- **Replica Set Topology**: Represents the MongoDB replica set (`replSetName`, `oplogSizeMB`, and `members`). Supports single-instance topologies (1 member elected immediately as `PRIMARY`) and multi-instance topologies (multiple members with configurable `host`, `priority`, `arbiterOnly`, `hidden`, and `votes`).
- **Security Keyfile**: Represents the shared secret file (`security.keyFile`) used for internal authentication between replica set members when access control (`security.authorization: enabled`) is active; auto-generated on the host for single-instance replica sets when `percona_mongodb_keyfile_content` is empty and required explicitly when multiple replica set members are configured.
- **Managed MongoDB User (`percona_mongodb_users` item)**: Represents an application database user account managed by the role on the initializer or standalone node (and replicated across the replica set), with attributes `name`, `password`, target `database`, assigned `roles`, and `state` (`present` or `absent`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy Percona Server for MongoDB with a single-instance replica set enabled across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in a single playbook execution, with the service active and the single node reporting replica set state `PRIMARY` (`myState: 1`) within 60 seconds.
- **SC-002**: A single-instance replica set deployed by the role successfully executes replica-set-dependent operations (such as oplog inspection and multi-document sessions/writes) immediately after role convergence.
- **SC-003**: When authentication is enabled (`percona_mongodb_auth_enabled: true`), 100% of unauthenticated data/admin commands are rejected, while the configured admin user and 100% of present users in `percona_mongodb_users` can authenticate and perform operations permitted by their assigned roles.
- **SC-004**: Re-running the role on an already converged host with identical variables produces 0 changed tasks across all 5 supported Linux distributions.
- **SC-005**: Any invalid input variable (such as an unsupported OS family, invalid port, missing admin password when authentication is enabled, or missing `percona_mongodb_keyfile_content` in a multi-node authenticated replica set) is caught by pre-flight assertions before modifying system state.

## Assumptions

- Target hosts run `systemd` on Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) or RedHat-family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL) distributions on 64-bit (`x86_64` / `aarch64`) hardware and have outbound internet access to `repo.percona.com`.
- The role name is `percona_mongodb` (residing under `roles/percona_mongodb/` with all variables prefixed `percona_mongodb_`) to match `percona_mysql` and collection naming conventions.
- Percona Server for MongoDB `8.0` (`psmdb-80`) is used as the default release series, while allowing operators to override `percona_mongodb_version` (e.g., `"7.0"` / `"psmdb-70"` or `"6.0"` / `"psmdb-60"`).
- Default network binding (`percona_mongodb_bind_ip`) is `"0.0.0.0"` and `percona_mongodb_replset_advertise_host` defaults to `"{{ ansible_default_ipv4.address | default('127.0.0.1') }}"` to match the `consul` and `percona_mysql` roles in this collection and allow single-instance or multi-instance replica set communication out of the box.
- Replica set mode (`percona_mongodb_replset_enabled`) is enabled by default (`true`) with `percona_mongodb_replset_name: "rs0"` and `percona_mongodb_replset_members: []` so that a single-instance replica set works out of the box with zero extra configuration, while still allowing standalone mode (`percona_mongodb_replset_enabled: false`) or multi-node replica sets (`percona_mongodb_replset_members` populated with multiple hosts).
- All MongoDB administrative operations (replica set status check, `rs.initiate()`, `rs.reconfig()`, admin user bootstrap, and application user management) are executed idempotently via the native `mongosh` CLI installed by Percona Server for MongoDB, avoiding any target-host Python driver (`pymongo`) or external Ansible collection dependencies.
- Sharded cluster components (`mongos`, config server replica sets) and TLS certificate generation are out of scope for this role, though custom TLS or audit parameters can be passed through `percona_mongodb_extra_config`.
