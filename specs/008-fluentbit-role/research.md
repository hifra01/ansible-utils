# Phase 0 Research: Fluent Bit Log Collector and Forwarder Role (`fluentbit`)

**Feature**: `008-fluentbit-role`  
**Date**: 2026-11-14

## 1. Official Package Repository & Installation Strategy (`packages.fluentbit.io`)

- **Decision**:
  - Install `fluent-bit` from the official Fluent Bit package repositories at `https://packages.fluentbit.io` on both Debian-family and RedHat-family systems.
  - **Debian / Ubuntu (`vars/Debian.yml` & `tasks/setup-Debian.yml`)**:
    - Ensure `/etc/apt/keyrings` exists (`mode: '0755'`).
    - Download the official Fluent Bit GPG signing key from `https://packages.fluentbit.io/fluentbit.key` to `/etc/apt/keyrings/fluentbit.asc` (`mode: '0644'`).
    - Map `ansible_facts['distribution']` (`Ubuntu` -> `ubuntu`, `Debian` -> `debian`) and `ansible_facts['distribution_release']` (`jammy`, `noble`, `bookworm`) to the repository URL:
      `deb [signed-by=/etc/apt/keyrings/fluentbit.asc] https://packages.fluentbit.io/{{ ansible_facts['distribution'] | lower }}/{{ ansible_facts['distribution_release'] }} {{ ansible_facts['distribution_release'] }} main`
    - Manage `/etc/apt/sources.list.d/fluent-bit.list` via `ansible.builtin.apt_repository` and update the APT cache when changed.
  - **RedHat / Rocky Linux (`vars/RedHat.yml` & `tasks/setup-RedHat.yml`)**:
    - Configure `/etc/yum.repos.d/fluent-bit.repo` via `ansible.builtin.yum_repository` pointing to `https://packages.fluentbit.io/centos/$releasever/` (or `almalinux/$releasever/` / `rockylinux/$releasever/` — `centos/$releasever/` is the canonical upstream path supporting EL 8 and EL 9 with `gpgcheck: true` and `gpgkey: https://packages.fluentbit.io/fluentbit.key`).
  - **Package & Binary Layout**:
    - The upstream package name is `fluent-bit`.
    - It installs the binary to `/opt/fluent-bit/bin/fluent-bit`, default configs to `/etc/fluent-bit/fluent-bit.conf` and `/etc/fluent-bit/parsers.conf`, and systemd unit to `/lib/systemd/system/fluent-bit.service` (or `/usr/lib/systemd/system/fluent-bit.service`).
- **Rationale**:
  - Using the official upstream repositories guarantees up-to-date Fluent Bit v3.x/v4.x releases across Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 8, and Rocky Linux 9 with native `[MULTILINE_PARSER]`, `gelf`, `loki`, and `systemd` plugin support.
- **Alternatives Considered**:
  - *Compiling from source or downloading standalone tarballs*: Rejected because upstream APT/YUM repositories provide signed packages, automatic dependency resolution, and native systemd unit files.

## 2. Classic INI Configuration Format & Pre-Restart Validation (`--dry-run`)

- **Decision**:
  - Manage `/etc/fluent-bit/fluent-bit.conf` and `/etc/fluent-bit/parsers.conf` in Fluent Bit's classic INI-style format (confirmed in Session 2026-11-14 Q1).
  - Create `/var/lib/fluent-bit` (`owner: root`, `group: root`, `mode: '0750'`) as the persistent directory for SQLite tail offset databases (`laravel.db`, `nginx_access.db`, `nginx_error.db`, `syslog.db`).
  - Validate configuration before restarting the service using `/opt/fluent-bit/bin/fluent-bit --dry-run --config {{ fluentbit_config_dir }}/fluent-bit.conf`.
  - Because `fluent-bit.conf` references `Parsers_File {{ fluentbit_config_dir }}/parsers.conf`, `tasks/configure.yml` MUST render `parsers.conf` **before** rendering `fluent-bit.conf`, and run an explicit dry-run verification task (plus handler validation prior to service restart).
- **Rationale**:
  - Matches the upstream `fluent-bit.service` `ExecStart=/opt/fluent-bit/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf` without requiring systemd unit overrides.
  - Pre-restart `--dry-run` catches malformed regexes, invalid plugin names, or missing keys before interrupting an active log shipping daemon.
- **Alternatives Considered**:
  - *YAML configuration (`fluent-bit.yaml`)*: Rejected in clarification Q1 in favor of the upstream default INI format.

## 3. Laravel Multiline Log Parsing Pipeline (`[MULTILINE_PARSER]` + Regex `parser` Filter)

- **Decision**:
  - Define two parser blocks in `/etc/fluent-bit/parsers.conf` for Laravel logs (confirmed in Session 2026-11-14 Q2):
    1. `[MULTILINE_PARSER]` named `laravel_multiline`:
       - `type: regex`
       - `flush_timeout: 1000`
       - `rule "start_state" "/^\\[\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:[+-]\\d{2}:?\\d{2}|Z)?\\] \\S+\\.[A-Z]+: .*/" "cont"`
       - `rule "cont" "/^(?!\\[\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}).*/" "cont"`
    2. `[PARSER]` named `laravel`:
       - `Format: regex`
       - `Regex: /^\[(?<time>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{2}:?\d{2}|Z)?)\]\s+(?<env>[\w-]+)\.(?<level>[A-Z]+):\s+(?<message>[\s\S]*)$/`
  - In `/etc/fluent-bit/fluent-bit.conf`:
    - Configure `[INPUT] Name tail` with `Tag {{ fluentbit_laravel_tag }}`, `Path {{ fluentbit_laravel_log_paths | join(',') }}`, `Multiline.Parser laravel_multiline`, `DB {{ fluentbit_storage_dir }}/laravel.db`, `Mem_Buf_Limit {{ fluentbit_laravel_mem_buf_limit }}`, `Buffer_Max_Size 1M`, `Skip_Long_Lines On`, and `Refresh_Interval 5`.
    - Configure `[FILTER] Name parser` matching `{{ fluentbit_laravel_tag }}` with `Key_Name log`, `Parser laravel`, and `Reserve_Data On`.
    - Configure `[FILTER] Name modify` matching `{{ fluentbit_laravel_tag }}` to set `Add log_source laravel`, `Copy log message` (as fallback if a line did not match the regex), and `Remove_wildcard log`.
- **Rationale**:
  - `Multiline.Parser laravel_multiline` concatenates the `[YYYY-MM-DD HH:MM:SS] env.LEVEL: ...` header line and all subsequent stack trace frames (`#0 ...`, `[stacktrace]`, previous exceptions, JSON context) into a single `log` string.
  - Applying `[FILTER] Name parser` with `/[\s\S]*/` on `message` extracts `time`, `env`, `level`, and the entire multi-line `message` body cleanly.
- **Alternatives Considered**:
  - *Legacy `Multiline On` + `Parser_Firstline`*: Deprecated in Fluent Bit 2.x/3.x.

## 4. Nginx Access & Error Log Parsing and System Log Normalization

- **Decision**:
  - **Nginx Access Logs (`nginx.access`)**:
    - Define `[PARSER] Name nginx_access` (`Format regex`) matching standard Nginx `main` / combined format:
      `^(?<remote>[^ ]*) (?<host>[^ ]*) (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)"(?:\s+"(?<http_x_forwarded_for>[^"]*)")?)?`
      with `Time_Key time`, `Time_Format %d/%b/%Y:%H:%M:%S %z`, `Time_Keep On`.
    - Read via `[INPUT] Name tail` (without `Parser` in `[INPUT]` so raw `log` is preserved initially), then apply:
      1. `[FILTER] Name parser` (`Match {{ fluentbit_nginx_access_tag }}`, `Key_Name log`, `Parser nginx_access`, `Reserve_Data On`, `Preserve_Key On`).
      2. `[FILTER] Name modify` (`Match {{ fluentbit_nginx_access_tag }}`, `Add log_source nginx_access`, `Add level INFO`, `Rename log message`).
      This guarantees both structured HTTP fields (`remote`, `method`, `path`, `code`, `size`, `referer`, `agent`, `http_x_forwarded_for`) AND a non-empty `message` field containing the raw access line for Graylog GELF compatibility (confirmed in Session 2026-11-14 Q3).
  - **Nginx Error Logs (`nginx.error`)**:
    - Define `[PARSER] Name nginx_error` (`Format regex`):
      `^(?<time>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(?<level>\w+)\] (?<pid>\d+)\#(?<tid>\d+): (?:\*(?<cid>\d+) )?(?<message>.*)$`
      with `Time_Key time`, `Time_Format %Y/%m/%d %H:%M:%S`, `Time_Keep On`.
    - Read via `[INPUT] Name tail`, then apply `[FILTER] Name parser` (`Key_Name log`, `Parser nginx_error`, `Reserve_Data On`, `Preserve_Key On`) and `[FILTER] Name modify` (`Add log_source nginx_error`, `Copy log message`, `Remove log`).
  - **System Logs (`system.syslog`)**:
    - Support `fluentbit_system_log_mode`: `"systemd"` (default), `"syslog"`, or `"both"`.
    - When `"systemd"` or `"both"`: configure `[INPUT] Name systemd` (`Tag {{ fluentbit_system_tag }}`, `Read_From_Tail On`, `Strip_Underscores On`, optional `Systemd_Filter` entries). Normalize journald keys via `[FILTER] Name modify`: `Add log_source system`, `Copy MESSAGE message`, `Copy SYSLOG_IDENTIFIER syslog_identifier`, `Copy PRIORITY priority`, `Add level INFO`.
    - When `"syslog"` or `"both"`: configure `[INPUT] Name tail` on `{{ fluentbit_system_log_paths | join(',') }}` (`vars/Debian.yml`: `["/var/log/syslog", "/var/log/auth.log"]`; `vars/RedHat.yml`: `["/var/log/messages", "/var/log/secure"]`), parsed via `syslog-rfc3164` (`Reserve_Data On`, `Preserve_Key On`) and normalized with `Add log_source system`, `Copy log message`.
  - **Global Hostname Enrichment**:
    - Include `[FILTER] Name record_modifier` (`Match *`, `Record hostname ${HOSTNAME}`) so every record has `hostname` populated for both Loki labels and Graylog host mapping.
- **Rationale**:
  - Guarantees every log event across all 3 sources has `message`, `hostname`, `log_source`, and `level`, preventing Graylog from dropping GELF packets and preventing Loki label lookup warnings.

## 5. Graylog (`gelf`) and Grafana Loki (`loki`) Output Configuration

- **Decision**:
  - **Graylog Output (`[OUTPUT] Name gelf`)**:
    - Enabled when `fluentbit_graylog_enabled: true`.
    - Directives: `Match {{ fluentbit_graylog_match }}`, `Host {{ fluentbit_graylog_host }}`, `Port {{ fluentbit_graylog_port }}`, `Mode {{ fluentbit_graylog_mode }}` (`udp`, `tcp`, or `tls`), `Gelf_Short_Message_Key message`, `Gelf_Host_Key hostname`, `Gelf_Full_Message_Key full_message`.
    - When `fluentbit_graylog_mode == 'tls'`, set `tls On` and `tls.verify {{ 'On' if fluentbit_graylog_tls_verify else 'Off' }}`.
    - Render any key-value pairs in `fluentbit_graylog_extra_options`.
  - **Grafana Loki Output (`[OUTPUT] Name loki`)**:
    - Enabled when `fluentbit_loki_enabled: true`.
    - Directives: `Match {{ fluentbit_loki_match }}`, `Host {{ fluentbit_loki_host }}`, `Port {{ fluentbit_loki_port }}`, `uri {{ fluentbit_loki_uri }}`, `labels {{ fluentbit_loki_labels | join(', ') }}`, `line_format {{ fluentbit_loki_line_format }}`, `tls {{ 'On' if fluentbit_loki_tls else 'Off' }}`, `tls.verify {{ 'On' if fluentbit_loki_tls_verify else 'Off' }}`.
    - Optional authentication/tenancy directives rendered when non-empty: `tenant_id`, `http_user`, `http_passwd`, `bearer_token`.
    - Render any key-value pairs in `fluentbit_loki_extra_options`.
  - **Fallback & Custom Outputs**:
    - When `fluentbit_stdout_enabled: true`, render `[OUTPUT] Name stdout` (`Match *`, `Format json_lines`).
    - Render any custom output dicts in `fluentbit_extra_outputs`.
    - When no output (`graylog`, `loki`, `stdout`, or `extra_outputs`) is enabled, render `[OUTPUT] Name null` (`Match *`) so default role convergence and `--dry-run` validation succeed cleanly without requiring an external collector first.
- **Rationale**:
  - Supports sending to Graylog only, Loki only, or both simultaneously, while keeping out-of-the-box default convergence safe and self-contained.

## 6. Multi-Distro Molecule Verification Strategy

- **Decision**:
  - Scaffold `roles/fluentbit/` via `ansible-galaxy role init --init-path roles fluentbit` and `molecule init scenario default` inside `roles/fluentbit/`.
  - Keep the RHEL 8 `python39` bootstrap in `molecule/default/prepare.yml`, and also set up:
    1. Sample log directories (`/var/www/demo/storage/logs`, `/var/log/nginx`) and initial log files.
    2. Two lightweight local receiver services in `prepare.yml` (or mock listeners / file output + HTTP/UDP receivers using Python's standard library `http.server` / `socket` as systemd background units on `127.0.0.1:3100` for Loki `/loki/api/v1/push` and `127.0.0.1:12201` UDP/TCP for Graylog GELF, plus a `[OUTPUT] Name file` or `fluentbit_extra_outputs` capture file `/tmp/fluentbit-output.log` for deterministic payload inspection).
  - In `molecule/default/converge.yml`, apply `hifra01.utils.fluentbit` with:
    - `fluentbit_http_server: true` (`127.0.0.1:2020`)
    - `fluentbit_laravel_enabled: true`
    - `fluentbit_nginx_enabled: true`
    - `fluentbit_system_log_enabled: true`
    - `fluentbit_graylog_enabled: true` (`127.0.0.1`, port `12201`, mode `udp`)
    - `fluentbit_loki_enabled: true` (`127.0.0.1`, port `3100`)
    - `fluentbit_extra_outputs` writing parsed records to `/var/log/fluentbit-verified.jsonl` (`Name file`) so `verify.yml` can deterministically inspect the exact parsed JSON structure on disk in addition to verifying Loki HTTP push requests and Graylog GELF reception.
  - In `molecule/default/verify.yml`, write a multi-line Laravel exception log (with header + `#0`, `#1` stack trace frames), an Nginx access log line, an Nginx error log line, and a systemd journal entry, wait briefly for the 1-second flush interval, and assert:
    1. `/opt/fluent-bit/bin/fluent-bit --dry-run --config /etc/fluent-bit/fluent-bit.conf` succeeds (`rc == 0`).
    2. `fluent-bit.service` is enabled and active (`running`), and `http://127.0.0.1:2020/api/v1/health` (or `/`) returns HTTP 200.
    3. The Laravel multiline exception was consolidated into a single structured record with `env: "production"`, `level: "ERROR"`, and `message` containing both the exception message and `#0` / `#1` stack trace lines.
    4. The Nginx access log record contains extracted `remote`, `method`, `path`, `code`, `agent`, and non-empty `message`.
    5. The Nginx error log record contains extracted `level`, `pid`, `tid`, and `message`.
    6. Both Graylog (`gelf`) and Loki (`loki`) outputs processed records without output errors.
- **Rationale**:
  - Verifies real multi-line parsing, Nginx access/error parsing, system log collection, and dual Graylog + Loki shipping across all 5 CI distributions (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`).
