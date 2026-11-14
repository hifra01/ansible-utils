# Phase 0 Research: Prometheus NGINX Exporter Role (`nginx_exporter`)

**Feature**: `009-nginx-exporter-role`  
**Date**: 2026-11-14

## 1. Binary Acquisition, Archive Layout & Checksum Verification

- **Decision**:
  - Download the official precompiled Prometheus NGINX Exporter release tarball (`nginx-prometheus-exporter_{{ nginx_exporter_version }}_linux_{{ _nginx_exporter_arch }}.tar.gz`) from `{{ nginx_exporter_download_url }}` (defaulting to `https://github.com/nginx/nginx-prometheus-exporter/releases/download/v{{ nginx_exporter_version }}/nginx-prometheus-exporter_{{ nginx_exporter_version }}_linux_{{ _nginx_exporter_arch }}.tar.gz`).
  - Map `ansible_architecture` (`x86_64` → `amd64`, `aarch64` → `arm64`, `armv7l` → `armv7`) via `nginx_exporter_arch_map` and assert supported architectures at the start of `tasks/main.yml`.
  - Verify the archive SHA256 checksum using `sha256:{{ nginx_exporter_checksum }}` when explicitly provided, or `sha256:{{ nginx_exporter_checksums_url }}` (`https://github.com/nginx/nginx-prometheus-exporter/releases/download/v{{ nginx_exporter_version }}/nginx-prometheus-exporter_{{ nginx_exporter_version }}_checksums.txt`) passed directly to `ansible.builtin.get_url`'s `checksum:` parameter.
  - Ensure `dest:` in `get_url` uses the exact upstream filename (`{{ _nginx_exporter_tempdir.path }}/nginx-prometheus-exporter_{{ nginx_exporter_version }}_linux_{{ _nginx_exporter_arch }}.tar.gz`) so `get_url`'s checksum manifest parser matches the filename unambiguously.
  - Note that unlike `node_exporter` (which extracts into a versioned subdirectory), the upstream `nginx-prometheus-exporter` tarball extracts the `nginx-prometheus-exporter` binary directly at the root of the extraction directory (`{{ _nginx_exporter_tempdir.path }}/nginx-prometheus-exporter`).
  - Guard downloading and extraction with an installed binary version check (`{{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter --version`) so subsequent runs do not re-download or re-extract when `nginx_exporter_version` is already installed.
- **Rationale**:
  - Verified directly against upstream `v1.4.1` release assets on GitHub (`nginx-prometheus-exporter_1.4.1_checksums.txt` and `nginx-prometheus-exporter_1.4.1_linux_amd64.tar.gz`).
  - `nginx-prometheus-exporter --version` outputs version information to stdout/stderr, enabling fast local idempotency checks without network requests on subsequent playbook runs.
- **Alternatives Considered**:
  - *Installing from OS repositories*: Rejected because neither Debian/Ubuntu nor RHEL/Rocky base repositories package `nginx-prometheus-exporter` consistently at current upstream versions.

## 2. Dedicated System User, Group & Binary Ownership

- **Decision**:
  - Create system group `{{ nginx_exporter_system_group }}` (default `"nginx_exporter"`, `system: true`) and system user `{{ nginx_exporter_system_user }}` (default `"nginx_exporter"`, `system: true`, `shell: "{{ nginx_exporter_nologin_shell }}"`, `create_home: false`, `home: "/"`).
  - Install the binary at `{{ nginx_exporter_bin_dir }}/nginx-prometheus-exporter` (default `"/usr/local/bin/nginx-prometheus-exporter"`) owned by `root:root` with mode `'0755'`.
- **Rationale**:
  - Follows the exact least-privilege security model established by `roles/node_exporter` (Principle III & IV). Running as an unprivileged user ensures the exporter cannot modify its own binary or access root-only files.
- **Alternatives Considered**:
  - *Running as the `nginx` / `www-data` user*: Rejected because `nginx_exporter` only needs HTTP network access to the `stub_status` endpoint and does not need access to NGINX private TLS keys or web root files.

## 3. Scrape URI Formatting & CLI Flags in `nginx_exporter.service.j2`

- **Decision**:
  - Render `/etc/systemd/system/nginx_exporter.service` via `templates/nginx_exporter.service.j2`.
  - Support `nginx_exporter_scrape_uri` as either a non-empty string (default `"http://127.0.0.1:8080/stub_status"`) or a non-empty list of strings (e.g., `["http://127.0.0.1:8080/stub_status", "http://127.0.0.1:8081/stub_status"]`):
    - If `nginx_exporter_scrape_uri is string`: pass `--nginx.scrape-uri={{ nginx_exporter_scrape_uri }}`.
    - If `nginx_exporter_scrape_uri is sequence`: pass `--nginx.scrape-uri={{ uri }}` for each item in `nginx_exporter_scrape_uri`.
  - Pass core CLI flags supported by `nginx-prometheus-exporter` v1.x:
    - `--web.listen-address={{ nginx_exporter_web_listen_address }}`
    - `--web.telemetry-path={{ nginx_exporter_web_telemetry_path }}`
    - `--nginx.timeout={{ nginx_exporter_timeout }}`
    - When `nginx_exporter_nginx_plus | bool`: `--nginx.plus`
    - When `not (nginx_exporter_ssl_verify | bool)`: `--no-nginx.ssl-verify` (in Kingpin-based `nginx-prometheus-exporter` v1.x, boolean flags default to false/true and `--nginx.ssl-verify` is enabled via `--nginx.ssl-verify` or disabled via `--no-nginx.ssl-verify`; we will verify exact CLI flag behavior of the v1.4.1 binary).
    - When `nginx_exporter_web_config | length > 0`: `--web.config.file={{ nginx_exporter_config_dir }}/config.yml`
    - For each raw flag in `nginx_exporter_extra_flags`: append the flag string.
- **Rationale**:
  - Matches clarified requirement Session 2026-11-14 Q1 (`FR-006`) and upstream `nginx-prometheus-exporter` v1.4.1 CLI flags.
- **Alternatives Considered**:
  - *Using environment variables (`SCRAPE_URI`, `LISTEN_ADDRESS`)*: Rejected in favor of explicit CLI flags in `ExecStart` for consistency with `roles/node_exporter` and clear `systemctl cat nginx_exporter` visibility.

## 4. Companion `stub_status` Toggle in `roles/nginx`

- **Decision**:
  - Add user-tunable defaults to `roles/nginx/defaults/main.yml`:
    - `nginx_stub_status_enabled: false`
    - `nginx_stub_status_host: "127.0.0.1"`
    - `nginx_stub_status_port: 8080`
    - `nginx_stub_status_path: "/stub_status"`
    - `nginx_stub_status_allow: ["127.0.0.1", "::1"]`
    - `nginx_stub_status_access_log: "off"`
  - Create `roles/nginx/templates/stub_status.conf.j2` rendering:
    ```nginx
    server {
        listen {{ nginx_stub_status_host }}:{{ nginx_stub_status_port }};
        server_name localhost;

        location {{ nginx_stub_status_path }} {
            stub_status;
            access_log {{ nginx_stub_status_access_log }};
    {% for ip in nginx_stub_status_allow %}
            allow {{ ip }};
    {% endfor %}
            deny all;
        }
    }
    ```
  - In `roles/nginx/tasks/main.yml`:
    - Assert valid `nginx_stub_status_*` types/values.
    - When `nginx_stub_status_enabled | bool`: render `{{ nginx_config_dir }}/conf.d/stub_status.conf` (`mode: '0644'`) notifying `"validate and reload nginx"`.
    - When `not (nginx_stub_status_enabled | bool)`: ensure `{{ nginx_config_dir }}/conf.d/stub_status.conf` is `absent`, notifying `"validate and reload nginx"`.
    - In `Clean up unused site configurations`, update the exclusion list from `['cloudflare.conf', 'trusted_proxies.conf']` to `['cloudflare.conf', 'trusted_proxies.conf', 'stub_status.conf']` so RedHat systems (where `nginx_site_enabled_dir` is `/etc/nginx/conf.d`) never purge `stub_status.conf`.
- **Rationale**:
  - Solves the RedHat `/etc/nginx/conf.d` cleanup conflict identified during architecture review and incorporates the clarified `access_log off;` default (Session 2026-11-14 Q3).
- **Alternatives Considered**:
  - *Having `roles/nginx_exporter` write directly to `/etc/nginx/conf.d/stub_status.conf`*: Rejected because any subsequent run of `roles/nginx` on RedHat would delete the file unless `roles/nginx` is aware of it, and it violates role isolation when `nginx_exporter` is used with custom or remote NGINX instances.

## 5. Multi-Distro Molecule Verification Strategy

- **Decision**:
  - In `roles/nginx_exporter/molecule/default/`:
    - `converge.yml` includes `hifra01.utils.nginx` with `nginx_stub_status_enabled: true` (using the default `127.0.0.1:8080/stub_status` and default site on port 80), followed by `hifra01.utils.nginx_exporter` (with `basic_auth_users` in `nginx_exporter_web_config` and `--log.level=info` in `nginx_exporter_extra_flags`).
    - `verify.yml` asserts:
      1. `/usr/local/bin/nginx-prometheus-exporter` exists with mode `'0755'` and outputs version `1.4.1`.
      2. `nginx_exporter` user and group exist with `nologin` shell.
      3. `nginx_exporter.service` is active and enabled.
      4. `/etc/nginx_exporter/config.yml` exists with mode `'0640'`.
      5. Unauthenticated `GET http://127.0.0.1:9113/metrics` returns `401 Unauthorized`.
      6. Authenticated `GET http://127.0.0.1:9113/metrics` returns `200 OK` and includes `nginx_up 1`, `nginx_connections_accepted`, `nginx_connections_active`, and `nginx_http_requests_total`.
      7. Re-converging with `nginx_exporter_web_config: {}` removes `/etc/nginx_exporter/config.yml` and allows unauthenticated `GET http://127.0.0.1:9113/metrics` (`200 OK`, `nginx_up 1`).
  - In `roles/nginx/molecule/default/`:
    - Note that `roles/nginx/molecule/default/converge.yml` already binds `cf_protected` to port `8080`, `custom_inline` to `8081`, and `custom_templated` to `8082`. Therefore, in `roles/nginx/molecule/default/converge.yml`, test `nginx_stub_status_enabled: true` with `nginx_stub_status_port: 8085` (or test it in `converge.yml` and verify `http://127.0.0.1:8085/stub_status` returns `Active connections:` in `verify.yml`, and also verify cleanup when `nginx_stub_status_enabled: false`).
- **Rationale**:
  - Directly implements Session 2026-11-14 Q2 while avoiding port `8080` collision with `cf_protected` in `roles/nginx/molecule/default/converge.yml`.
