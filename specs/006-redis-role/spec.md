# Feature Specification: Redis Open Source Role (`redis`)

**Feature Branch**: `006-redis-role`

**Created**: 2026-11-09

**Status**: Draft

**Input**: User description: "create ansible role to install redis open source with ability to set password. name branch based on convention"

## Clarifications

### Session 2026-11-09

- Q: Which package sources should the role support for installing Redis Open Source? (FR-003) → A: Standard OS distribution repositories by default, with an optional toggle (`redis_install_repo: true`) to configure official `packages.redis.io` repositories.
- Q: How should the role protect sensitive password values from leaking in Ansible execution logs and diffs? (FR-006) → A: Provide a configurable `redis_no_log` variable defaulting to `true` to suppress task logging on sensitive template tasks when `redis_password` is set.
- Q: Should the role optionally configure host kernel parameters recommended by Redis, such as `vm.overcommit_memory` and `net.core.somaxconn`? (FR-004) → A: Provide an optional toggle (`redis_sysctl`, default `false`) to configure recommended kernel parameters via `ansible.posix.sysctl` when enabled.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy and Run Redis Open Source on Target Hosts (Priority: P1)

Infrastructure operators and platform engineers need to install and manage Redis Open Source as a reliable background service on Linux hosts across their fleet so that applications can use it as an in-memory data structure store, cache, or message broker.

**Why this priority**: Installing the Redis server package, rendering a deterministic baseline configuration, and managing the system service lifecycle is the foundational capability required before any authentication, network tuning, or application workloads can connect.

**Independent Test**: Can be fully tested by applying the role to a clean Linux host with default settings, verifying that the Redis package is installed, the system service is enabled at boot and actively running, and a local `redis-cli ping` command returns `PONG`.

**Acceptance Scenarios**:

1. **Given** a clean supported Linux host (Debian/Ubuntu or RHEL/Rocky/AlmaLinux), **When** the operator applies the `redis` role with default settings, **Then** Redis Open Source is installed, its configuration file and data/log directories are provisioned with appropriate ownership and permissions, the Redis service is enabled on boot and started, and it responds to local `PING` requests on the default port (`6379`).
2. **Given** an already provisioned host with Redis running, **When** the operator re-runs the role with unchanged variables, **Then** no packages are reinstalled, configuration files remain unmodified, the Redis service is not restarted, and the playbook run completes with zero changes (idempotent).
3. **Given** a running Redis host, **When** a role-managed configuration parameter is modified and the role is re-applied, **Then** the configuration file is updated and the Redis service is restarted to apply the new settings cleanly.

---

### User Story 2 - Configure Redis Password Authentication (Priority: P2)

Security and infrastructure engineers need to set and enforce a password (`requirepass`) on Redis instances—or explicitly run without a password on isolated loopback interfaces—so that unauthorized clients cannot read or modify cached or persisted data.

**Why this priority**: Securing Redis with authentication is an explicit user requirement and a critical production control, especially whenever Redis is reachable across a network or shared host environment.

**Independent Test**: Can be independently tested by setting a non-empty `redis_password` variable, applying the role, and verifying that unauthenticated commands (`redis-cli get test`) are rejected with `NOAUTH Authentication required`, whereas authenticated commands (`redis-cli -a <password> ping`) succeed with `PONG`.

**Acceptance Scenarios**:

1. **Given** a host where `redis_password` is set to a non-empty secret string, **When** the role is applied, **Then** the rendered Redis configuration includes the `requirepass` directive with restricted file permissions (`0640` owned by the Redis system user/group), the service restarts if changed, unauthenticated client commands are rejected with `NOAUTH`, and authenticated client requests succeed.
2. **Given** a host where `redis_password` is empty (`""`, the default), **When** the role is applied, **Then** the `requirepass` directive is omitted from the configuration and local clients can execute commands without supplying a password.
3. **Given** a host previously configured with a password, **When** the operator updates `redis_password` to a new secret or clears it to `""` and re-runs the role, **Then** the configuration is updated idempotently, the service is restarted, and Redis immediately enforces the updated authentication state without leaking sensitive values in Ansible task logs (`no_log` / diff protection where appropriate).

---

### User Story 3 - Customize Network Binding, Memory Policy, and Persistence Settings (Priority: P3)

Infrastructure operators need to tune Redis network bindings, port, protected mode, memory limits (`maxmemory` and `maxmemory-policy`), and persistence options (RDB snapshots and AOF) so each Redis instance matches its workload profile (e.g., ephemeral cache vs. persistent queue).

**Why this priority**: Production deployments frequently require binding Redis to internal private network interfaces, capping memory consumption to prevent host OOM kills, and selecting an eviction policy suited to application caching needs.

**Independent Test**: Can be tested by overriding network bind addresses, port, memory limit, eviction policy, and extra configuration directives in role variables, converging the role, and verifying via `redis-cli CONFIG GET` and socket inspection that Redis is listening on the expected socket with the configured runtime parameters.

**Acceptance Scenarios**:

1. **Given** custom network settings (`redis_bind`, `redis_port`, `redis_protected_mode`), **When** the role is applied, **Then** the Redis daemon listens exclusively on the specified address(es) and port and enforces the specified protected mode setting.
2. **Given** custom memory and persistence parameters (`redis_maxmemory`, `redis_maxmemory_policy`, `redis_save`, `redis_appendonly`, or `redis_extra_config`), **When** the role is applied, **Then** the rendered configuration reflects those values and `CONFIG GET` confirms the active daemon settings match.

---

### Edge Cases

- **Unsupported operating system family**: When executed on an OS family outside `Debian` and `RedHat` (e.g., Alpine or Archlinux), the role fails immediately with a clear, descriptive assertion message before installing packages or writing files.
- **Passwords containing spaces or special characters**: When `redis_password` contains spaces, quotes, or special characters, the configuration template properly quotes and escapes the password string in `requirepass` so Redis parses the exact password without syntax errors.
- **Distribution-specific paths, user/group names, and service units**: Debian-family (`redis-server` service, `/etc/redis/redis.conf`, `redis:redis` user/group) and RedHat-family (`redis` service, `/etc/redis/redis.conf` or `/etc/redis.conf`, `redis:redis` user/group) differ in package/service names and default config paths; the role isolates these differences in `vars/<ansible_os_family>.yml` so user variables behave identically across all supported distributions.
- **Systemd `supervised` integration**: The rendered configuration aligns `supervised systemd` (or configurable supervision mode) and `daemonize no` (matching the distribution's systemd unit type) so systemd accurately tracks the Redis daemon lifecycle without startup timeouts.
- **Invalid port or configuration values**: If a user configures an invalid port number (outside `1..65535`) or an invalid parameter causes Redis to fail on startup, the role fails fast during input validation or service start and surfaces a clear error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The role MUST validate at the start of `tasks/main.yml` that the target host belongs to a supported OS family (`Debian` or `RedHat`) and that key inputs (such as `redis_port`) are valid, failing immediately with a descriptive message on unsupported platforms or invalid parameters.
- **FR-002**: The role MUST isolate OS-specific package names, service unit names, system user/group names, configuration file paths, and runtime/PID directory paths in `vars/Debian.yml` and `vars/RedHat.yml`.
- **FR-003**: The role MUST install the Redis Open Source server package using standard OS distribution repositories by default, and optionally configure the official `packages.redis.io` upstream repository (APT repo and GPG key on Debian/Ubuntu; RPM repo and GPG key on RHEL/Rocky) when `redis_install_repo` is set to `true`.
- **FR-004**: The role MUST provide user-tunable, `redis_`-prefixed variables in `defaults/main.yml` for core Redis configuration, including at minimum:
  - `redis_install_repo` (boolean to configure official `packages.redis.io` repository, default `false`)
  - `redis_package_state` (package installation state, default `"present"`)
  - `redis_service_enabled` (boolean to enable service at boot, default `true`)
  - `redis_service_state` (desired service state, default `"started"`)
  - `redis_bind` (string or list of IP addresses to bind to, default `"127.0.0.1 -::1"` or `["127.0.0.1", "-::1"]`)
  - `redis_port` (TCP listening port, default `6379`)
  - `redis_protected_mode` (boolean or `"yes"`/`"no"` for Redis protected mode, default `true`)
  - `redis_password` (optional authentication password string for `requirepass`, default `""` meaning no password authentication)
  - `redis_no_log` (boolean to suppress task logging on sensitive template tasks when password is configured, default `true`)
  - `redis_tcp_backlog` (`tcp-backlog`, default `511`)
  - `redis_timeout` (client idle timeout in seconds, default `0`)
  - `redis_tcp_keepalive` (TCP keepalive in seconds, default `300`)
  - `redis_databases` (number of databases, default `16`)
  - `redis_loglevel` (server verbosity level: `debug`, `verbose`, `notice`, `warning`, default `"notice"`)
  - `redis_logfile` (log file path, default OS-appropriate path such as `"/var/log/redis/redis-server.log"` or `"/var/log/redis/redis.log"`)
  - `redis_dir` (working directory for RDB/AOF persistence files, default `"/var/lib/redis"`)
  - `redis_save` (list of RDB snapshot save intervals, e.g., `["3600 1", "300 100", "60 10000"]`, or empty list `[]` to disable RDB snapshots)
  - `redis_appendonly` (boolean to enable AOF persistence, default `false`)
  - `redis_maxmemory` (maximum memory limit, e.g., `"256mb"`, default `""` / unset)
  - `redis_maxmemory_policy` (eviction policy when `maxmemory` is reached, default `"noeviction"`)
  - `redis_extra_config` (dictionary or list of additional raw `redis.conf` directives for advanced customization, default `{}`)
  - `redis_sysctl` (boolean to configure recommended Linux kernel sysctl parameters via `ansible.posix.sysctl`, default `false`)
- **FR-005**: When `redis_password` is set to a non-empty string, the role MUST configure the `requirepass` directive in `redis.conf` (properly quoted so special characters and spaces are preserved); when `redis_password` is empty (`""`), the role MUST omit `requirepass` so password authentication is disabled.
- **FR-006**: The role MUST render the Redis configuration file with restricted permissions (`mode: '0640'`, owned by `redis:redis` or `root:redis` according to OS convention) so that any configured `requirepass` secret in `redis.conf` is not world-readable, and MUST apply `no_log: "{{ redis_no_log }}"` when `redis_password` is set to prevent credentials from leaking into task logs or diffs.
- **FR-007**: The role MUST manage the Redis systemd service (enabled at boot and started by default) and trigger a service restart via an Ansible handler whenever the rendered Redis configuration file changes.
- **FR-008**: When `redis_sysctl` is set to `true`, the role MUST configure recommended host kernel parameters (`vm.overcommit_memory = 1` and `net.core.somaxconn = 512`) using `ansible.posix.sysctl` persistently across reboots.
- **FR-009**: All tasks in the role MUST follow collection conventions (FQCNs, named tasks in imperative case, quoted octal file modes, `redis_` variable prefixing) and be strictly idempotent, producing zero changed tasks and zero service restarts on a second consecutive run with unchanged variables across all supported distributions.

### Key Entities

- **Redis Daemon (`redis-server`)**: The in-memory key-value data store service running under systemd supervision on the target host. Key attributes include network bind addresses, listening port, authentication state, persistence rules, and memory limits.
- **Redis Configuration (`redis.conf`)**: The primary configuration file rendered from a Jinja2 template, owned with restricted permissions (`0640`) to protect authentication credentials (`requirepass`) while defining runtime behavior.
- **Persistence Store (`/var/lib/redis`)**: The local filesystem directory owned by the `redis` system user where RDB snapshots (`dump.rdb`) and Append-Only Files (`appendonly.aof`) are stored.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy and start Redis Open Source across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in a single execution, with the service reaching an active (running) state and responding to client queries on the configured port within 30 seconds.
- **SC-002**: When `redis_password` is configured, 100% of unauthenticated data commands are rejected by the server (`NOAUTH`), and 100% of requests authenticated with the configured password succeed (`PONG` / read-write operations).
- **SC-003**: The rendered Redis configuration file enforces `0640` permissions on 100% of target hosts so non-privileged local users cannot read the password from disk.
- **SC-004**: Re-running the role on an already converged host with identical variables produces 0 changed tasks and 0 service restarts across all 5 supported distributions.
- **SC-005**: Executing the role on an unsupported OS family or with invalid configuration inputs fails before modifying system packages or disrupting existing services.

## Assumptions

- Target hosts run `systemd` as their init and service manager across supported Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) and RedHat-family (Rocky Linux 8, Rocky Linux 9) distributions.
- Installing Redis Open Source from standard distribution package repositories (`redis-server` on Debian/Ubuntu, `redis` on Rocky Linux/RHEL) is the default (`redis_install_repo: false`) across all five CI matrix distributions, while setting `redis_install_repo: true` enables the official `packages.redis.io` repository when a newer upstream release is required.
- By default, Redis binds to loopback interfaces (`127.0.0.1` and `-::1`) on port `6379` with `protected-mode yes` and an empty `redis_password` (`""`), matching upstream security defaults while allowing operators to set `redis_password` and custom `redis_bind` addresses for network-accessible deployments.
- Host kernel tuning (`redis_sysctl`) is disabled by default (`false`) to ensure safe execution in unprivileged container environments (e.g., Molecule testing) while allowing bare-metal and VM operators to enable recommended memory overcommit and socket connection parameters.
- Redis ACL multi-user management (beyond the default user password via `requirepass`), Redis Sentinel, and Redis Cluster multi-node sharding orchestration are out of scope for the baseline role unless passed through `redis_extra_config`.
