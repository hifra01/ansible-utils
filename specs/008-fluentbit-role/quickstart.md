# Quickstart & Validation Guide: `hifra01.utils.fluentbit`

**Feature**: `008-fluentbit-role`  
**Date**: 2026-11-14

## Prerequisites

- Python virtual environment with collection test dependencies installed:
  ```bash
  source .venv/bin/activate
  pip install -r requirements.txt
  ```
- Running Docker daemon (for Molecule multi-distro container verification).

---

## Scenario 1: Static Analysis & Linting

From the repository root, run `yamllint` and `ansible-lint`:

```bash
yamllint .
ansible-lint
```

**Expected Outcome**: Both linters exit `0` with zero warnings or errors.

---

## Scenario 2: Single-Distro Molecule Verification

Test the `fluentbit` role on Ubuntu 24.04:

```bash
./test-matrix.sh -r fluentbit -o ubuntu2404
```

Or run Molecule steps interactively from inside `roles/fluentbit`:

```bash
cd roles/fluentbit
molecule converge
molecule verify
molecule idempotence
molecule destroy
```

**Expected Outcome**:
- `prepare`: Bootstraps Python 3.9 on RHEL/Rocky 8 if applicable, creates sample `/var/www/demo/storage/logs/laravel.log` and `/var/log/nginx/{access,error}.log` directories, and starts lightweight mock Graylog UDP (`127.0.0.1:12201`) and Loki HTTP (`127.0.0.1:3100`) listeners.
- `converge`: Configures the official Fluent Bit repository (`packages.fluentbit.io`), installs `fluent-bit`, creates `/var/lib/fluent-bit` (`0750`), renders `/etc/fluent-bit/parsers.conf` and `/etc/fluent-bit/fluent-bit.conf`, validates the configuration with `/opt/fluent-bit/bin/fluent-bit --dry-run`, and starts/enables `fluent-bit.service`.
- `verify`:
  1. Verifies `/opt/fluent-bit/bin/fluent-bit` binary exists and `--dry-run` configuration validation passes.
  2. Verifies `fluent-bit.service` is active (`running`) and enabled at boot, and the built-in HTTP monitoring endpoint (`http://127.0.0.1:2020/api/v1/health`) returns HTTP 200.
  3. Writes a multi-line Laravel exception log (with stack trace lines `#0`, `#1`), an Nginx access log entry, an Nginx error log entry, and a system log entry, then verifies:
     - The Laravel multi-line exception is grouped into a single structured event with `env: "production"`, `level: "ERROR"`, and the full multi-line `message`.
     - The Nginx access log entry is parsed into `remote`, `method`, `path`, `code`, `agent`, and preserves a non-empty `message` field.
     - The Nginx error log entry is parsed into `level`, `pid`, `tid`, and `message`.
     - System log entries are collected with `log_source: "system"` and `message`.
     - Payloads are delivered to both the Graylog (`gelf`) and Loki (`loki`) endpoints without output errors.
- `idempotence`: Re-running `converge` produces `changed=0` and 0 service restarts.

---

## Scenario 3: Full 5-Distro CI Matrix Verification

Execute Molecule tests across all five supported distributions in parallel using the repository's matrix runner:

```bash
./test-matrix.sh -r fluentbit
```

**Expected Outcome**: All 5 distributions (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) pass with zero failures.

---

## Example Playbook Usage

### 1. Ship Laravel, Nginx, and System Logs to Grafana Loki

```yaml
---
- name: Deploy Fluent Bit forwarding logs to Grafana Loki
  hosts: app_servers
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
          - "env=$env"
```

### 2. Ship Laravel, Nginx, and System Logs to Graylog (GELF over UDP/TCP/TLS)

```yaml
---
- name: Deploy Fluent Bit forwarding logs to Graylog via GELF
  hosts: web_servers
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

### 3. Dual Shipping to Both Graylog and Grafana Loki

```yaml
---
- name: Deploy Fluent Bit forwarding logs to both Graylog and Loki
  hosts: prod_servers
  become: true
  roles:
    - role: hifra01.utils.fluentbit
      vars:
        fluentbit_http_server: true
        fluentbit_graylog_enabled: true
        fluentbit_graylog_host: "graylog.internal.example.com"
        fluentbit_graylog_port: 12201
        fluentbit_graylog_mode: "tcp"
        fluentbit_loki_enabled: true
        fluentbit_loki_host: "loki.internal.example.com"
        fluentbit_loki_port: 3100
        fluentbit_loki_tenant_id: "production"
```
