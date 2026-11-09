# Phase 0 Research: Redis Open Source Role (`redis`)

**Feature**: `006-redis-role`  
**Date**: 2026-11-09

## 1. Package Installation, Repository Sources & OS Dispatches

- **Decision**:
  - Install Redis Open Source from standard distribution package repositories by default (`redis_install_repo: false`):
    - Debian / Ubuntu: package `redis-server`, service name `redis-server`, default config `/etc/redis/redis.conf`.
    - RedHat / Rocky Linux (8 & 9): package `redis`, service name `redis`, default config `/etc/redis/redis.conf` (with `/etc/redis.conf` symlinked or standard).
  - When `redis_install_repo: true`, optionally configure the official `packages.redis.io` repository and GPG signing keys before installing packages:
    - Debian / Ubuntu: download official Redis GPG key (`https://packages.redis.io/gpg`) and configure APT repository (`deb [signed-by=...] https://packages.redis.io/deb {{ ansible_distribution_release }} main`).
    - RedHat / Rocky Linux: configure official YUM/DNF repository (`https://packages.redis.io/rpm/rhel{{ ansible_distribution_major_version }}`) and GPG key (`https://packages.redis.io/gpg`).
  - Isolate all OS-divergent package names, service unit names, user/group accounts, and default file paths into `vars/Debian.yml` and `vars/RedHat.yml`.
- **Rationale**:
  - Standard distribution repositories are pre-configured, fast, and completely reliable across all 5 target test distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in CI containers without requiring external network repository keys during default test runs.
  - Adding the optional `redis_install_repo: true` toggle satisfies users requiring the newest upstream Redis Open Source release (Redis 7.x/8.x) on distributions that ship older versions (e.g., Rocky Linux 8 shipping Redis 5.0/6.0).
  - Isolating OS-specific names in `vars/<ansible_os_family>.yml` satisfies Constitution Principle III.
- **Alternatives Considered**:
  - *Compiling Redis from source code*: Rejected because building from source requires C compiler toolchains, slows down provisioning, complicates uninstall/upgrade paths, and violates Debian/RHEL packaging best practices.
  - *Hardcoding `redis-server` across all OS families*: Rejected because RHEL/Rocky packages the daemon and systemd service as `redis`, not `redis-server`.

## 2. Password Authentication & Execution Log Protection

- **Decision**:
  - In `roles/redis/defaults/main.yml`, define `redis_password: ""` (defaulting to empty string, meaning no password required).
  - When `redis_password | length > 0`, render `requirepass {{ redis_password | quote }}` in the Redis configuration template (`redis.conf.j2`).
  - When `redis_password | length == 0`, omit the `requirepass` directive completely so password authentication is not enforced.
  - Render the Redis configuration file with restricted permissions: `mode: '0640'`, owned by `root:{{ redis_system_group }}` on Debian and `{{ redis_system_user }}:{{ redis_system_group }}` on RedHat.
  - Provide a user-tunable boolean `redis_no_log: true` in `defaults/main.yml`.
  - On the configuration template task, set `no_log: "{{ redis_no_log and (redis_password | length > 0) }}"` so plaintext passwords do not appear in Ansible stdout logs, CI output, or `--diff` output.
- **Rationale**:
  - Directly fulfills the primary user requirement ("with ability to set password").
  - Quoting the password in `redis.conf` prevents parsing errors if the user's password contains special characters, spaces, or hashes.
  - Restricting file permissions to `0640` prevents unprivileged local users from reading the password from disk.
  - Suppressing task logs via `redis_no_log: true` prevents credential leaks in CI and orchestration logs while allowing operators to set `redis_no_log: false` for debugging during local testing.
- **Alternatives Considered**:
  - *Redis 6+ ACL user directives (`user default on >password ~* &* +@all`)*: Evaluated, but `requirepass` is backwards-compatible across all Redis versions (including Redis 5.x on Rocky Linux 8) and seamlessly sets the `default` user password in Redis 6+.
  - *Hardcoding `no_log: true` unconditionally*: Rejected during clarification (Session 2026-11-09 Q2) in favor of a configurable `redis_no_log` toggle.

## 3. Daemon Configuration, Systemd Supervision & Handler Management

- **Decision**:
  - Render the primary configuration file from `templates/redis.conf.j2` to `{{ redis_config_file }}`.
  - In `redis.conf.j2`, configure:
    - `supervised systemd` (or `supervised auto`) and `daemonize no` when managed by systemd.
    - `bind {{ redis_bind if redis_bind is string else redis_bind | join(' ') }}` (default `"127.0.0.1 -::1"`).
    - `port {{ redis_port }}` (default `6379`).
    - `protected-mode {{ 'yes' if redis_protected_mode else 'no' }}`.
    - `dir {{ redis_dir }}` (default `"/var/lib/redis"`).
    - `logfile {{ redis_logfile }}` (OS-specific log path).
    - `maxmemory {{ redis_maxmemory }}` and `maxmemory-policy {{ redis_maxmemory_policy }}` when `redis_maxmemory` is specified.
    - Snapshot rules via `redis_save` (e.g., `["3600 1", "300 100", "60 10000"]`).
    - Append-only file persistence via `appendonly {{ 'yes' if redis_appendonly else 'no' }}`.
    - Support raw key-value / dictionary / list overrides via `redis_extra_config`.
  - In `handlers/main.yml`, define a single service restart handler:
    ```yaml
    - name: Restart redis
      ansible.builtin.service:
        name: "{{ redis_service_name }}"
        state: restarted
      listen: "restart redis"
    ```
- **Rationale**:
  - Systemd requires Redis not to fork into the background when `Type=notify` or `Type=simple` is used in the distribution's systemd unit file; setting `supervised systemd` and `daemonize no` ensures clean process tracking.
  - Grouping service restarts via `listen: "restart redis"` aligns with Constitution Principle IV.
- **Alternatives Considered**:
  - *Dynamic runtime password updates via `redis-cli CONFIG SET requirepass`*: Rejected because changes to `redis.conf` must persist across host reboots, and Ansible handler restart is idempotent, deterministic, and avoids socket/authentication handshake races during playbook execution.

## 4. Host Kernel Tuning (`redis_sysctl`)

- **Decision**:
  - Define `redis_sysctl: false` in `defaults/main.yml`.
  - When `redis_sysctl` is set to `true`, execute tasks using `ansible.posix.sysctl`:
    - `vm.overcommit_memory = 1` (`state: present`, `reload: true`, `sysctl_set: true`)
    - `net.core.somaxconn = 512` (`state: present`, `reload: true`, `sysctl_set: true`)
  - Guard the sysctl tasks with `when: redis_sysctl | bool` and ignore errors in Docker / containerized environments where sysctl writes may be restricted.
- **Rationale**:
  - Redis startup logs issue explicit warnings if `vm.overcommit_memory` is `0` or `net.core.somaxconn` is `128`.
  - Defaulting to `false` ensures the role executes cleanly inside unprivileged containers and Molecule testing environments without permission errors.
- **Alternatives Considered**:
  - *Always modifying `/etc/sysctl.conf`*: Rejected during clarification (Session 2026-11-09 Q3) because modifying global host kernel parameters unconditionally can disrupt containerized environments or other workloads.

## 5. Multi-Distro Molecule Verification Strategy

- **Decision**:
  - Scaffold the role via `ansible-galaxy role init --init-path roles redis` and `molecule init scenario default` from inside `roles/redis`.
  - Test across all 5 collection CI matrix distributions:
    1. Ubuntu 22.04 (`geerlingguy/docker-ubuntu2204-ansible:latest`)
    2. Ubuntu 24.04 (`geerlingguy/docker-ubuntu2404-ansible:latest`)
    3. Debian 12 (`geerlingguy/docker-debian12-ansible:latest`)
    4. Rocky Linux 9 (`geerlingguy/docker-rockylinux9-ansible:latest`)
    5. Rocky Linux 8 (`geerlingguy/docker-rockylinux8-ansible:latest`)
  - Include the Python 3.9 bootstrap in `prepare.yml` for Rocky Linux 8.
  - In `converge.yml`, execute `hifra01.utils.redis` with a configured test password (e.g. `redis_password: "MoleculeSecretPassword123!"`).
  - In `verify.yml`, assert:
    1. The Redis package is installed.
    2. The Redis service (`redis-server` on Debian/Ubuntu, `redis` on Rocky Linux) is running and enabled.
    3. The configuration file exists with permissions `0640`.
    4. Port `6379` is open and listening.
    5. An unauthenticated `redis-cli ping` command is rejected with `NOAUTH`.
    6. An authenticated `redis-cli -a MoleculeSecretPassword123! ping` command returns `PONG`.
    7. Idempotence test passes with 0 changed tasks.
- **Rationale**:
  - Provides rigorous end-to-end verification of all acceptance criteria and security guarantees across all supported platforms.
