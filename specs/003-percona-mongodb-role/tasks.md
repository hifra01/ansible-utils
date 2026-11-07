---

description: "Task list for Percona Server for MongoDB Role (percona_mongodb) implementation"
---

# Tasks: Percona Server for MongoDB Role (`percona_mongodb`)

**Input**: Design documents from `/specs/003-percona-mongodb-role/`

**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule verification (`molecule test` across all 5 CI images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Ansible role**: `roles/percona_mongodb/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)
- **CI workflow**: `.github/workflows/ci.yml`
- **Repository documentation**: `AGENTS.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the role and Molecule scenario using official CLI tools per Constitution Principle II

- [X] T001 Scaffold the `percona_mongodb` role skeleton using `ansible-galaxy role init --init-path roles percona_mongodb` to create `roles/percona_mongodb/`
- [X] T002 Remove the unused generated `roles/percona_mongodb/files/` directory and initialize the default Molecule scenario using `molecule init scenario default` inside `roles/percona_mongodb/molecule/default/`
- [X] T003 Remove any generated `roles/percona_mongodb/molecule/default/create.yml` or `roles/percona_mongodb/molecule/default/destroy.yml` and configure the privileged systemd Docker driver in `roles/percona_mongodb/molecule/default/molecule.yml` using `roles/consul/molecule/default/molecule.yml` as baseline
- [X] T004 [P] Create `roles/percona_mongodb/molecule/default/prepare.yml` with the RHEL/Rocky 8 `python39` bootstrap via `ansible.builtin.raw`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core metadata, OS variables, defaults, Percona repository setup, package installation, and validation handlers that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Populate Galaxy metadata (`author`, `description`, `license`, `min_ansible_version: "2.21"`, `platforms` for Debian/Ubuntu/EL 8-9, and `galaxy_tags`) in `roles/percona_mongodb/meta/main.yml`
- [X] T006 [P] Define internal version-to-repository mapping (`_percona_mongodb_repo_map` mapping `"8.0"` -> `"psmdb-80"`, `"7.0"` -> `"psmdb-70"`, `"6.0"` -> `"psmdb-60"`, `"psmdb-80"` -> `"psmdb-80"`, `"psmdb-70"` -> `"psmdb-70"`, `"psmdb-60"` -> `"psmdb-60"`) in `roles/percona_mongodb/vars/main.yml`
- [X] T007 [P] Define Debian-family variables (`percona_mongodb_prerequisite_packages`, `percona_mongodb_packages: ["percona-server-mongodb"]`, `percona_mongodb_service_name: "mongod"`, `percona_mongodb_user: "mongod"`, `percona_mongodb_group: "mongod"`, `percona_mongodb_config_file: "/etc/mongod.conf"`, `percona_mongodb_db_path: "/var/lib/mongodb"`, `percona_mongodb_log_path: "/var/log/mongodb/mongod.log"`, `percona_mongodb_pid_file_path: "/var/run/mongod.pid"`, `percona_mongodb_process_fork: true`) in `roles/percona_mongodb/vars/Debian.yml`
- [X] T008 [P] Define RedHat-family variables (`percona_mongodb_prerequisite_packages`, `percona_mongodb_packages: ["percona-server-mongodb"]`, `percona_mongodb_service_name: "mongod"`, `percona_mongodb_user: "mongod"`, `percona_mongodb_group: "mongod"`, `percona_mongodb_config_file: "/etc/mongod.conf"`, `percona_mongodb_db_path: "/var/lib/mongo"`, `percona_mongodb_log_path: "/var/log/mongo/mongod.log"`, `percona_mongodb_pid_file_path: "/var/run/mongod.pid"`, `percona_mongodb_process_fork: true`) in `roles/percona_mongodb/vars/RedHat.yml`
- [X] T009 Define all `percona_mongodb_*` user-tunable default variables in `roles/percona_mongodb/defaults/main.yml` adhering to `data-model.md` constraints: `percona_mongodb_version: "8.0"` (`One of "8.0", "7.0", "6.0", "psmdb-80", "psmdb-70", "psmdb-60"`), `percona_mongodb_package_state: "present"` (`"present" or "latest"`), `percona_mongodb_apt_release_deb_url`, `percona_mongodb_yum_release_rpm_url`, `percona_mongodb_bind_ip: "0.0.0.0"` (`Non-empty comma-separated IPv4/IPv6/hostname string or "0.0.0.0"`), `percona_mongodb_port: 27017` (`Integer between 1 and 65535`), `percona_mongodb_wiredtiger_cache_size_gb: null` (`Positive number (> 0) if specified; omitted when null`), `percona_mongodb_extra_config: {}` (`Mapping merged recursively into /etc/mongod.conf`), `percona_mongodb_replset_enabled: true` (`Boolean (true / false)`), `percona_mongodb_replset_name: "rs0"` (`Non-empty string when percona_mongodb_replset_enabled: true`), `percona_mongodb_replset_init: true` (`Boolean (true / false)`), `percona_mongodb_replset_advertise_host: "{{ ansible_default_ipv4.address | default('127.0.0.1') }}"` (`Non-empty hostname or IP address`), `percona_mongodb_replset_members: []` (`When empty ([]), auto-populates a 1-node replica set with {{ percona_mongodb_replset_advertise_host }}:{{ percona_mongodb_port }}`), `percona_mongodb_oplog_size_mb: null` (`Positive integer (>= 1) if specified; omitted when null`), `percona_mongodb_auth_enabled: true` (`Boolean (true / false)`), `percona_mongodb_keyfile_path: "/etc/mongod.keyfile"` (`Absolute filesystem path`), `percona_mongodb_keyfile_content: ""` (`Must be non-empty (6–1024 base64 chars) when percona_mongodb_replset_enabled: true, percona_mongodb_auth_enabled: true, and percona_mongodb_replset_members | length > 1; auto-generated on host when empty in single-instance mode`), `percona_mongodb_admin_user: "admin"` (`Non-empty string when percona_mongodb_auth_enabled: true`), `percona_mongodb_admin_password: "changeme_admin_password"` (`Non-empty string when percona_mongodb_auth_enabled: true`), and `percona_mongodb_users: []` (`List of application user dictionaries`)
- [X] T010 [P] Implement official Percona APT repository setup (`percona-release` DEB download/installation and idempotent `percona-release enable-only {{ _percona_mongodb_repo_product }} release` guarded by `stat` on `/etc/apt/sources.list.d/percona-{{ _percona_mongodb_repo_product }}-release.list`) in `roles/percona_mongodb/tasks/setup-Debian.yml`
- [X] T011 [P] Implement official Percona YUM/DNF repository setup (`percona-release` RPM installation and idempotent `percona-release enable-only {{ _percona_mongodb_repo_product }} release` guarded by `stat` on `/etc/yum.repos.d/percona-{{ _percona_mongodb_repo_product }}-release.repo`) in `roles/percona_mongodb/tasks/setup-RedHat.yml`
- [X] T012 Implement Percona Server for MongoDB package installation (`{{ percona_mongodb_packages }}`) and data/log directory ownership enforcement (`{{ percona_mongodb_db_path }}` and `{{ percona_mongodb_log_path | dirname }}` owned by `{{ percona_mongodb_user }}:{{ percona_mongodb_group }}`, mode `'0755'`) in `roles/percona_mongodb/tasks/install.yml`
- [X] T013 [P] Implement YAML configuration validation and `mongod` service restart + port wait handlers grouped under `listen: "restart mongod"` in `roles/percona_mongodb/handlers/main.yml`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Deploy Percona Server for MongoDB with Single-Instance Replica Set (Priority: P1) 🎯 MVP

**Goal**: Install Percona Server for MongoDB 8.0, render `/etc/mongod.conf` (`mode: '0644'`), manage the replica set security keyfile (`mode: '0400'`), start and enable `mongod`, and automatically initialize a single-instance replica set (`percona_mongodb_replset_members: []`) that elects the local instance as `PRIMARY` (or run as standalone when `percona_mongodb_replset_enabled: false`).

**Independent Test**: Provision a single Linux host with default replica set settings, verify `mongod` is enabled and active, confirm `rs.status()` reports `ok: 1`, `set: "rs0"`, `members.length === 1`, and `myState === 1` (`PRIMARY`), and verify a second converge run produces `changed=0`.

### Implementation for User Story 1

- [X] T014 [P] [US1] Create `roles/percona_mongodb/templates/mongod.conf.j2` building a structured dictionary (`net.bindIp`, `net.port`, `processManagement.fork`, `processManagement.pidFilePath`, `storage.dbPath`, optional `storage.wiredTiger.engineConfig.cacheSizeGB` when `percona_mongodb_wiredtiger_cache_size_gb` is not `null`, `systemLog`, optional `replication.replSetName` and `replication.oplogSizeMB` when `percona_mongodb_replset_enabled` is `true`, optional `security.authorization: "enabled"` when `percona_mongodb_auth_enabled` is `true` and `security.keyFile` when both `percona_mongodb_replset_enabled` and `percona_mongodb_auth_enabled` are `true`, merged recursively with `percona_mongodb_extra_config`) and rendering via `to_nice_yaml(indent=2)`
- [X] T015 [US1] Implement `roles/percona_mongodb/tasks/configure.yml` to manage `{{ percona_mongodb_keyfile_path }}` (`owner: "{{ percona_mongodb_user }}"`, `group: "{{ percona_mongodb_group }}"`, `mode: '0400'`, writing `percona_mongodb_keyfile_content` when non-empty or auto-generating a 756-byte base64 keyfile via `openssl rand -base64 756` when `percona_mongodb_keyfile_content` is empty and `percona_mongodb_replset_members | length <= 1`), render `{{ percona_mongodb_config_file }}` (`mode: '0644'`, notifying `"restart mongod"`), ensure `{{ percona_mongodb_service_name }}` is enabled and started, flush handlers, and wait for `127.0.0.1:{{ percona_mongodb_port }}`
- [X] T016 [US1] Implement single-instance replica set initialization in `roles/percona_mongodb/tasks/replicaset.yml` (probe admin auth status if `percona_mongodb_auth_enabled` is `true`, normalize desired replica set members defaulting to `[{ '_id': 0, 'host': percona_mongodb_replset_advertise_host ~ ':' ~ (percona_mongodb_port | string) }]` when `percona_mongodb_replset_members` is empty, inspect `rs.status()`, execute `rs.initiate({ _id: percona_mongodb_replset_name, members: ... })` when uninitialized (`code == 94` / `NotYetInitialized`), and poll `db.hello().isWritablePrimary` until the node reaches `PRIMARY` state within 60 seconds)
- [X] T017 [US1] Implement `roles/percona_mongodb/tasks/main.yml` with platform assertion (`ansible_facts['os_family'] in ['Debian', 'RedHat']`), input assertions (`percona_mongodb_version` in `_percona_mongodb_repo_map`, `percona_mongodb_package_state in ['present', 'latest']`, `percona_mongodb_port` `Integer between 1 and 65535`, `percona_mongodb_bind_ip` `Non-empty comma-separated IPv4/IPv6/hostname string or "0.0.0.0"`, `percona_mongodb_replset_name` `Non-empty string when percona_mongodb_replset_enabled: true`, `percona_mongodb_replset_advertise_host` `Non-empty hostname or IP address`, `percona_mongodb_oplog_size_mb` `Positive integer (>= 1) if specified; omitted when null`, `percona_mongodb_wiredtiger_cache_size_gb` `Positive number (> 0) if specified; omitted when null`, `percona_mongodb_admin_user` and `percona_mongodb_admin_password` `Non-empty string when percona_mongodb_auth_enabled: true`, and `percona_mongodb_keyfile_content` `Must be non-empty (6–1024 base64 chars) when percona_mongodb_replset_enabled: true, percona_mongodb_auth_enabled: true, and percona_mongodb_replset_members | length > 1`), OS variable loading, OS repository setup dispatch (`setup-{{ ansible_facts['os_family'] }}.yml`), `install.yml`, `configure.yml`, and `replicaset.yml`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Initialize or Reconfigure a Multi-Instance Replica Set (Priority: P2)

**Goal**: Support explicit multi-node or custom-attribute replica set member definitions in `percona_mongodb_replset_members` (`host`, `priority`, `arbiterOnly`, `hidden`, `votes`) and idempotently reconcile already-initialized replica sets using `rs.reconfig()` only when member definitions differ.

**Independent Test**: Converge with custom member attributes in `percona_mongodb_replset_members` (or update member priority/host), verify `rs.conf().members` reflects the declared configuration, and verify a second converge run reports `changed=0`.

### Implementation for User Story 2

- [X] T018 [US2] Add validation in `roles/percona_mongodb/tasks/main.yml` for `percona_mongodb_replset_members` items (`host` `Non-empty host:port (or host, which defaults to :{{ percona_mongodb_port }})`, optional `_id` `Non-negative integer unique within members`, optional `priority` `Number between 0 and 1000`, optional `arbiterOnly` `Boolean (true / false)`, optional `hidden` `Boolean (true / false); if true, priority must be 0`, optional `votes` `0 or 1`)
- [X] T019 [US2] Extend `roles/percona_mongodb/tasks/replicaset.yml` to normalize string or dictionary items in `percona_mongodb_replset_members` and, when the replica set is already initialized and `percona_mongodb_replset_init` is `true`, compare `rs.conf().members` against the desired member list (`host`, `priority`, `arbiterOnly`, `hidden`, `votes`), executing `rs.reconfig(cfg)` (with `{ force: true }` fallback if no writable primary is currently elected) only when differences exist

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Manage Authentication, Users, and Custom Server Configuration (Priority: P3)

**Goal**: Bootstrap the administrative user (`percona_mongodb_admin_user`) in the `admin` database (closing the MongoDB localhost exception without restarting `mongod`), declaratively provision/update/remove application database users (`percona_mongodb_users`) on the initializer (`percona_mongodb_replset_init: true`) or standalone (`percona_mongodb_replset_enabled: false`) node, and verify authentication and multi-document transactions in Molecule.

**Independent Test**: Converge with `percona_mongodb_auth_enabled: true`, `percona_mongodb_users` defined, and custom server tuning (`percona_mongodb_oplog_size_mb`), then verify in `verify.yml` that unauthenticated commands are rejected, the admin and application users authenticate, and a multi-document ACID transaction succeeds on the single-instance replica set.

### Implementation for User Story 3

- [X] T020 [P] [US3] Implement `roles/percona_mongodb/tasks/users.yml` to bootstrap `{{ percona_mongodb_admin_user }}` in `admin` with `root`, `userAdminAnyDatabase`, and `clusterAdmin` roles when `percona_mongodb_auth_enabled` is `true` and admin auth is not yet active, validate `percona_mongodb_users` items (`name` `Non-empty username`, `password` `Non-empty password string` when `state == 'present'`, optional `database` default `"admin"` `Non-empty target database name where the user is defined`, `roles` `Non-empty list of role strings or { role, db } dicts` when `state == 'present'`, optional `state` `Must be "present" or "absent"`), and iterate over `percona_mongodb_users` with `loop_control.loop_var: mongodb_user`
- [X] T021 [P] [US3] Implement `roles/percona_mongodb/tasks/user-item.yml` to idempotently create, update (`roles` or password via `db.auth()` check), or drop (`state == 'absent'`) each `mongodb_user` in `{{ mongodb_user.database | default('admin') }}` via `mongosh` with `no_log: true` and `changed_when: "'CHANGED' in _percona_mongodb_user_result.stdout"`
- [X] T022 [US3] Include `users.yml` in `roles/percona_mongodb/tasks/main.yml` when `(not (percona_mongodb_replset_enabled | bool)) or (percona_mongodb_replset_init | bool)`
- [X] T023 [US3] Configure `roles/percona_mongodb/molecule/default/converge.yml` and `roles/percona_mongodb/molecule/default/verify.yml` to converge `hifra01.utils.percona_mongodb` (single-instance replica set `rs0`, `percona_mongodb_auth_enabled: true`, `percona_mongodb_oplog_size_mb: 256`, and `percona_mongodb_users` with `app_user` on `app_db`) and verify service status, `/etc/mongod.conf` (`0644`) and `/etc/mongod.keyfile` (`0400`) permissions, port `27017` listening, unauthenticated `rs.status()` rejection, authenticated `rs.status()` reporting `PRIMARY` (`myState: 1`) with 1 member, and `app_user` executing a multi-document ACID transaction

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, CI workflow registration, linting, and full 5-distro Molecule verification

- [X] T024 [P] Write complete role documentation (description, supported platforms, requirements, role variables with defaults, single-instance replica set, multi-node replica set, and standalone playbook examples, license) in `roles/percona_mongodb/README.md`
- [X] T025 [P] Add the `percona_mongodb` role to the Roles table in `AGENTS.md`
- [X] T026 [P] Register `percona_mongodb` in all four required locations (`detect-changes.outputs`, `paths-filter` `filters`, `molecule.strategy.matrix.role`, and the role check `case` statement) in `.github/workflows/ci.yml`
- [X] T027 Run `yamllint .` and `ansible-lint` from the repository root and fix any warnings or errors across `roles/percona_mongodb/`, `AGENTS.md`, and `.github/workflows/ci.yml`
- [X] T028 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from `roles/percona_mongodb/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational phase completion
  - User Story 1 (P1): Single-instance replica set & standalone deployment (`templates/mongod.conf.j2`, `configure.yml`, `replicaset.yml`, `main.yml`)
  - User Story 2 (P2): Multi-instance replica set member normalization and idempotent `rs.reconfig()` reconciliation (`main.yml`, `replicaset.yml`)
  - User Story 3 (P3): Admin user bootstrap, `percona_mongodb_users` management, and full Molecule verification (`users.yml`, `user-item.yml`, `converge.yml`, `verify.yml`)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Starts immediately after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Extends `roles/percona_mongodb/tasks/replicaset.yml` and `roles/percona_mongodb/tasks/main.yml` created in US1
- **User Story 3 (P3)**: Tasks `T020` (`users.yml`) and `T021` (`user-item.yml`) can be written in parallel with US1/US2, then wired into `main.yml` (`T022`) after US1's `replicaset.yml` guarantees `PRIMARY` election before user creation

### Parallel Opportunities

- In **Phase 2 (Foundational)**: `T005` (`meta/main.yml`), `T006` (`vars/main.yml`), `T007` (`vars/Debian.yml`), `T008` (`vars/RedHat.yml`), `T010` (`tasks/setup-Debian.yml`), `T011` (`tasks/setup-RedHat.yml`), and `T013` (`handlers/main.yml`) touch independent files and can be implemented in parallel.
- In **Phase 5 (User Story 3)**: `T020` (`tasks/users.yml`) and `T021` (`tasks/user-item.yml`) touch independent files and can be implemented in parallel.
- In **Phase 6 (Polish)**: `T024` (`roles/percona_mongodb/README.md`), `T025` (`AGENTS.md`), and `T026` (`.github/workflows/ci.yml`) touch independent files and can run in parallel before linting (`T027`) and Molecule matrix testing (`T028`).

---

## Parallel Example: Foundational & Story Tasks

```bash
# Launch parallel Foundational tasks (Phase 2):
Task: "T005 [P] Populate Galaxy metadata in roles/percona_mongodb/meta/main.yml"
Task: "T006 [P] Define internal version-to-repository mapping in roles/percona_mongodb/vars/main.yml"
Task: "T007 [P] Define Debian-family variables in roles/percona_mongodb/vars/Debian.yml"
Task: "T008 [P] Define RedHat-family variables in roles/percona_mongodb/vars/RedHat.yml"
Task: "T010 [P] Implement official Percona APT repository setup in roles/percona_mongodb/tasks/setup-Debian.yml"
Task: "T011 [P] Implement official Percona YUM/DNF repository setup in roles/percona_mongodb/tasks/setup-RedHat.yml"
Task: "T013 [P] Implement YAML configuration validation and service restart handlers in roles/percona_mongodb/handlers/main.yml"

# Launch parallel User Story 3 tasks (Phase 5):
Task: "T020 [P] [US3] Implement roles/percona_mongodb/tasks/users.yml"
Task: "T021 [P] [US3] Implement roles/percona_mongodb/tasks/user-item.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`–`T004`)
2. Complete Phase 2: Foundational (`T005`–`T013`)
3. Complete Phase 3: User Story 1 (`T014`–`T017`)
4. **STOP and VALIDATE**: Verify single-instance replica set deployment (`PRIMARY` state) and standalone mode

### Incremental Delivery

1. Complete Setup + Foundational → Percona 8.0 (`psmdb-80`) repo, package install, defaults, and handlers ready
2. Add User Story 1 → Single-instance replica set auto-initialization and standalone mode working (MVP!)
3. Add User Story 2 → Multi-node replica set member normalization and idempotent `rs.reconfig()` working
4. Add User Story 3 → Admin user bootstrap, `percona_mongodb_users` management, and Molecule verification working
5. Complete Polish → Docs, CI registration, `yamllint .`, `ansible-lint`, and full 5-distro Molecule test loop
