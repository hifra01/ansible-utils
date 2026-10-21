# Quickstart & Validation Guide: `hifra01.utils.consul`

**Feature**: `001-consul-role`  
**Date**: 2026-10-18

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
cd roles/consul
molecule converge
molecule verify
molecule idempotence
molecule destroy
```

**Expected Outcome**:
- `prepare` installs Python 3.9 on Rocky 8 (when applicable) and plants a stale service file (`/etc/consul.d/service-stale.json`) to verify purge behavior.
- `converge` installs HashiCorp Consul, configures the node in `server` mode (`consul_bootstrap_expect: 1`), renders advertised services in `/etc/consul.d/service-*.json`, purges `/etc/consul.d/service-stale.json`, validates `/etc/consul.d`, and starts `consul.service`.
- `idempotence` re-runs `converge` with `changed=0`.
- `verify` confirms:
  1. `consul` binary and systemd service are active.
  2. `consul members` lists the node in `server` mode as `alive`.
  3. Local HTTP catalog API (`http://127.0.0.1:8500/v1/agent/services`) returns all defined `consul_services` with expected ports, tags, and metadata.
  4. `/etc/consul.d/service-stale.json` has been removed.
  5. Client mode configuration (`consul_mode: "client"`) renders `server = false`, omits `bootstrap_expect`, and passes `consul validate`.

---

## Scenario 3: Full 5-Distro Matrix Verification

Run the mandatory 5-distro verification loop from `roles/consul/`:

```bash
cd roles/consul
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
- name: Deploy Consul Server Node
  hosts: consul_servers
  become: true
  roles:
    - role: hifra01.utils.consul
      vars:
        consul_mode: "server"
        consul_bootstrap_expect: 1
        consul_ui: true
        consul_client_addr: "0.0.0.0"

- name: Deploy Consul Client Node with Advertised Services
  hosts: app_servers
  become: true
  roles:
    - role: hifra01.utils.consul
      vars:
        consul_mode: "client"
        consul_retry_join:
          - "10.0.1.10"
        consul_services:
          - name: "web"
            id: "web-80"
            port: 80
            tags:
              - "http"
              - "production"
            meta:
              version: "1.0.0"
            checks:
              - id: "web-tcp"
                name: "TCP on port 80"
                tcp: "127.0.0.1:80"
                interval: "10s"
                timeout: "2s"
```
