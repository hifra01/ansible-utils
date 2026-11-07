# Percona Server for MongoDB Role (`hifra01.utils.percona_mongodb`)

Ansible role to install and configure Percona Server for MongoDB (PSMDB 8.0, 7.0, or 6.0) from official Percona repositories (`percona-release`), manage `/etc/mongod.conf`, configure keyfile authentication, set up single-node or multi-node replica sets, and manage database users.

## Supported Platforms

* **Debian Family**: Debian 12 (Bookworm), Ubuntu 22.04 (Jammy), Ubuntu 24.04 (Noble)
* **RedHat Family**: Rocky Linux 8 & 9, AlmaLinux 8 & 9, RHEL 8 & 9

## Requirements

* `ansible-core >= 2.21.0`
* Requires systemd init system on target hosts.
* Fact gathering (`gather_facts: true`) must be enabled.
* Target hosts require Python 3 and standard utilities (`curl` / `wget` for repository package download).

## Role Variables

| Variable | Default | Description |
|---|---|---|
| `percona_mongodb_version` | `"8.0"` | Percona MongoDB major release series (`"8.0"`, `"7.0"`, `"6.0"`, or `"psmdb-80"`, etc.) |
| `percona_mongodb_package_state` | `"present"` | Package installation state (`"present"` or `"latest"`) |
| `percona_mongodb_apt_release_deb_url` | `"https://repo.percona.com/apt/percona-release_latest.generic_all.deb"` | Official Percona release package URL for Debian/Ubuntu |
| `percona_mongodb_yum_release_rpm_url` | `"https://repo.percona.com/yum/percona-release-latest.noarch.rpm"` | Official Percona release package URL for RHEL/Rocky |
| `percona_mongodb_bind_ip` | `"0.0.0.0"` | IP interface(s) mongod listens on |
| `percona_mongodb_port` | `27017` | Port mongod listens on |
| `percona_mongodb_wiredtiger_cache_size_gb` | `null` | WiredTiger storage engine cache size in GB (`null` lets mongod use default memory sizing) |
| `percona_mongodb_extra_config` | `{}` | Additional dictionary recursively merged into rendered `/etc/mongod.conf` |
| `percona_mongodb_replset_enabled` | `true` | Enable MongoDB replica set mode |
| `percona_mongodb_replset_name` | `"rs0"` | Replica set cluster name |
| `percona_mongodb_replset_init` | `true` | Designates this host to initialize replica set and reconcile member state |
| `percona_mongodb_replset_advertise_host` | `"{{ ansible_facts['default_ipv4']['address'] \| default('127.0.0.1') }}"` | Hostname or IP advertised to other replica set members and clients |
| `percona_mongodb_replset_members` | `[]` | List of member definitions (strings `"host:port"` or dictionaries with `host`, `priority`, etc.) |
| `percona_mongodb_oplog_size_mb` | `null` | Replication oplog size in MB (`null` uses MongoDB default) |
| `percona_mongodb_auth_enabled` | `true` | Enable MongoDB security authorization and keyfile authentication |
| `percona_mongodb_keyfile_path` | `"/etc/mongod.keyfile"` | Absolute path to the shared keyfile (mode `0400`, owned by `mongod:mongod`) |
| `percona_mongodb_keyfile_content` | `""` | Keyfile content (6-1024 base64 chars). Auto-generated if empty and single-node cluster |
| `percona_mongodb_admin_user` | `"admin"` | Administrative superuser username (bootstrapped via localhost exception) |
| `percona_mongodb_admin_password` | `"changeme_admin_password"` | Administrative superuser password |
| `percona_mongodb_users` | `[]` | List of application users to manage idempotently |

### Keyfile Authentication

When `percona_mongodb_auth_enabled: true` and `percona_mongodb_replset_enabled: true`:
- If `percona_mongodb_keyfile_content` is provided, it is deployed to `/etc/mongod.keyfile` with permissions `0400` and owner `mongod:mongod`.
- If `percona_mongodb_keyfile_content` is empty and the deployment is a single-instance replica set (`percona_mongodb_replset_members | length <= 1`), a random 756-character base64 keyfile is generated automatically on the host.
- For multi-node replica sets (`> 1` member), `percona_mongodb_keyfile_content` must be provided (e.g., via Ansible Vault) so all replica set members share identical cluster credentials.

### User Management (`percona_mongodb_users`)

Each item in `percona_mongodb_users` supports:
- `name`: Username (required string)
- `password`: Password (required string when `state == "present"`)
- `database`: Authentication database where user is defined (optional string, defaults to `"admin"`)
- `roles`: List of roles assigned to the user (required list when `state == "present"`). Can be strings (e.g. `"readWrite"`) or dicts (e.g. `{ role: "readWrite", db: "app_db" }`).
- `state`: `"present"` or `"absent"` (optional string, defaults to `"present"`)

User management is executed on the replica set initializer node (or standalone node) and automatically replicates to all replica set members.

## Example Playbooks

### Single-Instance Replica Set (ACID Transactions / Change Streams)

```yaml
---
- name: Deploy Single-Instance MongoDB Replica Set
  hosts: db_servers
  become: true
  roles:
    - role: hifra01.utils.percona_mongodb
      vars:
        percona_mongodb_replset_enabled: true
        percona_mongodb_replset_name: "rs0"
        percona_mongodb_admin_password: "vault_mongodb_admin_password"
        percona_mongodb_users:
          - name: "app_user"
            password: "vault_mongodb_app_password"
            database: "app_db"
            roles:
              - role: "readWrite"
                db: "app_db"
```

### Multi-Node Replica Set (3-Node Cluster)

```yaml
---
- name: Deploy 3-Node MongoDB Replica Set
  hosts: mongo_cluster
  become: true
  roles:
    - role: hifra01.utils.percona_mongodb
      vars:
        percona_mongodb_replset_enabled: true
        percona_mongodb_replset_name: "rs0"
        percona_mongodb_replset_init: "{{ inventory_hostname == groups['mongo_cluster'][0] }}"
        percona_mongodb_keyfile_content: "{{ vault_mongodb_shared_keyfile }}"
        percona_mongodb_replset_members:
          - host: "mongo1.internal:27017"
            priority: 2
          - host: "mongo2.internal:27017"
            priority: 1
          - host: "mongo3.internal:27017"
            priority: 1
        percona_mongodb_admin_password: "{{ vault_mongodb_admin_password }}"
        percona_mongodb_users:
          - name: "app_user"
            password: "{{ vault_mongodb_app_password }}"
            database: "app_production"
            roles:
              - role: "readWrite"
                db: "app_production"
```

### Standalone Instance (No Replica Set)

```yaml
---
- name: Deploy Standalone MongoDB
  hosts: db_servers
  become: true
  roles:
    - role: hifra01.utils.percona_mongodb
      vars:
        percona_mongodb_replset_enabled: false
        percona_mongodb_admin_password: "vault_mongodb_admin_password"
        percona_mongodb_users:
          - name: "reporting"
            password: "vault_reporting_password"
            database: "analytics"
            roles:
              - role: "read"
                db: "analytics"
```

## License

MIT
