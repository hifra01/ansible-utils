# Feature Specification: Fluent Bit Log Collector and Forwarder Role (`fluentbit`)

**Feature Branch**: `008-fluentbit-role`

**Created**: 2026-11-10

**Status**: Draft

**Input**: User description: "create ansible role to install fluentbit with ability to parse laravel multiline log, nginx access and error log, system log, and send them to graylog or loki. name branch based on convention."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install and Manage Fluent Bit Daemon on Target Hosts (Priority: P1)

Infrastructure operators and site reliability engineers need to install Fluent Bit from official upstream repositories on Linux servers and manage it as a persistent systemd service so that host and application logs can be collected, parsed, buffered, and forwarded reliably with minimal CPU and memory overhead.

**Why this priority**: Installing the Fluent Bit package, configuring its base service settings, validating configuration files before service reload/restart, and maintaining a running daemon is the foundational prerequisite before any log parsing or forwarding pipeline can operate.

**Independent Test**: Can be fully tested by applying the `fluentbit` role to a clean Linux host with default settings, verifying that the official repository is configured, the `fluent-bit` package is installed, configuration validation (`--dry-run`) succeeds, the `fluent-bit` systemd service is enabled at boot and actively running, and the HTTP monitoring/health endpoint (when enabled) or service status reports healthy operation.

**Acceptance Scenarios**:

1. **Given** a clean supported Linux host (Debian/Ubuntu or RHEL/Rocky/AlmaLinux), **When** the operator applies the `fluentbit` role with default settings, **Then** the official Fluent Bit repository is configured, the `fluent-bit` package is installed, `/etc/fluent-bit/fluent-bit.conf` and `/etc/fluent-bit/parsers.conf` are rendered and validated, the state directory `/var/lib/fluent-bit` is created for tail position tracking, and the `fluent-bit` systemd service is enabled and started.
2. **Given** an already provisioned host with Fluent Bit running, **When** the operator re-runs the role with unchanged variables, **Then** no packages are reinstalled, configuration files remain unmodified, the `fluent-bit` service is not restarted, and the playbook completes with zero changes (idempotent).
3. **Given** a host with an active Fluent Bit service, **When** an operator provides an invalid configuration setting or malformed parser definition, **Then** the pre-restart configuration validation (`fluent-bit --dry-run`) fails fast and halts the play before restarting or breaking the active daemon.

---

### User Story 2 - Collect and Parse Laravel Multiline Logs, Nginx Access/Error Logs, and System Logs (Priority: P2)

Platform and application engineers need built-in, toggleable log input and parsing pipelines for Laravel application logs (including multi-line stack traces and exception dumps), Nginx web server access and error logs, and host system logs (systemd journal and/or syslog files) so that raw log streams are transformed into structured records with accurate timestamps, severity levels, and extracted fields.

**Why this priority**: Collecting and accurately structuring the three core log sources requested by the user (Laravel multiline logs, Nginx access/error logs, and Linux system logs) is the primary data-processing value of the role.

**Independent Test**: Can be independently tested by enabling the Laravel, Nginx, and system log inputs on a test host, writing sample log entries (including a multi-line Laravel exception with stack trace frames, an Nginx access request line, an Nginx error line, and a system log entry), and verifying that Fluent Bit parses each source into structured events where the entire Laravel multi-line exception is emitted as a single consolidated log record rather than fragmented per-line events.

**Acceptance Scenarios**:

1. **Given** the Laravel log input is enabled and pointed at one or more Laravel log file patterns (e.g., `/var/www/*/storage/logs/*.log`), **When** Laravel writes a log entry containing a `[YYYY-MM-DD HH:MM:SS] environment.LEVEL: message` header followed by multi-line stack trace frames (`#0 ...`, `#1 ...`, `[stacktrace]`, or JSON context lines), **Then** Fluent Bit combines the header and all continuation lines into a single structured log record containing extracted `time`, `env`, `level`, and full multi-line `message` fields.
2. **Given** the Nginx log input is enabled, **When** Nginx writes entries to `/var/log/nginx/access.log` and `/var/log/nginx/error.log` (or custom configured paths), **Then** Fluent Bit parses access log lines into structured HTTP fields (`remote`, `user`, `method`, `path`, `code`, `size`, `referer`, `agent`, `http_x_forwarded_for`) and error log lines into structured diagnostic fields (`level`, `pid`, `tid`, `cid`, `message`).
3. **Given** the system log input is enabled, **When** the operating system or host services (such as `sshd`, `sudo`, `systemd`, or kernel) emit log events via systemd journal or `/var/log/syslog` / `/var/log/messages`, **Then** Fluent Bit collects and enriches those records with host and unit/syslog metadata (`hostname`, `syslog_identifier`, `priority`, `message`).
4. **Given** tail-based file inputs (Laravel and Nginx logs) are configured with persistent state tracking (`DB`), **When** the `fluent-bit` service is restarted, **Then** Fluent Bit resumes reading from the last recorded byte offset in `/var/lib/fluent-bit/` without re-sending previously ingested log lines or dropping lines written during the brief restart window.

---

### User Story 3 - Forward Structured Logs to Graylog, Grafana Loki, or Both (Priority: P3)

Infrastructure operators need to configure Fluent Bit to ship collected and parsed logs to Graylog (via GELF over UDP/TCP/TLS), Grafana Loki (via HTTP/HTTPS Loki push API with structured stream labels), or both destinations simultaneously so that logs are centrally indexed, searchable, and alertable in the organization's observability platform.

**Why this priority**: Delivering structured logs to Graylog and/or Loki completes the observability pipeline and fulfills the user's requirement for selectable centralized log destinations.

**Independent Test**: Can be independently tested by configuring the role with Graylog (`gelf`) output and/or Loki (`loki`) output (pointing to a local receiver or mock endpoint during verification), generating sample Laravel, Nginx, and system log entries, and verifying that formatted GELF messages and/or Loki JSON push payloads with expected stream labels (`job`, `host`, `source`, `level`, `env`) are transmitted without output plugin errors.

**Acceptance Scenarios**:

1. **Given** Graylog output is enabled with target host, port, and protocol settings (`udp`, `tcp`, or `tls`), **When** logs are collected from any enabled source, **Then** Fluent Bit normalizes ensuring a non-empty short message and forwards records using the `gelf` output plugin with mapped host, timestamp, severity level, and structured custom fields.
2. **Given** Grafana Loki output is enabled with target host, port, TLS/auth options, and label mappings, **When** logs are collected from any enabled source, **Then** Fluent Bit forwards batches to Loki's push endpoint (`/loki/api/v1/push`) with configured stream labels (such as `host`, `source`, `job`, `env`, `level`) and structured or JSON line formatting.
3. **Given** both Graylog and Loki outputs are enabled simultaneously (or switched independently via role boolean/list variables), **When** the role is applied, **Then** Fluent Bit routes all matched log streams (`laravel.*`, `nginx.*`, `system.*`, and any custom tags) to every enabled destination without duplicating input tail readers.

---

### Edge Cases

- **Unsupported operating system family**: When executed on an OS family outside `Debian` and `RedHat` (e.g., Alpine or Archlinux), the role fails immediately at the beginning of execution with a clear assertion error message before modifying repositories or files.
- **Missing log files at startup**: When Laravel or Nginx log directories or files do not yet exist on the host at the time Fluent Bit starts (e.g., before the web server or application is deployed), Fluent Bit starts cleanly and automatically begins tailing matching files as soon as they are created (`Path` wildcard scanning).
- **Very long or rapid Laravel stack traces**: When a Laravel exception spans dozens of stack frames or exceeds standard single-line buffer sizes, the multiline parser buffer and `Buffer_Max_Size` accommodate the complete trace without truncating or splitting mid-trace, and flush lingering partial multiline buffers after a configurable timeout (e.g., `multiline.flush` / `Mem_Buf_Limit`).
- **GELF requirement for `short_message` field**: Graylog's GELF specification strictly drops messages lacking a `short_message` key (`Gelf_Short_Message_Key`); the role ensures parsed records from Nginx access logs (which may not natively contain a `message` field) and systemd journal entries map or synthesize a non-empty `message` field before reaching the `gelf` output plugin.
- **Destination unavailability / network backpressure**: When the remote Graylog or Loki server is temporarily unreachable, Fluent Bit retries delivery according to configurable `Retry_Limit` and memory/filesystem buffering limits without crashing the daemon or exhausting host memory.
- **Invalid output configuration**: When a user enables Graylog or Loki output without providing a valid target host or port, or enables no output plugins at all while `fluentbit_require_output` is true, pre-flight assertions fail fast with an actionable error message.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The role MUST validate at the beginning of `tasks/main.yml` that the target host belongs to a supported OS family (`Debian` or `RedHat`) and that configured variables (log source settings, Graylog/Loki output parameters, and transport protocols) are valid, failing fast with a descriptive assertion message otherwise.
- **FR-002**: The role MUST isolate OS-specific repository URLs, GPG keys, package names, and default system log paths/modes in `vars/Debian.yml` and `vars/RedHat.yml`.
- **FR-003**: The role MUST configure the official Fluent Bit package repository (`https://packages.fluentbit.io`) with GPG signature verification on both Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) and RedHat-family (Rocky Linux 8, Rocky Linux 9) distributions and install the `fluent-bit` package.
- **FR-004**: The role MUST manage the Fluent Bit configuration directory (`/etc/fluent-bit`), main configuration file (`/etc/fluent-bit/fluent-bit.conf`), parser configuration file (`/etc/fluent-bit/parsers.conf`), and persistent tail state directory (`/var/lib/fluent-bit`) with appropriate ownership (`root:root`) and quoted octal permissions (`'0640'` or `'0644'` for config files, `'0750'` for state directory).
- **FR-005**: The role MUST configure and manage a multiline parser (`laravel_multiline`) and companion regex parser capable of parsing standard Laravel log entries (`[YYYY-MM-DD HH:MM:SS] <env>.<LEVEL>: <message>` plus any subsequent stack trace or context continuation lines not starting with a new timestamp bracket) into a single structured record with `time`, `env`, `level`, and `message` fields.
- **FR-006**: The role MUST configure and manage parsers and `tail` inputs for Nginx access logs (extracting `remote`, `host`, `user`, `time`, `method`, `path`, `code`, `size`, `referer`, `agent`, `http_x_forwarded_for`, and preserving/constructing a `message` summary field for GELF compatibility) and Nginx error logs (extracting `time`, `level`, `pid`, `tid`, `cid`, and `message`).
- **FR-007**: The role MUST configure and manage system log collection supporting systemd journal (`systemd` input plugin) and/or traditional syslog files (`/var/log/syslog` and `/var/log/auth.log` on Debian-family; `/var/log/messages` and `/var/log/secure` on RedHat-family), normalizing records so a consistent `message`, `level`/`priority`, and `hostname` field are present across both modes.
- **FR-008**: The role MUST support forwarding collected logs to Graylog using Fluent Bit's `gelf` output plugin (configurable host, port, mode `udp`/`tcp`/`tls`, TLS verification options, and GELF key mappings) and/or Grafana Loki using Fluent Bit's `loki` output plugin (configurable host, port, URI `/loki/api/v1/push`, TLS, optional HTTP basic auth or bearer token, tenant ID, line format, and stream labels), plus an optional `stdout` or custom output list for testing and extensibility.
- **FR-009**: The role MUST provide user-tunable, `fluentbit_`-prefixed variables in `defaults/main.yml` with explanatory comments, including at minimum:
  - `fluentbit_package_state` (package state for `fluent-bit`, default `"present"`)
  - `fluentbit_service_enabled` (boolean to enable `fluent-bit` service at boot, default `true`)
  - `fluentbit_service_state` (desired `fluent-bit` service state, default `"started"`)
  - `fluentbit_config_dir` (configuration directory path, default `"/etc/fluent-bit"`)
  - `fluentbit_storage_dir` (persistent state/position database directory, default `"/var/lib/fluent-bit"`)
  - `fluentbit_flush_interval` (service flush interval in seconds, default `1`)
  - `fluentbit_log_level` (daemon internal log level: `error`, `warning`, `info`, `debug`, `trace`, default `"info"`)
  - `fluentbit_http_server` (boolean to enable built-in HTTP monitoring server, default `false`)
  - `fluentbit_http_listen` (HTTP monitoring bind address, default `"127.0.0.1"`)
  - `fluentbit_http_port` (HTTP monitoring port, default `2020`)
  - `fluentbit_laravel_enabled` (boolean to enable Laravel multiline log collection, default `true`)
  - `fluentbit_laravel_log_paths` (list of file path globs for Laravel logs, default `["/var/www/*/storage/logs/*.log", "/var/log/laravel/*.log"]`)
  - `fluentbit_laravel_tag` (tag assigned to Laravel log records, default `"laravel.app"`)
  - `fluentbit_laravel_mem_buf_limit` (memory buffer limit for Laravel tail input, default `"10MB"`)
  - `fluentbit_nginx_enabled` (boolean to enable Nginx access and error log collection, default `true`)
  - `fluentbit_nginx_access_log_paths` (list of file path globs for Nginx access logs, default `["/var/log/nginx/*access*.log"]`)
  - `fluentbit_nginx_error_log_paths` (list of file path globs for Nginx error logs, default `["/var/log/nginx/*error*.log"]`)
  - `fluentbit_nginx_access_tag` (tag for Nginx access logs, default `"nginx.access"`)
  - `fluentbit_nginx_error_tag` (tag for Nginx error logs, default `"nginx.error"`)
  - `fluentbit_system_log_enabled` (boolean to enable host system log collection, default `true`)
  - `fluentbit_system_log_mode` (system log input mode: `"systemd"` for journald, `"syslog"` for `/var/log/` files, or `"both"`, default `"systemd"`)
  - `fluentbit_system_log_paths` (list of syslog file paths when mode is `"syslog"` or `"both"`, defaulting to OS-appropriate paths from `vars/<os_family>.yml`)
  - `fluentbit_system_systemd_filters` (optional list of `Systemd_Filter` unit expressions such as `_SYSTEMD_UNIT=sshd.service`, default `[]` for all units)
  - `fluentbit_system_tag` (tag for system log records, default `"system.syslog"`)
  - `fluentbit_extra_parsers` (list of custom parser definitions to append to `parsers.conf`, default `[]`)
  - `fluentbit_extra_inputs` (list of custom `[INPUT]` block dictionaries, default `[]`)
  - `fluentbit_extra_filters` (list of custom `[FILTER]` block dictionaries, default `[]`)
  - `fluentbit_graylog_enabled` (boolean to enable Graylog `gelf` output, default `false`)
  - `fluentbit_graylog_host` (Graylog target hostname or IP, default `"127.0.0.1"`)
  - `fluentbit_graylog_port` (Graylog GELF input port, default `12201`)
  - `fluentbit_graylog_mode` (GELF transport protocol: `"udp"`, `"tcp"`, or `"tls"`, default `"udp"`)
  - `fluentbit_graylog_match` (tag match pattern for Graylog output, default `"*"`)
  - `fluentbit_graylog_tls_verify` (boolean to verify TLS certificate when mode is `"tls"`, default `true`)
  - `fluentbit_graylog_extra_options` (dictionary of additional key-value directives for the `gelf` output block, default `{}`)
  - `fluentbit_loki_enabled` (boolean to enable Grafana Loki output, default `false`)
  - `fluentbit_loki_host` (Loki target hostname or IP, default `"127.0.0.1"`)
  - `fluentbit_loki_port` (Loki HTTP/HTTPS port, default `3100`)
  - `fluentbit_loki_uri` (Loki push API URI path, default `"/loki/api/v1/push"`)
  - `fluentbit_loki_match` (tag match pattern for Loki output, default `"*"`)
  - `fluentbit_loki_tls` (boolean to enable TLS for Loki output, default `false`)
  - `fluentbit_loki_tls_verify` (boolean to verify Loki TLS certificate, default `true`)
  - `fluentbit_loki_tenant_id` (optional `X-Scope-OrgID` tenant identifier for multi-tenant Loki, default `""`)
  - `fluentbit_loki_http_user` (optional HTTP basic auth username for Loki, default `""`)
  - `fluentbit_loki_http_passwd` (optional HTTP basic auth password/token for Loki, default `""`)
  - `fluentbit_loki_bearer_token` (optional HTTP Bearer token for Loki, default `""`)
  - `fluentbit_loki_labels` (list of `key=value` or field accessor strings for Loki stream labels, default `["job=fluentbit", "host=$hostname", "source=$log_source", "level=$level"]`)
  - `fluentbit_loki_line_format` (Loki payload line format: `"json"` or `"key_value"`, default `"json"`)
  - `fluentbit_loki_extra_options` (dictionary of additional key-value directives for the `loki` output block, default `{}`)
  - `fluentbit_stdout_enabled` (boolean to enable `stdout` output plugin, useful for local debugging or when neither Graylog nor Loki is enabled, default `false`)
  - `fluentbit_extra_outputs` (list of custom `[OUTPUT]` block dictionaries, default `[]`)
- **FR-010**: The role MUST validate rendered Fluent Bit configuration files using `/opt/fluent-bit/bin/fluent-bit --dry-run --config {{ fluentbit_config_dir }}/fluent-bit.conf` before restarting the `fluent-bit` systemd service in handlers (`validate and restart fluent-bit`).
- **FR-011**: All tasks in the role MUST adhere to collection coding standards (FQCNs, descriptive task names in imperative case, quoted octal file modes, `fluentbit_` variable prefixing, and OS family vars dispatch) and be strictly idempotent across all 5 supported CI matrix distributions.

### Key Entities

- **Fluent Bit Daemon (`fluent-bit.service`)**: The lightweight log processor and forwarder running under systemd supervision (`fluent-bit` package installed into `/opt/fluent-bit/bin/fluent-bit` with configuration in `/etc/fluent-bit/`).
- **Log Source Pipeline (`[INPUT]` & `[FILTER]`)**: Modular ingestion definitions for Laravel multiline application logs (`laravel.*`), Nginx access and error logs (`nginx.access`, `nginx.error`), and host system logs (`system.syslog`), enriched with common host/source metadata and normalized message/severity fields.
- **Parser Registry (`/etc/fluent-bit/parsers.conf`)**: Definitions of regular expression and multiline parsers (`laravel_multiline`, `nginx_access`, `nginx_error`, `syslog-rfc3164` / `syslog-rfc5424`) used to convert unstructured log text into typed key-value fields.
- **Log Destination (`[OUTPUT]`)**: Configured forwarding sinks sending enriched log records to Graylog (`gelf` plugin over UDP/TCP/TLS) and/or Grafana Loki (`loki` plugin over HTTP/HTTPS with stream labels), or custom outputs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy and start the Fluent Bit service across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in a single playbook execution, with the service reaching an active (running) state within 30 seconds.
- **SC-002**: 100% of multi-line Laravel exception log entries (header line plus multi-line stack trace) written to monitored Laravel log paths are grouped and emitted as a single structured event containing extracted timestamp, environment, severity level, and full stack trace message.
- **SC-003**: 100% of standard Nginx access log lines, Nginx error log lines, and host system log entries are parsed into structured records with their expected fields and forwarded to the configured Graylog (GELF) and/or Loki destination endpoints within 5 seconds of being written.
- **SC-004**: Re-running the role on an already converged host with unchanged variables results in 0 changed tasks and 0 service restarts across all 5 supported distributions.
- **SC-005**: 100% of syntax or schema errors introduced in Fluent Bit inputs, parsers, filters, or outputs are caught by pre-restart dry-run validation before interrupting an active running daemon.

## Assumptions

- Target hosts use `systemd` as their init and service manager across supported Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) and RedHat-family (Rocky Linux 8, Rocky Linux 9) distributions.
- Target hosts have outbound network access to `https://packages.fluentbit.io` to fetch the official Fluent Bit GPG key and OS packages during installation, and network reachability to the user's Graylog and/or Loki endpoints at runtime.
- Fluent Bit runs as `root` (the upstream package systemd unit default) so that it has read access to `/var/log/nginx/*.log`, `/var/log/syslog` or `/var/log/messages`, systemd journal files (`/var/log/journal` / `/run/log/journal`), and application log directories under `/var/www/*/storage/logs/*.log` without requiring complex ACL changes on third-party log directories.
- When neither `fluentbit_graylog_enabled`, `fluentbit_loki_enabled`, `fluentbit_stdout_enabled`, nor `fluentbit_extra_outputs` is enabled by the user, the role automatically configures a safe null (`null`) or `stdout` fallback output so that default installations (and baseline convergence tests) start cleanly and validate with `fluent-bit --dry-run` out of the box.
- Provisioning the remote Graylog server or Grafana Loki server itself is outside the scope of this role; this role manages the host-side Fluent Bit agent, its log collection/parsing rules, and its forwarding outputs.
