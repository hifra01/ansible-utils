# Quickstart & Validation Guide: `hifra01.utils.percona_mongodb`

**Feature**: `003-percona-mongodb-role`  
**Date**: 2026-11-05

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

## Scenario 2: Single-Distro Molecule Iteration (Single-Instance Replica Set)

Run the Molecule scenario against the default Ubuntu 24.04 container:

```bash
cd roles/percona_mongodb
molecule converge
molecule verify
molecule idempotence
molecule destroy
```

**Expected Outcome**:
- `prepare` bootstraps Python 3.9 on Rocky Linux 8 when applicable.
- `converge`:
  - Installs Percona Server for MongoDB 8.0 (`psmdb-80`) from the official Percona repository.
  - Auto-generates `/etc/mongod.keyfile` (`0400`, owned by `mongod:mongod`).
  - Configures `/etc/mongod.conf` (`0644`) with `replication.replSetName: "rs0"`, `security.authorization: enabled`, and `security.keyFile: /etc/mongod.keyfile`.
  - Starts `mongod`, initializes the 1-node replica set (`rs0`), waits until the instance is elected `PRIMARY`, bootstraps the `admin` user, and provisions `app_user` on `app_db`.
- `idempotence` re-runs `converge` with `changed=0`.
- `verify` confirms:
  1. `mongod` systemd service is enabled and active.
  2. `/etc/mongod.conf` (`0644`) and `/etc/mongod.keyfile` (`0400`, `mongod:mongod`) have expected permissions.
  3. Port `27017` is listening.
  4. Unauthenticated `rs.status()` is rejected (`Unauthorized`).
  5. Authenticated `rs.status()` reports `ok: 1`, `set: "rs0"`, `members.length === 1`, and `myState === 1` (`PRIMARY`).
  6. `app_user` authenticates against `app_db` and executes a multi-document ACID transaction.

---

## Scenario 3: Full 5-Distro Matrix Verification

Run the mandatory 5-distro verification loop from `roles/percona_mongodb/`:

```bash
cd roles/percona_mongodb
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

### Single-Instance Replica Set (Default Mode)

```yaml
---
- name: Deploy Percona Server for MongoDB (1-Node Replica Set)
  hosts: mongodb_single
  become: true
  roles:
    - role: hifra01.utils.percona_mongodb
      vars:
        percona_mongodb_version: "8.0"
        percona_mongodb_replset_enabled: true
        percona_mongodb_replset_name: "rs0"
        percona_mongodb_admin_user: "admin"
        percona_mongodb_admin_password: "StrongAdminPassword!123"
        percona_mongodb_oplog_size_mb: 512
        percona_mongodb_users:
          - name: "app_user"
            password: "StrongAppPassword!123"
            database: "app_production"
            roles:
              - "readWrite"
```

### Multi-Instance 3-Node Replica Set

```yaml
---
- name: Deploy Percona Server for MongoDB 3-Node Replica Set
  hosts: mongodb_cluster
  become: true
  roles:
    - role: hifra01.utils.percona_mongodb
      vars:
        percona_mongodb_version: "8.0"
        percona_mongodb_replset_enabled: true
        percona_mongodb_replset_name: "rs0"
        percona_mongodb_replset_init: "{{ inventory_hostname == groups['mongodb_cluster'][0] }}"
        percona_mongodb_keyfile_content: "{{ vault_mongodb_keyfile_base64 }}"
        percona_mongodb_admin_user: "admin"
        percona_mongodb_admin_password: "{{ vault_mongodb_admin_password }}"
        percona_mongodb_replset_members:
          - host: "10.0.1.11:27017"
            priority: 2
          - host: "10.0.1.12:27017"
            priority: 1
          - host: "10.0.1.13:27017"
            priority: 1
```
