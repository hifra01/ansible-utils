# Role Interface Contract: `hifra01.utils.node_exporter`

**Feature**: `004-node-exporter-role`  
**Date**: 2026-11-07

## 1. Public Role Variables (`roles/node_exporter/defaults/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# defaults file for node_exporter

# Node Exporter release version (without leading 'v')
node_exporter_version: "1.8.2"

# Optional explicit SHA256 checksum digest (64 hex chars).
# When empty (""), the checksum is fetched automatically from node_exporter_checksums_url.
node_exporter_checksum: ""

# Architecture mapping from ansible_architecture to Prometheus release naming
node_exporter_arch_map:
  x86_64: amd64
  aarch64: arm64
  armv7l: armv7

# Download URLs for the release archive and sha256sums.txt
node_exporter_download_url: >-
  https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/node_exporter-{{ node_exporter_version }}.linux-{{ node_exporter_arch_map[ansible_architecture] | default(ansible_architecture) }}.tar.gz
node_exporter_checksums_url: >-
  https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/sha256sums.txt

# Installation & configuration paths
node_exporter_bin_dir: "/usr/local/bin"
node_exporter_config_dir: "/etc/node_exporter"
node_exporter_textfile_dir: "/var/lib/node_exporter/textfile_collector"

# Dedicated unprivileged system account
node_exporter_system_user: "node_exporter"
node_exporter_system_group: "node_exporter"

# Network listen socket and HTTP telemetry path
node_exporter_web_listen_address: "0.0.0.0:9100"
node_exporter_web_telemetry_path: "/metrics"

# Collectors to explicitly enable (--collector.<name>)
# Supports plain strings (e.g. "systemd") or single-key option dicts:
#   - systemd
#   - filesystem:
#       mount-points-exclude: "^/(sys|proc|dev|host|etc)($|/)"
node_exporter_enabled_collectors: []

# Collectors to explicitly disable (--no-collector.<name>)
node_exporter_disabled_collectors: []

# Raw extra command-line flags passed to node_exporter
node_exporter_extra_flags: []

# Optional web configuration (TLS and/or Basic Auth) rendered to {{ node_exporter_config_dir }}/config.yml
# Example:
#   tls_server_config:
#     cert_file: /etc/node_exporter/node_exporter.crt
#     key_file: /etc/node_exporter/node_exporter.key
#   basic_auth_users:
#     prometheus: "$2y$10$..."
node_exporter_web_config: {}
```

## 2. OS-Specific Variables (`roles/node_exporter/vars/<ansible_os_family>.yml`)

### `roles/node_exporter/vars/Debian.yml`
```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for node_exporter (Debian family)

node_exporter_prerequisite_packages:
  - ca-certificates
  - curl
  - tar

node_exporter_service_name: "node_exporter"
node_exporter_nologin_shell: "/usr/sbin/nologin"
```

### `roles/node_exporter/vars/RedHat.yml`
```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for node_exporter (RedHat family)

node_exporter_prerequisite_packages:
  - ca-certificates
  - curl
  - tar

node_exporter_service_name: "node_exporter"
node_exporter_nologin_shell: "/sbin/nologin"
```

## 3. Generated File Contracts

### `/etc/systemd/system/node_exporter.service`
- **Owner/Group**: `root:root`
- **Mode**: `'0644'`
- **Structure**:
  ```ini
  # Managed by Ansible (hifra01.utils.node_exporter)
  [Unit]
  Description=Prometheus Node Exporter
  Documentation=https://prometheus.io/docs/guides/node-exporter/
  Wants=network-online.target
  After=network-online.target

  [Service]
  Type=simple
  User=node_exporter
  Group=node_exporter
  ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=0.0.0.0:9100 \
    --web.telemetry-path=/metrics \
    --collector.textfile \
    --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
  SyslogIdentifier=node_exporter
  Restart=always
  RestartSec=5

  [Install]
  WantedBy=multi-user.target
  ```

### `/etc/node_exporter/config.yml` (when `node_exporter_web_config` is non-empty)
- **Owner/Group**: `root:{{ node_exporter_system_group }}`
- **Mode**: `'0640'`
- **Absent when**: `node_exporter_web_config | length == 0`
- **Structure**:
  ```yaml
  # Managed by Ansible (hifra01.utils.node_exporter)
  ---
  basic_auth_users:
    prometheus: $2b$12$...
  ```

## 4. Handler Contract (`roles/node_exporter/handlers/main.yml`)

- **Listener `"validate and restart node_exporter"`**:
  1. `Reload systemd daemon for node_exporter`: runs `ansible.builtin.systemd` with `daemon_reload: true`.
  2. `Validate node_exporter binary before restart`: runs `{{ node_exporter_bin_dir }}/node_exporter --version` (`changed_when: false`).
  3. `Restart node_exporter`: restarts `{{ node_exporter_service_name }}` (`state: restarted`).
