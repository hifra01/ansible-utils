# Phase 0 Research: HashiCorp Consul Role (`consul`)

**Feature**: `001-consul-role`  
**Date**: 2026-10-18

## 1. Official HashiCorp Package Repositories Across Debian & RedHat Families

- **Decision**:
  - **Debian Family (Ubuntu 22.04, Ubuntu 24.04, Debian 12)**: Download the official HashiCorp ASCII-armored GPG key (`https://apt.releases.hashicorp.com/gpg`) to `/etc/apt/keyrings/hashicorp.asc` (mode `'0644'`) and configure the APT repository in `/etc/apt/sources.list.d/hashicorp.list` using `ansible.builtin.apt_repository` with `signed-by=/etc/apt/keyrings/hashicorp.asc` and architecture mapping (`x86_64 -> amd64`, `aarch64 -> arm64`, `armv7l -> armhf`).
  - **RedHat Family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL)**: Install `yum-utils` and download `https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo` to `/etc/yum.repos.d/hashicorp.repo` (mode `'0644'`) using `ansible.builtin.get_url`.
- **Rationale**:
  - Matches the exact pattern established in `roles/docker/tasks/setup-repository.yml`.
  - Avoids deprecated `apt-key` on Debian 12 / Ubuntu 24.04 and avoids shelling out to `yum-config-manager`.
  - Official HashiCorp `consul` packages automatically create the `consul` system user/group, `/etc/consul.d`, `/opt/consul`, `/usr/bin/consul`, and the systemd unit `/lib/systemd/system/consul.service` (or `/usr/lib/systemd/system/consul.service`).
- **Alternatives Considered**:
  - *Downloading precompiled Consul ZIP archives from `releases.hashicorp.com`*: Rejected because it requires manual user/group creation, custom systemd unit maintenance, and manual binary upgrades instead of native OS package management.
  - *Using `yum-config-manager --add-repo` via `command`*: Rejected because `ansible.builtin.get_url` to `/etc/yum.repos.d/hashicorp.repo` is natively idempotent without `command` wrappers.

## 2. Consul Agent Configuration Structure & Stock Conffile Handling

- **Decision**:
  - Manage `/etc/consul.d/consul.hcl` directly via `templates/consul.hcl.j2` (owned by `consul:consul`, mode `'0640'`).
  - Optionally render `/etc/consul.d/extra.json` when `consul_extra_config` is non-empty (and ensure `/etc/consul.d/extra.json` is `absent` when `consul_extra_config` is empty).
  - Render each advertised service in `consul_services` to `/etc/consul.d/service-{{ service.id | default(service.name) }}.json` via `templates/service.json.j2` (owned by `consul:consul`, mode `'0640'`).
- **Rationale**:
  - The official `consul` deb/rpm package ships `/etc/consul.d/consul.hcl` as a package conffile containing default settings (`datacenter = "dc1"`, `data_dir = "/opt/consul"`). Overwriting `/etc/consul.d/consul.hcl` in place prevents duplicate/conflicting configuration directives while preserving package manager conffile tracking.
  - Isolating each service in `/etc/consul.d/service-<id>.json` allows clean per-service updates and deterministic orphan cleanup (`consul_services_purge: true`) using `ansible.builtin.find` on `service-*.json` without touching the main `consul.hcl` file.
- **Alternatives Considered**:
  - *Putting all services inside `consul.hcl`*: Rejected because modular per-service files (`service-<id>.json`) are easier to inspect, validate, and serialize cleanly from structured Ansible dictionaries using `to_nice_json`.
  - *Writing `consul.json` and deleting `consul.hcl`*: Rejected because deleting a packaged conffile can cause dpkg/rpm to restore it or prompt during package upgrades.

## 3. Network Binding & Advertise Address Defaults in Multi-Interface / Container Hosts

- **Decision**:
  - Default `consul_bind_addr` to `"0.0.0.0"`, `consul_client_addr` to `"127.0.0.1"`, and `consul_advertise_addr` to `"{{ ansible_default_ipv4.address | default('127.0.0.1') }}"`.
- **Rationale**:
  - When `bind_addr` is `"0.0.0.0"` on a host with multiple private IPv4 interfaces (e.g., `eth0` plus `docker0`) or inside a container without a default route, Consul refuses to start unless `advertise_addr` resolves to a single concrete IPv4 address.
  - Using `ansible_default_ipv4.address | default('127.0.0.1')` guarantees out-of-the-box startup on both multi-NIC Linux servers and isolated Molecule Docker containers while still allowing operators to override `consul_advertise_addr` per host.
- **Alternatives Considered**:
  - *Leaving `advertise_addr` unset by default*: Rejected because hosts running Docker (`docker0` bridge) alongside `eth0` fail Consul startup with `Multiple private IPv4 addresses found`.

## 4. Configuration Validation and Reload vs. Restart Semantics

- **Decision**:
  - Validate the entire configuration directory using `consul validate {{ consul_config_dir }}` inside handlers before reloading or restarting the `consul` service, grouped via `listen:` (`"validate and reload consul"` and `"validate and restart consul"`), matching `roles/nginx/handlers/main.yml`.
  - Changes to `/etc/consul.d/consul.hcl` or `/etc/consul.d/extra.json` notify `"validate and restart consul"` (since mode, `bootstrap_expect`, `data_dir`, and bind addresses require a process restart).
  - Changes to `/etc/consul.d/service-*.json` (adding, modifying, or purging advertised services) notify `"validate and reload consul"` (`state: reloaded`), which triggers Consul's SIGHUP handler to reload service definitions in place without dropping cluster membership.
- **Rationale**:
  - Directly satisfies Constitution Principle IV ("Service configuration handlers MUST validate configuration before reloading or restarting, grouped via `listen:`") and FR-009/FR-010.
- **Alternatives Considered**:
  - *Using `validate:` parameter on `template` tasks only*: Insufficient on its own because `consul validate` validates a directory (`/etc/consul.d`) as a cohesive unit rather than an isolated single-file fragment in `/tmp` when cross-file references or JSON/HCL merges are evaluated. Running `consul validate {{ consul_config_dir }}` in the handler listener validates the complete `/etc/consul.d` directory prior to reload/restart.

## 5. Multi-Distro Molecule Verification & RHEL/Rocky 8 Compatibility

- **Decision**:
  - Use the collection's standard `molecule/default/molecule.yml` (Docker driver with systemd, `${MOLECULE_DISTRO:-geerlingguy/docker-ubuntu2404-ansible}`) and the minimal RHEL 8 Python 3.9 bootstrap in `prepare.yml` (`raw` install of `python39` on release 8 without hardcoding `set_fact: ansible_python_interpreter: /usr/bin/python3.9`, matching `roles/docker` and `roles/nginx`).
  - Test both operational modes (`server` and `client`) and service advertisement/cleanup during the Molecule test sequence:
    - `converge.yml` converges the node in `server` mode (`consul_mode: "server"`, `consul_bootstrap_expect: 1`, `consul_ui: true`) with multiple `consul_services` (e.g., a web service with TCP/HTTP check and a database service with tags/metadata) so the local Consul cluster forms a leader and serves the catalog HTTP API (`http://127.0.0.1:8500/v1/agent/services` and `consul members`).
    - `verify.yml` asserts:
      1. `consul` package and `/usr/bin/consul` binary are installed.
      2. `/etc/consul.d/consul.hcl` and `/etc/consul.d/service-*.json` exist with expected mode `'0640'` and owner `consul:consul`.
      3. `consul validate /etc/consul.d` exits `0`.
      4. `consul` systemd service is enabled and active (`running`).
      5. `consul members` shows the node as a `server` in `alive` status.
      6. Querying the local agent HTTP API (`http://127.0.0.1:8500/v1/agent/services`) returns all defined `consul_services` with matching ports, tags, and metadata.
      7. Service purge/client-mode verification: Verify that an orphaned `/etc/consul.d/service-stale.json` (planted in `prepare.yml`) was purged during converge, and verify `client` mode configuration rendering and validation via role task invocation in `verify.yml` (restoring `server` state afterward).
- **Rationale**:
  - Ensures 100% of functional requirements (server mode, client mode, service advertisement, service purge, config validation, and idempotency) are verified across all 5 CI distros (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`).
  - Avoiding `set_fact: ansible_python_interpreter: /usr/bin/python3.9` on Rocky 8 allows Ansible's `dnf` module to automatically respawn onto `/usr/libexec/platform-python` where `python3-dnf` bindings exist.
- **Alternatives Considered**:
  - *Multi-container Molecule scenario*: Single-container systemd scenario with `consul_mode: "server"` (`bootstrap_expect: 1`) plus client-mode verification is faster, matches the CI matrix architecture across all existing roles in `hifra01.utils`, and requires no custom Docker network orchestration in GitHub Actions.
