# Data Model: Percona Server for MongoDB Role (`percona_mongodb`)

**Feature**: `003-percona-mongodb-role`  
**Date**: 2026-11-05

## Entities

### 1. Percona MongoDB Instance Configuration (`percona_mongodb_*` top-level variables)

Represents the per-host `mongod` server configuration rendered to `/etc/mongod.conf` and the security keyfile managed at `{{ percona_mongodb_keyfile_path }}`.

| Field / Variable | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `percona_mongodb_version` | `string` | `"8.0"` | Yes | One of `"8.0"`, `"7.0"`, `"6.0"`, `"psmdb-80"`, `"psmdb-70"`, `"psmdb-60"` |
| `percona_mongodb_package_state` | `string` | `"present"` | Yes | `"present"` or `"latest"` |
| `percona_mongodb_bind_ip` | `string` | `"0.0.0.0"` | Yes | Non-empty comma-separated IPv4/IPv6/hostname string or `"0.0.0.0"` |
| `percona_mongodb_port` | `integer` | `27017` | Yes | Integer between `1` and `65535` |
| `percona_mongodb_wiredtiger_cache_size_gb` | `float` / `null` | `null` | No | Positive number (`> 0`) if specified; omitted when `null` |
| `percona_mongodb_extra_config` | `dict` | `{}` | No | Mapping merged recursively into `/etc/mongod.conf` |
| `percona_mongodb_replset_enabled` | `boolean` | `true` | Yes | Boolean (`true` / `false`) |
| `percona_mongodb_replset_name` | `string` | `"rs0"` | When `replset_enabled` | Non-empty string when `percona_mongodb_replset_enabled: true` |
| `percona_mongodb_replset_init` | `boolean` | `true` | Yes | Boolean (`true` / `false`) |
| `percona_mongodb_replset_advertise_host` | `string` | `"{{ ansible_default_ipv4.address \| default('127.0.0.1') }}"` | When `replset_enabled` | Non-empty hostname or IP address |
| `percona_mongodb_replset_members` | `list[Member \| string]` | `[]` | No | When empty (`[]`), auto-populates a 1-node replica set with `{{ percona_mongodb_replset_advertise_host }}:{{ percona_mongodb_port }}` |
| `percona_mongodb_oplog_size_mb` | `integer` / `null` | `null` | No | Positive integer (`>= 1`) if specified; omitted when `null` |
| `percona_mongodb_auth_enabled` | `boolean` | `true` | Yes | Boolean (`true` / `false`) |
| `percona_mongodb_keyfile_path` | `string` | `"/etc/mongod.keyfile"` | When `replset_enabled` and `auth_enabled` | Absolute filesystem path |
| `percona_mongodb_keyfile_content` | `string` | `""` | Conditional | Must be non-empty (6–1024 base64 chars) when `percona_mongodb_replset_enabled: true`, `percona_mongodb_auth_enabled: true`, and `percona_mongodb_replset_members \| length > 1`; auto-generated on host when empty in single-instance mode |
| `percona_mongodb_admin_user` | `string` | `"admin"` | When `auth_enabled` | Non-empty string when `percona_mongodb_auth_enabled: true` |
| `percona_mongodb_admin_password` | `string` | `"changeme_admin_password"` | When `auth_enabled` | Non-empty string when `percona_mongodb_auth_enabled: true` |
| `percona_mongodb_users` | `list[MongoUser]` | `[]` | No | List of application user dictionaries (see Entity 3) |

---

### 2. Replica Set Member Definition (`percona_mongodb_replset_members` item)

Represents a member node in the MongoDB replica set configuration (`rs.initiate()` / `rs.reconfig()`). Can be passed either as a plain `"host:port"` / `"host"` string or as a dictionary:

| Field | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `_id` | `integer` | Auto-assigned (`0..N-1`) | No | Non-negative integer unique within `members` |
| `host` | `string` | — | **Yes** | Non-empty `host:port` (or `host`, which defaults to `:{{ percona_mongodb_port }}`) |
| `priority` | `number` | `1` (or `0` when `arbiterOnly` / `hidden`) | No | Number between `0` and `1000` |
| `arbiterOnly` | `boolean` | `false` | No | Boolean (`true` / `false`) |
| `hidden` | `boolean` | `false` | No | Boolean (`true` / `false`); if `true`, `priority` must be `0` |
| `votes` | `integer` | `1` | No | `0` or `1` |

---

### 3. Managed MongoDB User (`percona_mongodb_users` item)

Represents an application database user account provisioned on the initializer (`percona_mongodb_replset_init: true`) or standalone (`percona_mongodb_replset_enabled: false`) node.

| Field | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `name` | `string` | — | **Yes** | Non-empty username |
| `password` | `string` | — | When `state == 'present'` | Non-empty password string |
| `database` | `string` | `"admin"` | No | Non-empty target database name where the user is defined |
| `roles` | `list[string \| dict]` | `[]` | When `state == 'present'` | Non-empty list of role strings (e.g., `"readWrite"`, normalized to `{ role: "readWrite", db: item.database }`) or `{ role: "<role>", db: "<db>" }` dicts |
| `state` | `string` | `"present"` | No | Must be `"present"` or `"absent"` |

## Relationships & Lifecycle Transitions

1. **Percona MongoDB Instance (1) ──> (0..1) Security Keyfile**:
   - When `percona_mongodb_replset_enabled: true` and `percona_mongodb_auth_enabled: true`, the instance requires `{{ percona_mongodb_keyfile_path }}` (`0400`, owned by `mongod:mongod`).
2. **Replica Set Initializer (1) ──> (1..N) Replica Set Members**:
   - When `percona_mongodb_replset_enabled: true` and `percona_mongodb_replset_init: true`, the initializer node initializes a 1-node replica set (`percona_mongodb_replset_members: []`) or a multi-node replica set (`percona_mongodb_replset_members` list) and reconciles member attributes via `rs.reconfig()`.
3. **Replica Set Initializer / Standalone Node (1) ──> (0..N) Managed MongoDB Users**:
   - Admin user bootstrap and `percona_mongodb_users` reconciliation run on the initializer or standalone node, and MongoDB replicates `admin.system.users` across all replica set members.
4. **State Transitions**:
   - **Initial Single-Instance Replica Set Provisioning**: Percona repo configured -> `percona-server-mongodb` installed -> keyfile generated (`0400`) -> `/etc/mongod.conf` rendered -> `mongod` started -> `rs.initiate()` executed over localhost exception -> node elected `PRIMARY` -> admin user created (closing localhost exception) -> `percona_mongodb_users` reconciled.
   - **Subsequent Converge / Reconfiguration**: `/etc/mongod.conf` and keyfile verified (`changed=0`) -> admin auth verified -> `rs.conf()` compared against desired members (`rs.reconfig()` run only on diff) -> `percona_mongodb_users` compared against `db.getUser()` (`createUser`/`updateUser`/`dropUser` run only on diff).
