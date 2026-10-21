---

description: "Task list for HashiCorp Consul Role (consul) implementation"
---

# Tasks: HashiCorp Consul Role (`consul`)

**Input**: Design documents from `/specs/001-consul-role/`

**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule verification (`molecule test` across all 5 CI images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Ansible role**: `roles/consul/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)
- **CI workflow**: `.github/workflows/ci.yml`
- **Repository documentation**: `AGENTS.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the role and Molecule scenario using official CLI tools per Constitution Principle II

- [X] T001 Scaffold the `consul` role skeleton using `ansible-galaxy role init --init-path roles consul` to create `roles/consul/`
- [X] T002 Remove the unused generated `roles/consul/files/` directory and initialize the default Molecule scenario using `molecule init scenario default` inside `roles/consul/molecule/default/`
- [X] T003 Remove any generated `roles/consul/molecule/default/create.yml` or `roles/consul/molecule/default/destroy.yml` and configure the Docker systemd driver in `roles/consul/molecule/default/molecule.yml` using `roles/docker/molecule/default/molecule.yml` as baseline
- [X] T004 [P] Create `roles/consul/molecule/default/prepare.yml` with the RHEL 8 `python39` bootstrap and a pre-existing stale service fixture at `/etc/consul.d/service-stale.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core metadata, OS variables, defaults, repository setup, package installation, and validation handlers that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Populate Galaxy metadata (`author`, `description`, `license`, `min_ansible_version: "2.15"`, `platforms` for Debian/Ubuntu/EL 8-9, and `galaxy_tags`) in `roles/consul/meta/main.yml`
- [X] T006 [P] Define Debian-family prerequisite packages (`apt-transport-https`, `ca-certificates`, `curl`, `gnupg`) and `consul_service_name: "consul"` in `roles/consul/vars/Debian.yml`
- [X] T007 [P] Define RedHat-family prerequisite packages (`yum-utils`, `ca-certificates`, `curl`) and `consul_service_name: "consul"` in `roles/consul/vars/RedHat.yml`
- [X] T008 Define all `consul_*` user-tunable default variables in `roles/consul/defaults/main.yml` adhering to `data-model.md` constraints: `consul_mode: "client"` (`Must be "server" or "client"`), `consul_bootstrap_expect: 1` (`Integer >= 1; omitted from config when consul_mode == 'client'`), `consul_datacenter: "dc1"` (`Non-empty string`), `consul_node_name: "{{ inventory_hostname }}"` (`Non-empty string`), `consul_data_dir: "/opt/consul"` (`Absolute path`), `consul_config_dir: "/etc/consul.d"` (`Absolute path`), `consul_bind_addr: "0.0.0.0"` (`Valid IPv4/IPv6 address or Go-sockaddr template`), `consul_advertise_addr: "{{ ansible_default_ipv4.address | default('127.0.0.1') }}"` (`Valid routable/private IPv4/IPv6 address`), `consul_client_addr: "127.0.0.1"` (`Valid IPv4/IPv6 address list`), `consul_ui: false` (`Boolean (true / false)`), `consul_log_level: "INFO"` (`One of "TRACE", "DEBUG", "INFO", "WARN", "ERR"`), `consul_retry_join: []` (`List of peer IPs, DNS names, or cloud auto-join expressions`), `consul_encrypt: ""` (`Optional 32-byte base64-encoded gossip key`), `consul_extra_config: {}` (`Arbitrary top-level Consul configuration key-value map`), `consul_services: []`, `consul_services_purge: true`, `consul_package_name: "consul"`, `consul_package_state: "present"` (`"present" or "latest"`), and repository URLs/architecture mappings
- [X] T009 [P] Implement official HashiCorp APT repository and GPG keyring setup in `roles/consul/tasks/setup-Debian.yml`
- [X] T010 [P] Implement official HashiCorp YUM/DNF repository setup in `roles/consul/tasks/setup-RedHat.yml`
- [X] T011 Implement Consul package installation and `/etc/consul.d` + `/opt/consul` directory ownership/permissions (`consul:consul`, mode `'0750'`) in `roles/consul/tasks/install.yml`
- [X] T012 [P] Implement `consul validate {{ consul_config_dir }}` and service reload/restart handlers grouped under `listen: "validate and reload consul"` and `listen: "validate and restart consul"` in `roles/consul/handlers/main.yml`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Deploy Consul Agent as Server or Client (Priority: P1) 🎯 MVP

**Goal**: Allow operators to install HashiCorp Consul on Debian and RedHat family hosts and run the agent in either `server` mode (with configurable `consul_bootstrap_expect`) or `client` mode (`server = false`, `bootstrap_expect` omitted).

**Independent Test**: Provision a host in `server` mode (`consul_bootstrap_expect: 1`) or `client` mode, verify the `consul` systemd service is enabled and active, confirm `consul members` reports the active node, and verify a second converge run produces `changed=0`.

### Implementation for User Story 1

- [X] T013 [P] [US1] Create the core agent configuration template in `roles/consul/templates/consul.hcl.j2` rendering `datacenter`, `node_name`, `data_dir`, `log_level`, `server = true` with `bootstrap_expect = {{ consul_bootstrap_expect }}` when `consul_mode == 'server'`, and `server = false` (omitting `bootstrap_expect`) when `consul_mode == 'client'`
- [X] T014 [US1] Implement `roles/consul/tasks/configure.yml` to render `{{ consul_config_dir }}/consul.hcl` (owner `{{ consul_user }}`, group `{{ consul_group }}`, mode `'0640'`, notifying `"validate and restart consul"`), flush handlers when needed, and ensure `{{ consul_service_name }}` is enabled and started
- [X] T015 [US1] Implement `roles/consul/tasks/main.yml` with platform assertion (`ansible_os_family in ['Debian', 'RedHat']`), input assertions (`consul_mode` `Must be "server" or "client"`, `consul_bootstrap_expect` `Integer >= 1` when `consul_mode == 'server'`), OS variable loading (`{{ ansible_os_family }}.yml`), OS repository dispatch (`setup-{{ ansible_os_family }}.yml`), `install.yml`, and `configure.yml`
- [X] T016 [US1] Configure `roles/consul/molecule/default/converge.yml` and `roles/consul/molecule/default/verify.yml` to converge `hifra01.utils.consul` in `server` mode and verify package installation, `consul.hcl` permissions, `consul validate`, `consul.service` active status, `consul members` output, and `client` mode configuration rendering

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Advertise Node Services on Each Host (Priority: P2)

**Goal**: Allow operators to define per-host advertised services via `consul_services` (with `name`, `id`, `port`, `address`, `tags`, `meta`, and `checks`), render each service to `{{ consul_config_dir }}/service-<id>.json`, purge removed service files when `consul_services_purge: true`, and reload Consul without a full process restart.

**Independent Test**: Provide multiple services in `consul_services` on a node, converge the role, verify via `http://127.0.0.1:8500/v1/agent/services` that all declared services and metadata are registered, and confirm that `/etc/consul.d/service-stale.json` was purged.

### Implementation for User Story 2

- [X] T017 [P] [US2] Create the advertised service template in `roles/consul/templates/service.json.j2` serializing a `service` JSON object supporting `name` (`Non-empty service name ([a-zA-Z0-9_-]+)`), `id` (defaulting to `consul_service.name`, `Unique service instance ID on this host; safe filename characters ([a-zA-Z0-9_-]+)`), optional `port` (`Integer between 1 and 65535 if specified`), optional `address` (`Optional IP/hostname override for the service`), optional `tags` (`List of string tags`), optional `meta` (`Key-value metadata strings`), and optional `checks` (`id`, `name`, mutually exclusive `http` / `tcp` / `args`, `interval` default `"10s"`, `timeout` default `"2s"`, `deregister_critical_service_after`)
- [X] T018 [US2] Implement `roles/consul/tasks/services.yml` to validate `consul_services` items against `data-model.md` constraints, render each service to `{{ consul_config_dir }}/service-{{ consul_service.id | default(consul_service.name) }}.json` using `loop_control.loop_var: consul_service` (owner `{{ consul_user }}`, group `{{ consul_group }}`, mode `'0640'`, notifying `"validate and reload consul"`), and purge unmanaged `service-*.json` files when `consul_services_purge` is `true`
- [X] T019 [US2] Include `services.yml` from `roles/consul/tasks/main.yml` prior to starting/ensuring the `consul` service
- [X] T020 [US2] Extend `roles/consul/molecule/default/converge.yml` and `roles/consul/molecule/default/verify.yml` with `consul_services` definitions (`web` and `redis` services with tags, metadata, and health checks) and verify registration via `/v1/agent/services` and removal of `/etc/consul.d/service-stale.json`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Configure Cluster Joining, Networking, and UI Access (Priority: P3)

**Goal**: Allow operators to customize `consul_bind_addr`, `consul_advertise_addr`, `consul_client_addr`, `consul_retry_join`, `consul_ui`, `consul_encrypt`, and `consul_extra_config` for multi-node cluster networking and Web UI access.

**Independent Test**: Override network bind/advertise/client addresses, `consul_retry_join`, `consul_ui: true`, and `consul_extra_config`, converge the role, and verify that `consul.hcl` and `extra.json` reflect those settings, pass `consul validate`, and expose the Consul HTTP UI/API.

### Implementation for User Story 3

- [X] T021 [P] [US3] Update `roles/consul/templates/consul.hcl.j2` to render `bind_addr`, `advertise_addr`, `client_addr`, `ui_config { enabled = ... }`, conditional `retry_join` list, and conditional `encrypt` key
- [X] T022 [US3] Update `roles/consul/tasks/configure.yml` to render `{{ consul_config_dir }}/extra.json` (mode `'0640'`, owner `{{ consul_user }}`, group `{{ consul_group }}`) when `consul_extra_config` is non-empty and remove `{{ consul_config_dir }}/extra.json` when `consul_extra_config` is empty, notifying `"validate and restart consul"`
- [X] T023 [US3] Extend `roles/consul/molecule/default/converge.yml` and `roles/consul/molecule/default/verify.yml` to test `consul_ui: true`, custom `consul_datacenter`, `consul_bind_addr`, `consul_client_addr`, `consul_retry_join`, and verify UI/API reachability and rendered `consul.hcl` directives

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, CI workflow registration, linting, and full 5-distro Molecule verification

- [X] T024 [P] Write complete role documentation (description, supported platforms, requirements, role variables with defaults, server/client and service advertisement playbook examples, license) in `roles/consul/README.md`
- [X] T025 [P] Add the `consul` role to the Roles table in `AGENTS.md`
- [X] T026 Register `consul` in all four required locations (`detect-changes.outputs`, `paths-filter` `filters`, `molecule.strategy.matrix.role`, and the role check `case` statement) in `.github/workflows/ci.yml`
- [X] T027 Run `yamllint .` and `ansible-lint` from the repository root and fix any warnings or errors across `roles/consul/` and `.github/workflows/ci.yml`
- [X] T028 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from `roles/consul/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational phase completion
  - User Story 1 (P1): Base server/client agent deployment (`consul.hcl` & `configure.yml`)
  - User Story 2 (P2): Advertised service definitions (`service.json.j2` & `services.yml`)
  - User Story 3 (P3): Cluster joining, networking, UI config, and `extra.json` (`consul.hcl.j2` & `configure.yml`)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start immediately after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2); integrates cleanly into `roles/consul/tasks/main.yml` alongside US1
- **User Story 3 (P3)**: Extends `roles/consul/templates/consul.hcl.j2` and `roles/consul/tasks/configure.yml` created in US1

### Parallel Opportunities

- In **Phase 2 (Foundational)**: `T005` (`meta/main.yml`), `T006` (`vars/Debian.yml`), `T007` (`vars/RedHat.yml`), `T009` (`tasks/setup-Debian.yml`), `T010` (`tasks/setup-RedHat.yml`), and `T012` (`handlers/main.yml`) touch distinct files and can be implemented in parallel.
- Across **User Stories**: `T013` (`templates/consul.hcl.j2`) and `T017` (`templates/service.json.j2`) touch separate templates and can be developed in parallel after Phase 2.
- In **Phase 6 (Polish)**: `T024` (`roles/consul/README.md`), `T025` (`AGENTS.md`), and `T026` (`.github/workflows/ci.yml`) touch independent files and can run in parallel before linting (`T027`) and Molecule matrix testing (`T028`).

---

## Parallel Example: Foundational & Story Templates

```bash
# Launch parallel Foundational tasks (Phase 2):
Task: "T005 [P] Populate Galaxy metadata in roles/consul/meta/main.yml"
Task: "T006 [P] Define Debian-family prerequisite packages in roles/consul/vars/Debian.yml"
Task: "T007 [P] Define RedHat-family prerequisite packages in roles/consul/vars/RedHat.yml"
Task: "T009 [P] Implement official HashiCorp APT repository setup in roles/consul/tasks/setup-Debian.yml"
Task: "T010 [P] Implement official HashiCorp YUM/DNF repository setup in roles/consul/tasks/setup-RedHat.yml"
Task: "T012 [P] Implement consul validate and reload/restart handlers in roles/consul/handlers/main.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`–`T004`)
2. Complete Phase 2: Foundational (`T005`–`T012`)
3. Complete Phase 3: User Story 1 (`T013`–`T016`)
4. **STOP and VALIDATE**: Converge and verify server/client deployment via Molecule

### Incremental Delivery

1. Complete Setup + Foundational → Package repo, installation, defaults, and handlers ready
2. Add User Story 1 → Server/Client agent deployment working → Verify via Molecule (MVP!)
3. Add User Story 2 → Per-host service advertisement and orphan purge working → Verify via Molecule catalog API
4. Add User Story 3 → Cluster joining, network bindings, UI, and `extra.json` working → Verify via Molecule
5. Complete Polish → Docs, CI registration, `yamllint .`, `ansible-lint`, and full 5-distro Molecule test loop
