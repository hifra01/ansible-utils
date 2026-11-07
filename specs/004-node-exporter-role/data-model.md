# Data Model: Prometheus Node Exporter Role (`node_exporter`)

**Feature**: `004-node-exporter-role`  
**Date**: 2026-11-07

## Entities

### 1. Node Exporter Daemon & Role Configuration (`node_exporter_*` variables)

Represents the per-host Prometheus Node Exporter installation, service account, network socket, collector configuration, and web security settings defined in `roles/node_exporter/defaults/main.yml`.

| Field / Variable | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `node_exporter_version` | `string` | `"1.8.2"` | Yes | Non-empty semantic version string (`X.Y.Z`, without leading `v`) |
| `node_exporter_checksum` | `string` | `""` | No | Optional 64-character hex SHA256 digest; when empty `""`, resolved dynamically from `node_exporter_checksums_url` |
| `node_exporter_download_url` | `string` | `"https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/node_exporter-{{ node_exporter_version }}.linux-{{ _node_exporter_arch }}.tar.gz"` | Yes | Valid HTTP/HTTPS URL to `.tar.gz` release archive |
| `node_exporter_checksums_url` | `string` | `"https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/sha256sums.txt"` | Yes | Valid HTTP/HTTPS URL to upstream `sha256sums.txt` |
| `node_exporter_bin_dir` | `string` | `"/usr/local/bin"` | Yes | Absolute directory path |
| `node_exporter_config_dir` | `string` | `"/etc/node_exporter"` | Yes | Absolute directory path |
| `node_exporter_system_user` | `string` | `"node_exporter"` | Yes | Non-empty Linux username |
| `node_exporter_system_group` | `string` | `"node_exporter"` | Yes | Non-empty Linux group name |
| `node_exporter_web_listen_address` | `string` | `"0.0.0.0:9100"` | Yes | Non-empty `[host]:port` string with valid TCP port (`1..65535`) |
| `node_exporter_web_telemetry_path` | `string` | `"/metrics"` | Yes | Non-empty URL path starting with `/` |
| `node_exporter_textfile_dir` | `string` | `"/var/lib/node_exporter/textfile_collector"` | No | Absolute path (or empty string `""` to disable automatic textfile directory setup) |
| `node_exporter_enabled_collectors` | `list[string \| dict]` | `[]` | No | List of collector names (`"systemd"`) or single-key option dicts (`{"filesystem": {"mount-points-exclude": "^/(sys\|proc)"}}`) |
| `node_exporter_disabled_collectors` | `list[string]` | `[]` | No | List of collector name strings (`["arp", "bcache"]`) |
| `node_exporter_extra_flags` | `list[string]` | `[]` | No | List of raw CLI flag strings (`["--log.level=info"]`) |
| `node_exporter_web_config` | `dict` | `{}` | No | Dictionary matching Prometheus exporter-toolkit `web-config.yml` schema (`tls_server_config`, `http_server_config`, `basic_auth_users`) |

---

### 2. Collector Configuration Entry (`node_exporter_enabled_collectors` item)

Represents an explicitly enabled collector and its optional sub-flags rendered into `/etc/systemd/system/node_exporter.service`.

| Variant | Example Input | Rendered CLI Flag(s) | Validation Rules |
|---|---|---|---|
| **Plain String** | `"processes"` | `--collector.processes` | Non-empty collector identifier (`[a-zA-Z0-9_.-]+`) |
| **Single-Key Mapping** | `{"filesystem": {"mount-points-exclude": "^/(sys\|proc)"}}` | `--collector.filesystem` <br> `--collector.filesystem.mount-points-exclude="^/(sys\|proc)"` | Dictionary with 1 collector name key mapping to a dictionary of sub-flag key-value options |

---

### 3. Web Security Configuration (`node_exporter_web_config`)

Represents the optional Prometheus exporter-toolkit configuration rendered to `{{ node_exporter_config_dir }}/config.yml` when non-empty.

| Top-Level Key | Type | Required | Description / Validation |
|---|---|---|---|
| `tls_server_config` | `dict` | No | Optional dictionary containing `cert_file`, `key_file`, optional `client_auth_type`, `client_ca_file`, `cipher_suites`, `min_version` |
| `http_server_config` | `dict` | No | Optional dictionary containing `http2` boolean or `headers` map |
| `basic_auth_users` | `dict[string, string]` | No | Optional mapping of `username: "<bcrypt_password_hash>"` |

---

### 4. Textfile Metric Store (`node_exporter_textfile_dir`)

Represents the filesystem directory watched by the `textfile` collector on the host.

| Attribute | Value / Rule |
|---|---|
| **Path** | `{{ node_exporter_textfile_dir }}` (default `"/var/lib/node_exporter/textfile_collector"`) |
| **Owner / Group** | `{{ node_exporter_system_user }}:{{ node_exporter_system_group }}` |
| **Permissions** | `'0755'` |
| **CLI Flag Binding** | Automatically adds `--collector.textfile.directory={{ node_exporter_textfile_dir }}` when `node_exporter_textfile_dir \| length > 0` and `"textfile"` is not in `node_exporter_disabled_collectors` |

## Relationships & Lifecycle State Transitions

1. **Node Exporter Daemon (1) ──> (1) System Account (`node_exporter:node_exporter`)**:
   - The `node_exporter.service` systemd unit executes as `User={{ node_exporter_system_user }}` and `Group={{ node_exporter_system_group }}`.
2. **Node Exporter Daemon (1) ──> (0..1) Textfile Metric Store**:
   - When `node_exporter_textfile_dir` is non-empty, the directory is provisioned before service start and linked via `--collector.textfile.directory`.
3. **Node Exporter Daemon (1) ──> (0..1) Web Security Configuration (`config.yml`)**:
   - When `node_exporter_web_config` is non-empty, `{{ node_exporter_config_dir }}/config.yml` is rendered (`0640`, `root:{{ node_exporter_system_group }}`) and passed via `--web.config.file`.
   - When `node_exporter_web_config` is `{}` (empty), `{{ node_exporter_config_dir }}/config.yml` is removed (`state: absent`) and `--web.config.file` is omitted from `node_exporter.service`.
4. **State Transitions**:
   - **Fresh Install**: Platform/input assertions pass → OS prerequisite packages (`tar`, `curl`, `ca-certificates`) installed → System group/user created → Binary archive downloaded & SHA256 verified → Binary extracted to `{{ node_exporter_bin_dir }}/node_exporter` → Textfile directory and optional `config.yml` created → `/etc/systemd/system/node_exporter.service` rendered → `systemd daemon_reload` + service enabled & started.
   - **Version Upgrade**: `{{ node_exporter_bin_dir }}/node_exporter --version` differs from `node_exporter_version` → New release tarball downloaded & SHA256 verified → Binary replaced → Handler validates and restarts `node_exporter.service`.
   - **Configuration / Collector Change**: `node_exporter.service` or `config.yml` modified → Handler reloads systemd daemon, validates binary/unit, and restarts `node_exporter.service`.
   - **Idempotent Re-run**: Installed binary version matches `node_exporter_version` and templates match on-disk files → Zero downloads, zero file modifications, zero service restarts (`changed=0`).
