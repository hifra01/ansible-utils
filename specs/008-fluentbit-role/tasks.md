---
description: "Task list for Fluent Bit Log Collector and Forwarder Role (fluentbit) implementation"
---

# Tasks: Fluent Bit Log Collector and Forwarder Role (`fluentbit`)

**Input**: Design documents from `/specs/008-fluentbit-role/`

**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule container verification (`molecule test` across all 5 CI matrix images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Ansible role**: `roles/fluentbit/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)
- **CI workflow**: `.github/workflows/ci.yml`
- **Repository documentation**: `AGENTS.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the role and Molecule scenario using official CLI tools per Constitution Principle II

- [X] T001 Scaffold the `fluentbit` role skeleton using `ansible-galaxy role init --init-path roles fluentbit` to create `roles/fluentbit/`
- [X] T002 Remove the unused generated `roles/fluentbit/files/` directory and initialize the default Molecule scenario using `molecule init scenario default` inside `roles/fluentbit/`
- [X] T003 Remove any generated `roles/fluentbit/molecule/default/create.yml` or `roles/fluentbit/molecule/default/destroy.yml` and configure the Docker systemd driver in `roles/fluentbit/molecule/default/molecule.yml` using `roles/datetime/molecule/default/molecule.yml` as baseline
- [X] T004 [P] Create `roles/fluentbit/molecule/default/prepare.yml` with the RHEL 8 `python39` bootstrap tasks, sample log directories (`/var/www/demo/storage/logs`, `/var/log/nginx`), and lightweight mock Graylog UDP (`127.0.0.1:12201`) and Loki HTTP (`127.0.0.1:3100`) receiver services

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core metadata, OS variables, user-tunable defaults, and service handlers that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Populate Galaxy metadata (`author: "Hilman F. Rakhmad"`, `description`, `license: "MIT"`, `min_ansible_version: "2.21.0"`, `platforms` for Debian/Ubuntu/EL 8-9, and `galaxy_tags`) in `roles/fluentbit/meta/main.yml`
- [X] T006 [P] Define Debian-family variables (`fluentbit_pre_packages: ['ca-certificates', 'curl', 'gnupg']`, `fluentbit_gpg_key_url: 'https://packages.fluentbit.io/fluentbit.key'`, `fluentbit_apt_key_path: '/etc/apt/keyrings/fluentbit.asc'`, `fluentbit_apt_repo`, `fluentbit_apt_repo_filename: 'fluent-bit'`, `fluentbit_package_name: 'fluent-bit'`, `fluentbit_service_name: 'fluent-bit'`, `fluentbit_bin_path: '/opt/fluent-bit/bin/fluent-bit'`, and `fluentbit_default_syslog_paths: ['/var/log/syslog', '/var/log/auth.log']`) in `roles/fluentbit/vars/Debian.yml`
- [X] T007 [P] Define RedHat-family variables (`fluentbit_pre_packages: ['ca-certificates']`, `fluentbit_gpg_key_url: 'https://packages.fluentbit.io/fluentbit.key'`, `fluentbit_yum_baseurl: 'https://packages.fluentbit.io/centos/$releasever/'`, `fluentbit_package_name: 'fluent-bit'`, `fluentbit_service_name: 'fluent-bit'`, `fluentbit_bin_path: '/opt/fluent-bit/bin/fluent-bit'`, and `fluentbit_default_syslog_paths: ['/var/log/messages', '/var/log/secure']`) in `roles/fluentbit/vars/RedHat.yml`
- [X] T008 Define all `fluentbit_*` user-tunable default variables in `roles/fluentbit/defaults/main.yml` adhering to `data-model.md` constraints: `fluentbit_package_state: "present"` (`"present"` or `"latest"`), `fluentbit_service_enabled: true`, `fluentbit_service_state: "started"` (`"started"` or `"stopped"`), `fluentbit_config_dir: "/etc/fluent-bit"`, `fluentbit_storage_dir: "/var/lib/fluent-bit"` (`mode: '0750'`), `fluentbit_flush_interval: 1` (`> 0`), `fluentbit_log_level: "info"` (`"off"`, `"error"`, `"warning"`, `"info"`, `"debug"`, `"trace"`), `fluentbit_http_server: false`, `fluentbit_http_listen: "127.0.0.1"`, `fluentbit_http_port: 2020` (`1..65535`), `fluentbit_laravel_enabled: true`, `fluentbit_laravel_log_paths: ["/var/www/*/storage/logs/*.log", "/var/log/laravel/*.log"]`, `fluentbit_laravel_tag: "laravel.app"`, `fluentbit_laravel_mem_buf_limit: "10MB"`, `fluentbit_nginx_enabled: true`, `fluentbit_nginx_access_log_paths: ["/var/log/nginx/*access*.log"]`, `fluentbit_nginx_error_log_paths: ["/var/log/nginx/*error*.log"]`, `fluentbit_nginx_access_tag: "nginx.access"`, `fluentbit_nginx_error_tag: "nginx.error"`, `fluentbit_system_log_enabled: true`, `fluentbit_system_log_mode: "systemd"` (`"systemd"`, `"syslog"`, or `"both"`), `fluentbit_system_log_paths: []`, `fluentbit_system_systemd_filters: []`, `fluentbit_system_tag: "system.syslog"`, `fluentbit_extra_parsers: []`, `fluentbit_extra_inputs: []`, `fluentbit_extra_filters: []`, `fluentbit_graylog_enabled: false`, `fluentbit_graylog_host: "127.0.0.1"`, `fluentbit_graylog_port: 12201` (`1..65535`), `fluentbit_graylog_mode: "udp"` (`"udp"`, `"tcp"`, or `"tls"`), `fluentbit_graylog_match: "*"`, `fluentbit_graylog_tls_verify: true`, `fluentbit_graylog_extra_options: {}`, `fluentbit_loki_enabled: false`, `fluentbit_loki_host: "127.0.0.1"`, `fluentbit_loki_port: 3100` (`1..65535`), `fluentbit_loki_uri: "/loki/api/v1/push"`, `fluentbit_loki_match: "*"`, `fluentbit_loki_tls: false`, `fluentbit_loki_tls_verify: true`, `fluentbit_loki_tenant_id: ""`, `fluentbit_loki_http_user: ""`, `fluentbit_loki_http_passwd: ""`, `fluentbit_loki_bearer_token: ""`, `fluentbit_loki_labels: ["job=fluentbit", "host=$hostname", "source=$log_source", "level=$level"]`, `fluentbit_loki_line_format: "json"` (`"json"` or `"key_value"`), `fluentbit_loki_extra_options: {}`, `fluentbit_stdout_enabled: false`, and `fluentbit_extra_outputs: []`
- [X] T009 [P] Implement validation-guarded service restart handlers (`Validate fluent-bit configuration` executing `{{ fluentbit_bin_path }} --dry-run --config {{ fluentbit_config_dir }}/fluent-bit.conf` and `Restart fluent-bit` listening on `"validate and restart fluent-bit"`) in `roles/fluentbit/handlers/main.yml`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Install and Manage Fluent Bit Daemon on Target Hosts (Priority: P1) 🎯 MVP

**Goal**: Configure the official `packages.fluentbit.io` repository across Debian and RedHat distributions, install `fluent-bit`, create `/etc/fluent-bit` (`'0755'`) and `/var/lib/fluent-bit` (`'0750'`), render and dry-run validate classic INI-style `/etc/fluent-bit/parsers.conf` (`'0644'`) and `/etc/fluent-bit/fluent-bit.conf` (`'0640'`), and manage `fluent-bit.service` idempotently.

**Independent Test**: Apply the role to a clean Linux host with default settings, verify the `fluent-bit` package and `/opt/fluent-bit/bin/fluent-bit` binary are installed, verify `--dry-run` validation passes, verify `/var/lib/fluent-bit` exists with mode `'0750'`, verify `fluent-bit.service` is active and enabled, and verify a second run produces `changed=0`.

### Implementation for User Story 1

- [X] T010 [P] [US1] Implement Debian repository setup in `roles/fluentbit/tasks/setup-Debian.yml` (install `fluentbit_pre_packages`, ensure `/etc/apt/keyrings` exists with mode `'0755'`, download GPG signing key to `{{ fluentbit_apt_key_path }}` with mode `'0644'`, configure `{{ fluentbit_apt_repo }}` in `/etc/apt/sources.list.d/fluent-bit.list`, and update APT cache when changed)
- [X] T011 [P] [US1] Implement RedHat repository setup in `roles/fluentbit/tasks/setup-RedHat.yml` (install `fluentbit_pre_packages` and configure `/etc/yum.repos.d/fluent-bit.repo` via `ansible.builtin.yum_repository` with `baseurl: "{{ fluentbit_yum_baseurl }}"`, `gpgcheck: true`, and `gpgkey: "{{ fluentbit_gpg_key_url }}"`)
- [X] T012 [US1] Implement package installation tasks in `roles/fluentbit/tasks/install.yml` to install `{{ fluentbit_package_name }}` with state `{{ fluentbit_package_state }}`
- [X] T013 [P] [US1] Create base `roles/fluentbit/templates/parsers.conf.j2` and `roles/fluentbit/templates/fluent-bit.conf.j2` with `[SERVICE]` settings (`Flush`, `Daemon Off`, `Log_Level`, `Parsers_File`, `HTTP_Server`, `HTTP_Listen`, `HTTP_Port`, `storage.path`), global `record_modifier` filter (`Record hostname ${HOSTNAME}`), and fallback `null` output when no output is enabled
- [X] T014 [US1] Implement configuration and service management in `roles/fluentbit/tasks/configure.yml` to create `{{ fluentbit_config_dir }}` (`'0755'`) and `{{ fluentbit_storage_dir }}` (`'0750'`), render `parsers.conf` (`'0644'`) and `fluent-bit.conf` (`'0640'`) notifying `"validate and restart fluent-bit"`, validate configuration via `{{ fluentbit_bin_path }} --dry-run --config {{ fluentbit_config_dir }}/fluent-bit.conf`, flush handlers, and ensure `{{ fluentbit_service_name }}` is `{{ fluentbit_service_state }}` and enabled `{{ fluentbit_service_enabled }}`
- [X] T015 [US1] Implement main task orchestration in `roles/fluentbit/tasks/main.yml` with platform and input validation assertions (`ansible_os_family in ['Debian', 'RedHat']`, valid `fluentbit_log_level`, `fluentbit_system_log_mode in ['systemd', 'syslog', 'both']`, `fluentbit_graylog_mode in ['udp', 'tcp', 'tls']`, `fluentbit_loki_line_format in ['json', 'key_value']`, valid port ranges `1..65535`, and non-empty log paths/hosts when enabled), OS variable inclusion (`vars/{{ ansible_os_family }}.yml`), and inclusion of `setup-{{ ansible_os_family }}.yml`, `install.yml`, and `configure.yml`
- [X] T016 [US1] Configure baseline `roles/fluentbit/molecule/default/converge.yml` and `roles/fluentbit/molecule/default/verify.yml` to converge `hifra01.utils.fluentbit` and assert `/opt/fluent-bit/bin/fluent-bit` binary installation, `--dry-run` validation success, `/var/lib/fluent-bit` directory permissions (`'0750'`), active `fluent-bit.service`, and HTTP 200 on `http://127.0.0.1:2020/api/v1/health`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Collect and Parse Laravel Multiline Logs, Nginx Access/Error Logs, and System Logs (Priority: P2)

**Goal**: Implement parsers, inputs, and normalization filters for Laravel multiline logs (`[MULTILINE_PARSER] laravel_multiline` + regex `laravel` parser extracting `time`, `env`, `level`, `message`), Nginx access logs (`nginx_access` parser extracting HTTP fields + `Rename log message`), Nginx error logs (`nginx_error` parser extracting `time`, `level`, `pid`, `tid`, `cid`, `message`), and host system logs (`systemd` journal and/or `syslog-rfc3164` files).

**Independent Test**: Enable Laravel, Nginx, and system log inputs on a test host, write a multi-line Laravel exception log with stack trace lines, an Nginx access request line, an Nginx error line, and a system log entry, and verify that Fluent Bit emits consolidated structured records with extracted fields, persistent SQLite offset files in `/var/lib/fluent-bit/*.db`, and a non-empty `message` field on every record.

### Implementation for User Story 2

- [X] T017 [US2] Add `[MULTILINE_PARSER]` (`laravel_multiline` with `type: regex`, `flush_timeout: 1000`, and `start_state`/`cont` rules), `[PARSER]` (`laravel` extracting `time`, `env`, `level`, `message`), `[PARSER]` (`nginx_access` extracting `remote`, `host`, `user`, `time`, `method`, `path`, `code`, `size`, `referer`, `agent`, `http_x_forwarded_for`), `[PARSER]` (`nginx_error` extracting `time`, `level`, `pid`, `tid`, `cid`, `message`), `[PARSER]` (`syslog-rfc3164`), and `fluentbit_extra_parsers` iteration to `roles/fluentbit/templates/parsers.conf.j2`
- [X] T018 [US2] Add Laravel multiline `[INPUT]` (`Name tail`, `Multiline.Parser laravel_multiline`, `DB {{ fluentbit_storage_dir }}/laravel.db`, `Mem_Buf_Limit {{ fluentbit_laravel_mem_buf_limit }}`, `Buffer_Max_Size 1M`, `Skip_Long_Lines On`) and `[FILTER]` stages (`Name parser` with `Parser laravel` and `Reserve_Data On`, plus `Name modify` setting `Add log_source laravel` and normalizing `message`) to `roles/fluentbit/templates/fluent-bit.conf.j2`
- [X] T019 [US2] Add Nginx access and error `[INPUT]` (`Name tail` with `DB {{ fluentbit_storage_dir }}/nginx_access.db` and `nginx_error.db`) and `[FILTER]` stages (`Name parser` with `Parser nginx_access` / `nginx_error`, `Reserve_Data On`, `Preserve_Key On`, plus `Name modify` setting `log_source` and normalizing `log` to `message`) to `roles/fluentbit/templates/fluent-bit.conf.j2`
- [X] T020 [US2] Add system log `[INPUT]` and `[FILTER]` stages supporting `fluentbit_system_log_mode` (`"systemd"` using `Name systemd` with optional `Systemd_Filter`, `"syslog"` using `Name tail` on `fluentbit_system_log_paths` or `fluentbit_default_syslog_paths` with `Parser syslog-rfc3164`, or `"both"`), plus `fluentbit_extra_inputs` and `fluentbit_extra_filters` iteration in `roles/fluentbit/templates/fluent-bit.conf.j2`
- [X] T021 [US2] Extend `roles/fluentbit/molecule/default/converge.yml` and `roles/fluentbit/molecule/default/verify.yml` to inject a multi-line Laravel exception log (header + `#0` and `#1` stack frames), an Nginx access log line, an Nginx error log line, and a system log entry, asserting that the multi-line Laravel trace is emitted as a single consolidated record and all sources contain their expected parsed fields and SQLite DB files in `/var/lib/fluent-bit/`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Forward Structured Logs to Graylog, Grafana Loki, or Both (Priority: P3)

**Goal**: Configure `[OUTPUT]` blocks in `/etc/fluent-bit/fluent-bit.conf` to ship parsed logs to Graylog (`Name gelf` over `udp`/`tcp`/`tls` with `Gelf_Short_Message_Key message` and `Gelf_Host_Key hostname`), Grafana Loki (`Name loki` over HTTP/HTTPS with stream `labels`, `line_format`, optional TLS/auth/tenant settings), `stdout`, and `fluentbit_extra_outputs`.

**Independent Test**: Enable both Graylog (`gelf`) and Loki (`loki`) outputs in `converge.yml` pointing to the local mock receivers prepared on `127.0.0.1:12201` (UDP) and `127.0.0.1:3100` (HTTP), generate sample Laravel, Nginx, and system logs, and verify in `verify.yml` that both the Graylog receiver and Loki `/loki/api/v1/push` receiver receive structured payloads with expected fields and stream labels.

### Implementation for User Story 3

- [X] T022 [US3] Add Graylog `[OUTPUT]` (`Name gelf`, `Match {{ fluentbit_graylog_match }}`, `Host {{ fluentbit_graylog_host }}`, `Port {{ fluentbit_graylog_port }}`, `Mode {{ fluentbit_graylog_mode }}`, `Gelf_Short_Message_Key message`, `Gelf_Host_Key hostname`, conditional TLS verify, and `fluentbit_graylog_extra_options`) and Grafana Loki `[OUTPUT]` (`Name loki`, `Match {{ fluentbit_loki_match }}`, `Host {{ fluentbit_loki_host }}`, `Port {{ fluentbit_loki_port }}`, `uri {{ fluentbit_loki_uri }}`, `labels`, `line_format`, conditional TLS/tenant/auth, and `fluentbit_loki_extra_options`), plus `stdout` and `fluentbit_extra_outputs` blocks to `roles/fluentbit/templates/fluent-bit.conf.j2`
- [X] T023 [US3] Extend `roles/fluentbit/molecule/default/converge.yml` and `roles/fluentbit/molecule/default/verify.yml` to enable both `fluentbit_graylog_enabled: true` (`127.0.0.1:12201`) and `fluentbit_loki_enabled: true` (`127.0.0.1:3100`) and assert that both Graylog GELF messages (with `short_message` and `_env`/`_level`) and Loki JSON push payloads (with `job`, `host`, `source`, `level` stream labels) are received by the mock listeners

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Role documentation, CI matrix registration, linting, and full 5-distro Molecule verification

- [X] T024 [P] Write comprehensive role documentation (description, supported platforms, requirements, role variables with defaults, example playbooks for Loki, Graylog, and dual shipping, license) in `roles/fluentbit/README.md`
- [X] T025 [P] Add the `fluentbit` role to the Roles table in `AGENTS.md`
- [X] T026 [P] Register `fluentbit` in all four required locations (`detect-changes.outputs`, `paths-filter` `filters`, `molecule.strategy.matrix.role`, and the role-check `case` statement) in `.github/workflows/ci.yml`
- [X] T027 Run `yamllint .` and `ansible-lint` from the repository root and fix any warnings or errors across `roles/fluentbit/`, `AGENTS.md`, and `.github/workflows/ci.yml`
- [X] T028 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from `roles/fluentbit/` (or via `./test-matrix.sh -r fluentbit`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational (Phase 2) completion
  - User Story 1 (Phase 3) provides repository configuration, `fluent-bit` package installation, base config rendering, dry-run validation, and systemd daemon lifecycle management (MVP)
  - User Story 2 (Phase 4) builds on User Story 1 by adding the Laravel multiline, Nginx access/error, and system log parsers, inputs, and filters
  - User Story 3 (Phase 5) builds on User Stories 1 & 2 by adding Graylog (`gelf`) and Grafana Loki (`loki`) output routing and end-to-end delivery verification
- **Polish (Phase 6)**: Depends on all user stories (Phase 3-5) being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Extends `parsers.conf.j2` and `fluent-bit.conf.j2` established in US1
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Extends `fluent-bit.conf.j2` `[OUTPUT]` section to forward records parsed in US2

### Parallel Opportunities

- Within Phase 1: `T004` [P] (`prepare.yml`) can run in parallel with `T003` (`molecule.yml`).
- Within Phase 2: `T005` [P] (`meta/main.yml`), `T006` [P] (`vars/Debian.yml`), `T007` [P] (`vars/RedHat.yml`), and `T009` [P] (`handlers/main.yml`) can be developed in parallel.
- Within Phase 3: `T010` [P] (`setup-Debian.yml`), `T011` [P] (`setup-RedHat.yml`), and `T013` [P] (`parsers.conf.j2` & `fluent-bit.conf.j2`) can run in parallel.
- Within Phase 6: `T024` [P] (`README.md`), `T025` [P] (`AGENTS.md`), and `T026` [P] (`ci.yml`) can be edited in parallel before running linters (`T027`) and Molecule tests (`T028`).

---

## Parallel Example: Foundational & User Story 1

```bash
# Foundational tasks that can run in parallel:
Task: "Populate Galaxy metadata in roles/fluentbit/meta/main.yml"
Task: "Define Debian-family variables in roles/fluentbit/vars/Debian.yml"
Task: "Define RedHat-family variables in roles/fluentbit/vars/RedHat.yml"
Task: "Implement validation-guarded service restart handlers in roles/fluentbit/handlers/main.yml"

# User Story 1 tasks that can run in parallel:
Task: "Implement Debian repository setup in roles/fluentbit/tasks/setup-Debian.yml"
Task: "Implement RedHat repository setup in roles/fluentbit/tasks/setup-RedHat.yml"
Task: "Create base roles/fluentbit/templates/parsers.conf.j2 and roles/fluentbit/templates/fluent-bit.conf.j2"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001` - `T004`)
2. Complete Phase 2: Foundational (`T005` - `T009`)
3. Complete Phase 3: User Story 1 (`T010` - `T016`)
4. **STOP and VALIDATE**: Run `molecule converge && molecule verify` to test User Story 1 independently.

### Incremental Delivery

1. Setup + Foundational → Role skeleton, metadata, OS vars, defaults, handlers ready.
2. User Story 1 → Repository configured, `fluent-bit` installed, base config dry-run validated, daemon running and healthy (MVP).
3. User Story 2 → Laravel multiline, Nginx access/error, and host system log parsing and normalization pipelines active.
4. User Story 3 → Graylog (`gelf`) and Grafana Loki (`loki`) output forwarding active and verified end-to-end.
5. Polish → Documentation (`README.md`, `AGENTS.md`), CI matrix registration, lint clean, and 5-distro container verification.
