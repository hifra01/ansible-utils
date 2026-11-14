# Quickstart & Validation Guide: `hifra01.utils.nginx_exporter` & `hifra01.utils.nginx` (`stub_status`)

**Feature**: `009-nginx-exporter-role`  
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

## Scenario 2: Single-Distro Molecule Iteration (`nginx_exporter`)

Run the Molecule scenario for `nginx_exporter` against the default Ubuntu 24.04 container:

```bash
cd roles/nginx_exporter
molecule converge
molecule verify
molecule idempotence
molecule destroy
```

**Expected Outcome**:
- `prepare` bootstraps Python 3.9 on Rocky Linux 8 (when applicable).
- `converge` applies `hifra01.utils.nginx` with `nginx_stub_status_enabled: true` (exposing `http://127.0.0.1:8080/stub_status`) followed by `hifra01.utils.nginx_exporter`, creating the `nginx_exporter` system user/group, downloading and SHA256-verifying the official `nginx-prometheus-exporter` binary archive, installing `/usr/local/bin/nginx-prometheus-exporter`, rendering `/etc/nginx_exporter/config.yml` and `/etc/systemd/system/nginx_exporter.service`, and enabling/starting `nginx_exporter.service`.
- `idempotence` re-runs `converge` with `changed=0` (no binary re-download or service restart).
- `verify` confirms:
  1. `/usr/local/bin/nginx-prometheus-exporter` exists with mode `'0755'` and reports the configured `nginx_exporter_version`.
  2. `nginx_exporter` system user and group exist with non-interactive login shell.
  3. `nginx_exporter.service` is enabled and active (`running`).
  4. `/etc/nginx_exporter/config.yml` exists (`0640`) and enforces HTTP Basic Auth (`401 Unauthorized` without credentials).
  5. Authenticated `http://127.0.0.1:9113/metrics` returns HTTP `200` and includes `nginx_up 1`, `nginx_connections_accepted`, `nginx_connections_active`, and `nginx_http_requests_total`.
  6. Resetting `nginx_exporter_web_config` to `{}` removes `/etc/nginx_exporter/config.yml` and serves `http://127.0.0.1:9113/metrics` (`200 OK`, `nginx_up 1`) without credentials.

---

## Scenario 3: Full 5-Distro Matrix Verification (`nginx_exporter` & `nginx`)

Run the mandatory 5-distro verification loop for `roles/nginx_exporter` (and `roles/nginx`):

```bash
for role in nginx nginx_exporter; do
  cd /Users/hill/.t3/worktrees/utils/t3-80125b49-3a157d10ae9f8043/roles/$role
  for img in \
    geerlingguy/docker-ubuntu2204-ansible:latest \
    geerlingguy/docker-ubuntu2404-ansible:latest \
    geerlingguy/docker-debian12-ansible:latest \
    geerlingguy/docker-rockylinux9-ansible:latest \
    geerlingguy/docker-rockylinux8-ansible:latest; do
    echo "=== $role: $img"
    MOLECULE_DISTRO="$img" molecule test && echo "PASS $role $img" || echo "FAIL $role $img"
  done
done
```

**Expected Outcome**: All 5 distributions report `PASS` for both `nginx` and `nginx_exporter`.

---

## Example Playbook Usage

See [contracts/role-interface.md](contracts/role-interface.md) and [data-model.md](data-model.md) for the complete variable schema.

```yaml
---
- name: Deploy NGINX with stub_status and Prometheus NGINX Exporter
  hosts: web_servers
  become: true
  roles:
    - role: hifra01.utils.nginx
      vars:
        nginx_stub_status_enabled: true
        nginx_stub_status_host: "127.0.0.1"
        nginx_stub_status_port: 8080
        nginx_stub_status_path: "/stub_status"

    - role: hifra01.utils.nginx_exporter
      vars:
        nginx_exporter_version: "1.4.1"
        nginx_exporter_web_listen_address: "0.0.0.0:9113"
        nginx_exporter_scrape_uri: "http://127.0.0.1:8080/stub_status"

- name: Deploy NGINX Exporter with Multiple Scrape Targets and Basic Auth
  hosts: multi_nginx_nodes
  become: true
  roles:
    - role: hifra01.utils.nginx_exporter
      vars:
        nginx_exporter_scrape_uri:
          - "http://127.0.0.1:8080/stub_status"
          - "http://127.0.0.1:8081/stub_status"
        nginx_exporter_extra_flags:
          - "--log.level=info"
        nginx_exporter_web_config:
          basic_auth_users:
            prometheus: "$2b$12$xZ7zEaVjOgF6mGHmDSMcRuMz5Zvp2o4ysMEau1sCcfzgI.r4Ktsd6"
```
