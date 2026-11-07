---
description: "Task list for Prometheus Node Exporter Role (node_exporter) implementation"
---

# Tasks: Prometheus Node Exporter Role (`node_exporter`)

**Input**: Design documents from `/specs/004-node-exporter-role/`

**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule verification (`molecule test` across all 5 CI images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Ansible role**: `roles/node_exporter/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)
- **CI workflow**: `.github/workflows/ci.yml`
- **Repository documentation**: `AGENTS.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the role and Molecule scenario using official CLI tools per Constitution Principle II

- [X] T001 Scaffold the `node_exporter` role skeleton using `ansible-galaxy role init --init-path roles node_exporter` to create `roles/node_exporter/`
- [X] T002 Remove the unused generated `roles/node_exporter/files/` directory and initialize the default Molecule scenario using `molecule init scenario default` inside `roles/node_exporter/molecule/default/`
- [X] T003 Remove any generated `roles/node_exporter/molecule/default/create.yml` or `roles/node_exporter/molecule/default/destroy.yml` and configure the Docker systemd driver in `roles/node_exporter/molecule/default/molecule.yml` using `roles/datetime/molecule/default/molecule.yml` as baseline
- [X] T004 [P] Create `roles/node_exporter/molecule/default/prepare.yml` with the RHEL 8 `python39` bootstrap tasks

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core metadata, OS variables, defaults, and validation/restart handlers that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Populate Galaxy metadata (`author`, `description`, `license`, `min_ansible_version: "2.21.0"`, `platforms` for Debian/Ubuntu/EL 8-9, and `galaxy_tags`) in `roles/node_exporter/meta/main.yml`
- [X] T006 [P] Define Debian-family prerequisite packages (`ca-certificates`, `curl`, `tar`), `node_exporter_service_name: "node_exporter"`, and `node_exporter_nologin_shell: "/usr/sbin/nologin"` in `roles/node_exporter/vars/Debian.yml`
- [X] T007 [P] Define RedHat-family prerequisite packages (`ca-certificates`, `curl`, `tar`), `node_exporter_service_name: "node_exporter"`, and `node_exporter_nologin_shell: "/sbin/nologin"` in `roles/node_exporter/vars/RedHat.yml`
- [X] T008 Define all `node_exporter_*` user-tunable default variables in `roles/node_exporter/defaults/main.yml` adhering to `data-model.md` constraints: `node_exporter_version: "1.8.2"` (`Non-empty semantic version string (X.Y.Z, without leading v)`), `node_exporter_checksum: ""` (`Optional 64-character hex SHA256 digest; when empty "", resolved dynamically from node_exporter_checksums_url`), `node_exporter_arch_map` (`x86_64: amd64`, `aarch64: arm64`, `armv7l: armv7`), `node_exporter_download_url` (`Valid HTTP/HTTPS URL to .tar.gz release archive`), `node_exporter_checksums_url` (`Valid HTTP/HTTPS URL to upstream sha256sums.txt`), `node_exporter_bin_dir: "/usr/local/bin"` (`Absolute directory path`), `node_exporter_config_dir: "/etc/node_exporter"` (`Absolute directory path`), `node_exporter_system_user: "node_exporter"` (`Non-empty Linux username`), `node_exporter_system_group: "node_exporter"` (`Non-empty Linux group name`), `node_exporter_web_listen_address: "0.0.0.0:9100"` (`Non-empty [host]:port string with valid TCP port (1..65535)`), `node_exporter_web_telemetry_path: "/metrics"` (`Non-empty URL path starting with /`), `node_exporter_textfile_dir: "/var/lib/node_exporter/textfile_collector"` (`Absolute path (or empty string "" to disable automatic textfile directory setup)`), `node_exporter_enabled_collectors: []` (`List of collector names ("systemd") or single-key option dicts ({"filesystem": {"mount-points-exclude": "^/(sys|proc)"}})`), `node_exporter_disabled_collectors: []` (`List of collector name strings (["arp", "bcache"])`), `node_exporter_extra_flags: []` (`List of raw CLI flag strings (["--log.level=info"])`), and `node_exporter_web_config: {}` (`Dictionary matching Prometheus exporter-toolkit web-config.yml schema (tls_server_config, http_server_config, basic_auth_users)`)
- [X] T009 [P] Implement systemd daemon reload, binary validation (`{{ node_exporter_bin_dir }}/node_exporter --version`), and service restart handlers grouped under `listen: "validate and restart node_exporter"` in `roles/node_exporter/handlers/main.yml`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Deploy and Run Node Exporter on Target Hosts (Priority: P1) 🎯 MVP

**Goal**: Install the Prometheus Node Exporter binary from official GitHub Releases with SHA256 verification, provision the unprivileged `node_exporter` system user and group, and manage the `node_exporter.service` systemd daemon idempotently across Debian and RedHat family hosts.

**Independent Test**: Apply the role to a clean Linux host with default settings, verify `/usr/local/bin/node_exporter` is installed with mode `'0755'` and matches `node_exporter_version`, confirm `node_exporter.service` is active and enabled, verify an HTTP GET request to `http://127.0.0.1:9100/metrics` returns HTTP `200` with standard metrics, and confirm a second run produces `changed=0`.

### Implementation for User Story 1

- [X] T010 [P] [US1] Create the systemd unit template in `roles/node_exporter/templates/node_exporter.service.j2` configuring `User={{ node_exporter_system_user }}`, `Group={{ node_exporter_system_group }}`, and `ExecStart={{ node_exporter_bin_dir }}/node_exporter` with `--web.listen-address={{ node_exporter_web_listen_address }}` and `--web.telemetry-path={{ node_exporter_web_telemetry_path }}`
- [X] T011 [US1] Implement `roles/node_exporter/tasks/install.yml` to install `node_exporter_prerequisite_packages`, create `node_exporter_system_group` and `node_exporter_system_user` (`system: true`, `shell: "{{ node_exporter_nologin_shell }}"`, `create_home: false`), check installed `{{ node_exporter_bin_dir }}/node_exporter` version to avoid redundant downloads, download and SHA256-verify the release tarball (`sha256:{{ node_exporter_checksum if node_exporter_checksum | length > 0 else node_exporter_checksums_url }}`), extract and install `{{ node_exporter_bin_dir }}/node_exporter` (`owner: root`, `group: root`, `mode: '0755'`, notifying `"validate and restart node_exporter"`), and clean up temporary archive files
- [X] T012 [US1] Implement `roles/node_exporter/tasks/configure.yml` to render `/etc/systemd/system/node_exporter.service` (`owner: root`, `group: root`, `mode: '0644'`, notifying `"validate and restart node_exporter"`), flush handlers when needed, and ensure `{{ node_exporter_service_name }}` is enabled and started
- [X] T013 [US1] Implement `roles/node_exporter/tasks/main.yml` with platform assertion (`ansible_os_family in ['Debian', 'RedHat']`), architecture assertion (`ansible_architecture in ['x86_64', 'aarch64', 'armv7l']`), input validation assertions for all `node_exporter_*` variables per `data-model.md`, OS variable loading (`{{ ansible_os_family }}.yml`), `install.yml`, and `configure.yml`
- [X] T014 [US1] Configure `roles/node_exporter/molecule/default/converge.yml` and `roles/node_exporter/molecule/default/verify.yml` to converge `hifra01.utils.node_exporter` and verify binary permissions/version, system user/group existence, `node_exporter.service` active/enabled state, and HTTP `200` metrics response on port `9100`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Configure Network Binding and Service Access (Priority: P2)

**Goal**: Allow operators to customize the network listen address/port (`node_exporter_web_listen_address`), telemetry path (`node_exporter_web_telemetry_path`), and optional TLS/basic authentication web security configuration (`node_exporter_web_config` rendered to `{{ node_exporter_config_dir }}/config.yml`).

**Independent Test**: Configure custom listen address/port and `node_exporter_web_config` (such as `basic_auth_users`), apply the role, verify `/etc/node_exporter/config.yml` is rendered with mode `'0640'` (`root:{{ node_exporter_system_group }}`) and `--web.config.file` is active in `node_exporter.service`, confirm unauthenticated HTTP requests receive `401 Unauthorized` while authenticated requests receive `200 OK`, and confirm resetting `node_exporter_web_config: {}` removes `/etc/node_exporter/config.yml` and `--web.config.file`.

### Implementation for User Story 2

- [X] T015 [P] [US2] Create the web configuration template in `roles/node_exporter/templates/config.yml.j2` serializing `node_exporter_web_config` (`tls_server_config`, `http_server_config`, `basic_auth_users`) as YAML
- [X] T016 [US2] Update `roles/node_exporter/tasks/configure.yml` and `roles/node_exporter/templates/node_exporter.service.j2` so that when `node_exporter_web_config` is non-empty, `{{ node_exporter_config_dir }}` (`mode: '0750'`, `owner: root`, `group: "{{ node_exporter_system_group }}"`) and `{{ node_exporter_config_dir }}/config.yml` (`mode: '0640'`, `owner: root`, `group: "{{ node_exporter_system_group }}"`) are rendered and `--web.config.file={{ node_exporter_config_dir }}/config.yml` is passed to `ExecStart`; when `node_exporter_web_config` is empty (`{}`), ensure `{{ node_exporter_config_dir }}/config.yml` is `absent` and omit `--web.config.file`
- [X] T017 [US2] Extend `roles/node_exporter/molecule/default/verify.yml` to test `node_exporter_web_config` with `basic_auth_users` (verifying `/etc/node_exporter/config.yml` mode `'0640'`, HTTP `401` without auth, HTTP `200` with auth) and verify cleanup (`config.yml` removed) when `node_exporter_web_config` is reset to `{}`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Manage Metric Collectors and Custom Textfile Metrics (Priority: P3)

**Goal**: Allow operators to enable or disable specific collectors (`node_exporter_enabled_collectors` supporting both plain strings and single-key option dicts, `node_exporter_disabled_collectors`, and `node_exporter_extra_flags`) and provision the local textfile collector directory (`node_exporter_textfile_dir`) so `.prom` files are exported in `/metrics`.\n\n**Independent Test**: Configure `node_exporter_enabled_collectors` (with both a plain collector string and a parameterized collector dict), `node_exporter_disabled_collectors`, and `node_exporter_textfile_dir`, place a `.prom` file in `/var/lib/node_exporter/textfile_collector/`, and verify that `node_exporter.service` contains the expected `--collector.*` and `--no-collector.*` flags and `/metrics` exports the custom textfile metric.

### Implementation for User Story 3

- [X] T018 [US3] Update `roles/node_exporter/tasks/configure.yml` to create and manage `{{ node_exporter_textfile_dir }}` (and its parent directory) with `owner: "{{ node_exporter_system_user }}"`, `group: "{{ node_exporter_system_group }}"`, and `mode: '0755'` when `node_exporter_textfile_dir | length > 0`
- [X] T019 [US3] Update `roles/node_exporter/templates/node_exporter.service.j2` to render `--collector.textfile` and `--collector.textfile.directory={{ node_exporter_textfile_dir }}` (when `node_exporter_textfile_dir` is non-empty and `"textfile"` is not disabled), iterate `node_exporter_enabled_collectors` (rendering `--collector.<name>` for plain strings and `--collector.<name>` plus `--collector.<name>.<opt>=<val>` for single-key option mappings), iterate `node_exporter_disabled_collectors` (`--no-collector.<name>`), and append `node_exporter_extra_flags`
- [X] T020 [US3] Extend `roles/node_exporter/molecule/default/converge.yml` and `roles/node_exporter/molecule/default/verify.yml` to configure `node_exporter_enabled_collectors`, `node_exporter_disabled_collectors`, and `node_exporter_textfile_dir`, write a sample `.prom` metric file into `/var/lib/node_exporter/textfile_collector/`, and assert that the custom metric and collector flags are active in `/metrics` and `node_exporter.service`

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, CI workflow registration, linting, and full 5-distro Molecule verification

- [X] T021 [P] Write complete role documentation (description, supported platforms, requirements, role variables with defaults, collector/textfile/web_config playbook examples, license) in `roles/node_exporter/README.md`
- [X] T022 [P] Add the `node_exporter` role to the Roles table in `AGENTS.md`
- [X] T023 [P] Register `node_exporter` in all four required locations (`detect-changes.outputs`, `paths-filter` `filters`, `molecule.strategy.matrix.role`, and the role check `case` statement) in `.github/workflows/ci.yml`
- [X] T024 Run `yamllint .` and `ansible-lint` from the repository root and fix any warnings or errors across `roles/node_exporter/`, `AGENTS.md`, and `.github/workflows/ci.yml`
- [X] T025 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from `roles/node_exporter/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational phase completion
  - User Story 1 (P1): Binary download/verification, system user/group, base systemd unit & service lifecycle (`install.yml`, `configure.yml`, `node_exporter.service.j2`)
  - User Story 2 (P2): Network listen socket & optional web security configuration (`config.yml.j2`, `configure.yml`, `node_exporter.service.j2`)
  - User Story 3 (P3): Collector flags & textfile collector directory (`configure.yml`, `node_exporter.service.j2`)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start immediately after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Builds on `configure.yml` and `node_exporter.service.j2` from US1; `templates/config.yml.j2` (`T015`) can be created in parallel with US1
- **User Story 3 (P3)**: Extends `configure.yml` and `node_exporter.service.j2` with collector and textfile directory management

### Parallel Opportunities

- In **Phase 2 (Foundational)**: `T005` (`meta/main.yml`), `T006` (`vars/Debian.yml`), `T007` (`vars/RedHat.yml`), and `T009` (`handlers/main.yml`) touch distinct files and can be implemented in parallel.
- Across **User Stories**: `T010` (`templates/node_exporter.service.j2`) and `T015` (`templates/config.yml.j2`) touch separate template files and can be developed in parallel after Phase 2.
- In **Phase 6 (Polish)**: `T021` (`roles/node_exporter/README.md`), `T022` (`AGENTS.md`), and `T023` (`.github/workflows/ci.yml`) touch independent files and can run in parallel before linting (`T024`) and Molecule matrix testing (`T025`).

---

## Parallel Example: Foundational & Story Templates

```bash
# Launch parallel Foundational tasks (Phase 2):
Task: "T005 [P] Populate Galaxy metadata in roles/node_exporter/meta/main.yml"
Task: "T006 [P] Define Debian-family prerequisite packages in roles/node_exporter/vars/Debian.yml"
Task: "T007 [P] Define RedHat-family prerequisite packages in roles/node_exporter/vars/RedHat.yml"
Task: "T009 [P] Implement systemd reload, binary validation, and restart handlers in roles/node_exporter/handlers/main.yml"

# Launch parallel Polish tasks (Phase 6):
Task: "T021 [P] Write complete role documentation in roles/node_exporter/README.md"
Task: "T022 [P] Add the node_exporter role to the Roles table in AGENTS.md"
Task: "T023 [P] Register node_exporter in all four required locations in .github/workflows/ci.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`–`T004`)
2. Complete Phase 2: Foundational (`T005`–`T009`)
3. Complete Phase 3: User Story 1 (`T010`–`T014`)
4. **STOP and VALIDATE**: Converge and verify Node Exporter service and `/metrics` endpoint via Molecule

### Incremental Delivery

1. Complete Setup + Foundational → Metadata, OS vars, defaults, and handlers ready
2. Add User Story 1 → Binary download, SHA256 verification, system user, and systemd unit working → Verify via Molecule (MVP!)
3. Add User Story 2 → Custom listen binding and `/etc/node_exporter/config.yml` web security working → Verify via Molecule
4. Add User Story 3 → Collector flags (`--collector.*`, `--no-collector.*`) and textfile collector directory working → Verify via Molecule
5. Complete Polish → Docs, CI registration, `yamllint .`, `ansible-lint`, and full 5-distro Molecule test loop
