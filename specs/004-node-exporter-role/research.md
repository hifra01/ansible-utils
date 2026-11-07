# Phase 0 Research: Prometheus Node Exporter Role (`node_exporter`)

**Feature**: `004-node-exporter-role`  
**Date**: 2026-11-07

## 1. Binary Acquisition, Architecture Mapping & Checksum Verification

- **Decision**:
  - Download the official precompiled Prometheus Node Exporter release tarball (`node_exporter-{{ node_exporter_version }}.linux-{{ _node_exporter_arch }}.tar.gz`) from `{{ node_exporter_download_url }}` (defaulting to `https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/node_exporter-{{ node_exporter_version }}.linux-{{ _node_exporter_arch }}.tar.gz`).
  - Map `ansible_architecture` (`x86_64` → `amd64`, `aarch64` → `arm64`, `armv7l` → `armv7`) in `vars/main.yml` (or OS vars) and assert supported architectures at the start of `tasks/main.yml`.
  - Verify the archive SHA256 checksum using `sha256:{{ node_exporter_checksum }}` when explicitly provided by the user, or `sha256:{{ node_exporter_checksums_url }}` (`https://github.com/prometheus/node_exporter/releases/download/v{{ node_exporter_version }}/sha256sums.txt`) passed directly to `ansible.builtin.get_url`'s `checksum:` parameter.
  - Guard downloading and extraction with an installed binary version check (`{{ node_exporter_bin_dir }}/node_exporter --version`) or `stat` check so subsequent runs do not re-download or re-extract when the target version is already installed.
- **Rationale**:
  - Official distro repositories (APT/DNF) either lag significantly behind upstream Prometheus releases or lack `node_exporter` altogether in base RHEL/Rocky repositories without EPEL.
  - `ansible.builtin.get_url` natively supports `checksum: "sha256:<url_to_sha256sums.txt>"`, automatically matching the filename against the remote `sha256sums.txt` manifest while allowing offline/air-gapped users to supply a literal SHA256 digest via `node_exporter_checksum`.
  - Checking the installed binary version before downloading ensures fast, offline-friendly idempotency on already converged hosts and clean upgrades when `node_exporter_version` changes.
- **Alternatives Considered**:
  - *Installing via OS package managers (`apt`/`dnf`)*: Rejected during clarification because package names (`prometheus-node-exporter` vs `golang-github-prometheus-node-exporter` vs EPEL `node_exporter`), binary paths, and CLI flags vary wildly across distros and versions.
  - *Delegating download to `localhost` (`delegate_to: localhost`) and copying binary*: Rejected because target hosts in this collection (and Molecule Docker containers) download directly from upstream releases, avoiding controller temporary directory races during parallel execution.

## 2. Dedicated System User, Group & Directory Permissions

- **Decision**:
  - Create system group `{{ node_exporter_system_group }}` (default `"node_exporter"`, `system: true`) and system user `{{ node_exporter_system_user }}` (default `"node_exporter"`, `system: true`, `shell: "/usr/sbin/nologin"`, `create_home: false`, `home: "/"`).
  - Install the `node_exporter` binary at `{{ node_exporter_bin_dir }}/node_exporter` (default `"/usr/local/bin/node_exporter"`) owned by `root:root` with mode `'0755'`.
  - Create the textfile collector directory `{{ node_exporter_textfile_dir }}` (default `"/var/lib/node_exporter/textfile_collector"`) when `node_exporter_textfile_dir | length > 0`, owned by `{{ node_exporter_system_user }}:{{ node_exporter_system_group }}` with mode `'0755'` ( ensuring parent directory `/var/lib/node_exporter` exists with `'0755'`).
- **Rationale**:
  - Owning the binary by `root:root` prevents the unprivileged `node_exporter` user from modifying its own executable if compromised.
  - Owning `node_exporter_textfile_dir` by `node_exporter:node_exporter` with mode `'0755'` allows both root cron jobs and scripts running under the `node_exporter` group/user to write `.prom` files readable by the daemon.
- **Alternatives Considered**:
  - *Running `node_exporter` as `root`*: Rejected as a security anti-pattern; standard host metrics in `/proc` and `/sys` are world-readable.

## 3. Collector Flags & Textfile Collector Configuration

- **Decision**:
  - Render `/etc/systemd/system/node_exporter.service` via `templates/node_exporter.service.j2`.
  - In `ExecStart`, pass:
    - `--web.listen-address={{ node_exporter_web_listen_address }}`
    - `--web.telemetry-path={{ node_exporter_web_telemetry_path }}`
    - When `node_exporter_textfile_dir | length > 0`: `--collector.textfile --collector.textfile.directory={{ node_exporter_textfile_dir }}` (unless `"textfile"` is in `node_exporter_disabled_collectors` or already explicitly configured in `node_exporter_enabled_collectors`).
    - For each item in `node_exporter_enabled_collectors`:
      - If item is a string (e.g., `"systemd"`): render `--collector.systemd`.
      - If item is a mapping (e.g., `{"filesystem": {"mount-points-exclude": "^/(sys|proc)"}}`): render `--collector.filesystem` and `--collector.filesystem.mount-points-exclude="^/(sys|proc)"` for each key-value option.
    - For each collector name in `node_exporter_disabled_collectors`: render `--no-collector.<name>`.
    - When `node_exporter_web_config` is non-empty: render `--web.config.file={{ node_exporter_config_dir }}/config.yml`.
    - For each raw flag in `node_exporter_extra_flags`: append the flag string.
- **Rationale**:
  - Matches the clarified specification (Session 2026-11-07 Q2) and established Prometheus community conventions, supporting both simple collector toggles and parameterized collectors cleanly inside a deterministic Jinja2 template.
- **Alternatives Considered**:
  - *Using an `/etc/default/node_exporter` or `/etc/sysconfig/node_exporter` `EnvironmentFile`*: Rejected because rendering flags directly in `/etc/systemd/system/node_exporter.service` avoids systemd environment variable word-splitting pitfalls with complex regex flags (such as `mount-points-exclude`) and keeps configuration in a single unit file.

## 4. Web Configuration (`--web.config.file`) & Handler Validation

- **Decision**:
  - When `node_exporter_web_config` is non-empty (`node_exporter_web_config | length > 0`):
    - Ensure `{{ node_exporter_config_dir }}` (default `"/etc/node_exporter"`) exists (`owner: root`, `group: "{{ node_exporter_system_group }}"`, `mode: '0750'`).
    - Render `{{ node_exporter_config_dir }}/config.yml` from `templates/config.yml.j2` (`{{ node_exporter_web_config | to_nice_yaml(indent=2) }}`, `owner: root`, `group: "{{ node_exporter_system_group }}"`, `mode: '0640'`).
  - When `node_exporter_web_config` is empty (`{}`):
    - Ensure `{{ node_exporter_config_dir }}/config.yml` is `absent`.
  - Group service restart handlers via `listen: "validate and restart node_exporter"`:
    1. Run `ansible.builtin.systemd` with `daemon_reload: true`.
    2. Validate the binary and flags (`{{ node_exporter_bin_dir }}/node_exporter --version` and systemd unit verification) before restarting `node_exporter.service` (`state: restarted`).
- **Rationale**:
  - Satisfies Constitution Principle IV ("Service configuration handlers MUST validate configuration before reloading or restarting, grouped via `listen:`") and FR-008/FR-009.
- **Alternatives Considered**:
  - *Leaving an empty `/etc/node_exporter/config.yml` when `node_exporter_web_config` is `{}`*: Rejected during clarification (Session 2026-11-07 Q3) in favor of clean file removal and omitting `--web.config.file`.

## 5. Multi-Distro Molecule Verification & RHEL 8 Compatibility

- **Decision**:
  - Scaffold the role with `ansible-galaxy role init --init-path roles node_exporter` and `molecule init scenario default`.
  - Use the standard 5-distro Docker systemd setup (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) with the RHEL 8 `python39` bootstrap in `prepare.yml`.
  - In `prepare.yml`, pre-create a sample custom textfile metric (`/var/lib/node_exporter/textfile_collector/custom_test.prom` containing `node_exporter_custom_test_metric 42`) or create it in `verify.yml` to test `SC-003`.
  - In `converge.yml`, apply `hifra01.utils.node_exporter` with custom collector configurations (e.g., enabling a collector and configuring textfile directory).
  - In `verify.yml`, assert:
    1. `node_exporter` binary exists at `/usr/local/bin/node_exporter` with mode `'0755'` and outputs the expected `node_exporter_version`.
    2. `node_exporter` user and group exist as system accounts with `/usr/sbin/nologin`.
    3. `node_exporter.service` is enabled and active (`running`).
    4. Port `9100` is listening and `http://127.0.0.1:9100/metrics` returns HTTP `200` containing `node_exporter_build_info` and standard metrics (`node_cpu_seconds_total`, `node_memory_`).
    5. Writing a `.prom` file into `/var/lib/node_exporter/textfile_collector/molecule_test.prom` exposes the custom metric on subsequent scrapes of `http://127.0.0.1:9100/metrics`.
    6. Applying `node_exporter_web_config` (e.g., `basic_auth_users`) renders `/etc/node_exporter/config.yml` with mode `'0640'` and enforces HTTP Basic Auth (`401 Unauthorized` without credentials, `200 OK` with credentials), then cleanly removes `/etc/node_exporter/config.yml` when reset to `{}`.
- **Rationale**:
  - Comprehensively verifies all 3 user stories and all 5 success criteria (`SC-001` through `SC-005`) across all 5 supported Linux distributions in a single automated Molecule test suite.
