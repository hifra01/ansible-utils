# Quickstart & Validation Guide: `hifra01.utils.redis`

**Feature**: `006-redis-role`  
**Date**: 2026-11-09

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

Test the `redis` role on Ubuntu 24.04:

```bash
cd roles/redis
molecule converge
molecule verify
molecule idempotence
molecule destroy
```

**Expected Outcome**:
- `prepare`: Bootstraps Python 3.9 on RHEL/Rocky 8 if applicable.
- `converge`: Installs the Redis package, creates directories, renders `/etc/redis/redis.conf` with restricted permissions (`0640`), starts and enables the Redis systemd service with a test password.
- `verify`:
  1. Checks that the Redis service is active and enabled.
  2. Confirms port 6379 is listening.
  3. Verifies that unauthenticated `redis-cli ping` fails with `NOAUTH`.
  4. Verifies that authenticated `redis-cli -a <password> ping` returns `PONG`.
  5. Verifies that `/etc/redis/redis.conf` has permissions `0640`.
- `idempotence`: Re-running `converge` produces `changed=0` and 0 service restarts.

---

## Scenario 3: Full 5-Distro CI Matrix Verification

Execute Molecule tests across all five supported distributions:

```bash
cd roles/redis
for distro in \
  geerlingguy/docker-ubuntu2204-ansible:latest \
  geerlingguy/docker-ubuntu2404-ansible:latest \
  geerlingguy/docker-debian12-ansible:latest \
  geerlingguy/docker-rockylinux9-ansible:latest \
  geerlingguy/docker-rockylinux8-ansible:latest; do
  echo "=== Testing $distro ==="
  MOLECULE_DISTRO="$distro" molecule test && echo "PASS: $distro" || echo "FAIL: $distro"
done
```

Or using the repository matrix runner:

```bash
./test-matrix.sh -r redis
```

**Expected Outcome**: All 5 distributions pass with zero failures.

---

## Example Playbook Usage

### 1. Default (Unauthenticated, Loopback Only)

```yaml
---
- name: Deploy default Redis Open Source
  hosts: redis_hosts
  become: true
  roles:
    - role: hifra01.utils.redis
```

### 2. Password-Protected Cache with Memory Cap

```yaml
---
- name: Deploy authenticated Redis cache
  hosts: cache_servers
  become: true
  roles:
    - role: hifra01.utils.redis
      vars:
        redis_bind: "0.0.0.0"
        redis_password: "{{ vault_redis_password }}"
        redis_maxmemory: "1gb"
        redis_maxmemory_policy: "allkeys-lru"
        redis_appendonly: true
```
