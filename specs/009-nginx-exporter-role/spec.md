# Feature Specification: Prometheus NGINX Exporter Role (`nginx_exporter`)

**Feature Branch**: `009-nginx-exporter-role`

**Created**: 2026-11-10

**Status**: Draft

**Input**: User description: "create role nginx_exporter separated from nginx role based on the discussion, name branch based on convention"

## Clarifications

### Session 2026-11-14

- Q: Should `nginx_exporter_scrape_uri` accept a single URI string, a list of URI strings, or either format? (FR-006) → A: Either a string or a list of strings (e.g., `"http://127.0.0.1:8080/stub_status"` or `["http://127.0.0.1:8080/stub_status", "http://127.0.0.1:8081/stub_status"]`).
- Q: How should the `nginx_exporter` Molecule scenario provide a live NGINX `stub_status` endpoint during testing to verify `nginx_up 1`? (SC-001) → A: Converge `hifra01.utils.nginx` (`nginx_stub_status_enabled: true`) alongside `hifra01.utils.nginx_exporter` in `nginx_exporter`'s Molecule scenario, and also verify `stub_status` in `nginx`'s Molecule scenario.
- Q: Should the `stub_status` location in `/etc/nginx/conf.d/stub_status.conf` disable NGINX access logging (`access_log off;`) by default? (FR-009) → A: Disable access logging by default via a tunable `nginx_stub_status_access_log: "off"` variable (`access_log {{ nginx_stub_status_access_log }};`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy and Run Prometheus NGINX Exporter on Target Hosts (Priority: P1)

Infrastructure operators and site reliability engineers need to install Prometheus NGINX Exporter (`nginx-prometheus-exporter`) as a standalone, managed background service on Linux hosts running NGINX so that web server telemetry (active connections, accepted/handled connections, reading/writing/waiting states, and total requests) can be continuously scraped by Prometheus.

**Why this priority**: Installing the `nginx-prometheus-exporter` binary, provisioning a dedicated unprivileged service account, and managing the systemd service lifecycle is the foundational capability required to export NGINX metrics.

**Independent Test**: Can be fully tested by converging `hifra01.utils.nginx` with `nginx_stub_status_enabled: true` alongside `hifra01.utils.nginx_exporter` on a clean Linux host, and verifying that the `nginx-prometheus-exporter` binary is installed, the `nginx_exporter` systemd service is active and enabled on boot, and an HTTP GET request to `:9113/metrics` returns HTTP 200 with `nginx_up 1` and standard `nginx_connections_*` / `nginx_http_requests_total` metrics.

**Acceptance Scenarios**:

1. **Given** a clean supported Linux host (Debian/Ubuntu or RHEL/Rocky/AlmaLinux) with an accessible NGINX `stub_status` endpoint, **When** the operator applies the `nginx_exporter` role with default settings, **Then** the official `nginx-prometheus-exporter` archive is downloaded, verified against its SHA256 checksum, extracted to `/usr/local/bin/nginx-prometheus-exporter`, started as an unprivileged `nginx_exporter` systemd service, enabled at boot, and serves Prometheus metrics on port `9113` with `nginx_up 1`.
2. **Given** an already provisioned host with `nginx_exporter` running, **When** the operator re-runs the role with unchanged variables, **Then** no archives are re-downloaded, configuration files and unit definitions remain unmodified, the service is not restarted, and the playbook completes with zero changes (idempotent).
3. **Given** an existing host running an older version of `nginx_exporter`, **When** the operator updates `nginx_exporter_version` and applies the role, **Then** the new binary version is downloaded, verified, and installed, the service is restarted cleanly, and `/metrics` reflects the updated exporter version.

---

### User Story 2 - Enable `stub_status` in the `nginx` Role for Seamless Composition (Priority: P2)

Infrastructure operators composing `hifra01.utils.nginx` and `hifra01.utils.nginx_exporter` on the same host need a clean, opt-in toggle in the `nginx` role (`nginx_stub_status_enabled: true`) to expose the local `stub_status` endpoint without having it purged by the `nginx` role's unmanaged configuration cleanup task.

**Why this priority**: Because the `nginx` role automatically deletes unmanaged `.conf` files in `nginx_site_enabled_dir` (which is `/etc/nginx/conf.d` on RedHat-family systems), managing `stub_status.conf` via a first-class toggle inside `roles/nginx` ensures both roles work together reliably across Debian and RedHat without file ownership conflicts.

**Independent Test**: Can be tested by applying `hifra01.utils.nginx` with `nginx_stub_status_enabled: true`, verifying that `/etc/nginx/conf.d/stub_status.conf` is rendered, preserved across cleanup tasks, and responds to `http://127.0.0.1:8080/stub_status` with NGINX's `Active connections:` payload.

**Acceptance Scenarios**:

1. **Given** a host managed by `hifra01.utils.nginx` with `nginx_stub_status_enabled: true`, **When** the `nginx` role is applied, **Then** `/etc/nginx/conf.d/stub_status.conf` is rendered listening on `{{ nginx_stub_status_host }}:{{ nginx_stub_status_port }}{{ nginx_stub_status_path }}` restricted to `{{ nginx_stub_status_allow }}` IPs with `access_log {{ nginx_stub_status_access_log }};`, preserved during unused site cleanup, and serves `stub_status` metrics.
2. **Given** a host managed by `hifra01.utils.nginx` with `nginx_stub_status_enabled: false` (the default), **When** the `nginx` role is applied, **Then** `/etc/nginx/conf.d/stub_status.conf` is ensured absent and NGINX reloads cleanly if it previously existed.

---

### User Story 3 - Customize Scrape Targets, Listen Address, and Web Security (Priority: P3)

Platform and security engineers need to customize the exporter's network binding (`--web.listen-address`), telemetry path (`--web.telemetry-path`), target NGINX scrape URI(s) (`--nginx.scrape-uri`), timeout/SSL flags, and optional TLS or Basic Authentication (`--web.config.file`) so the exporter adheres to internal network segmentation and security policies.

**Why this priority**: Production environments frequently bind exporters to internal management IPs, scrape custom NGINX ports/paths or NGINX Plus APIs, and optionally secure `/metrics` with TLS or HTTP Basic Auth.

**Independent Test**: Can be tested by overriding `nginx_exporter_web_listen_address`, `nginx_exporter_scrape_uri`, `nginx_exporter_extra_flags`, and `nginx_exporter_web_config`, applying the role, and verifying that the systemd unit and `/etc/nginx_exporter/config.yml` reflect the custom configuration and the service responds on the custom socket.

**Acceptance Scenarios**:

1. **Given** a host configured with custom `nginx_exporter_web_listen_address` (e.g., `127.0.0.1:9113`) and custom `nginx_exporter_scrape_uri` (provided as either a single URI string or a list of URI strings), **When** the role is applied, **Then** `nginx_exporter` binds exclusively to the specified address/port and scrapes the configured URI(s).
2. **Given** a non-empty `nginx_exporter_web_config` dictionary (e.g., `tls_server_config` or `basic_auth_users`), **When** the role is applied, **Then** `/etc/nginx_exporter/config.yml` is rendered with `0640` permissions owned by `root:{{ nginx_exporter_system_group }}` and passed via `--web.config.file=/etc/nginx_exporter/config.yml`.
3. **Given** `nginx_exporter_web_config` is later cleared to `{}`, **When** the role is re-applied, **Then** `/etc/nginx_exporter/config.yml` is removed and `--web.config.file` is omitted from the service command line.

---

### Edge Cases

- **Unsupported operating system family**: When executed on an OS family outside `Debian` and `RedHat`, the role fails immediately at the top of `tasks/main.yml` with a descriptive assertion message before downloading archives or modifying the system.
- **Unsupported CPU architecture**: When executed on an architecture outside `x86_64`, `aarch64`, and `armv7l`, the role fails during pre-flight assertion checks with a clear message.
- **Unreachable NGINX `stub_status` at startup**: Even if the target NGINX `stub_status` endpoint is temporarily unreachable when `nginx_exporter` starts, `nginx-prometheus-exporter` still starts and serves `/metrics` (reporting `nginx_up 0`) without crashing the systemd unit.
- **Corrupted or mismatched archive checksum**: If the downloaded tarball does not match the upstream `checksums.txt` (or explicit `nginx_exporter_checksum`), the download task fails before replacing any existing `/usr/local/bin/nginx-prometheus-exporter` binary.
- **RedHat `/etc/nginx/conf.d` cleanup interaction**: On RedHat-family systems where `nginx_site_enabled_dir` is `/etc/nginx/conf.d`, `stub_status.conf` is explicitly excluded from the `Clean up unused site configurations` task in `roles/nginx` when `nginx_stub_status_enabled: true`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `nginx_exporter` role MUST validate at the start of `tasks/main.yml` that the target host belongs to a supported OS family (`Debian` or `RedHat`), a supported CPU architecture (`x86_64`, `aarch64`, `armv7l`), and valid role input variables, failing fast with an informative error message otherwise.
- **FR-002**: The `nginx_exporter` role MUST download the official precompiled Prometheus NGINX Exporter release tarball (`nginx-prometheus-exporter_<version>_linux_<arch>.tar.gz`) from GitHub Releases (`github.com/nginx/nginx-prometheus-exporter`) or a user-overridden URL and verify its SHA256 checksum against the upstream `nginx-prometheus-exporter_<version>_checksums.txt` (or an explicit `nginx_exporter_checksum` variable) before extracting.
- **FR-003**: The `nginx_exporter` role MUST install the `nginx-prometheus-exporter` binary into `{{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter` (default `/usr/local/bin/nginx-prometheus-exporter`) with mode `'0755'` owned by `root:root`.
- **FR-004**: The `nginx_exporter` role MUST create a dedicated unprivileged system group and user (`nginx_exporter_system_group` and `nginx_exporter_system_user`, defaulting to `nginx_exporter`) with `system: true`, `create_home: false`, and a non-interactive login shell (`/usr/sbin/nologin` or `/sbin/nologin`).
- **FR-005**: The `nginx_exporter` role MUST configure and manage a hardened systemd service unit (`/etc/systemd/system/nginx_exporter.service`) running as `{{ nginx_exporter_system_user }}:{{ nginx_exporter_system_group }}`, enabled at boot and started by default.
- **FR-006**: The `nginx_exporter` role MUST provide user-tunable, `nginx_exporter_`-prefixed variables in `roles/nginx_exporter/defaults/main.yml`, including at minimum:
  - `nginx_exporter_version` (release version without leading `v`, e.g., `"1.4.1"`)
  - `nginx_exporter_checksum` (optional explicit 64-character hex SHA256 digest; when empty `""`, resolved automatically from `nginx_exporter_checksums_url`)
  - `nginx_exporter_arch_map` (architecture mapping dictionary: `x86_64: amd64`, `aarch64: arm64`, `armv7l: armv7`)
  - `nginx_exporter_download_url` (tarball download URL from GitHub Releases)
  - `nginx_exporter_checksums_url` (upstream `nginx-prometheus-exporter_<version>_checksums.txt` URL)
  - `nginx_exporter_bin_dir` (binary installation directory, default `"/usr/local/bin"`)
  - `nginx_exporter_config_dir` (configuration directory for optional web config, default `"/etc/nginx_exporter"`)
  - `nginx_exporter_system_user` (system user, default `"nginx_exporter"`)
  - `nginx_exporter_system_group` (system group, default `"nginx_exporter"`)
  - `nginx_exporter_web_listen_address` (listen address and port passed to `--web.listen-address`, default `"0.0.0.0:9113"`)
  - `nginx_exporter_web_telemetry_path` (metrics HTTP path passed to `--web.telemetry-path`, default `"/metrics"`)
  - `nginx_exporter_scrape_uri` (target NGINX `stub_status` or NGINX Plus API URI(s) passed to `--nginx.scrape-uri`, accepting either a non-empty string or a non-empty list of strings, default `"http://127.0.0.1:8080/stub_status"`)
  - `nginx_exporter_nginx_plus` (boolean to enable `--nginx.plus` for NGINX Plus API scraping, default `false`)
  - `nginx_exporter_ssl_verify` (boolean to control `--nginx.ssl-verify` when scraping HTTPS endpoints, default `true`)
  - `nginx_exporter_timeout` (scrape timeout duration passed to `--nginx.timeout`, default `"5s"`)
  - `nginx_exporter_extra_flags` (list of additional raw CLI flags passed to the daemon, default `[]`)
  - `nginx_exporter_web_config` (optional dictionary for TLS and/or basic authentication rendered to `{{ nginx_exporter_config_dir }}/config.yml`, default `{}`)
  - `nginx_exporter_service_enabled` (boolean to enable service at boot, default `true`)
  - `nginx_exporter_service_state` (desired service state, default `"started"`)
- **FR-007**: When `nginx_exporter_web_config` is non-empty, the `nginx_exporter` role MUST render `{{ nginx_exporter_config_dir }}/config.yml` with mode `'0640'` owned by `root:{{ nginx_exporter_system_group }}` and pass `--web.config.file={{ nginx_exporter_config_dir }}/config.yml` to the daemon; when `nginx_exporter_web_config` is empty (`{}`), the role MUST ensure `{{ nginx_exporter_config_dir }}/config.yml` is absent and omit the flag.
- **FR-008**: The `nginx_exporter` role MUST isolate OS-specific prerequisite packages (`tar`, `gzip`) and nologin shell paths in `vars/Debian.yml` and `vars/RedHat.yml`, and reload systemd / restart `nginx_exporter` via handlers whenever the binary, systemd unit, or web config changes.
- **FR-009**: The existing `nginx` role (`roles/nginx`) MUST support an opt-in `stub_status` configuration via `nginx_`-prefixed default variables:
  - `nginx_stub_status_enabled` (boolean, default `false`)
  - `nginx_stub_status_host` (bind address for stub_status server block, default `"127.0.0.1"`)
  - `nginx_stub_status_port` (listen port for stub_status server block, default `8080`)
  - `nginx_stub_status_path` (location path for stub_status, default `"/stub_status"`)
  - `nginx_stub_status_allow` (list of allowed client IPs/CIDRs before `deny all`, default `["127.0.0.1", "::1"]`)
  - `nginx_stub_status_access_log` (access_log setting inside the stub_status location block, default `"off"`)
  When `nginx_stub_status_enabled: true`, `roles/nginx` MUST render `{{ nginx_config_dir }}/conf.d/stub_status.conf`, exclude `stub_status.conf` from the unused site cleanup task, and validate/reload NGINX; when `false`, `roles/nginx` MUST ensure `{{ nginx_config_dir }}/conf.d/stub_status.conf` is absent.
- **FR-010**: All tasks across both `roles/nginx_exporter` and `roles/nginx` MUST be strictly idempotent, adhere to collection lint rules (`yamllint .` and `ansible-lint`), register `nginx_exporter` in `.github/workflows/ci.yml` and `AGENTS.md`, and pass Molecule verification across all 5 supported CI matrix distributions (with `roles/nginx_exporter/molecule/default/` converging `hifra01.utils.nginx` with `nginx_stub_status_enabled: true` alongside `hifra01.utils.nginx_exporter`, and `roles/nginx/molecule/default/` also verifying `stub_status` behavior).

### Key Entities

- **NGINX Exporter Daemon (`nginx-prometheus-exporter`)**: Standalone Prometheus exporter service running under systemd on port `9113` by default, scraping NGINX's `stub_status` or NGINX Plus API and translating those stats into Prometheus metrics (`nginx_up`, `nginx_connections_active`, `nginx_http_requests_total`, etc.).
- **Service Account (`nginx_exporter`)**: Dedicated unprivileged system user and group executing the exporter process.
- **NGINX `stub_status` Endpoint**: Local HTTP status endpoint (`/etc/nginx/conf.d/stub_status.conf`) optionally provisioned by the `nginx` role on `127.0.0.1:8080/stub_status` for local exporter scraping.
- **Web Security Configuration (`config.yml`)**: Optional YAML configuration file in `/etc/nginx_exporter/config.yml` configuring TLS and/or HTTP Basic Authentication for the exporter's HTTP server.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy `nginx` (with `nginx_stub_status_enabled: true`) and `nginx_exporter` across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in a single playbook run, with `nginx_exporter.service` active and enabled within 30 seconds.
- **SC-002**: 100% of HTTP GET requests to `http://127.0.0.1:9113/metrics` return HTTP status 200 and include `nginx_up 1` along with `nginx_connections_accepted`, `nginx_connections_active`, and `nginx_http_requests_total`.
- **SC-003**: Executing the role a second consecutive time with unchanged variables produces 0 changed tasks and 0 service restarts across all supported distributions.
- **SC-004**: `yamllint .` and `ansible-lint` pass with zero errors from the repository root.

## Assumptions

- Target hosts use `systemd` as their service manager across supported Debian-family (Debian 12, Ubuntu 22.04, Ubuntu 24.04) and RedHat-family (Rocky Linux 8, Rocky Linux 9) distributions.
- Upstream binary releases follow the official `nginx/nginx-prometheus-exporter` GitHub Release naming convention (`nginx-prometheus-exporter_<version>_linux_<arch>.tar.gz` and `nginx-prometheus-exporter_<version>_checksums.txt`).
- Default listening socket for `nginx_exporter` is `0.0.0.0:9113` (standard Prometheus allocation for NGINX Exporter) and default scrape target is `http://127.0.0.1:8080/stub_status`.
- Firewall configuration (`ufw`/`firewalld`) and central Prometheus server scrape configuration are outside the scope of this role.
