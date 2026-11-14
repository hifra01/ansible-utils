---
description: "Task list for Prometheus NGINX Exporter Role (nginx_exporter) and companion nginx stub_status implementation"
---

# Tasks: Prometheus NGINX Exporter Role (`nginx_exporter`)

**Input**: Design documents from `/specs/009-nginx-exporter-role/`

**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule verification (`molecule test` across all 5 CI images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **New Ansible role**: `roles/nginx_exporter/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)
- **Companion Ansible role**: `roles/nginx/` (`defaults/`, `tasks/`, `templates/`, `molecule/default/`, `README.md`)
- **CI workflow**: `.github/workflows/ci.yml`
- **Repository documentation**: `AGENTS.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the `nginx_exporter` role and Molecule scenario using official CLI tools per Constitution Principle II

- [X] T001 Scaffold the `nginx_exporter` role skeleton using `ansible-galaxy role init --init-path roles nginx_exporter` to create `roles/nginx_exporter/`
- [X] T002 Remove the unused generated `roles/nginx_exporter/files/` directory and initialize the default Molecule scenario using `molecule init scenario default` inside `roles/nginx_exporter/molecule/default/`
- [X] T003 Remove any generated `roles/nginx_exporter/molecule/default/create.yml` or `roles/nginx_exporter/molecule/default/destroy.yml` and configure the Docker systemd driver in `roles/nginx_exporter/molecule/default/molecule.yml` using `roles/node_exporter/molecule/default/molecule.yml` as baseline
- [X] T004 [P] Create `roles/nginx_exporter/molecule/default/prepare.yml` with the RHEL 8 `python39` bootstrap tasks

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core metadata, OS variables, defaults, and validation/restart handlers that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Populate Galaxy metadata (`author`, `description`, `license`, `min_ansible_version: "2.21.0"`, `platforms` for Debian/Ubuntu/EL 8-9, and `galaxy_tags`) in `roles/nginx_exporter/meta/main.yml`
- [X] T006 [P] Define Debian-family prerequisite packages (`ca-certificates`, `curl`, `tar`), `nginx_exporter_service_name: "nginx_exporter"`, and `nginx_exporter_nologin_shell: "/usr/sbin/nologin"` in `roles/nginx_exporter/vars/Debian.yml`
- [X] T007 [P] Define RedHat-family prerequisite packages (`ca-certificates`, `tar`), `nginx_exporter_service_name: "nginx_exporter"`, and `nginx_exporter_nologin_shell: "/sbin/nologin"` in `roles/nginx_exporter/vars/RedHat.yml`
- [X] T008 Define all `nginx_exporter_*` user-tunable default variables in `roles/nginx_exporter/defaults/main.yml` adhering to `data-model.md` constraints: `nginx_exporter_version: "1.4.1"` (`Non-empty semantic version string (X.Y.Z, without leading v)`), `nginx_exporter_checksum: ""` (`Optional 64-character hex SHA256 digest; when empty "", resolved dynamically from nginx_exporter_checksums_url`), `nginx_exporter_arch_map` (`Mapping from ansible_architecture to upstream release archive suffix`: `x86_64: amd64`, `aarch64: arm64`, `armv7l: armv7`), `nginx_exporter_download_url` (`Valid HTTP/HTTPS URL to .tar.gz release archive`), `nginx_exporter_checksums_url` (`Valid HTTP/HTTPS URL to upstream checksums.txt`), `nginx_exporter_bin_dir: "/usr/local/bin"` (`Absolute directory path (^/)`), `nginx_exporter_config_dir: "/etc/nginx_exporter"` (`Absolute directory path (^/)`), `nginx_exporter_system_user: "nginx_exporter"` (`Non-empty Linux username`), `nginx_exporter_system_group: "nginx_exporter"` (`Non-empty Linux group name`), `nginx_exporter_web_listen_address: "0.0.0.0:9113"` (`Non-empty [host]:port string`), `nginx_exporter_web_telemetry_path: "/metrics"` (`Non-empty URL path starting with /`), `nginx_exporter_scrape_uri: "http://127.0.0.1:8080/stub_status"` (`Non-empty string or non-empty list of strings representing http://, https://, or unix: NGINX status URI(s)`), `nginx_exporter_nginx_plus: false` (`Boolean (true passes --nginx.plus)`), `nginx_exporter_ssl_verify: true` (`Boolean (true passes --nginx.ssl-verify, false passes --no-nginx.ssl-verify)`), `nginx_exporter_timeout: "5s"` (`Non-empty Go duration string (e.g., "5s", "10s")`), `nginx_exporter_extra_flags: []` (`List of raw CLI flag strings (["--log.level=info"])`), `nginx_exporter_web_config: {}` (`Dictionary matching Prometheus exporter-toolkit web-config.yml schema (tls_server_config, http_server_config, basic_auth_users)`), `nginx_exporter_service_enabled: true` (`Boolean to enable nginx_exporter.service at boot`), and `nginx_exporter_service_state: "started"` (`Desired systemd service state ("started" or "stopped")`)
- [X] T009 [P] Implement systemd daemon reload, binary validation (`{{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter --version`), and service restart handlers grouped under `listen: "validate and restart nginx_exporter"` in `roles/nginx_exporter/handlers/main.yml`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Deploy and Run Prometheus NGINX Exporter on Target Hosts (Priority: P1) 🎯 MVP

**Goal**: Install the `nginx-prometheus-exporter` binary from official GitHub Releases with SHA256 verification, provision the unprivileged `nginx_exporter` system user and group, and manage the `nginx_exporter.service` systemd daemon idempotently across Debian and RedHat family hosts.

**Independent Test**: Apply the role to a clean Linux host, verify `/usr/local/bin/nginx-prometheus-exporter` is installed with mode `'0755'` and matches `nginx_exporter_version`, confirm `nginx_exporter.service` is active and enabled, verify an HTTP GET request to `http://127.0.0.1:9113/metrics` returns HTTP `200` with `nginx_up` and exporter build metrics, and confirm a second run produces `changed=0`.

### Implementation for User Story 1

- [X] T010 [P] [US1] Create the systemd unit template in `roles/nginx_exporter/templates/nginx_exporter.service.j2` configuring `User={{ nginx_exporter_system_user }}`, `Group={{ nginx_exporter_system_group }}`, and `ExecStart={{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter` with `--web.listen-address={{ nginx_exporter_web_listen_address }}`, `--web.telemetry-path={{ nginx_exporter_web_telemetry_path }}`, `--nginx.scrape-uri` (supporting string or sequence), and `--nginx.timeout={{ nginx_exporter_timeout }}`
- [X] T011 [US1] Implement `roles/nginx_exporter/tasks/install.yml` to update apt cache on Debian family, install `nginx_exporter_prerequisite_packages`, create `nginx_exporter_system_group` and `nginx_exporter_system_user` (`system: true`, `shell: "{{ nginx_exporter_nologin_shell }}"`, `create_home: false`), check installed `{{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter --version` output to avoid redundant downloads, download and SHA256-verify the release tarball (`sha256:{{ nginx_exporter_checksum if (nginx_exporter_checksum | length > 0) else nginx_exporter_checksums_url }}`), extract and install `{{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter` (`owner: root`, `group: root`, `mode: '0755'`, notifying `"validate and restart nginx_exporter"`), and clean up temporary archive files
- [X] T012 [US1] Implement `roles/nginx_exporter/tasks/configure.yml` to render `/etc/systemd/system/nginx_exporter.service` (`owner: root`, `group: root`, `mode: '0644'`, notifying `"validate and restart nginx_exporter"`), flush handlers, and ensure `{{ nginx_exporter_service_name }}` matches `nginx_exporter_service_enabled` and `nginx_exporter_service_state`
- [X] T013 [US1] Implement `roles/nginx_exporter/tasks/main.yml` with platform assertion (`ansible_facts['os_family'] in ['Debian', 'RedHat']`), architecture assertion (`ansible_facts['architecture'] in ['x86_64', 'aarch64', 'armv7l']`), input validation assertions for all `nginx_exporter_*` variables per `data-model.md`, OS variable loading (`{{ ansible_facts['os_family'] }}.yml`), `install.yml`, and `configure.yml`

**Checkpoint**: At this point, User Story 1 is functional and ready for integration with `stub_status` and custom security configurations

---

## Phase 4: User Story 2 - Enable `stub_status` in the `nginx` Role for Seamless Composition (Priority: P2)

**Goal**: Provide a first-class opt-in `nginx_stub_status_enabled` toggle in `roles/nginx` that renders `/etc/nginx/conf.d/stub_status.conf`, disables access logging for scrape requests by default (`nginx_stub_status_access_log: "off"`), and excludes `stub_status.conf` from unused site cleanup on both Debian and RedHat families.

**Independent Test**: Apply `hifra01.utils.nginx` with `nginx_stub_status_enabled: true`, verify `/etc/nginx/conf.d/stub_status.conf` is rendered and preserved across unused site cleanup, confirm `http://127.0.0.1:<port>/stub_status` returns HTTP `200` with `Active connections:`, and verify setting `nginx_stub_status_enabled: false` removes `/etc/nginx/conf.d/stub_status.conf`.

### Implementation for User Story 2

- [X] T014 [P] [US2] Add `nginx_stub_status_*` default variables to `roles/nginx/defaults/main.yml` adhering to `data-model.md` constraints: `nginx_stub_status_enabled: false` (`Boolean (true renders /etc/nginx/conf.d/stub_status.conf; false ensures it is absent)`), `nginx_stub_status_host: "127.0.0.1"` (`Non-empty IP address or hostname to bind`), `nginx_stub_status_port: 8080` (`Valid TCP port (1..65535)`), `nginx_stub_status_path: "/stub_status"` (`Non-empty URL path starting with /`), `nginx_stub_status_allow: ["127.0.0.1", "::1"]` (`Sequence of allowed client IP addresses or CIDR blocks before deny all;`), and `nginx_stub_status_access_log: "off"` (`Non-empty string for the access_log directive inside the stub_status location`)
- [X] T015 [P] [US2] Create `roles/nginx/templates/stub_status.conf.j2` rendering the `server` block on `{{ nginx_stub_status_host }}:{{ nginx_stub_status_port }}` and `location {{ nginx_stub_status_path }}` with `stub_status;`, `access_log {{ nginx_stub_status_access_log }};`, `allow` rules for `nginx_stub_status_allow`, and `deny all;`
- [X] T016 [US2] Update `roles/nginx/tasks/main.yml` to assert valid `nginx_stub_status_*` inputs, render `{{ nginx_config_dir }}/conf.d/stub_status.conf` (`mode: '0644'`, notifying `"validate and reload nginx"`) when `nginx_stub_status_enabled | bool`, ensure `{{ nginx_config_dir }}/conf.d/stub_status.conf` is `absent` (notifying `"validate and reload nginx"`) when `not (nginx_stub_status_enabled | bool)`, and add `'stub_status.conf'` to the exclusion list in `Clean up unused site configurations`
- [X] T017 [US2] Update `roles/nginx/molecule/default/converge.yml` and `roles/nginx/molecule/default/verify.yml` to enable `nginx_stub_status_enabled: true` (on port `8085` to avoid colliding with the existing `cf_protected` test vhost on port `8080`), assert `/etc/nginx/conf.d/stub_status.conf` content (`stub_status;`, `access_log off;`, `allow 127.0.0.1;`) and HTTP `200` `Active connections:` response on `http://127.0.0.1:8085/stub_status`, and verify `stub_status.conf` is removed when `nginx_stub_status_enabled: false`

**Checkpoint**: At this point, `roles/nginx` supports `stub_status` cleanly across Debian and RedHat without cleanup conflicts

---

## Phase 5: User Story 3 - Customize Scrape Targets, Listen Address, and Web Security (Priority: P3)

**Goal**: Allow operators to customize scrape URI(s) (`nginx_exporter_scrape_uri` as string or list), NGINX Plus / SSL verify / timeout / extra CLI flags, and optional TLS / HTTP Basic Authentication (`nginx_exporter_web_config` rendered to `{{ nginx_exporter_config_dir }}/config.yml`), and verify full end-to-end composition of `hifra01.utils.nginx` + `hifra01.utils.nginx_exporter` in Molecule.

**Independent Test**: Converge `hifra01.utils.nginx` (`nginx_stub_status_enabled: true`) alongside `hifra01.utils.nginx_exporter` with `nginx_exporter_web_config` (`basic_auth_users`) and `nginx_exporter_extra_flags`, verify `/etc/nginx_exporter/config.yml` mode `'0640'` (`root:{{ nginx_exporter_system_group }}`), confirm unauthenticated requests to `:9113/metrics` return `401 Unauthorized` while authenticated requests return `200 OK` with `nginx_up 1`, `nginx_connections_accepted`, `nginx_connections_active`, and `nginx_http_requests_total`, and confirm resetting `nginx_exporter_web_config: {}` removes `/etc/nginx_exporter/config.yml` and serves `:9113/metrics` (`200 OK`, `nginx_up 1`) without credentials.

### Implementation for User Story 3

- [X] T018 [P] [US3] Create the web configuration template in `roles/nginx_exporter/templates/config.yml.j2` serializing `nginx_exporter_web_config` (`tls_server_config`, `http_server_config`, `basic_auth_users`) as YAML
- [X] T019 [US3] Update `roles/nginx_exporter/tasks/configure.yml` and `roles/nginx_exporter/templates/nginx_exporter.service.j2` so that when `nginx_exporter_web_config | length > 0`, `{{ nginx_exporter_config_dir }}` (`mode: '0750'`, `owner: root`, `group: "{{ nginx_exporter_system_group }}"`) and `{{ nginx_exporter_config_dir }}/config.yml` (`mode: '0640'`, `owner: root`, `group: "{{ nginx_exporter_system_group }}"`) are rendered and `--web.config.file={{ nginx_exporter_config_dir }}/config.yml` is passed to `ExecStart`; when `nginx_exporter_web_config | length == 0`, ensure `{{ nginx_exporter_config_dir }}/config.yml` is `absent` and omit `--web.config.file`; also render `--nginx.plus` (when `nginx_exporter_nginx_plus | bool`), `--nginx.ssl-verify` / `--no-nginx.ssl-verify` (per `nginx_exporter_ssl_verify`), and `nginx_exporter_extra_flags`
- [X] T020 [US3] Implement `roles/nginx_exporter/molecule/default/converge.yml` and `roles/nginx_exporter/molecule/default/verify.yml` to converge `hifra01.utils.nginx` (`nginx_stub_status_enabled: true`) and `hifra01.utils.nginx_exporter` (with `nginx_exporter_extra_flags` and `nginx_exporter_web_config.basic_auth_users`), assert binary existence/version, system user/group, systemd unit flags, `config.yml` permissions (`0640`), HTTP `401` unauthenticated / HTTP `200` authenticated scrape with `nginx_up 1`, `nginx_connections_accepted`, `nginx_connections_active`, and `nginx_http_requests_total`, and verify both `config.yml` removal when `nginx_exporter_web_config: {}` and list-form `nginx_exporter_scrape_uri: ["http://127.0.0.1:8080/stub_status"]` rendering in `nginx_exporter.service`

**Checkpoint**: All user stories are now independently functional and verified end-to-end

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, CI workflow registration, linting, and full 5-distro Molecule verification across both roles

- [X] T021 [P] Write complete role documentation (description, supported platforms, requirements, role variables with defaults, single/multi-target and `nginx` composition playbook examples, license) in `roles/nginx_exporter/README.md`
- [X] T022 [P] Update `roles/nginx/README.md` to document the new `nginx_stub_status_*` variables and an example enabling `stub_status` for Prometheus `nginx_exporter`
- [X] T023 [P] Add the `nginx_exporter` role to the Roles table (and update `nginx` description if applicable) in `AGENTS.md`
- [X] T024 [P] Register `nginx_exporter` in all four required locations (`detect-changes.outputs`, `paths-filter` `filters`, `molecule.strategy.matrix.role`, and the role check `case` statement) in `.github/workflows/ci.yml`
- [X] T025 Run `yamllint .` and `ansible-lint` from the repository root and fix any warnings or errors across `roles/nginx_exporter/`, `roles/nginx/`, `AGENTS.md`, and `.github/workflows/ci.yml`
- [X] T026 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from both `roles/nginx/` and `roles/nginx_exporter/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS `nginx_exporter` user stories
- **User Stories (Phase 3–5)**:
  - User Story 1 (P1): Binary download/verification, system user/group, base systemd unit & service lifecycle (`install.yml`, `configure.yml`, `nginx_exporter.service.j2`)
  - User Story 2 (P2): Companion `stub_status` toggle in `roles/nginx` (`defaults/main.yml`, `templates/stub_status.conf.j2`, `tasks/main.yml`, `molecule/default/`) — touches `roles/nginx` and can be implemented in parallel with US1
  - User Story 3 (P3): Custom scrape URIs, flags, `config.yml` web security, and end-to-end Molecule verification combining `hifra01.utils.nginx` (`stub_status`) and `hifra01.utils.nginx_exporter`
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start immediately after Foundational (Phase 2)
- **User Story 2 (P2)**: Modifies `roles/nginx/` only; has no dependency on Phase 2 of `roles/nginx_exporter` and can run in parallel with US1
- **User Story 3 (P3)**: Builds on US1 (`roles/nginx_exporter`) and uses US2 (`hifra01.utils.nginx` with `nginx_stub_status_enabled: true`) in `roles/nginx_exporter/molecule/default/converge.yml`

### Parallel Opportunities

- In **Phase 2 (Foundational)**: `T005` (`meta/main.yml`), `T006` (`vars/Debian.yml`), `T007` (`vars/RedHat.yml`), and `T009` (`handlers/main.yml`) touch distinct files and can be implemented in parallel.
- Across **User Stories**: `T010` (`roles/nginx_exporter/templates/nginx_exporter.service.j2`), `T014` (`roles/nginx/defaults/main.yml`), `T015` (`roles/nginx/templates/stub_status.conf.j2`), and `T018` (`roles/nginx_exporter/templates/config.yml.j2`) touch separate files and can be developed in parallel.
- In **Phase 6 (Polish)**: `T021` (`roles/nginx_exporter/README.md`), `T022` (`roles/nginx/README.md`), `T023` (`AGENTS.md`), and `T024` (`.github/workflows/ci.yml`) touch independent files and can run in parallel before linting (`T025`) and Molecule matrix testing (`T026`).

---

## Parallel Example: Foundational & Cross-Role Tasks

```bash
# Launch parallel Foundational tasks (Phase 2):
Task: "T005 [P] Populate Galaxy metadata in roles/nginx_exporter/meta/main.yml"
Task: "T006 [P] Define Debian-family prerequisite packages in roles/nginx_exporter/vars/Debian.yml"
Task: "T007 [P] Define RedHat-family prerequisite packages in roles/nginx_exporter/vars/RedHat.yml"
Task: "T009 [P] Implement systemd reload, binary validation, and restart handlers in roles/nginx_exporter/handlers/main.yml"

# Launch parallel Polish tasks (Phase 6):
Task: "T021 [P] Write complete role documentation in roles/nginx_exporter/README.md"
Task: "T022 [P] Update roles/nginx/README.md to document nginx_stub_status_* variables"
Task: "T023 [P] Add the nginx_exporter role to the Roles table in AGENTS.md"
Task: "T024 [P] Register nginx_exporter in all four required locations in .github/workflows/ci.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Complete Phase 1: Setup (`T001`–`T004`)
2. Complete Phase 2: Foundational (`T005`–`T009`)
3. Complete Phase 3: User Story 1 (`T010`–`T013`) and Phase 4: User Story 2 (`T014`–`T017`)
4. **STOP and VALIDATE**: Verify `nginx` `stub_status` and `nginx_exporter` service installation

### Incremental Delivery

1. Complete Setup + Foundational → Metadata, OS vars, defaults, and handlers ready
2. Add User Story 1 → `nginx-prometheus-exporter` binary download, SHA256 verification, system user, and systemd unit working
3. Add User Story 2 → `roles/nginx` `stub_status.conf` toggle and cleanup exclusion working across Debian and RedHat
4. Add User Story 3 → Multi-URI scrape support, `/etc/nginx_exporter/config.yml` web security, and full end-to-end Molecule verification (`nginx_up 1`) working
5. Complete Polish → Docs, CI registration, `yamllint .`, `ansible-lint`, and full 5-distro Molecule test loop for both roles
