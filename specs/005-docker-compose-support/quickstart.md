# Quickstart & Validation Guide: `hifra01.utils.docker`

**Feature**: `005-docker-compose-support`  
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
.venv/bin/yamllint .
.venv/bin/ansible-lint
```

**Expected Outcome**: Both linters exit `0` with zero errors.

---

## Scenario 2: Single-Distro Molecule Iteration

Run the Molecule scenario against the default Ubuntu 24.04 container:

```bash
cd roles/docker
../../.venv/bin/molecule converge
../../.venv/bin/molecule idempotence
../../.venv/bin/molecule verify
../../.venv/bin/molecule destroy
```

**Expected Outcome**:
- `prepare` bootstraps Python 3.9 on RHEL/Rocky 8 and creates a pre-existing unmanaged directory `/srv/unmanaged-data` to test non-destructive `/srv` behavior.
- `converge` installs Docker CE + `docker-compose-plugin`, configures `/etc/docker/daemon.json`, and deploys Compose projects:
  1. `webapp`: saved in the default `/srv/webapp/compose.yml` with `.env` (`mode: '0600'`) and started (`state: present`).
  2. `templated_app`: rendered from a custom Jinja2 `template` with injected `vars` into a custom directory (`/srv/templated_app/docker-compose.yml`) and started.
  3. `stopped_app`: written to `/srv/stopped_app/compose.yml` with `state: stopped`.
- `idempotence` re-runs `converge` and reports `changed=0` across all tasks.
- `verify` asserts:
  1. `docker` service is active and `docker compose version` succeeds.
  2. `/srv/webapp/compose.yml` (`0644`) and `/srv/webapp/.env` (`0600`) exist and the `webapp` container is running.
  3. `/srv/templated_app/docker-compose.yml` contains interpolated `vars` and its service container is running.
  4. `/srv/stopped_app/compose.yml` exists and its service container is not running.
  5. `/srv/unmanaged-data` still exists untouched.
  6. Applying `state: absent` (both default file-only removal and `remove_dir: true` + `remove_volumes: true`) cleanly tears down the target project's containers and removes files/directories as configured.

---

## Scenario 3: Full 5-Distro Matrix Verification

Run the mandatory 5-distro verification loop from `roles/docker/`:

```bash
cd roles/docker
for img in \
  geerlingguy/docker-ubuntu2204-ansible:latest \
  geerlingguy/docker-ubuntu2404-ansible:latest \
  geerlingguy/docker-debian12-ansible:latest \
  geerlingguy/docker-rockylinux9-ansible:latest \
  geerlingguy/docker-rockylinux8-ansible:latest; do
  echo "=== $img"
  MOLECULE_DISTRO="$img" ../../.venv/bin/molecule test && echo "PASS $img" || echo "FAIL $img"
done
```

**Expected Outcome**: All 5 distributions report `PASS`.

---

## Example Playbook Usage

See [contracts/role-interface.md](contracts/role-interface.md) and [data-model.md](data-model.md) for the complete variable schema.

```yaml
---
- name: Install Docker and deploy Compose stacks in /srv/<name>
  hosts: docker_hosts
  become: true
  roles:
    - role: hifra01.utils.docker
      vars:
        docker_users:
          - deploy
        docker_compose_projects:
          - name: whoami
            env:
              WHOAMI_PORT: "8080"
            content: |
              services:
                whoami:
                  image: traefik/whoami:latest
                  ports:
                    - "${WHOAMI_PORT}:80"
                  restart: unless-stopped
```
