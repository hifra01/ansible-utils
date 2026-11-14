# Role Interface Contract: `hifra01.utils.fluentbit`

**Feature**: `008-fluentbit-role`  
**Date**: 2026-11-14

## 1. Public Role Variables (`roles/fluentbit/defaults/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# defaults file for fluentbit

# Package and service state
fluentbit_package_state: present
fluentbit_service_enabled: true
fluentbit_service_state: started

# Configuration and persistent state directories
fluentbit_config_dir: "/etc/fluent-bit"
fluentbit_storage_dir: "/var/lib/fluent-bit"

# Global [SERVICE] settings
fluentbit_flush_interval: 1
fluentbit_log_level: "info"
fluentbit_http_server: false
fluentbit_http_listen: "127.0.0.1"
fluentbit_http_port: 2020

# Laravel multiline log input & parser configuration
fluentbit_laravel_enabled: true
fluentbit_laravel_log_paths:
  - "/var/www/*/storage/logs/*.log"
  - "/var/log/laravel/*.log"
fluentbit_laravel_tag: "laravel.app"
fluentbit_laravel_mem_buf_limit: "10MB"

# Nginx access and error log input & parser configuration
fluentbit_nginx_enabled: true
fluentbit_nginx_access_log_paths:
  - "/var/log/nginx/*access*.log"
fluentbit_nginx_error_log_paths:
  - "/var/log/nginx/*error*.log"
fluentbit_nginx_access_tag: "nginx.access"
fluentbit_nginx_error_tag: "nginx.error"

# System log input configuration ("systemd", "syslog", or "both")
fluentbit_system_log_enabled: true
fluentbit_system_log_mode: "systemd"
fluentbit_system_log_paths: []
fluentbit_system_systemd_filters: []
fluentbit_system_tag: "system.syslog"

# Extensibility lists for custom parsers, inputs, and filters
fluentbit_extra_parsers: []
fluentbit_extra_inputs: []
fluentbit_extra_filters: []

# Graylog (GELF) output configuration
fluentbit_graylog_enabled: false
fluentbit_graylog_host: "127.0.0.1"
fluentbit_graylog_port: 12201
fluentbit_graylog_mode: "udp"
fluentbit_graylog_match: "*"
fluentbit_graylog_tls_verify: true
fluentbit_graylog_extra_options: {}

# Grafana Loki output configuration
fluentbit_loki_enabled: false
fluentbit_loki_host: "127.0.0.1"
fluentbit_loki_port: 3100
fluentbit_loki_uri: "/loki/api/v1/push"
fluentbit_loki_match: "*"
fluentbit_loki_tls: false
fluentbit_loki_tls_verify: true
fluentbit_loki_tenant_id: ""
fluentbit_loki_http_user: ""
fluentbit_loki_http_passwd: ""
fluentbit_loki_bearer_token: ""
fluentbit_loki_labels:
  - "job=fluentbit"
  - "host=$hostname"
  - "source=$log_source"
  - "level=$level"
fluentbit_loki_line_format: "json"
fluentbit_loki_extra_options: {}

# Optional stdout and custom outputs
fluentbit_stdout_enabled: false
fluentbit_extra_outputs: []
```

## 2. OS-Specific Variables (`roles/fluentbit/vars/<ansible_os_family>.yml`)

### `roles/fluentbit/vars/Debian.yml`

```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for fluentbit (Debian family)

fluentbit_pre_packages:
  - ca-certificates
  - curl
  - gnupg

fluentbit_gpg_key_url: "https://packages.fluentbit.io/fluentbit.key"
fluentbit_apt_key_path: "/etc/apt/keyrings/fluentbit.asc"
fluentbit_apt_repo: >-
  deb [signed-by=/etc/apt/keyrings/fluentbit.asc]
  https://packages.fluentbit.io/{{ ansible_facts['distribution'] | lower }}/{{ ansible_facts['distribution_release'] }}
  {{ ansible_facts['distribution_release'] }} main
fluentbit_apt_repo_filename: "fluent-bit"

fluentbit_package_name: fluent-bit
fluentbit_service_name: fluent-bit
fluentbit_bin_path: /opt/fluent-bit/bin/fluent-bit

fluentbit_default_syslog_paths:
  - /var/log/syslog
  - /var/log/auth.log
```

### `roles/fluentbit/vars/RedHat.yml`

```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for fluentbit (RedHat family)

fluentbit_pre_packages:
  - ca-certificates

fluentbit_gpg_key_url: "https://packages.fluentbit.io/fluentbit.key"
fluentbit_yum_baseurl: "https://packages.fluentbit.io/centos/$releasever/"

fluentbit_package_name: fluent-bit
fluentbit_service_name: fluent-bit
fluentbit_bin_path: /opt/fluent-bit/bin/fluent-bit

fluentbit_default_syslog_paths:
  - /var/log/messages
  - /var/log/secure
```

## 3. Handlers Contract (`roles/fluentbit/handlers/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# handlers file for fluentbit

- name: Validate fluent-bit configuration
  ansible.builtin.command:
    cmd: "{{ fluentbit_bin_path }} --dry-run --config {{ fluentbit_config_dir }}/fluent-bit.conf"
  changed_when: false
  listen: "validate and restart fluent-bit"

- name: Restart fluent-bit
  ansible.builtin.service:
    name: "{{ fluentbit_service_name }}"
    state: restarted
  when: fluentbit_service_state == 'started'
  listen: "validate and restart fluent-bit"
```

## 4. Rendered Configuration Contract (`/etc/fluent-bit/parsers.conf` & `/etc/fluent-bit/fluent-bit.conf`)

### `/etc/fluent-bit/parsers.conf` (`templates/parsers.conf.j2`)

Defines:
- `[MULTILINE_PARSER] name laravel_multiline` (`type regex`, `flush_timeout 1000`, `start_state` matching `^\[\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:?\d{2}|Z)?\] \S+\.[A-Z]+: .*` -> `"cont"`, and `cont` matching `^(?!\[\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}).*` -> `"cont"`).
- `[PARSER] Name laravel` (`Format regex`, `Regex ^\[(?<time>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:?\d{2}|Z)?)\]\s+(?<env>[\w-]+)\.(?<level>[A-Z]+):\s+(?<message>[\s\S]*)$`).
- `[PARSER] Name nginx_access` (`Format regex` extracting `remote`, `host`, `user`, `time`, `method`, `path`, `code`, `size`, `referer`, `agent`, `http_x_forwarded_for`).
- `[PARSER] Name nginx_error` (`Format regex` extracting `time`, `level`, `pid`, `tid`, `cid`, `message`).
- `[PARSER] Name syslog-rfc3164` (`Format regex` extracting `time`, `host`, `ident`, `pid`, `message`).
- Any custom entries from `fluentbit_extra_parsers`.

### `/etc/fluent-bit/fluent-bit.conf` (`templates/fluent-bit.conf.j2`)

Defines:
- `[SERVICE]` block (`Flush`, `Daemon Off`, `Log_Level`, `Parsers_File`, `HTTP_Server`, `HTTP_Listen`, `HTTP_Port`, `storage.path`).
- Conditional `[INPUT]` and `[FILTER]` blocks for:
  - Laravel multiline logs (`tail` with `Multiline.Parser laravel_multiline`, `parser` filter with `Parser laravel` and `Reserve_Data On`, `modify` filter setting `log_source laravel` and normalizing `message`).
  - Nginx access logs (`tail`, `parser` filter with `Parser nginx_access`, `Reserve_Data On`, `Preserve_Key On`, `modify` filter setting `log_source nginx_access`, `Add level INFO`, and `Rename log message`).
  - Nginx error logs (`tail`, `parser` filter with `Parser nginx_error`, `Reserve_Data On`, `Preserve_Key On`, `modify` filter setting `log_source nginx_error` and normalizing `message`).
  - System logs (`systemd` and/or `tail` syslog files, normalized with `modify` filter so `message`, `log_source system`, and `level` are always present).
- Global `[FILTER] Name record_modifier` adding `hostname ${HOSTNAME}`.
- Conditional `[OUTPUT]` blocks for Graylog (`Name gelf` with `Gelf_Short_Message_Key message`, `Gelf_Host_Key hostname`), Grafana Loki (`Name loki` with `labels`, `line_format`), `stdout`, `fluentbit_extra_outputs`, or fallback `null` output when no output is enabled.
