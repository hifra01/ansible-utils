# Phase 0 Research: Percona Server for MySQL Role (`percona_mysql`)

**Feature**: `002-percona-mysql-role`  
**Date**: 2026-10-30

## 1. Official Percona Repository & Package Setup Across Debian & RedHat Families

- **Decision**:
  - **Repository Bootstrap (`percona-release`)**:
    - **Debian Family (Ubuntu 22.04, Ubuntu 24.04, Debian 12)**: Install prerequisite packages (`ca-certificates`, `curl`, `gnupg`, `lsb-release`), download `https://repo.percona.com/apt/percona-release_latest.generic_all.deb` to `/tmp/percona-release_latest.generic_all.deb` (guarded by `stat` on `/usr/bin/percona-release`), and install via `ansible.builtin.apt: deb: ...`.
    - **RedHat Family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL)**: Install `https://repo.percona.com/yum/percona-release-latest.noarch.rpm` via `ansible.builtin.dnf` with `disable_gpg_check: true` (matching `roles/php/tasks/setup-RedHat.yml`).
  - **Version Mapping & `percona-release enable-only`**:
    - Map user-friendly `percona_mysql_version` (`"8.4"`, `"8.4-lts"`, `"ps-84-lts"`) to the Percona product code `ps-84-lts` (and `"8.0"` / `"ps-80"` to `ps-80`).
    - On RedHat-family systems, disable the built-in DNF `mysql` module stream first (`dnf -y module disable mysql`, guarded by checking `/etc/dnf/modules.d/mysql.module` state) so `percona-server-server` is not masked by AppStream.
    - Enable the Percona Server repository idempotently by checking whether the repo marker file (`/etc/apt/sources.list.d/percona-ps-84-lts-release.list` on Debian or `/etc/yum.repos.d/percona-ps-84-lts-release.repo` on RedHat) exists, and if not, running `percona-release enable-only <repo_code> release` (plus `apt_repository` / `apt: update_cache: true` on Debian).
  - **Packages & Service Names**:
    - **Debian Family**: `percona-server-server`, `percona-server-client`; systemd service `mysql`.
    - **RedHat Family**: `percona-server-server`, `percona-server-client`; systemd service `mysqld`.
- **Rationale**:
  - `percona-release` is Percona's official cross-distro repository management package and handles GPG key rotation and distro codename mapping automatically.
  - Using `percona-release enable-only <product> release` (rather than `percona-release setup -y ps-84-lts`) avoids `percona-release setup` internally invoking `dnf module disable` or `apt-get update` unpredictably and allows clean idempotent file-existence guarding on `/etc/apt/sources.list.d/percona-<product>-release.list` / `/etc/yum.repos.d/percona-<product>-release.repo`.
- **Alternatives Considered**:
  - *Manually templating APT/YUM repository URLs without `percona-release`*: Rejected because Percona splits repositories by product code (`ps-84-lts`, `ps-80`, `tools`, `telemetry`) and rotates signing keys inside `percona-release`.

## 2. Drop-In Configuration Architecture & `mysqld --validate-config`

- **Decision**:
  - Render the role-managed `[mysqld]` configuration into a high-precedence drop-in file:
    - **Debian Family**: `/etc/mysql/conf.d/99-percona-managed.cnf` (owner `root:root`, mode `'0644'`).
    - **RedHat Family**: `/etc/my.cnf.d/99-percona-managed.cnf` (owner `root:root`, mode `'0644'`), and ensure `/etc/my.cnf` contains `!includedir /etc/my.cnf.d` via `ansible.builtin.lineinfile`.
  - Validate the complete MySQL configuration before restarting the service using `/usr/sbin/mysqld --validate-config` inside the `"validate and restart mysql"` handler listener.
- **Rationale**:
  - Debian/Ubuntu and RHEL/Rocky have different default socket paths (`/var/run/mysqld/mysqld.sock` vs `/var/lib/mysql/mysql.sock`), PID file paths, and log locations defined in the package-supplied base config. Placing role-managed directives in `99-percona-managed.cnf` preserves OS-native paths while deterministically overriding replication, read-only, network, and tuning settings.
  - `mysqld --validate-config` parses the full option-file inclusion chain and exits non-zero on any unknown or invalid directive without starting the storage engine.
- **Alternatives Considered**:
  - *Overwriting `/etc/my.cnf` or `/etc/mysql/mysql.conf.d/mysqld.cnf`*: Rejected during `/speckit-clarify` (Question 1, Option A chosen) because it risks breaking distro-specific socket/AppArmor/systemd expectations.

## 3. Root Authentication Bootstrap & Native `mysql` CLI Idempotency

- **Decision**:
  - Use the native `mysql` CLI binary with `/root/.my.cnf` (`mode: '0600'`) and idempotent SQL queries for all administrative operations (root bootstrap, anonymous/test cleanup, replication user management, database/user provisioning, and replica channel configuration).
  - **Root Password Bootstrap Flow**:
    1. Check if `mysql --defaults-file=/root/.my.cnf -e "SELECT 1;"` already succeeds (`changed_when: false`, `failed_when: false`).
    2. If `/root/.my.cnf` does not yet work:
       - Test passwordless local socket connection (`mysql --no-defaults -u root -e "SELECT 1;"`, typical on fresh Debian/Ubuntu installs).
       - If socket auth requires a password (typical on fresh RedHat/Rocky installs where `mysqld --initialize` writes a temporary password to `/var/log/mysqld.log`), extract the temporary password from `/var/log/mysqld.log` (`grep 'temporary password'`) and execute `mysql --no-defaults --connect-expired-password -u root -p"<temp_pass>" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '<percona_mysql_root_password>';"`.
       - If passwordless socket auth succeeded, execute `ALTER USER 'root'@'localhost' IDENTIFIED BY '<percona_mysql_root_password>';`.
    3. Render `/root/.my.cnf` (`owner: root`, `group: root`, `mode: '0600'`) with `[client]` `user=root` and `password="{{ percona_mysql_root_password }}"`.
    4. If `/root/.my.cnf` already existed and authenticated before a password change variable update, update the MySQL root user password first if `/root/.my.cnf` template would change.
  - **Idempotent Database & User Management via `mysql` CLI**:
    - **Databases**: Query `SELECT SCHEMA_NAME, DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '...'` and only execute `CREATE DATABASE` / `ALTER DATABASE` / `DROP DATABASE` when actual state differs from desired state.
    - **Users & Grants**: Query `mysql.user` and `SHOW GRANTS FOR 'user'@'host'` before running `CREATE USER IF NOT EXISTS`, `ALTER USER`, `GRANT`, or `DROP USER` so repeat runs report `changed=0`.
- **Rationale**:
  - Chosen during `/speckit-clarify` (Question 2, Option A). Avoids adding `community.mysql` to `galaxy.yml` and avoids installing `python3-pymysql` or `python3-mysqldb` (which fails on Rocky Linux 8 when running under `/usr/bin/python3.9` without matching C/PyMySQL wheels).
- **Alternatives Considered**:
  - *`community.mysql.mysql_user` / `mysql_db`*: Rejected because it requires external collection dependency and target-host Python MySQL libraries.

## 4. Master & Replica Configuration (`PS 8.4 LTS` Terminology & GTID Auto-Positioning)

- **Decision**:
  - **Shared GTID & Binary Logging Defaults**:
    - `server-id = {{ percona_mysql_server_id }}`
    - `gtid_mode = {{ percona_mysql_gtid_mode }}` (`ON`)
    - `enforce_gtid_consistency = {{ percona_mysql_enforce_gtid_consistency }}` (`ON`)
    - `log_bin = {{ percona_mysql_log_bin }}` (`mysql-bin`)
    - `binlog_format = {{ percona_mysql_binlog_format }}` (`ROW`)
    - `binlog_expire_logs_seconds = {{ percona_mysql_binlog_expire_logs_seconds }}` (`604800`)
  - **Master Mode (`percona_mysql_role == "master"`)**:
    - Sets `read_only = OFF` and `super_read_only = OFF` in `99-percona-managed.cnf`.
    - Creates `percona_mysql_replication_user`@`percona_mysql_replication_host` (using `caching_sha2_password` or `GET_MASTER_PUBLIC_KEY = 1` on replica) and grants `REPLICATION SLAVE, REPLICATION CLIENT ON *.*`.
  - **Replica Mode (`percona_mysql_role == "replica"`)**:
    - Sets `read_only = ON` and `super_read_only = ON` in `99-percona-managed.cnf`.
    - Uses MySQL 8.4 syntax (`SHOW REPLICA STATUS\G`, `STOP REPLICA`, `CHANGE REPLICATION SOURCE TO ... SOURCE_AUTO_POSITION = 1, GET_SOURCE_PUBLIC_KEY = 1`, `START REPLICA`), since MySQL 8.4 removed the deprecated `SHOW SLAVE STATUS` / `CHANGE MASTER TO` / `START SLAVE` statements.
    - Checks `SHOW REPLICA STATUS\G` first: only executes `STOP REPLICA` + `CHANGE REPLICATION SOURCE TO` if `Source_Host`, `Source_Port`, `Source_User`, or `Auto_Position` do not match the desired configuration, and only executes `START REPLICA` if `Replica_IO_Running != 'Yes'` or `Replica_SQL_Running != 'Yes'` (when `percona_mysql_replica_start_replication: true`).
- **Rationale**:
  - In Percona Server 8.4 LTS, `SHOW SLAVE STATUS`, `CHANGE MASTER TO`, and `START SLAVE` are removed in favor of `SHOW REPLICA STATUS`, `CHANGE REPLICATION SOURCE TO`, and `START REPLICA` (which are also supported in MySQL 8.0.23+).
  - Including `GET_SOURCE_PUBLIC_KEY = 1` in `CHANGE REPLICATION SOURCE TO` allows replicas to authenticate seamlessly over non-TLS Docker/private networks when the replication user uses MySQL 8.4's default `caching_sha2_password` plugin.
- **Alternatives Considered**:
  - *Legacy `CHANGE MASTER TO` / `SHOW SLAVE STATUS`*: Rejected because MySQL 8.4 removed those SQL statements completely.

## 5. Multi-Distro Two-Container Molecule Topology (`mysql-master` + `mysql-replica`)

- **Decision**:
  - Configure `roles/percona_mysql/molecule/default/molecule.yml` with two containers on a shared Docker network (`molecule-mysql-net` or default bridge with hostname resolution):
    - `mysql-master`: `percona_mysql_role: "master"`, `percona_mysql_server_id: 1`
    - `mysql-replica`: `percona_mysql_role: "replica"`, `percona_mysql_server_id: 2`
  - Both containers run `${MOLECULE_DISTRO:-geerlingguy/docker-ubuntu2404-ansible}` with systemd enabled.
  - In `converge.yml`:
    - `mysql-master` is converged with `percona_mysql_role: "master"`, `percona_mysql_server_id: 1`, replication user `repl_user`, a test database `app_db`, and a test user `app_user`.
    - `mysql-replica` is converged with `percona_mysql_role: "replica"`, `percona_mysql_server_id: 2`, `percona_mysql_source_host: "{{ hostvars['mysql-master']['ansible_default_ipv4']['address'] }}"`, and replication credentials.
  - In `verify.yml`:
    - Assert service enabled/running, config file permissions (`'0644'`), `/root/.my.cnf` permissions (`'0600'`), and `mysqld --validate-config` on both hosts.
    - Assert `mysql-master` has `read_only = OFF`, `super_read_only = OFF`, `gtid_mode = ON`, `server_id = 1`, `app_db`, and `app_user`.
    - Assert `mysql-replica` has `read_only = ON`, `super_read_only = ON`, `gtid_mode = ON`, `server_id = 2`, `Replica_IO_Running: Yes`, and `Replica_SQL_Running: Yes`.
    - Insert a verification record on `mysql-master` (`app_db.replication_test`) and assert that `mysql-replica` replicates the exact row via GTID replication.
- **Rationale**:
  - Chosen during `/speckit-clarify` (Question 3, Option A). Proves live primary-to-replica GTID replication across all 5 CI distributions (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`).
- **Alternatives Considered**:
  - *Single container testing only*: Rejected in clarification because a 2-container scenario directly tests real replication traffic between `master` and `replica`.
