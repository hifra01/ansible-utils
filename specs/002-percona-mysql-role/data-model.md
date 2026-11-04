# Data Model: Percona Server for MySQL Role (`percona_mysql`)

**Feature**: `002-percona-mysql-role`  
**Date**: 2026-10-30

## Entities

### 1. Percona MySQL Node Configuration (`percona_mysql_*` top-level variables)

Represents the per-host Percona Server for MySQL configuration rendered to the OS-specific drop-in file (`99-percona-managed.cnf`) and administrative credentials in `/root/.my.cnf`.

| Field / Variable | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `percona_mysql_version` | `string` | `"8.4"` | Yes | One of `"8.4"`, `"8.4-lts"`, `"ps-84-lts"`, `"8.0"`, `"ps-80"` |
| `percona_mysql_role` | `string` | `"master"` | Yes | Must be `"master"` or `"replica"` |
| `percona_mysql_server_id` | `integer` | `1` | Yes | Positive integer (`>= 1`); must be unique across replicating nodes |
| `percona_mysql_bind_address` | `string` | `"0.0.0.0"` | Yes | Valid IPv4/IPv6 address or `"*"` |
| `percona_mysql_port` | `integer` | `3306` | Yes | Integer between `1` and `65535` |
| `percona_mysql_root_password` | `string` | `"changeme_root_password"` | Yes | Non-empty string |
| `percona_mysql_secure_installation` | `boolean` | `true` | Yes | Boolean (`true` / `false`) |
| `percona_mysql_gtid_mode` | `string` | `"ON"` | Yes | `"ON"`, `"ON_PERMISSIVE"`, `"OFF_PERMISSIVE"`, or `"OFF"` |
| `percona_mysql_enforce_gtid_consistency` | `string` | `"ON"` | Yes | `"ON"`, `"WARN"`, or `"OFF"` |
| `percona_mysql_log_bin` | `string` | `"mysql-bin"` | Yes | Non-empty string basename or path |
| `percona_mysql_binlog_format` | `string` | `"ROW"` | Yes | `"ROW"`, `"STATEMENT"`, or `"MIXED"` |
| `percona_mysql_binlog_expire_logs_seconds` | `integer` | `604800` | Yes | Positive integer (`>= 1`) |
| `percona_mysql_innodb_buffer_pool_size` | `string` | `"128M"` | Yes | Valid MySQL byte size string (`"128M"`, `"1G"`, etc.) |
| `percona_mysql_max_connections` | `integer` | `151` | Yes | Positive integer (`>= 1`) |
| `percona_mysql_extra_mysqld_config` | `dict` | `{}` | No | Dictionary of extra `[mysqld]` directives |
| `percona_mysql_package_state` | `string` | `"present"` | Yes | `"present"` or `"latest"` |

---

### 2. Replication Topology Link (`percona_mysql_replication_*` & `percona_mysql_source_*`)

Represents the credentials created on a `master` node and the replication channel configured on a `replica` node.

| Field / Variable | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `percona_mysql_replication_user` | `string` | `""` | Conditional | Required if `percona_mysql_role == 'replica'` and `percona_mysql_source_host != ''` |
| `percona_mysql_replication_password` | `string` | `""` | Conditional | Required when `percona_mysql_replication_user` is non-empty |
| `percona_mysql_replication_host` | `string` | `"%"` | No | Host mask for replication account on master |
| `percona_mysql_source_host` | `string` | `""` | No | IP address or hostname of the primary (`master`) node |
| `percona_mysql_source_port` | `integer` | `3306` | No | Integer port between `1` and `65535` |
| `percona_mysql_replica_start_replication` | `boolean` | `true` | Yes | Boolean (`true` / `false`) |

---

### 3. Managed Database (`percona_mysql_databases` list item)

Represents an application database schema managed via idempotent SQL checks when `percona_mysql_role == 'master'`.

| Field | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `name` | `string` | — | **Yes** | Non-empty identifier (`[a-zA-Z0-9_$]+`) |
| `encoding` / `charset` | `string` | `"utf8mb4"` | No | Valid MySQL character set name |
| `collation` | `string` | `"utf8mb4_unicode_ci"` | No | Valid MySQL collation name matching character set |
| `state` | `string` | `"present"` | No | `"present"` or `"absent"` |

---

### 4. Managed Database User (`percona_mysql_users` list item)

Represents a MySQL user account and grant specification managed via idempotent SQL checks when `percona_mysql_role == 'master'`.

| Field | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `name` | `string` | — | **Yes** | Non-empty MySQL username |
| `password` | `string` | — | Conditional | Required when `state == 'present'` |
| `host` | `string` | `"localhost"` | No | MySQL host specification (e.g. `"localhost"`, `"%"`, `"10.0.%"`) |
| `priv` | `string` | `"*.*:USAGE"` | No | Privilege string in `db.table:PRIV1,PRIV2` format (e.g. `"app_db.*:ALL"`) |
| `state` | `string` | `"present"` | No | `"present"` or `"absent"` |

## Relationships & Lifecycle Transitions

1. **Percona MySQL Node (`master`) (1) ──> (0..N) Managed Databases & Users**:
   - On `master` nodes, the role provisions all databases in `percona_mysql_databases` and user accounts in `percona_mysql_users`, plus the replication user (`percona_mysql_replication_user`@`percona_mysql_replication_host`).
2. **Percona MySQL Node (`master`) (1) <── (0..N) Percona MySQL Node (`replica`)**:
   - Replica nodes enforce `read_only = ON` and `super_read_only = ON` and connect to `percona_mysql_source_host:percona_mysql_source_port` using `CHANGE REPLICATION SOURCE TO ... SOURCE_AUTO_POSITION = 1, GET_SOURCE_PUBLIC_KEY = 1`.
3. **State Transitions**:
   - **Initial Provisioning**: `percona-release` installed -> product repository (`ps-84-lts`) enabled -> `percona-server-server` & `percona-server-client` installed -> `99-percona-managed.cnf` rendered -> `mysqld --validate-config` executed -> service started & enabled -> root password secured & `/root/.my.cnf` written.
   - **Master Provisioning**: Databases, users, and replication user created/updated idempotently.
   - **Replica Provisioning**: `SHOW REPLICA STATUS` inspected -> if source host/port/user/auto_position differ, `STOP REPLICA` + `CHANGE REPLICATION SOURCE TO` executed -> if `percona_mysql_replica_start_replication` is `true` and threads are not running, `START REPLICA` executed.
   - **Configuration Update**: Change to `99-percona-managed.cnf` triggers handler `"validate and restart mysql"`, which runs `mysqld --validate-config` before restarting `mysql` / `mysqld`.
