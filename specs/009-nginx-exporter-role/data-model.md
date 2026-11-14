# Data Model: Prometheus NGINX Exporter Role (`nginx_exporter`)

**Feature**: `009-nginx-exporter-role`  
**Date**: 2026-11-14

## Entities

### 1. NGINX Exporter Daemon & Role Configuration (`nginx_exporter_*` variables)

Represents the per-host Prometheus NGINX Exporter installation, service account, network socket, scrape parameters, and web security settings defined in `roles/nginx_exporter/defaults/main.yml`.

| Field / Variable | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `nginx_exporter_version` | `string` | `"1.4.1"` | Yes | Non-empty semantic version string (`X.Y.Z`, without leading `v`) |
| `nginx_exporter_checksum` | `string` | `""` | No | Optional 64-character hex SHA256 digest; when empty `""`, resolved dynamically from `nginx_exporter_checksums_url` |
| `nginx_exporter_arch_map` | `dict` | `{"x86_64": "amd64", "aarch64": "arm64", "armv7l": "armv7"}` | Yes | Mapping from `ansible_architecture` to upstream release archive suffix |
| `nginx_exporter_download_url` | `string` | `"https://github.com/nginx/nginx-prometheus-exporter/releases/download/v{{ nginx_exporter_version }}/nginx-prometheus-exporter_{{ nginx_exporter_version }}_linux_{{ ... }}.tar.gz"` | Yes | Valid HTTP/HTTPS URL to `.tar.gz` release archive |
| `nginx_exporter_checksums_url` | `string` | `"https://github.com/nginx/nginx-prometheus-exporter/releases/download/v{{ nginx_exporter_version }}/nginx-prometheus-exporter_{{ nginx_exporter_version }}_checksums.txt"` | Yes | Valid HTTP/HTTPS URL to upstream `checksums.txt` |
| `nginx_exporter_bin_dir` | `string` | `"/usr/local/bin"` | Yes | Absolute directory path (`^/`) |
| `nginx_exporter_config_dir` | `string` | `"/etc/nginx_exporter"` | Yes | Absolute directory path (`^/`) |
| `nginx_exporter_system_user` | `string` | `"nginx_exporter"` | Yes | Non-empty Linux username |
| `nginx_exporter_system_group` | `string` | `"nginx_exporter"` | Yes | Non-empty Linux group name |
| `nginx_exporter_web_listen_address` | `string` | `"0.0.0.0:9113"` | Yes | Non-empty `[host]:port` string |
| `nginx_exporter_web_telemetry_path` | `string` | `"/metrics"` | Yes | Non-empty URL path starting with `/` |
| `nginx_exporter_scrape_uri` | `string \| list[string]` | `"http://127.0.0.1:8080/stub_status"` | Yes | Non-empty string or non-empty list of strings representing `http://`, `https://`, or `unix:` NGINX status URI(s) |
| `nginx_exporter_nginx_plus` | `bool` | `false` | Yes | Boolean (`true` passes `--nginx.plus`) |
| `nginx_exporter_ssl_verify` | `bool` | `true` | Yes | Boolean (`true` passes `--nginx.ssl-verify`, `false` passes `--no-nginx.ssl-verify`) |
| `nginx_exporter_timeout` | `string` | `"5s"` | Yes | Non-empty Go duration string (e.g., `"5s"`, `"10s"`) |
| `nginx_exporter_extra_flags` | `list[string]` | `[]` | No | List of raw CLI flag strings (`["--log.level=info"]`) |
| `nginx_exporter_web_config` | `dict` | `{}` | No | Dictionary matching Prometheus exporter-toolkit `web-config.yml` schema (`tls_server_config`, `http_server_config`, `basic_auth_users`) |
| `nginx_exporter_service_enabled` | `bool` | `true` | Yes | Boolean to enable `nginx_exporter.service` at boot |
| `nginx_exporter_service_state` | `string` | `"started"` | Yes | Desired systemd service state (`"started"` or `"stopped"`) |

---

### 2. Companion NGINX `stub_status` Configuration (`nginx_stub_status_*` variables in `roles/nginx`)

Represents the opt-in NGINX status endpoint managed by `roles/nginx` at `{{ nginx_config_dir }}/conf.d/stub_status.conf`.

| Field / Variable | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `nginx_stub_status_enabled` | `bool` | `false` | Yes | Boolean (`true` renders `/etc/nginx/conf.d/stub_status.conf`; `false` ensures it is absent) |
| `nginx_stub_status_host` | `string` | `"127.0.0.1"` | Yes | Non-empty IP address or hostname to bind |
| `nginx_stub_status_port` | `int` | `8080` | Yes | Valid TCP port (`1..65535`) |
| `nginx_stub_status_path` | `string` | `"/stub_status"` | Yes | Non-empty URL path starting with `/` |
| `nginx_stub_status_allow` | `list[string]` | `["127.0.0.1", "::1"]` | Yes | Sequence of allowed client IP addresses or CIDR blocks before `deny all;` |
| `nginx_stub_status_access_log` | `string` | `"off"` | Yes | Non-empty string for the `access_log` directive inside the `stub_status` location |

---

### 3. Web Security Configuration (`nginx_exporter_web_config`)

Represents the optional Prometheus exporter-toolkit configuration rendered to `{{ nginx_exporter_config_dir }}/config.yml` when non-empty.

| Top-Level Key | Type | Required | Description / Validation |
|---|---|---|---|
| `tls_server_config` | `dict` | No | Optional dictionary containing `cert_file`, `key_file`, optional `client_auth_type`, `client_ca_file`, `cipher_suites`, `min_version` |
| `http_server_config` | `dict` | No | Optional dictionary containing `http2` boolean or `headers` map |
| `basic_auth_users` | `dict[string, string]` | No | Optional mapping of `username: "<bcrypt_password_hash>"` |

## Relationships & Lifecycle State Transitions

1. **NGINX Exporter Daemon (1) ──> (1) System Account (`nginx_exporter:nginx_exporter`)**:
   - The `nginx_exporter.service` systemd unit executes as `User={{ nginx_exporter_system_user }}` and `Group={{ nginx_exporter_system_group }}`.
2. **NGINX Exporter Daemon (1) ──> (1..N) Scrape Targets (`nginx_exporter_scrape_uri`)**:
   - Connects over HTTP/HTTPS/Unix socket to one or more NGINX `stub_status` (or NGINX Plus API) endpoints on every Prometheus `/metrics` scrape.
3. **NGINX Exporter Daemon (1) ──> (0..1) Web Security Configuration (`config.yml`)**:
   - When `nginx_exporter_web_config` is non-empty, `{{ nginx_exporter_config_dir }}/config.yml` is rendered (`0640`, `root:{{ nginx_exporter_system_group }}`) and passed via `--web.config.file`.
   - When `nginx_exporter_web_config` is `{}` (empty), `{{ nginx_exporter_config_dir }}/config.yml` is removed (`state: absent`) and `--web.config.file` is omitted from `nginx_exporter.service`.
4. **State Transitions**:
   - **Fresh Install**: Platform/arch/input assertions pass → OS prerequisite packages (`tar`, `ca-certificates`, `curl`) installed → System group/user created → Binary archive downloaded & SHA256 verified → Binary extracted to `{{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter` → Optional `config.yml` created → `/etc/systemd/system/nginx_exporter.service` rendered → `systemd daemon_reload` + service enabled & started.
   - **Version Upgrade**: `{{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter --version` differs from `nginx_exporter_version` → New release tarball downloaded & SHA256 verified → Binary replaced → Handler validates and restarts `nginx_exporter.service`.
   - **Configuration Change**: `nginx_exporter.service` or `config.yml` modified → Handler reloads systemd daemon, validates binary, and restarts `nginx_exporter.service`.
   - **Idempotent Re-run**: Installed binary version matches `nginx_exporter_version` and templates match on-disk files → Zero downloads, zero file modifications, zero service restarts (`changed=0`).
