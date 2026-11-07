---

description: "Task list for Percona Server for MySQL Role (percona_mysql) implementation"
---

# Tasks: Percona Server for MySQL Role (`percona_mysql`)

**Input**: Design documents from `/specs/002-percona-mysql-role/`

**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule verification (`molecule test` across all 5 CI images using the 2-container `mysql-master` + `mysql-replica` scenario) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Ansible role**: `roles/percona_mysql/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)
- **CI workflow**: `.github/workflows/ci.yml`
- **Repository documentation**: `AGENTS.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the role and Molecule scenario using official CLI tools per Constitution Principle II

- [X] T001 Scaffold the `percona_mysql` role skeleton using `ansible-galaxy role init --init-path roles percona_mysql` to create `roles/percona_mysql/`
- [X] T002 Remove the unused generated `roles/percona_mysql/files/` directory and initialize the default Molecule scenario using `molecule init scenario default` inside `roles/percona_mysql/molecule/default/`
- [X] T003 Remove any generated `roles/percona_mysql/molecule/default/create.yml` or `roles/percona_mysql/molecule/default/destroy.yml` and configure the 2-container (`mysql-master` and `mysql-replica`) Docker systemd driver in `roles/percona_mysql/molecule/default/molecule.yml` using `roles/consul/molecule/default/molecule.yml` as baseline
- [X] T004 [P] Create `roles/percona_mysql/molecule/default/prepare.yml` with the RHEL 8 `python39` bootstrap for both `mysql-master` and `mysql-replica`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core metadata, OS variables, defaults, Percona repository setup, package installation, and validation handlers that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Populate Galaxy metadata (`author`, `description`, `license`, `min_ansible_version: "2.15"`, `platforms` for Debian/Ubuntu/EL 8-9, and `galaxy_tags`) in `roles/percona_mysql/meta/main.yml`
- [X] T006 [P] Define Debian-family variables (`percona_mysql_prerequisite_packages`, `percona_mysql_packages`, `percona_mysql_service_name: "mysql"`, `percona_mysql_config_include_dir: "/etc/mysql/conf.d"`, `percona_mysql_dropin_config_file: "/etc/mysql/conf.d/99-percona-managed.cnf"`, `percona_mysql_main_config_file: "/etc/mysql/my.cnf"`, `percona_mysql_socket: "/var/run/mysqld/mysqld.sock"`, `percona_mysql_error_log_file: "/var/log/mysql/error.log"`) in `roles/percona_mysql/vars/Debian.yml`
- [X] T007 [P] Define RedHat-family variables (`percona_mysql_prerequisite_packages`, `percona_mysql_packages`, `percona_mysql_service_name: "mysqld"`, `percona_mysql_config_include_dir: "/etc/my.cnf.d"`, `percona_mysql_dropin_config_file: "/etc/my.cnf.d/99-percona-managed.cnf"`, `percona_mysql_main_config_file: "/etc/my.cnf"`, `percona_mysql_socket: "/var/lib/mysql/mysql.sock"`, `percona_mysql_error_log_file: "/var/log/mysqld.log"`) in `roles/percona_mysql/vars/RedHat.yml`
- [X] T008 Define all `percona_mysql_*` user-tunable default variables in `roles/percona_mysql/defaults/main.yml` adhering to `data-model.md` constraints: `percona_mysql_version: "8.4"` (`One of "8.4", "8.4-lts", "ps-84-lts", "8.0", "ps-80"`), `percona_mysql_role: "master"` (`Must be "master" or "replica"`), `percona_mysql_server_id: 1` (`Positive integer (>= 1); must be unique across replicating nodes`), `percona_mysql_bind_address: "0.0.0.0"` (`Valid IPv4/IPv6 address or "*"`), `percona_mysql_port: 3306` (`Integer between 1 and 65535`), `percona_mysql_root_password: "changeme_root_password"` (`Non-empty string`), `percona_mysql_secure_installation: true` (`Boolean (true / false)`), `percona_mysql_gtid_mode: "ON"` (`"ON", "ON_PERMISSIVE", "OFF_PERMISSIVE", or "OFF"`), `percona_mysql_enforce_gtid_consistency: "ON"` (`"ON", "WARN", or "OFF"`), `percona_mysql_log_bin: "mysql-bin"` (`Non-empty string basename or path`), `percona_mysql_binlog_format: "ROW"` (`"ROW", "STATEMENT", or "MIXED"`), `percona_mysql_binlog_expire_logs_seconds: 604800` (`Positive integer (>= 1)`), `percona_mysql_innodb_buffer_pool_size: "128M"` (`Valid MySQL byte size string ("128M", "1G", etc.)`), `percona_mysql_max_connections: 151` (`Positive integer (>= 1)`), `percona_mysql_extra_mysqld_config: {}` (`Dictionary of extra [mysqld] directives`), `percona_mysql_replication_user: ""` (`Required if percona_mysql_role == 'replica' and percona_mysql_source_host != ''`), `percona_mysql_replication_password: ""` (`Required when percona_mysql_replication_user is non-empty`), `percona_mysql_replication_host: "%"` (`Host mask for replication account on master`), `percona_mysql_source_host: ""` (`IP address or hostname of the primary (master) node`), `percona_mysql_source_port: 3306` (`Integer port between 1 and 65535`), `percona_mysql_replica_start_replication: true` (`Boolean (true / false)`), `percona_mysql_databases: []`, `percona_mysql_users: []`, and `percona_mysql_package_state: "present"` (`"present" or "latest"`)
- [X] T009 [P] Implement official Percona APT repository setup (`percona-release` DEB installation and idempotent `percona-release enable-only {{ percona_mysql_repo_product }} release`) in `roles/percona_mysql/tasks/setup-Debian.yml`
- [X] T010 [P] Implement official Percona YUM/DNF repository setup (`percona-release` RPM installation, idempotent `dnf module disable mysql`, and idempotent `percona-release enable-only {{ percona_mysql_repo_product }} release`) in `roles/percona_mysql/tasks/setup-RedHat.yml`
- [X] T011 Implement Percona Server package installation (`percona-server-server`, `percona-server-client`) and config include directory setup (`{{ percona_mysql_config_include_dir }}`, mode `'0755'`, plus `!includedir /etc/my.cnf.d` on RedHat) in `roles/percona_mysql/tasks/install.yml`
- [X] T012 [P] Implement `/usr/sbin/mysqld --validate-config` and service restart handlers grouped under `listen: "validate and restart mysql"` in `roles/percona_mysql/handlers/main.yml`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Install and Manage Percona Server for MySQL as a Primary (Master) Node (Priority: P1) 🎯 MVP

**Goal**: Install Percona Server for MySQL 8.4 LTS on Debian and RedHat family hosts, render the managed drop-in config (`99-percona-managed.cnf`) with `read_only = OFF` and `super_read_only = OFF` plus GTID binary logging, secure the `root` account and `/root/.my.cnf` (`mode: '0600'`), and provision the replication user (`REPLICATION SLAVE, REPLICATION CLIENT`) on `master` nodes.

**Independent Test**: Provision `mysql-master` with `percona_mysql_role: "master"`, verify the MySQL systemd service is enabled and active, confirm passwordless admin CLI access via `/root/.my.cnf`, verify `read_only = OFF`, `super_read_only = OFF`, `gtid_mode = ON`, and `REPLICATION SLAVE` grant for `percona_mysql_replication_user`, and verify a second converge run produces `changed=0`.

### Implementation for User Story 1

- [X] T013 [P] [US1] Create `roles/percona_mysql/templates/99-percona-managed.cnf.j2` rendering `[mysqld]` settings (`bind-address`, `port`, `server-id`, `gtid_mode`, `enforce_gtid_consistency`, `log_bin`, `binlog_format`, `binlog_expire_logs_seconds`, `innodb_buffer_pool_size`, `max_connections`, `read_only = OFF` and `super_read_only = OFF` when `percona_mysql_role == 'master'`, `read_only = ON` and `super_read_only = ON` when `percona_mysql_role == 'replica'`, and `percona_mysql_extra_mysqld_config` key-value pairs)
- [X] T014 [P] [US1] Create `roles/percona_mysql/templates/root-my.cnf.j2` rendering `[client]` `user=root` and quoted `password` for `/root/.my.cnf`
- [X] T015 [US1] Implement `roles/percona_mysql/tasks/configure.yml` to render `{{ percona_mysql_dropin_config_file }}` (mode `'0644'`, notifying `"validate and restart mysql"`), flush handlers, ensure `{{ percona_mysql_service_name }}` is enabled and started, bootstrap the MySQL `root` password across both socket-auth (Debian) and temporary-log-password (RedHat `/var/log/mysqld.log`) initial states, deploy `/root/.my.cnf` (`mode: '0600'`), and remove anonymous users / `test` database when `percona_mysql_secure_installation` is `true`
- [X] T016 [US1] Implement master replication user management in `roles/percona_mysql/tasks/replication.yml` (when `percona_mysql_role == 'master'` and `percona_mysql_replication_user != ''`, idempotently create `'{{ percona_mysql_replication_user }}'@'{{ percona_mysql_replication_host }}'` and grant `REPLICATION SLAVE, REPLICATION CLIENT ON *.*`)
- [X] T017 [US1] Implement `roles/percona_mysql/tasks/main.yml` with platform assertion (`ansible_os_family in ['Debian', 'RedHat']`), input assertions (`percona_mysql_role` `Must be "master" or "replica"`, `percona_mysql_server_id` `Positive integer (>= 1)`, `percona_mysql_port` `Integer between 1 and 65535`, `percona_mysql_root_password` `Non-empty string`, and replica credential requirements), OS variable loading (`{{ ansible_os_family }}.yml`), OS repository dispatch (`setup-{{ ansible_os_family }}.yml`), `install.yml`, `configure.yml`, and `replication.yml`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Configure Percona Server for MySQL as a Replica Node (Priority: P2)

**Goal**: Configure a node with `percona_mysql_role: "replica"` (`read_only = ON`, `super_read_only = ON`) and idempotently configure and start GTID auto-positioned replication (`CHANGE REPLICATION SOURCE TO ... SOURCE_AUTO_POSITION = 1, GET_SOURCE_PUBLIC_KEY = 1` and `START REPLICA`) from `percona_mysql_source_host`.

**Independent Test**: Provision `mysql-replica` connected to `mysql-master`, verify `read_only = ON`, `super_read_only = ON`, `Replica_IO_Running = Yes`, and `Replica_SQL_Running = Yes`, confirm data written on `mysql-master` replicates to `mysql-replica`, and verify a second converge run produces `changed=0`.

### Implementation for User Story 2

- [X] T018 [US2] Extend `roles/percona_mysql/tasks/replication.yml` for `percona_mysql_role == 'replica'` (when `percona_mysql_source_host | length > 0`, inspect `SHOW REPLICA STATUS\G`, idempotently run `STOP REPLICA` and `CHANGE REPLICATION SOURCE TO SOURCE_HOST='...', SOURCE_PORT=..., SOURCE_USER='...', SOURCE_PASSWORD='...', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1` only when source settings differ, and run `START REPLICA` when `percona_mysql_replica_start_replication` is `true` and `Replica_IO_Running != 'Yes'` or `Replica_SQL_Running != 'Yes'`)
- [X] T019 [US2] Configure `roles/percona_mysql/molecule/default/converge.yml` and `roles/percona_mysql/molecule/default/verify.yml` to converge `mysql-master` (`percona_mysql_role: "master"`, `percona_mysql_server_id: 1`) and `mysql-replica` (`percona_mysql_role: "replica"`, `percona_mysql_server_id: 2`, `percona_mysql_source_host` pointing to `mysql-master`) and verify service status, `read_only`/`super_read_only` states, `Replica_IO_Running`/`Replica_SQL_Running`, and live GTID row replication from `mysql-master` to `mysql-replica`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently and replicate live data

---

## Phase 5: User Story 3 - Manage Application Databases, Users, and Custom Server Tuning (Priority: P3)

**Goal**: Declaratively provision application databases (`percona_mysql_databases`), MySQL user accounts and privileges (`percona_mysql_users`), and custom server tuning parameters (`percona_mysql_innodb_buffer_pool_size`, `percona_mysql_max_connections`, `percona_mysql_extra_mysqld_config`) idempotently.

**Independent Test**: Define `percona_mysql_databases`, `percona_mysql_users`, and `percona_mysql_extra_mysqld_config` on `mysql-master`, converge the role, and verify in `verify.yml` that the databases exist with the configured character set/collation, the users can authenticate with their privileges, and the extra server variables are active.

### Implementation for User Story 3

- [X] T020 [P] [US3] Implement `roles/percona_mysql/tasks/databases.yml` to validate `percona_mysql_databases` items (`name` `Non-empty identifier ([a-zA-Z0-9_$]+)`, optional `encoding`/`charset` default `"utf8mb4"`, optional `collation` default `"utf8mb4_unicode_ci"`, optional `state` `"present" or "absent"`) and idempotently create, alter, or drop databases via `/root/.my.cnf` using `loop_control.loop_var: percona_mysql_db`
- [X] T021 [P] [US3] Implement `roles/percona_mysql/tasks/users.yml` to validate `percona_mysql_users` items (`name` `Non-empty MySQL username`, `password` `Required when state == 'present'`, optional `host` default `"localhost"`, optional `priv` default `"*.*:USAGE"` in `db.table:PRIV1,PRIV2` format, optional `state` `"present" or "absent"`) and idempotently create, update password/privileges, or drop users via `/root/.my.cnf` using `loop_control.loop_var: percona_mysql_user_item`
- [X] T022 [US3] Include `databases.yml` and `users.yml` in `roles/percona_mysql/tasks/main.yml` when `percona_mysql_role == 'master'`
- [X] T023 [US3] Extend `roles/percona_mysql/molecule/default/converge.yml` and `roles/percona_mysql/molecule/default/verify.yml` to provision `percona_mysql_databases` (`app_db`), `percona_mysql_users` (`app_user`), and `percona_mysql_extra_mysqld_config` on `mysql-master`, verifying schema character set/collation, user authentication/grants, and replication of `app_db` to `mysql-replica`

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, CI workflow registration, linting, and full 5-distro Molecule verification

- [X] T024 [P] Write complete role documentation (description, supported platforms, requirements, role variables with defaults, master/replica and database/user playbook examples, license) in `roles/percona_mysql/README.md`
- [X] T025 [P] Add the `percona_mysql` role to the Roles table in `AGENTS.md`
- [X] T026 Register `percona_mysql` in all four required locations (`detect-changes.outputs`, `paths-filter` `filters`, `molecule.strategy.matrix.role`, and the role check `case` statement) in `.github/workflows/ci.yml`
- [X] T027 Run `yamllint .` and `ansible-lint` from the repository root and fix any warnings or errors across `roles/percona_mysql/` and `.github/workflows/ci.yml`
- [X] T028 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from `roles/percona_mysql/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational phase completion
  - User Story 1 (P1): Primary (`master`) node installation, drop-in config, root bootstrap, and replication user creation
  - User Story 2 (P2): Replica (`replica`) node read-only mode and GTID auto-positioned replication channel setup
  - User Story 3 (P3): Application database, user/privilege management, and custom server tuning
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Starts immediately after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Builds on `roles/percona_mysql/tasks/replication.yml` and `templates/99-percona-managed.cnf.j2` from US1 to connect `mysql-replica` to `mysql-master`
- **User Story 3 (P3)**: Can be developed in parallel with US2 after US1's `configure.yml` (`/root/.my.cnf`) is ready

### Parallel Opportunities

- In **Phase 2 (Foundational)**: `T005` (`meta/main.yml`), `T006` (`vars/Debian.yml`), `T007` (`vars/RedHat.yml`), `T009` (`tasks/setup-Debian.yml`), `T010` (`tasks/setup-RedHat.yml`), and `T012` (`handlers/main.yml`) touch separate files and can be implemented in parallel.
- In **Phase 3 (User Story 1)**: `T013` (`templates/99-percona-managed.cnf.j2`) and `T014` (`templates/root-my.cnf.j2`) can be implemented in parallel.
- In **Phase 5 (User Story 3)**: `T020` (`tasks/databases.yml`) and `T021` (`tasks/users.yml`) touch independent files and can be implemented in parallel.
- In **Phase 6 (Polish)**: `T024` (`roles/percona_mysql/README.md`), `T025` (`AGENTS.md`), and `T026` (`.github/workflows/ci.yml`) touch independent files and can run in parallel before linting (`T027`) and Molecule matrix testing (`T028`).

---

## Parallel Example: Foundational & Story Tasks

```bash
# Launch parallel Foundational tasks (Phase 2):
Task: "T005 [P] Populate Galaxy metadata in roles/percona_mysql/meta/main.yml"
Task: "T006 [P] Define Debian-family variables in roles/percona_mysql/vars/Debian.yml"
Task: "T007 [P] Define RedHat-family variables in roles/percona_mysql/vars/RedHat.yml"
Task: "T009 [P] Implement official Percona APT repository setup in roles/percona_mysql/tasks/setup-Debian.yml"
Task: "T010 [P] Implement official Percona YUM/DNF repository setup in roles/percona_mysql/tasks/setup-RedHat.yml"
Task: "T012 [P] Implement mysqld --validate-config and service restart handlers in roles/percona_mysql/handlers/main.yml"

# Launch parallel User Story 3 tasks (Phase 5):
Task: "T020 [P] [US3] Implement roles/percona_mysql/tasks/databases.yml"
Task: "T021 [P] [US3] Implement roles/percona_mysql/tasks/users.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`–`T004`)
2. Complete Phase 2: Foundational (`T005`–`T012`)
3. Complete Phase 3: User Story 1 (`T013`–`T017`)
4. **STOP and VALIDATE**: Converge and verify `mysql-master` deployment via Molecule

### Incremental Delivery

1. Complete Setup + Foundational → Percona 8.4 LTS repo, installation, defaults, and handlers ready
2. Add User Story 1 → Primary (`master`) node deployment, root security, and replication user working (MVP!)
3. Add User Story 2 → Replica (`replica`) node read-only mode and live GTID auto-positioned replication working
4. Add User Story 3 → Declarative application databases, users/grants, and custom tuning working
5. Complete Polish → Docs, CI registration, `yamllint .`, `ansible-lint`, and full 5-distro Molecule test loop
