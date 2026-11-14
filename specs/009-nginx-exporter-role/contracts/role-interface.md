# Role Interface Contract: `hifra01.utils.nginx_exporter` & `hifra01.utils.nginx` (`stub_status`)

**Feature**: `009-nginx-exporter-role`  
**Date**: 2026-11-14

## 1. Public Role Variables (`roles/nginx_exporter/defaults/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# defaults file for nginx_exporter

# Prometheus NGINX Exporter release version (without leading 'v')
nginx_exporter_version: "1.4.1"

# Optional explicit SHA256 checksum digest (64 hex chars).
# When empty (""), the checksum is fetched automatically from nginx_exporter_checksums_url.
nginx_exporter_checksum: ""

# Architecture mapping from ansible_architecture to release archive naming
nginx_exporter_arch_map:
  x86_64: amd64
  aarch64: arm64
  armv7l: armv7

# Download URLs for the release archive and checksums.txt
nginx_exporter_download_url: >-
  https://github.com/nginx/nginx-prometheus-exporter/releases/download/v{{ nginx_exporter_version }}/nginx-prometheus-exporter_{{
  nginx_exporter_version }}_linux_{{
  nginx_exporter_arch_map[ansible_facts['architecture'] | default(ansible_architecture)] |
  default(ansible_facts['architecture'] | default(ansible_architecture)) }}.tar.gz
nginx_exporter_checksums_url: >-
  https://github.com/nginx/nginx-prometheus-exporter/releases/download/v{{ nginx_exporter_version }}/nginx-prometheus-exporter_{{
  nginx_exporter_version }}_checksums.txt

# Installation & configuration paths
nginx_exporter_bin_dir: "/usr/local/bin"
nginx_exporter_config_dir: "/etc/nginx_exporter"

# Dedicated unprivileged system account
nginx_exporter_system_user: "nginx_exporter"
nginx_exporter_system_group: "nginx_exporter"

# Network listen socket and HTTP telemetry path
nginx_exporter_web_listen_address: "0.0.0.0:9113"
nginx_exporter_web_telemetry_path: "/metrics"

# Target NGINX stub_status or NGINX Plus API URI(s).
# Accepts either a single URI string or a list of URI strings.
nginx_exporter_scrape_uri: "http://127.0.0.1:8080/stub_status"

# NGINX Plus API mode and scrape behavior
nginx_exporter_nginx_plus: false
nginx_exporter_ssl_verify: true
nginx_exporter_timeout: "5s"

# Raw extra command-line flags passed to nginx-prometheus-exporter
nginx_exporter_extra_flags: []

# Optional web configuration (TLS and/or Basic Auth) rendered to {{ nginx_exporter_config_dir }}/config.yml
nginx_exporter_web_config: {}

# Service lifecycle management
nginx_exporter_service_enabled: true
nginx_exporter_service_state: "started"
```

## 2. Companion `stub_status` Variables (`roles/nginx/defaults/main.yml`)

```yaml
# NGINX stub_status configuration (for Prometheus nginx_exporter scraping)
nginx_stub_status_enabled: false
nginx_stub_status_host: "127.0.0.1"
nginx_stub_status_port: 8080
nginx_stub_status_path: "/stub_status"
nginx_stub_status_allow:
  - "127.0.0.1"
  - "::1"
nginx_stub_status_access_log: "off"
```

## 3. OS-Specific Variables (`roles/nginx_exporter/vars/<ansible_os_family>.yml`)

### `roles/nginx_exporter/vars/Debian.yml`
```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for nginx_exporter (Debian family)

nginx_exporter_prerequisite_packages:
  - ca-certificates
  - curl
  - tar

nginx_exporter_service_name: "nginx_exporter"
nginx_exporter_nologin_shell: "/usr/sbin/nologin"
```

### `roles/nginx_exporter/vars/RedHat.yml`
```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for nginx_exporter (RedHat family)

nginx_exporter_prerequisite_packages:
  - ca-certificates
  - tar

nginx_exporter_service_name: "nginx_exporter"
nginx_exporter_nologin_shell: "/sbin/nologin"
```

## 4. Generated File Contracts

### `/etc/systemd/system/nginx_exporter.service`
- **Owner/Group**: `root:root`
- **Mode**: `'0644'`
- **Structure**:
  ```ini
  # Managed by Ansible (hifra01.utils.nginx_exporter)
  [Unit]
  Description=Prometheus NGINX Exporter
  Documentation=https://github.com/nginx/nginx-prometheus-exporter
  Wants=network-online.target
  After=network-online.target

  [Service]
  Type=simple
  User=nginx_exporter
  Group=nginx_exporter
  ExecStart=/usr/local/bin/nginx-prometheus-exporter \
    --web.listen-address=0.0.0.0:9113 \
    --web.telemetry-path=/metrics \
    --nginx.scrape-uri=http://127.0.0.1:8080/stub_status \
    --nginx.timeout=5s
  SyslogIdentifier=nginx_exporter
  Restart=always
  RestartSec=5

  [Install]
  WantedBy=multi-user.target
  ```

### `/etc/nginx_exporter/config.yml` (when `nginx_exporter_web_config` is non-empty)
- **Owner/Group**: `root:{{ nginx_exporter_system_group }}`
- **Mode**: `'0640'`
- **Absent when**: `nginx_exporter_web_config | length == 0`
- **Structure**:
  ```yaml
  # Managed by Ansible (hifra01.utils.nginx_exporter)
  ---
  basic_auth_users:
    prometheus: $2b$12$...
  ```

### `/etc/nginx/conf.d/stub_status.conf` (when `nginx_stub_status_enabled` is `true` in `roles/nginx`)
- **Owner/Group**: `root:root`
- **Mode**: `'0644'`
- **Absent when**: `not (nginx_stub_status_enabled | bool)`
- **Structure**:
  ```nginx
  server {
      listen 127.0.0.1:8080;
      server_name localhost;

      location /stub_status {
          stub_status;
          access_log off;
          allow 127.0.0.1;
          allow ::1;
          deny all;
      }
  }
  ```

## 5. Handler Contract (`roles/nginx_exporter/handlers/main.yml`)

- **Listener `"validate and restart nginx_exporter"`**:
  1. `Reload systemd daemon for nginx_exporter`: runs `ansible.builtin.systemd` with `daemon_reload: true`.
  2. `Validate nginx_exporter binary before restart`: runs `{{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter --version` (`changed_when: false`).
  3. `Restart nginx_exporter`: restarts `{{ nginx_exporter_service_name }}` (`state: restarted`).
