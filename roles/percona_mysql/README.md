# Percona Server for MySQL Role (`hifra01.utils.percona_mysql`)

Ansible role to install and manage Percona Server for MySQL (defaulting to Percona Server 8.4 LTS) in `master` or `replica` mode with GTID-based replication, declarative application databases and users, and drop-in configuration validation.

## Supported Platforms

* **Debian Family**: Debian 12 (Bookworm), Ubuntu 22.04 (Jammy), Ubuntu 24.04 (Noble)
* **RedHat Family**: Rocky Linux 8 & 9, AlmaLinux 8 & 9, RHEL 8 & 9

## Requirements

* `ansible-core >= 2.15`
* Requires systemd init system on target hosts.
* Fact gathering (`gather_facts: true`) must be enabled.

## Role Variables

| Variable | Default | Description |
|---|---|---|
| `percona_mysql_version` | `"8.4"` | Percona release series (`"8.4"`, `"8.4-lts"`, `"ps-84-lts"`, `"8.0"`, `"ps-80"`) |
| `percona_mysql_role` | `"master"` | Operational role: `"master"` or `"replica"` |
| `percona_mysql_server_id` | `1` | Unique MySQL server ID (positive integer >= 1) |
| `percona_mysql_bind_address` | `"0.0.0.0"` | Network bind address |
| `percona_mysql_port` | `3306` | MySQL listening port |
| `percona_mysql_root_password` | `"changeme_root_password"` | Administrative root password deployed to `/root/.my.cnf` |
| `percona_mysql_secure_installation` | `true` | Remove anonymous users and default test database |
| `percona_mysql_gtid_mode` | `"ON"` | Global GTID mode (`"ON"`, `"ON_PERMISSIVE"`, `"OFF_PERMISSIVE"`, `"OFF"`) |
| `percona_mysql_enforce_gtid_consistency` | `"ON"` | Enforce GTID consistency (`"ON"`, `"WARN"`, `"OFF"`) |
| `percona_mysql_log_bin` | `"mysql-bin"` | Binary log base filename |
| `percona_mysql_binlog_format` | `"ROW"` | Binary log format (`"ROW"`, `"STATEMENT"`, `"MIXED"`) |
| `percona_mysql_binlog_expire_logs_seconds` | `604800` | Binary log retention period in seconds (7 days) |
| `percona_mysql_innodb_buffer_pool_size` | `"128M"` | InnoDB buffer pool size |
| `percona_mysql_max_connections` | `151` | Maximum concurrent connections |
| `percona_mysql_extra_mysqld_config` | `{}` | Dictionary of additional `[mysqld]` configuration directives |
| `percona_mysql_replication_user` | `""` | Username for replication user created on master and used by replicas |
| `percona_mysql_replication_password` | `""` | Password for replication account |
| `percona_mysql_replication_host` | `"%"` | Host mask for replication account created on master |
| `percona_mysql_source_host` | `""` | Source primary (`master`) host address for replica nodes |
| `percona_mysql_source_port` | `3306` | Source primary port for replica nodes |
| `percona_mysql_replica_start_replication` | `true` | Automatically start replica threads after configuring replication source |
| `percona_mysql_databases` | `[]` | List of application databases to create on master |
| `percona_mysql_users` | `[]` | List of application user accounts to create on master |
| `percona_mysql_package_state` | `"present"` | Package installation state (`"present"` or `"latest"`) |

### Database Definition Structure (`percona_mysql_databases`)

Each item in `percona_mysql_databases` supports:
* `name`: Database schema name (required string)
* `encoding` or `charset`: Character set (optional string, default: `"utf8mb4"`)
* `collation`: Collation (optional string, default: `"utf8mb4_unicode_ci"`)
* `state`: Target state (optional string, `"present"` or `"absent"`, default: `"present"`)

### User Definition Structure (`percona_mysql_users`)

Each item in `percona_mysql_users` supports:
* `name`: Username (required string)
* `password`: User password (required string when `state == "present"`)
* `host`: Host mask (optional string, default: `"localhost"`)
* `priv`: Grant specification in `db.table:PRIV1,PRIV2` format (optional string, default: `"*.*:USAGE"`)
* `state`: Target state (optional string, `"present"` or `"absent"`, default: `"present"`)

## Example Playbooks

### Deploy a Primary (Master) Database Server

```yaml
---
- name: Deploy Percona MySQL Primary (Master)
  hosts: mysql_master
  become: true
  roles:
    - role: hifra01.utils.percona_mysql
      vars:
        percona_mysql_role: "master"
        percona_mysql_server_id: 1
        percona_mysql_root_password: "SecureRootPassword!123"
        percona_mysql_replication_user: "repl_user"
        percona_mysql_replication_password: "SecureReplPassword!123"
        percona_mysql_databases:
          - name: "app_production"
            encoding: "utf8mb4"
            collation: "utf8mb4_unicode_ci"
        percona_mysql_users:
          - name: "app_user"
            password: "SecureAppPassword!123"
            host: "%"
            priv: "app_production.*:ALL"
```

### Deploy a Replica Database Server

```yaml
---
- name: Deploy Percona MySQL Replica
  hosts: mysql_replicas
  become: true
  roles:
    - role: hifra01.utils.percona_mysql
      vars:
        percona_mysql_role: "replica"
        percona_mysql_server_id: 2
        percona_mysql_root_password: "SecureRootPassword!123"
        percona_mysql_source_host: "10.0.1.10"
        percona_mysql_source_port: 3306
        percona_mysql_replication_user: "repl_user"
        percona_mysql_replication_password: "SecureReplPassword!123"
        percona_mysql_replica_start_replication: true
```

## License

MIT-0

## Author Information

Hilman F. Rakhmad (`hifra.dev`)
