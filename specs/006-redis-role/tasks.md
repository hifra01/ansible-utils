---
description: "Task list for Redis Open Source Role (redis) implementation"
---

# Tasks: Redis Open Source Role (`redis`)

**Input**: Design documents from `/specs/006-redis-role/`

**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule verification (`molecule test` across all 5 CI images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Ansible role**: `roles/redis/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)
- **CI workflow**: `.github/workflows/ci.yml`
- **Repository documentation**: `AGENTS.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the role and Molecule scenario using official CLI tools per Constitution Principle II

- [X] T001 Scaffold the `redis` role skeleton using `ansible-galaxy role init --init-path roles redis` to create `roles/redis/`
- [X] T002 Remove the unused generated `roles/redis/files/` directory and initialize the default Molecule scenario using `molecule init scenario default` inside `roles/redis/`
- [X] T003 Remove any generated `roles/redis/molecule/default/create.yml` or `roles/redis/molecule/default/destroy.yml` and configure the Docker systemd driver in `roles/redis/molecule/default/molecule.yml` using `roles/datetime/molecule/default/molecule.yml` as baseline
- [X] T004 [P] Create `roles/redis/molecule/default/prepare.yml` with the RHEL 8 `python39` bootstrap tasks

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core metadata, OS variables, defaults, and restart handlers that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Populate Galaxy metadata (`author: "Hilman F. Rakhmad"`, `description`, `license: "MIT"`, `min_ansible_version: "2.21.0"`, `platforms` for Debian/Ubuntu/EL 8-9, and `galaxy_tags`) in `roles/redis/meta/main.yml`
- [X] T006 [P] Define Debian-family variables (`redis_package_name: "redis-server"`, `redis_service_name: "redis-server"`, `redis_config_dir: "/etc/redis"`, `redis_config_file: "/etc/redis/redis.conf"`, `redis_default_logfile: "/var/log/redis/redis-server.log"`, `redis_system_user: "redis"`, `redis_system_group: "redis"`, `redis_config_owner: "root"`, `redis_config_group: "redis"`, `redis_config_mode: '0640'`, and upstream repository URLs/keys) in `roles/redis/vars/Debian.yml`
- [X] T007 [P] Define RedHat-family variables (`redis_package_name: "redis"`, `redis_service_name: "redis"`, `redis_config_dir: "/etc/redis"`, `redis_config_file: "/etc/redis/redis.conf"`, `redis_default_logfile: "/var/log/redis/redis.log"`, `redis_system_user: "redis"`, `redis_system_group: "redis"`, `redis_config_owner: "redis"`, `redis_config_group: "redis"`, `redis_config_mode: '0640'`, and upstream repository URLs/keys) in `roles/redis/vars/RedHat.yml`
- [X] T008 Define all `redis_*` user-tunable default variables in `roles/redis/defaults/main.yml` adhering to `data-model.md` constraints: `redis_install_repo: false`, `redis_package_state: "present"`, `redis_service_enabled: true`, `redis_service_state: "started"`, `redis_bind: "127.0.0.1 -::1"`, `redis_port: 6379`, `redis_protected_mode: true`, `redis_password: ""`, `redis_no_log: true`, `redis_tcp_backlog: 511`, `redis_timeout: 0`, `redis_tcp_keepalive: 300`, `redis_databases: 16`, `redis_loglevel: "notice"`, `redis_logfile: ""`, `redis_dir: "/var/lib/redis"`, `redis_save: ["3600 1", "300 100", "60 10000"]`, `redis_appendonly: false`, `redis_maxmemory: ""`, `redis_maxmemory_policy: "noeviction"`, `redis_extra_config: {}`, and `redis_sysctl: false`
- [X] T009 [P] Implement service restart handler grouped under `listen: "restart redis"` in `roles/redis/handlers/main.yml`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Deploy and Run Redis Open Source on Target Hosts (Priority: P1) 🎯 MVP

**Goal**: Install the Redis Open Source server package across Debian and RedHat distributions, create configuration and data directories with proper permissions, render baseline `redis.conf`, and enable/start the systemd service idempotently.

**Independent Test**: Apply the role to a clean Linux host with default settings, verify the Redis package is installed, confirm `redis_service_name` is active and enabled, verify local `redis-cli ping` returns `PONG` on port 6379, and confirm a second run produces `changed=0`.

### Implementation for User Story 1

- [X] T010 [P] [US1] Create the primary configuration template in `roles/redis/templates/redis.conf.j2` configuring `bind`, `port`, `protected-mode`, `supervised systemd`, `daemonize no`, `dir`, `logfile`, `tcp-backlog`, `timeout`, `tcp-keepalive`, `databases`, `loglevel`, `save`, `appendonly`, `maxmemory`, `maxmemory-policy`, and `redis_extra_config`
- [X] T011 [US1] Implement optional upstream repository setup in `roles/redis/tasks/repo-Debian.yml` (APT signing key and deb repository for packages.redis.io) and `roles/redis/tasks/repo-RedHat.yml` (RPM repository for packages.redis.io)
- [X] T012 [US1] Implement `roles/redis/tasks/install.yml` to optionally include repo tasks when `redis_install_repo: true`, install `{{ redis_package_name }}` (`state: {{ redis_package_state }}`), and ensure `{{ redis_dir }}` and `/var/log/redis` exist with appropriate owner and mode
- [X] T013 [US1] Implement `roles/redis/tasks/configure.yml` to render `{{ redis_config_file }}` (`owner: {{ redis_config_owner }}`, `group: {{ redis_config_group }}`, `mode: {{ redis_config_mode }}`, notifying `"restart redis"`), flush handlers if needed, and ensure `{{ redis_service_name }}` is enabled and started
- [X] T014 [US1] Implement `roles/redis/tasks/main.yml` with platform assertion (`ansible_os_family in ['Debian', 'RedHat']`), input validation assertions for `redis_port` and other core inputs, OS variable loading (`{{ ansible_os_family }}.yml`), and inclusion of `install.yml` and `configure.yml`
- [X] T015 [US1] Configure baseline `roles/redis/molecule/default/converge.yml` and `roles/redis/molecule/default/verify.yml` to converge `hifra01.utils.redis` and verify service active/enabled state, port 6379 listening, and `redis-cli ping` returning `PONG`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Configure Redis Password Authentication (Priority: P2)

**Goal**: Configure and enforce password authentication via `requirepass` in `redis.conf` with restricted file permissions (`0640`), task log/diff suppression (`redis_no_log: true`), and support for unauthenticated or updated password states.

**Independent Test**: Set `redis_password: "MoleculeSecretPassword123!"`, apply the role, verify unauthenticated `redis-cli ping` fails with `NOAUTH Authentication required`, verify authenticated `redis-cli -a MoleculeSecretPassword123! ping` succeeds with `PONG`, and verify `/etc/redis/redis.conf` has permissions `0640`.

### Implementation for User Story 2

- [X] T016 [US2] Update `roles/redis/templates/redis.conf.j2` to conditionally render `requirepass {{ redis_password | quote }}` when `redis_password | length > 0`, and omit `requirepass` when `redis_password | length == 0`
- [X] T017 [US2] Update `roles/redis/tasks/configure.yml` to set `no_log: "{{ redis_no_log and (redis_password | length > 0) }}"` on the `redis.conf` template task and ensure file mode `'0640'` is enforced
- [X] T018 [US2] Extend `roles/redis/molecule/default/converge.yml` and `roles/redis/molecule/default/verify.yml` to converge with a test password (`redis_password: "MoleculeSecretPassword123!"`), assert that unauthenticated commands fail with `NOAUTH`, authenticated commands succeed with `PONG`, and verify `0640` file permissions on `redis.conf`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Customize Network Binding, Memory Policy, and Persistence Settings (Priority: P3)

**Goal**: Allow operators to customize network binding, memory limits/policies, RDB/AOF persistence, extra raw directives, and optional host kernel sysctl tuning (`redis_sysctl: true`).

**Independent Test**: Configure custom `redis_bind`, `redis_maxmemory`, `redis_maxmemory_policy`, `redis_appendonly`, and `redis_sysctl: true`, apply the role, and verify via `redis-cli CONFIG GET` and sysctl checks that parameters match.

### Implementation for User Story 3

- [X] T019 [US3] Implement `roles/redis/tasks/sysctl.yml` using `ansible.posix.sysctl` to set `vm.overcommit_memory = 1` and `net.core.somaxconn = 512` when `redis_sysctl: true` (with error handling for container environments) and include it from `roles/redis/tasks/main.yml`
- [X] T020 [US3] Verify that `roles/redis/templates/redis.conf.j2` properly formats custom `redis_bind` (string or list), `redis_save` entries, `redis_appendonly`, `redis_maxmemory`, `redis_maxmemory_policy`, and iterates `redis_extra_config` directives
- [X] T021 [US3] Extend `roles/redis/molecule/default/verify.yml` to assert that custom configuration parameters (`maxmemory`, `maxmemory-policy`, `appendonly`) are verified through `redis-cli CONFIG GET`

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Role documentation, CI matrix registration, linting, and full 5-distro Molecule verification

- [X] T022 [P] Write comprehensive role documentation (description, supported platforms, requirements, role variables with defaults, example playbooks with and without password, license) in `roles/redis/README.md`
- [X] T023 [P] Add the `redis` role to the Roles table in `AGENTS.md`
- [X] T024 [P] Register `redis` in all four required locations (`detect-changes.outputs`, `paths-filter` `filters`, `molecule.strategy.matrix.role`, and the role-check `case` statement) in `.github/workflows/ci.yml`
- [X] T025 Run `yamllint .` and `ansible-lint` from the repository root and fix any warnings or errors across `roles/redis/`, `AGENTS.md`, and `.github/workflows/ci.yml`
- [X] T026 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from `roles/redis/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational (Phase 2) completion
  - User Story 1 (Phase 3) provides the baseline role installation and execution (MVP)
  - User Story 2 (Phase 4) builds on User Story 1 by configuring password authentication and `0640` security
  - User Story 3 (Phase 5) builds on User Story 1 & 2 by tuning network, persistence, memory, and sysctl
- **Polish (Phase 6)**: Depends on all user stories (Phase 3-5) being complete

### Parallel Opportunities

- Within Phase 1: `T004` [P] (`prepare.yml`) can be developed in parallel with `T003` (`molecule.yml`).
- Within Phase 2: `T005` [P] (`meta/main.yml`), `T006` [P] (`vars/Debian.yml`), `T007` [P] (`vars/RedHat.yml`), and `T009` [P] (`handlers/main.yml`) can be implemented in parallel.
- Within Phase 3: `T010` [P] (`redis.conf.j2`) can be created in parallel with `T011` (`repo-*.yml`).
- Within Phase 6: `T022` [P] (`README.md`), `T023` [P] (`AGENTS.md`), and `T024` [P] (`ci.yml`) can be edited in parallel before running linters (`T025`) and Molecule tests (`T026`).

---

## Parallel Example: User Story 1 & Foundational

```bash
# Foundational tasks that can run in parallel:
Task: "Populate Galaxy metadata in roles/redis/meta/main.yml"
Task: "Define Debian-family variables in roles/redis/vars/Debian.yml"
Task: "Define RedHat-family variables in roles/redis/vars/RedHat.yml"
Task: "Implement service restart handler in roles/redis/handlers/main.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001` - `T004`)
2. Complete Phase 2: Foundational (`T005` - `T009`)
3. Complete Phase 3: User Story 1 (`T010` - `T015`)
4. **STOP and VALIDATE**: Run `molecule converge && molecule verify` to test User Story 1 independently.

### Incremental Delivery

1. Setup + Foundational → Role skeleton, metadata, OS vars, handlers ready.
2. User Story 1 → Package installed, service running, `redis-cli ping` works (MVP).
3. User Story 2 → Password authentication (`requirepass`), `0640` permissions, and `no_log` protection.
4. User Story 3 → Advanced network binding, memory limits, persistence, and `redis_sysctl` tuning.
5. Polish → Documentation (`README.md`, `AGENTS.md`), CI registration, lint clean, and 5-distro container verification.
