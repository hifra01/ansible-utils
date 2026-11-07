# Role Interface Contract: `hifra01.utils.percona_mysql`

**Feature**: `002-percona-mysql-role`  
**Date**: 2026-10-30

## 1. Public Role Variables (`roles/percona_mysql/defaults/main.yml`)

```yaml
# Percona Server for MySQL release series ("8.4", "ps-84-lts", "8.0", "ps-80")
percona_mysql_version: "8.4"
percona_mysql_version_map:
  "8.4": "ps-84-lts"
  "8.4-lts": "ps-84-lts"
  "ps-84-lts": "ps-84-lts"
  "8.0": "ps-80"
  "ps-80": "ps-80"
percona_mysql_repo_product: "{{ percona_mysql_version_map[percona_mysql_version | string] | default(percona_mysql_version) }}"

# Operational role for this MySQL node: "master" or "replica"
percona_mysql_role: "master"

# Unique MySQL server ID (positive integer >= 1)
percona_mysql_server_id: 1

# Network settings
percona_mysql_bind_address: "0.0.0.0"
percona_mysql_port: 3306

# Root authentication & security hardening
percona_mysql_root_password: "changeme_root_password"
percona_mysql_secure_installation: true

# Binary logging & GTID settings
percona_mysql_gtid_mode: "ON"
percona_mysql_enforce_gtid_consistency: "ON"
percona_mysql_log_bin: "mysql-bin"
percona_mysql_binlog_format: "ROW"
percona_mysql_binlog_expire_logs_seconds: 604800

# InnoDB & connection tuning
percona_mysql_innodb_buffer_pool_size: "128M"
percona_mysql_max_connections: 151

# Additional [mysqld] configuration directives
percona_mysql_extra_mysqld_config: {}

# Replication credentials (created on master; used by replica to connect to master)
percona_mysql_replication_user: ""
percona_mysql_replication_password: ""
percona_mysql_replication_host: "%"

# Replica source connection settings (used when percona_mysql_role == "replica")
percona_mysql_source_host: ""
percona_mysql_source_port: 3306
percona_mysql_replica_start_replication: true

# Application databases & users (provisioned when percona_mysql_role == "master")
percona_mysql_databases: []
percona_mysql_users: []

# Package & repository URLs
percona_mysql_package_state: "present"
percona_mysql_apt_release_deb_url: "https://repo.percona.com/apt/percona-release_latest.generic_all.deb"
percona_mysql_yum_release_rpm_url: "https://repo.percona.com/yum/percona-release-latest.noarch.rpm"
```

## 2. OS-Specific Variables (`roles/percona_mysql/vars/<ansible_os_family>.yml`)

### `roles/percona_mysql/vars/Debian.yml`
```yaml
percona_mysql_prerequisite_packages:
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
percona_mysql_packages:
  - percona-server-server
  - percona-server-client
percona_mysql_service_name: "mysql"
percona_mysql_config_include_dir: "/etc/mysql/conf.d"
percona_mysql_dropin_config_file: "/etc/mysql/conf.d/99-percona-managed.cnf"
percona_mysql_main_config_file: "/etc/mysql/my.cnf"
percona_mysql_socket: "/var/run/mysqld/mysqld.sock"
percona_mysql_error_log_file: "/var/log/mysql/error.log"
```

### `roles/percona_mysql/vars/RedHat.yml`
```yaml
percona_mysql_prerequisite_packages:
  - ca-certificates
  - gnupg2
percona_mysql_packages:
  - percona-server-server
  - percona-server-client
percona_mysql_service_name: "mysqld"
percona_mysql_config_include_dir: "/etc/my.cnf.d"
percona_mysql_dropin_config_file: "/etc/my.cnf.d/99-percona-managed.cnf"
percona_mysql_main_config_file: "/etc/my.cnf"
percona_mysql_socket: "/var/lib/mysql/mysql.sock"
percona_mysql_error_log_file: "/var/log/mysqld.log"
```

## 3. Generated File Contracts

### Drop-in Configuration (`99-percona-managed.cnf`)
- **Path**: `/etc/mysql/conf.d/99-percona-managed.cnf` (Debian) or `/etc/my.cnf.d/99-percona-managed.cnf` (RedHat)
- **Owner/Group**: `root:root`
- **Mode**: `'0644'`
- **Structure**:
  ```ini
  # Managed by Ansible (hifra01.utils.percona_mysql)
  [mysqld]
  bind-address = 0.0.0.0
  port = 3306
  server-id = 1
  gtid_mode = ON
  enforce_gtid_consistency = ON
  log_bin = mysql-bin
  binlog_format = ROW
  binlog_expire_logs_seconds = 604800
  innodb_buffer_pool_size = 128M
  max_connections = 151
  read_only = OFF
  super_read_only = OFF
  ```

### Root Client Credentials (`/root/.my.cnf`)
- **Owner/Group**: `root:root`
- **Mode**: `'0600'`
- **Structure**:
  ```ini
  # Managed by Ansible (hifra01.utils.percona_mysql)
  [client]
  user=root
  password="changeme_root_password"
  ```

## 4. Handler Contract (`roles/percona_mysql/handlers/main.yml`)

- **Listener `"validate and restart mysql"`**:
  1. `Validate mysql configuration for restart`: runs `/usr/sbin/mysqld --validate-config` (`changed_when: false`)
  2. `Restart mysql`: restarts `{{ percona_mysql_service_name }}` (`state: restarted`)
