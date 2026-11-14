Fluent Bit Role
===============

This role installs and configures Fluent Bit (`fluent-bit`) from official upstream repositories across Debian-family and RedHat-family Linux distributions.

It provides out-of-the-box, toggleable log collection and parsing pipelines for:
* **Laravel Multiline Logs**: Groups multiline stack traces and exception frames into consolidated structured log events with extracted `time`, `env`, `level`, and `message` fields using a dedicated multiline parser and regex parser filter.
* **Nginx Access & Error Logs**: Parses standard access logs into structured HTTP fields (`remote`, `method`, `path`, `code`, `agent`, etc.) with normalized `message` summaries, and error logs into structured diagnostic events.
* **Linux System Logs**: Ingests system logs via `systemd` journal or traditional syslog files (`/var/log/syslog`, `/var/log/messages`).
* **Log Forwarding Destinations**: Forwards structured records to Graylog (via GELF over UDP/TCP/TLS), Grafana Loki (via HTTP/HTTPS push endpoint with custom stream labels), or both simultaneously, plus optional stdout or custom outputs.

Configuration files (`/etc/fluent-bit/fluent-bit.conf` and `/etc/fluent-bit/parsers.conf`) are validated before service restart using `/opt/fluent-bit/bin/fluent-bit --dry-run`.

Supported Platforms
-------------------

This role is compatible with:
* **Debian / Ubuntu**: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Debian 12 (Bookworm)
* **RedHat / Rocky Linux**: Rocky Linux 8, Rocky Linux 9, AlmaLinux 8/9, RHEL 8/9

Requirements
------------

* Ansible Core >= 2.21.0
* Target system with `systemd` init and root/sudo privileges (`become: true`)
* `gather_facts: true` (relies on `ansible_os_family` and distribution details)

Role Variables
--------------

### Package & Service Management

| Variable | Type | Default | Description |
|---|---|---|---|
| `fluentbit_package_state` | String | `"present"` | Package installation state (`"present"` or `"latest"`). |
| `fluentbit_service_enabled` | Boolean | `true` | Whether the `fluent-bit` systemd service is enabled on boot. |
| `fluentbit_service_state` | String | `"started"` | Desired state of `fluent-bit.service` (`"started"`, `"stopped"`). |
| `fluentbit_config_dir` | String | `"/etc/fluent-bit"` | Directory where Fluent Bit configuration files reside. |
| `fluentbit_storage_dir` | String | `"/var/lib/fluent-bit"` | Directory for persistent SQLite offset databases (`mode: '0750'`). |
| `fluentbit_flush_interval` | Integer | `1` | Service flush interval in seconds. |
| `fluentbit_log_level` | String | `"info"` | Internal daemon log level (`"off"`, `"error"`, `"warning"`, `"info"`, `"debug"`, `"trace"`). |
| `fluentbit_http_server` | Boolean | `false` | Enable built-in HTTP monitoring and health endpoint. |
| `fluentbit_http_listen` | String | `"127.0.0.1"` | Bind address for built-in HTTP server. |
| `fluentbit_http_port` | Integer | `2020` | Listening TCP port for built-in HTTP server. |

### Laravel Multiline Log Pipeline

| Variable | Type | Default | Description |
|---|---|---|---|
| `fluentbit_laravel_enabled` | Boolean | `true` | Enable Laravel multiline log collection and parsing. |
| `fluentbit_laravel_log_paths` | List | `["/var/www/*/storage/logs/*.log", "/var/log/laravel/*.log"]` | Log file path patterns to monitor. |
| `fluentbit_laravel_tag` | String | `"laravel.app"` | Tag applied to Laravel log records. |
| `fluentbit_laravel_mem_buf_limit` | String | `"10MB"` | Memory buffer limit for the Laravel `tail` input. |

### Nginx Access & Error Log Pipeline

| Variable | Type | Default | Description |
|---|---|---|---|
| `fluentbit_nginx_enabled` | Boolean | `true` | Enable Nginx access and error log collection and parsing. |
| `fluentbit_nginx_access_log_paths` | List | `["/var/log/nginx/*access*.log"]` | Log file path patterns for Nginx access logs. |
| `fluentbit_nginx_error_log_paths` | List | `["/var/log/nginx/*error*.log"]` | Log file path patterns for Nginx error logs. |
| `fluentbit_nginx_access_tag` | String | `"nginx.access"` | Tag applied to Nginx access log records. |
| `fluentbit_nginx_error_tag` | String | `"nginx.error"` | Tag applied to Nginx error log records. |

### System Log Pipeline

| Variable | Type | Default | Description |
|---|---|---|---|
| `fluentbit_system_log_enabled` | Boolean | `true` | Enable host system log collection. |
| `fluentbit_system_log_mode` | String | `"systemd"` | System log collection mode: `"systemd"`, `"syslog"`, or `"both"`. |
| `fluentbit_system_log_paths` | List | `[]` | Syslog file paths (defaults to OS syslog files when mode includes `"syslog"`). |
| `fluentbit_system_systemd_filters` | List | `[]` | Optional `Systemd_Filter` unit expressions. |
| `fluentbit_system_tag` | String | `"system.syslog"` | Tag applied to system log records. |

### Output Destinations

| Variable | Type | Default | Description |
|---|---|---|---|
| `fluentbit_graylog_enabled` | Boolean | `false` | Enable forwarding logs to Graylog via GELF. |
| `fluentbit_graylog_host` | String | `"127.0.0.1"` | Graylog target hostname or IP. |
| `fluentbit_graylog_port` | Integer | `12201` | Graylog GELF listening port. |
| `fluentbit_graylog_mode` | String | `"udp"` | GELF transport mode: `"udp"`, `"tcp"`, or `"tls"`. |
| `fluentbit_graylog_match` | String | `"*"` | Tag pattern for Graylog output. |
| `fluentbit_graylog_tls_verify` | Boolean | `true` | Verify TLS certificate when mode is `"tls"`. |
| `fluentbit_graylog_extra_options` | Dictionary | `{}` | Additional key-value directives for Graylog `gelf` output. |
| `fluentbit_loki_enabled` | Boolean | `false` | Enable forwarding logs to Grafana Loki. |
| `fluentbit_loki_host` | String | `"127.0.0.1"` | Loki target hostname or IP. |
| `fluentbit_loki_port` | Integer | `3100` | Loki HTTP/HTTPS port. |
| `fluentbit_loki_uri` | String | `"/loki/api/v1/push"` | Loki push API endpoint URI. |
| `fluentbit_loki_match` | String | `"*"` | Tag pattern for Loki output. |
| `fluentbit_loki_tls` | Boolean | `false` | Enable HTTPS/TLS for Loki output. |
| `fluentbit_loki_tls_verify` | Boolean | `true` | Verify Loki TLS certificate. |
| `fluentbit_loki_tenant_id` | String | `""` | Optional `X-Scope-OrgID` tenant identifier. |
| `fluentbit_loki_http_user` | String | `""` | Optional HTTP basic authentication user. |
| `fluentbit_loki_http_passwd` | String | `""` | Optional HTTP basic authentication password. |
| `fluentbit_loki_bearer_token` | String | `""` | Optional Bearer token for authentication. |
| `fluentbit_loki_labels` | List | `["job=fluentbit", "host=$hostname", "source=$log_source", "level=$level"]` | Stream labels applied to Loki records. |
| `fluentbit_loki_line_format` | String | `"json"` | Loki line format (`"json"` or `"key_value"`). |
| `fluentbit_loki_extra_options` | Dictionary | `{}` | Additional key-value directives for Loki output. |
| `fluentbit_stdout_enabled` | Boolean | `false` | Enable printing parsed records to stdout (for debugging). |
| `fluentbit_extra_parsers` | List | `[]` | Additional custom parser definitions appended to `parsers.conf`. |
| `fluentbit_extra_inputs` | List | `[]` | Additional custom `[INPUT]` blocks for `fluent-bit.conf`. |
| `fluentbit_extra_filters` | List | `[]` | Additional custom `[FILTER]` blocks for `fluent-bit.conf`. |
| `fluentbit_extra_outputs` | List | `[]` | Additional custom `[OUTPUT]` blocks for `fluent-bit.conf`. |

Example Playbooks
-----------------

### Example 1: Forward Logs to Grafana Loki

```yaml
- hosts: appservers
  become: true
  roles:
    - role: hifra01.utils.fluentbit
      vars:
        fluentbit_laravel_enabled: true
        fluentbit_laravel_log_paths:
          - "/var/www/*/storage/logs/*.log"
        fluentbit_nginx_enabled: true
        fluentbit_system_log_enabled: true
        fluentbit_loki_enabled: true
        fluentbit_loki_host: "loki.internal.example.com"
        fluentbit_loki_port: 3100
        fluentbit_loki_labels:
          - "job=fluentbit"
          - "host=$hostname"
          - "source=$log_source"
          - "level=$level"
```

### Example 2: Forward Logs to Graylog (GELF over UDP)

```yaml
- hosts: webservers
  become: true
  roles:
    - role: hifra01.utils.fluentbit
      vars:
        fluentbit_laravel_enabled: true
        fluentbit_nginx_enabled: true
        fluentbit_system_log_enabled: true
        fluentbit_graylog_enabled: true
        fluentbit_graylog_host: "graylog.internal.example.com"
        fluentbit_graylog_port: 12201
        fluentbit_graylog_mode: "udp"
```

### Example 3: Dual Forwarding to Both Graylog and Loki

```yaml
- hosts: webservers
  become: true
  roles:
    - role: hifra01.utils.fluentbit
      vars:
        fluentbit_http_server: true
        fluentbit_graylog_enabled: true
        fluentbit_graylog_host: "graylog.internal.example.com"
        fluentbit_graylog_port: 12201
        fluentbit_loki_enabled: true
        fluentbit_loki_host: "loki.internal.example.com"
        fluentbit_loki_port: 3100
        fluentbit_loki_tenant_id: "production"
```

License
-------

MIT-0
