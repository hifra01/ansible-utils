# Quickstart & Validation Guide: `hifra01.utils.percona_mysql`

**Feature**: `002-percona-mysql-role`  
**Date**: 2026-10-30

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

## Scenario 2: Single-Distro Molecule Iteration (`mysql-master` + `mysql-replica`)

Run the Molecule scenario against the default Ubuntu 24.04 containers:

```bash
cd roles/percona_mysql
molecule converge
molecule verify
molecule idempotence
molecule destroy
```

**Expected Outcome**:
- `prepare` installs Python 3.9 on Rocky 8 (when applicable) on both `mysql-master` and `mysql-replica`.
- `converge`:
  - Installs Percona Server for MySQL 8.4 LTS (`ps-84-lts`) on both `mysql-master` and `mysql-replica`.
  - Configures `mysql-master` with `percona_mysql_role: "master"`, `percona_mysql_server_id: 1`, `read_only = OFF`, `super_read_only = OFF`, replication user `repl_user`, database `app_db`, and user `app_user`.
  - Configures `mysql-replica` with `percona_mysql_role: "replica"`, `percona_mysql_server_id: 2`, `read_only = ON`, `super_read_only = ON`, and connects it to `mysql-master` via GTID auto-positioning (`SOURCE_AUTO_POSITION = 1`).
- `idempotence` re-runs `converge` across both nodes with `changed=0`.
- `verify` confirms:
  1. `mysql`/`mysqld` systemd service is enabled and active on both hosts.
  2. `mysqld --validate-config` exits `0` on both hosts.
  3. `/root/.my.cnf` has mode `'0600'` and `99-percona-managed.cnf` has mode `'0644'`.
  4. `mysql-master` has `read_only = OFF`, `super_read_only = OFF`, `gtid_mode = ON`, `server_id = 1`, database `app_db`, and user `app_user`.
  5. `mysql-replica` has `read_only = ON`, `super_read_only = ON`, `gtid_mode = ON`, `server_id = 2`, `Replica_IO_Running = Yes`, and `Replica_SQL_Running = Yes`.
  6. Writing a row into `app_db.replication_probe` on `mysql-master` replicates automatically to `mysql-replica`.

---

## Scenario 3: Full 5-Distro Matrix Verification

Run the mandatory 5-distro verification loop from `roles/percona_mysql/`:

```bash
cd roles/percona_mysql
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
- name: Deploy Percona MySQL Primary (Master)
  hosts: mysql_master
  become: true
  roles:
    - role: hifra01.utils.percona_mysql
      vars:
        percona_mysql_version: "8.4"
        percona_mysql_role: "master"
        percona_mysql_server_id: 1
        percona_mysql_root_password: "StrongRootPassword!123"
        percona_mysql_replication_user: "repl_user"
        percona_mysql_replication_password: "StrongReplPassword!123"
        percona_mysql_databases:
          - name: "app_production"
            encoding: "utf8mb4"
            collation: "utf8mb4_0900_ai_ci"
        percona_mysql_users:
          - name: "app_user"
            password: "StrongAppPassword!123"
            host: "%"
            priv: "app_production.*:ALL"

- name: Deploy Percona MySQL Replica
  hosts: mysql_replicas
  become: true
  roles:
    - role: hifra01.utils.percona_mysql
      vars:
        percona_mysql_version: "8.4"
        percona_mysql_role: "replica"
        percona_mysql_server_id: 2
        percona_mysql_root_password: "StrongRootPassword!123"
        percona_mysql_source_host: "10.0.1.10"
        percona_mysql_source_port: 3306
        percona_mysql_replication_user: "repl_user"
        percona_mysql_replication_password: "StrongReplPassword!123"
        percona_mysql_replica_start_replication: true
```
