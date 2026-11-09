# Role Interface Contract: `hifra01.utils.redis`

**Feature**: `006-redis-role`  
**Date**: 2026-11-09

## 1. Public Role Variables (`roles/redis/defaults/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# defaults file for redis

# Repository configuration: when true, configures official packages.redis.io repository
redis_install_repo: false

# Package management
redis_package_state: present

# Service state management
redis_service_enabled: true
redis_service_state: started

# Network binding and security
redis_bind: "127.0.0.1 -::1"
redis_port: 6379
redis_protected_mode: true

# Authentication password (requirepass)
# When empty (""), authentication is disabled.
redis_password: ""

# Task output suppression: prevents password exposure in logs and diffs
redis_no_log: true

# General operational settings
redis_tcp_backlog: 511
redis_timeout: 0
redis_tcp_keepalive: 300
redis_databases: 16
redis_loglevel: notice

# Log file path: when empty (""), defaults to OS-appropriate path from vars/<OS>.yml
redis_logfile: ""

# Working directory for DB persistence files (dump.rdb, appendonly.aof)
redis_dir: "/var/lib/redis"

# Snapshotting (RDB) rules: list of "seconds changes" strings.
# Set to an empty list [] to disable RDB persistence.
redis_save:
  - "3600 1"
  - "300 100"
  - "60 10000"

# Append Only File (AOF) persistence
redis_appendonly: false

# Memory management
redis_maxmemory: ""
redis_maxmemory_policy: "noeviction"

# Raw custom configuration directives (dict or list of strings)
redis_extra_config: {}

# Host kernel tuning via ansible.posix.sysctl
# When true, configures vm.overcommit_memory = 1 and net.core.somaxconn = 512
redis_sysctl: false
```

## 2. OS-Specific Variables (`roles/redis/vars/<ansible_os_family>.yml`)

### `roles/redis/vars/Debian.yml`

```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for redis (Debian family)

redis_package_name: redis-server
redis_service_name: redis-server

redis_config_dir: /etc/redis
redis_config_file: /etc/redis/redis.conf
redis_default_logfile: /var/log/redis/redis-server.log

redis_system_user: redis
redis_system_group: redis

redis_config_owner: root
redis_config_group: redis
redis_config_mode: '0640'

redis_repo_apt_key_url: https://packages.redis.io/gpg
redis_repo_apt_key_path: /etc/apt/keyrings/redis.gpg
redis_repo_apt_url: >-
  deb [signed-by=/etc/apt/keyrings/redis.gpg] https://packages.redis.io/deb {{ ansible_distribution_release }} main
```

### `roles/redis/vars/RedHat.yml`

```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for redis (RedHat family)

redis_package_name: redis
redis_service_name: redis

redis_config_dir: /etc/redis
redis_config_file: /etc/redis/redis.conf
redis_default_logfile: /var/log/redis/redis.log

redis_system_user: redis
redis_system_group: redis

redis_config_owner: redis
redis_config_group: redis
redis_config_mode: '0640'

redis_repo_rpm_url: https://packages.redis.io/rpm/rhel{{ ansible_distribution_major_version }}
redis_repo_rpm_key_url: https://packages.redis.io/gpg
```

## 3. Handlers Contract (`roles/redis/handlers/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# handlers file for redis

- name: Restart redis
  ansible.builtin.service:
    name: "{{ redis_service_name }}"
    state: restarted
  listen: "restart redis"
```

## 4. Configuration Template Contract (`templates/redis.conf.j2`)

The rendered configuration file must enforce:
- `bind {{ redis_bind if redis_bind is string else redis_bind | join(' ') }}`
- `port {{ redis_port }}`
- `protected-mode {{ 'yes' if redis_protected_mode else 'no' }}`
- `requirepass {{ redis_password | quote }}` (rendered only when `redis_password | length > 0`)
- `supervised systemd`
- `daemonize no`
- `dir {{ redis_dir }}`
- `logfile {{ redis_logfile | default(redis_default_logfile, true) }}`
- `appendonly {{ 'yes' if redis_appendonly else 'no' }}`
- `maxmemory {{ redis_maxmemory }}` (rendered only when `redis_maxmemory | length > 0`)
- `maxmemory-policy {{ redis_maxmemory_policy }}`
- File permissions: mode `'0640'`, owned by `redis_config_owner:redis_config_group`.
