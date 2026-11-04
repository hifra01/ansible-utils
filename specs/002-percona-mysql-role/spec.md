# Feature Specification: Percona Server for MySQL Role (`percona_mysql`)

**Feature Branch**: `hifra01/feat-percona-mysql-role`

**Created**: 2026-10-30

**Status**: Draft

**Input**: User description: "ansible role to install and manage percona mysql, can run as master or replica"

## Clarifications

### Session 2026-10-30

- Q: What default Percona Server for MySQL version series should the role install when `percona_mysql_version` is not explicitly overridden? (FR-002, FR-005) → A: Default to Percona Server for MySQL 8.4 LTS (`"ps-84-lts"` / `8.4`).
- Q: How should the role manage the main MySQL configuration file versus the default configuration files installed by the Percona Server package? (FR-005, FR-009) → A: Render a dedicated drop-in config file (`99-percona-managed.cnf` in the OS config include directory: `/etc/mysql/conf.d/` on Debian and `/etc/my.cnf.d/` on RedHat, ensuring `!includedir` is present) that overrides package defaults cleanly.
- Q: How should the role execute local MySQL administrative operations (securing root, managing databases and users, and configuring replication)? (FR-004, FR-006, FR-007, FR-008) → A: Use the native `mysql` CLI binary (authenticated via `/root/.my.cnf`) with idempotent SQL checks, avoiding external collection (`community.mysql`) or target-host Python MySQL driver dependencies.
- Q: How should the Molecule `default` scenario test both `master` and `replica` modes across the CI distro matrix? (SC-001, SC-002) → A: Provision a two-container Molecule scenario (`mysql-master` + `mysql-replica`) using the same `${MOLECULE_DISTRO}` image to verify live end-to-end GTID replication.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install and Manage Percona Server for MySQL as a Primary (Master) Node (Priority: P1)

Infrastructure operators need to install Percona Server for MySQL on supported Linux hosts, secure the initial root account, apply deterministic server and replication parameters (`server-id`, binary logging, GTID mode), and run the node as an active writable primary (`master`) database server.

**Why this priority**: Installing the database engine, securing root access, and running a writable primary instance with binary logging enabled is the foundational capability required for both standalone database deployments and the source side of any replication topology.

**Independent Test**: Can be fully tested by provisioning a single Linux host with `percona_mysql_role: "master"`, verifying that the MySQL service is enabled and running, confirming passwordless local admin access via `/root/.my.cnf`, verifying that `read_only` is disabled (`OFF`), and checking that `server_id`, `gtid_mode`, and binary logging are active.

**Acceptance Scenarios**:

1. **Given** a clean supported Linux host (Debian/Ubuntu or RHEL/Rocky/AlmaLinux), **When** the operator provisions the host with `percona_mysql_role: "master"` (the default), **Then** the official Percona repository is configured for Percona Server 8.4 LTS (by default), Percona Server for MySQL is installed, the service is enabled and running, root credentials are secured, `read_only` and `super_read_only` are set to `OFF`, and binary logging with GTID is active.
2. **Given** a primary node with a defined replication user (`percona_mysql_replication_user`), **When** the role converges, **Then** the replication user account exists with the `REPLICATION SLAVE` privilege so replica nodes can authenticate and stream binary logs.
3. **Given** an already provisioned Percona MySQL host, **When** the operator re-runs the role with identical variables, **Then** no configuration files or user grants are modified, no service restarts occur, and the run completes with zero changes.

---

### User Story 2 - Configure Percona Server for MySQL as a Replica Node (Priority: P2)

Infrastructure operators need to designate a Percona Server for MySQL host as a `replica` node that enforces read-only protection against accidental application writes and connects to a designated primary (`master`) host to replicate changes automatically.

**Why this priority**: Running a node as a read-only replica connected to a primary server is the core high-availability and read-scaling capability requested alongside primary node deployment.

**Independent Test**: Can be independently tested in a two-node Molecule topology (`mysql-master` and `mysql-replica`) by provisioning the second host with `percona_mysql_role: "replica"`, verifying that `read_only` and `super_read_only` are enabled (`ON`), and confirming that the replica connects to `mysql-master` with GTID auto-positioning (`Replica_IO_Running: Yes`, `Replica_SQL_Running: Yes`) and replicates data written on the primary node.

**Acceptance Scenarios**:

1. **Given** a supported Linux host configured with `percona_mysql_role: "replica"` and a unique `percona_mysql_server_id`, **When** the role is applied, **Then** the server configuration enforces `read_only = ON` and `super_read_only = ON`, and the MySQL service runs cleanly in replica mode.
2. **Given** a replica node provided with primary connection parameters (`percona_mysql_source_host`, `percona_mysql_source_port`, `percona_mysql_replication_user`, `percona_mysql_replication_password`), **When** the role converges, **Then** the replica is configured to replicate from the specified source host using GTID auto-positioning (`SOURCE_AUTO_POSITION = 1`) and starts replication (when `percona_mysql_replica_start_replication` is enabled).
3. **Given** a replica node where `percona_mysql_source_host` is left empty (e.g., during pre-provisioning or standalone staging), **When** the role is applied, **Then** the node is configured with replica read-only settings and a unique `server-id` without failing on missing source connection execution.

---

### User Story 3 - Manage Application Databases, Users, and Custom Server Tuning (Priority: P3)

Infrastructure operators need to declaratively provision application databases, create MySQL user accounts with host-scoped privileges, and customize core InnoDB/network tuning parameters (`bind-address`, `port`, `innodb_buffer_pool_size`, `max_connections`, and extra options) through role variables.

**Why this priority**: Once the primary or replica database daemon is running, operators need a repeatable way to create application schemas, credentials, and performance settings without manual SQL intervention.

**Independent Test**: Can be tested by defining `percona_mysql_databases`, `percona_mysql_users`, and custom tuning parameters in role variables, converging the role, and querying the MySQL server to confirm the schemas exist with expected character sets/collations, users can authenticate with their assigned grants, and global server variables match the configured tuning values.

**Acceptance Scenarios**:

1. **Given** a primary Percona MySQL host with entries in `percona_mysql_databases` and `percona_mysql_users`, **When** the role is applied, **Then** each specified database is created with its configured character set and collation, and each user is created with the specified password, host scope, and privilege grants.
2. **Given** custom server tuning variables (such as `percona_mysql_port`, `percona_mysql_bind_address`, `percona_mysql_innodb_buffer_pool_size`, `percona_mysql_max_connections`, or `percona_mysql_extra_mysqld_config`), **When** the role is applied, **Then** the managed configuration file reflects those settings and the running MySQL instance applies them after a configuration-validated service restart.

---

### Edge Cases

- **Unsupported operating system family**: When executed against an OS family outside `Debian` and `RedHat`, the role fails immediately with a clear assertion message before modifying packages or files.
- **Invalid operational role or `server_id`**: When `percona_mysql_role` is set to a value other than `"master"` or `"replica"`, or when `percona_mysql_server_id` is not a positive integer (`>= 1`), the role fails fast during input validation.
- **Missing replication credentials when configuring a live replica**: When `percona_mysql_role` is `"replica"` and `percona_mysql_source_host` is non-empty, if `percona_mysql_replication_user` or `percona_mysql_replication_password` is missing, the role fails fast during validation with an actionable error message.
- **First-run root authentication vs. subsequent runs**: On fresh installations on RedHat-family systems (where Percona generates a temporary root password in `/var/log/mysqld.log`) or Debian-family systems (where local socket auth is initially active), the role cleanly transitions the root account to the configured `percona_mysql_root_password` and writes `/root/.my.cnf` (`mode: '0600'`) so subsequent runs authenticate idempotently without errors.
- **Invalid configuration syntax before restart**: If user-supplied parameters in `percona_mysql_extra_mysqld_config` produce invalid `mysqld` syntax, `mysqld --validate-config` catches the error before restarting the active MySQL service.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The role MUST validate that the target host belongs to a supported OS family (`Debian` or `RedHat`) and fail immediately with a descriptive message on unsupported platforms.
- **FR-002**: The role MUST configure the official Percona repository (via `percona-release` package and `percona-release setup` for the configured Percona Server series, defaulting to `8.4` / `"ps-84-lts"`) and install Percona Server for MySQL server and client packages on supported Debian-family and RedHat-family distributions.
- **FR-003**: The role MUST allow operators to select the node operational role via `percona_mysql_role` (`"master"` or `"replica"`, defaulting to `"master"`), and validate that only these two values are accepted.
- **FR-004**: The role MUST secure the local MySQL `root` user password using `percona_mysql_root_password`, deploy `/root/.my.cnf` with permissions `'0600'` for passwordless local administrative CLI and task execution, and optionally remove anonymous users and the default `test` database when `percona_mysql_secure_installation` (default `true`) is enabled, executing all SQL administrative operations via the native `mysql` CLI binary with idempotent SQL checks (without requiring `community.mysql` or target-host Python MySQL drivers).
- **FR-005**: The role MUST provide user-tunable, `percona_mysql_`-prefixed variables in `defaults/main.yml` for core server, networking, and replication settings, including at minimum:
  - `percona_mysql_version` (Percona release series, default `"8.4"` mapped to `ps-84-lts` or `"ps-84-lts"`)
  - `percona_mysql_role` (`"master"` or `"replica"`, default `"master"`)
  - `percona_mysql_server_id` (unique positive integer server ID, default `1`)
  - `percona_mysql_bind_address` (default `"0.0.0.0"`)
  - `percona_mysql_port` (default `3306`)
  - `percona_mysql_root_password` (default `"changeme_root_password"`)
  - `percona_mysql_secure_installation` (boolean, default `true`)
  - `percona_mysql_gtid_mode` (default `"ON"`)
  - `percona_mysql_enforce_gtid_consistency` (default `"ON"`)
  - `percona_mysql_log_bin` (binary log basename, default `"mysql-bin"`)
  - `percona_mysql_binlog_format` (default `"ROW"`)
  - `percona_mysql_binlog_expire_logs_seconds` (default `604800`)
  - `percona_mysql_innodb_buffer_pool_size` (default `"128M"`)
  - `percona_mysql_max_connections` (default `151`)
  - `percona_mysql_extra_mysqld_config` (optional dictionary of additional `[mysqld]` key-value directives, default `{}`)
  - `percona_mysql_replication_user` (optional string for replication account username, default `""`)
  - `percona_mysql_replication_password` (optional string for replication account password, default `""`)
  - `percona_mysql_replication_host` (host mask for replication user created on master, default `"%"`)
  - `percona_mysql_source_host` (primary host address for replica nodes, default `""`)
  - `percona_mysql_source_port` (primary port for replica nodes, default `3306`)
  - `percona_mysql_replica_start_replication` (boolean controlling whether the replica channel is started automatically when `percona_mysql_source_host` is set, default `true`)
  - `percona_mysql_databases` (list of database dictionaries supporting `name`, optional `encoding`/`charset` default `"utf8mb4"`, optional `collation` default `"utf8mb4_unicode_ci"`, and optional `state` default `"present"`, default `[]`)
  - `percona_mysql_users` (list of user dictionaries supporting `name`, `password`, optional `host` default `"localhost"`, optional `priv` default `"*.*:USAGE"`, and optional `state` default `"present"`, default `[]`)
- **FR-006**: When `percona_mysql_role` is `"master"`, the role MUST configure `read_only = OFF` and `super_read_only = OFF` in the managed MySQL configuration, and when `percona_mysql_replication_user` and `percona_mysql_replication_password` are non-empty, ensure the replication user exists with `REPLICATION SLAVE` (and `REPLICATION CLIENT`) privileges.
- **FR-007**: When `percona_mysql_role` is `"replica"`, the role MUST configure `read_only = ON`, `super_read_only = ON`, and `skip_replica_start` control as appropriate in the managed MySQL configuration, and when `percona_mysql_source_host` is non-empty, configure the replication source (`CHANGE REPLICATION SOURCE TO` with GTID auto-positioning `SOURCE_AUTO_POSITION = 1`) idempotently and start the replica threads if `percona_mysql_replica_start_replication` is `true`.
- **FR-008**: The role MUST provision any databases declared in `percona_mysql_databases` and user accounts declared in `percona_mysql_users` when running on a writable `"master"` node (or when explicitly enabled), maintaining idempotency across runs.
- **FR-009**: The role MUST render its managed `[mysqld]` settings into a dedicated high-precedence drop-in configuration file (`99-percona-managed.cnf` inside `/etc/mysql/conf.d/` on Debian-family and `/etc/my.cnf.d/` on RedHat-family, ensuring the parent configuration includes that directory) and validate the MySQL server configuration using `mysqld --validate-config` before restarting the MySQL systemd service via a handler grouped with `listen:`.
- **FR-010**: All tasks in the role MUST be strictly idempotent, producing zero changes on a second consecutive run with unchanged variables across all supported distributions.

### Key Entities

- **Percona MySQL Node**: Represents a Percona Server for MySQL instance managed by the role. Key attributes include operational role (`master` or `replica`), unique `server_id`, release series (default `8.4` / `ps-84-lts`), network bind address and port, GTID and binary log configuration, and read-only enforcement state.
- **Replication Topology Link**: Represents the primary-to-replica replication relationship, defined by the replication user credentials created on the `master` node and the source connection endpoint (`source_host`, `source_port`, GTID auto-positioning) configured on the `replica` node.
- **Managed Database (`percona_mysql_databases` item)**: Represents an application database schema managed by the role, with attributes `name`, `charset`/`encoding`, `collation`, and `state`.
- **Managed Database User (`percona_mysql_users` item)**: Represents a MySQL user account managed by the role, with attributes `name`, `password`, `host`, `priv`, and `state`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy Percona Server for MySQL in both `master` and `replica` modes (verified via a two-container `mysql-master` + `mysql-replica` Molecule topology per supported target Linux distribution) in a single playbook run, with the MySQL systemd service enabled, active, and accepting authenticated connections within 60 seconds.
- **SC-002**: 100% of nodes provisioned with `percona_mysql_role: "master"` report `read_only = OFF`, `super_read_only = OFF`, `gtid_mode = ON`, and active binary logging, and 100% of nodes provisioned with `percona_mysql_role: "replica"` report `read_only = ON`, `super_read_only = ON`, active replication threads (`Replica_IO_Running = Yes` and `Replica_SQL_Running = Yes`), and replicate data written to `mysql-master`.
- **SC-003**: 100% of databases declared in `percona_mysql_databases` and user accounts declared in `percona_mysql_users` are present and accessible with their configured privileges immediately after role convergence on a primary node.
- **SC-004**: Re-running the role on an already converged host (in either `master` or `replica` mode) with identical inputs results in 0 changed tasks across all supported Linux distributions.
- **SC-005**: Any invalid configuration directive, invalid `percona_mysql_role`, invalid `percona_mysql_server_id`, or unsupported OS family is caught by validation before disrupting an active database service.

## Assumptions

- Target hosts run `systemd` on Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) or RedHat-family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL) distributions and have outbound internet access to `repo.percona.com`.
- The role name is `percona_mysql` (residing under `roles/percona_mysql/` with all variables prefixed `percona_mysql_`) to match the user request and collection naming conventions.
- Percona Server for MySQL 8.4 LTS (`8.4` / `ps-84-lts`) is used as the default release series, while allowing operators to override `percona_mysql_version` (e.g., `"8.0"` / `"ps-80"`) if desired.
- Managed configuration is placed in a drop-in file (`99-percona-managed.cnf`) under the OS-specific MySQL include directory (`/etc/mysql/conf.d/` on Debian-family, `/etc/my.cnf.d/` on RedHat-family) so distribution-specific socket, pid-file, and datadir defaults are preserved.
- Database and user management and replication channel commands are executed via the native `mysql` CLI using `/root/.my.cnf` with idempotent SQL checks, avoiding external Ansible collection or host Python driver dependencies.
- GTID-based replication (`gtid_mode = ON`, `enforce_gtid_consistency = ON`, `SOURCE_AUTO_POSITION = 1`) is used as the standard replication mechanism because it eliminates manual binary log file/position tracking and is Percona's recommended best practice for MySQL 8.x.
- Initial data seeding/cloning (e.g., Percona XtraBackup or `mysqldump` snapshot transfer for existing large datasets) and automatic failover orchestration (e.g., Orchestrator or ProxySQL) are out of scope for this role.
