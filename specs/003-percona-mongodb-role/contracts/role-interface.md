# Role Interface Contract: `hifra01.utils.percona_mongodb`

**Feature**: `003-percona-mongodb-role`  
**Date**: 2026-11-05

## 1. Public Role Variables (`roles/percona_mongodb/defaults/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# defaults file for percona_mongodb

# Percona Server for MongoDB release series ("8.0", "7.0", "6.0", or "psmdb-80", "psmdb-70", "psmdb-60")
percona_mongodb_version: "8.0"

# Desired package state ("present" or "latest")
percona_mongodb_package_state: "present"

# Official Percona repository package URLs
percona_mongodb_apt_release_deb_url: "https://repo.percona.com/apt/percona-release_latest.generic_all.deb"
percona_mongodb_yum_release_rpm_url: "https://repo.percona.com/yum/percona-release-latest.noarch.rpm"

# Network configuration
percona_mongodb_bind_ip: "0.0.0.0"
percona_mongodb_port: 27017

# Storage & WiredTiger tuning (null uses OS/MongoDB defaults)
percona_mongodb_wiredtiger_cache_size_gb: null

# Additional top-level mongod.conf settings merged recursively
percona_mongodb_extra_config: {}

# Replica set configuration (enabled by default; supports 1-instance or multi-instance replica sets)
percona_mongodb_replset_enabled: true
percona_mongodb_replset_name: "rs0"
percona_mongodb_replset_init: true
percona_mongodb_replset_advertise_host: "{{ ansible_default_ipv4.address | default('127.0.0.1') }}"
percona_mongodb_replset_members: []
percona_mongodb_oplog_size_mb: null

# Security & authentication configuration
percona_mongodb_auth_enabled: true
percona_mongodb_keyfile_path: "/etc/mongod.keyfile"
percona_mongodb_keyfile_content: ""
percona_mongodb_admin_user: "admin"
percona_mongodb_admin_password: "changeme_admin_password"

# Application users provisioned on the replica set initializer or standalone node
percona_mongodb_users: []
```

## 2. OS-Specific Variables (`roles/percona_mongodb/vars/<ansible_os_family>.yml`)

### `roles/percona_mongodb/vars/Debian.yml`
```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for percona_mongodb (Debian family)

percona_mongodb_prerequisite_packages:
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
  - openssl

percona_mongodb_packages:
  - percona-server-mongodb

percona_mongodb_service_name: "mongod"
percona_mongodb_user: "mongod"
percona_mongodb_group: "mongod"
percona_mongodb_config_file: "/etc/mongod.conf"
percona_mongodb_db_path: "/var/lib/mongodb"
percona_mongodb_log_path: "/var/log/mongodb/mongod.log"
percona_mongodb_pid_file_path: "/var/run/mongod.pid"
percona_mongodb_process_fork: true
```

### `roles/percona_mongodb/vars/RedHat.yml`
```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for percona_mongodb (RedHat family)

percona_mongodb_prerequisite_packages:
  - ca-certificates
  - curl
  - gnupg2
  - openssl

percona_mongodb_packages:
  - percona-server-mongodb

percona_mongodb_service_name: "mongod"
percona_mongodb_user: "mongod"
percona_mongodb_group: "mongod"
percona_mongodb_config_file: "/etc/mongod.conf"
percona_mongodb_db_path: "/var/lib/mongo"
percona_mongodb_log_path: "/var/log/mongo/mongod.log"
percona_mongodb_pid_file_path: "/var/run/mongod.pid"
percona_mongodb_process_fork: true
```

## 3. Generated File Contracts

### Main Configuration (`/etc/mongod.conf`)
- **Path**: `/etc/mongod.conf`
- **Owner/Group**: `root:root`
- **Mode**: `'0644'`
- **Structure** (rendered via `to_nice_yaml(indent=2)`):
  ```yaml
  # Managed by Ansible (hifra01.utils.percona_mongodb)
  ---
  net:
    bindIp: 0.0.0.0
    port: 27017
  processManagement:
    fork: true
    pidFilePath: /var/run/mongod.pid
  replication:
    oplogSizeMB: 256
    replSetName: rs0
  security:
    authorization: enabled
    keyFile: /etc/mongod.keyfile
  storage:
    dbPath: /var/lib/mongodb
  systemLog:
    destination: file
    logAppend: true
    path: /var/log/mongodb/mongod.log
  ```

### Replica Set Keyfile (`/etc/mongod.keyfile`)
- **Path**: `{{ percona_mongodb_keyfile_path }}` (default `/etc/mongod.keyfile`)
- **Created When**: `percona_mongodb_replset_enabled: true` and `percona_mongodb_auth_enabled: true`
- **Owner/Group**: `{{ percona_mongodb_user }}:{{ percona_mongodb_group }}` (`mongod:mongod`)
- **Mode**: `'0400'`
- **Content**: `percona_mongodb_keyfile_content` if non-empty, or a 756-byte base64 keyfile generated once on the target host via `openssl rand -base64 756` when `percona_mongodb_replset_members | length <= 1`.

## 4. Handler Contract (`roles/percona_mongodb/handlers/main.yml`)

- **Listener `"restart mongod"`**:
  1. `Validate mongod configuration YAML syntax`: parses `{{ percona_mongodb_config_file }}` (`changed_when: false`) to ensure valid YAML and required top-level sections before restarting the daemon.
  2. `Restart mongod`: restarts `{{ percona_mongodb_service_name }}` (`state: restarted`) and waits for `127.0.0.1:{{ percona_mongodb_port }}` to accept connections.
