# Redis Open Source Role (`hifra01.utils.redis`)

Ansible role to install and configure Redis Open Source as a systemd service, with support for password authentication (`requirepass`), restricted file security (`0640`), network binding, memory policies, RDB/AOF persistence, and optional host kernel sysctl tuning.

## Supported Platforms

* **Debian Family**: Debian 12 (Bookworm), Ubuntu 22.04 (Jammy), Ubuntu 24.04 (Noble)
* **RedHat Family**: Rocky Linux 8 & 9, AlmaLinux 8 & 9, RHEL 8 & 9

## Requirements

* `ansible-core >= 2.21.0`
* Collection dependency: `ansible.posix >= 1.5.0` (for `ansible.posix.sysctl` when `redis_sysctl: true`)
* Requires systemd init system on target hosts.
* Fact gathering (`gather_facts: true`) must be enabled.

## Role Variables

| Variable | Default | Description |
|---|---|---|
| `redis_install_repo` | `false` | When `true`, configures official `packages.redis.io` upstream package repository |
| `redis_package_state` | `"present"` | Package installation state (`present`, `latest`) |
| `redis_service_enabled` | `true` | Whether the Redis service is enabled at system boot |
| `redis_service_state` | `"started"` | Desired state of the Redis service (`started`, `stopped`) |
| `redis_bind` | `"127.0.0.1 -::1"` | IP address(es) or interfaces Redis binds to |
| `redis_port` | `6379` | TCP listening port (`1..65535`) |
| `redis_protected_mode` | `true` | Enables protected mode when binding to network interfaces |
| `redis_password` | `""` | Secret authentication password (`requirepass`). Empty string disables authentication |
| `redis_no_log` | `true` | Suppresses task logging and diff output when `redis_password` is configured |
| `redis_tcp_backlog` | `511` | TCP listen backlog |
| `redis_timeout` | `0` | Client idle timeout in seconds (`0` disables timeout) |
| `redis_tcp_keepalive` | `300` | TCP keepalive interval in seconds |
| `redis_databases` | `16` | Number of databases |
| `redis_loglevel` | `"notice"` | Server logging verbosity (`debug`, `verbose`, `notice`, `warning`) |
| `redis_logfile` | `""` | Custom log file path (defaults to OS-specific path when empty) |
| `redis_dir` | `"/var/lib/redis"` | Working directory for DB persistence files |
| `redis_save` | `["3600 1", "300 100", "60 10000"]` | RDB snapshot save intervals. Empty list `[]` disables RDB |
| `redis_appendonly` | `false` | Enables Append-Only File (AOF) persistence |
| `redis_maxmemory` | `""` | Maximum memory limit (e.g., `"256mb"`, `"2gb"`) |
| `redis_maxmemory_policy` | `"noeviction"` | Eviction policy when `maxmemory` is reached |
| `redis_extra_config` | `{}` | Dictionary or list of raw `redis.conf` directives |
| `redis_sysctl` | `false` | When `true`, sets `vm.overcommit_memory = 1` and `net.core.somaxconn = 512` |

## Example Playbooks

### Default (Unauthenticated, Localhost Only)

```yaml
---
- name: Deploy default Redis server
  hosts: all
  become: true
  roles:
    - role: hifra01.utils.redis
```

### Password-Protected Cache with Memory Cap

```yaml
---
- name: Deploy secure Redis cache
  hosts: cache_servers
  become: true
  roles:
    - role: hifra01.utils.redis
      vars:
        redis_bind: "0.0.0.0"
        redis_password: "{{ vault_redis_password }}"
        redis_maxmemory: "1gb"
        redis_maxmemory_policy: "allkeys-lru"
        redis_appendonly: true
```

## License

MIT
