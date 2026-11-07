# Quickstart & Validation Guide: `hifra01.utils.node_exporter`

**Feature**: `004-node-exporter-role`  
**Date**: 2026-11-07

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

## Scenario 2: Single-Distro Molecule Iteration

Run the Molecule scenario against the default Ubuntu 24.04 container:

```bash
cd roles/node_exporter
molecule converge
molecule verify
molecule idempotence
molecule destroy
```

**Expected Outcome**:
- `prepare` bootstraps Python 3.9 on Rocky Linux 8 (when applicable).
- `converge` creates the `node_exporter` system user/group, downloads and SHA256-verifies the official Prometheus Node Exporter binary archive, installs `/usr/local/bin/node_exporter`, creates `/var/lib/node_exporter/textfile_collector`, renders `/etc/systemd/system/node_exporter.service`, and enables/starts `node_exporter.service`.
- `idempotence` re-runs `converge` with `changed=0` (no binary re-download or service restart).
- `verify` confirms:
  1. `/usr/local/bin/node_exporter` exists with mode `'0755'` and reports the configured `node_exporter_version`.
  2. `node_exporter` system user and group exist with non-interactive login shell.
  3. `node_exporter.service` is enabled and active (`running`).
  4. `http://127.0.0.1:9100/metrics` returns HTTP `200` and includes `node_exporter_build_info`, `node_cpu_seconds_total`, and `node_memory_` metrics.
  5. Placing a custom `.prom` file in `/var/lib/node_exporter/textfile_collector/` exposes the custom metric on subsequent HTTP `/metrics` scrapes.
  6. Applying `node_exporter_web_config` renders `/etc/node_exporter/config.yml` (`0640`), enforces basic authentication, and cleanly removes `/etc/node_exporter/config.yml` when reset to `{}`.

---

## Scenario 3: Full 5-Distro Matrix Verification

Run the mandatory 5-distro verification loop from `roles/node_exporter/`:

```bash
cd roles/node_exporter
for img in \
  geerlingguy/docker-ubuntu2204-ansible:latest \
  geerlingguy/docker-ubuntu2404-ansible:latest \
  geerlingguy/docker-debian12-ansible:latest \
  geerlingguy/docker-rockylinux9-ansible:latest \
  geerlingguy/docker-rockylinux8-ansible:latest; do
  echo "=== $img"
  MOLECULE_DISTRO="$img" molecule test && echo "PASS $img" || echo "FAIL $img"
done
```

**Expected Outcome**: All 5 distributions report `PASS`.

---

## Example Playbook Usage

See [contracts/role-interface.md](contracts/role-interface.md) and [data-model.md](data-model.md) for the complete variable schema.

```yaml
---
- name: Deploy Prometheus Node Exporter with Defaults
  hosts: all
  become: true
  roles:
    - role: hifra01.utils.node_exporter

- name: Deploy Node Exporter with Custom Collectors and Basic Auth
  hosts: monitored_nodes
  become: true
  roles:
    - role: hifra01.utils.node_exporter
      vars:
        node_exporter_version: "1.8.2"
        node_exporter_web_listen_address: "0.0.0.0:9100"
        node_exporter_enabled_collectors:
          - processes
          - filesystem:
              mount-points-exclude: "^/(sys|proc|dev|host|etc)($|/)"
        node_exporter_disabled_collectors:
          - arp
          - bcache
        node_exporter_web_config:
          basic_auth_users:
            prometheus: "$2b$12$hNf2lSsxfm0.i4a.1k2SOVyBCf551VRWrB0324/MPQ.1yG6ia1kG"
```
