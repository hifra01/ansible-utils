# Feature Specification: HashiCorp Consul Role (`consul`)

**Feature Branch**: `001-consul-role`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "create ansible role to install hashicorp consul, user can choose consul run as server or client on each server, and user able to define services to be advertised on each server"

## Clarifications

### Session 2026-10-21

- Q: What default values should the role use for `consul_bind_addr` and `consul_advertise_addr` when not explicitly overridden by the user? (FR-006) → A: Default `consul_bind_addr` to `"0.0.0.0"` and `consul_advertise_addr` to `"{{ ansible_default_ipv4.address | default('127.0.0.1') }}"`.
- Q: How should the role determine whether a configuration change triggers a service reload versus a full service restart? (FR-010) → A: Changes to main agent config (`consul.hcl`) validate and restart `consul`; changes to service files (`service-<id>.json`) validate and reload `consul`.
- Q: How should the role handle the default `/etc/consul.d/consul.hcl` file created by the official HashiCorp package during installation? (FR-008) → A: Render the main agent configuration directly to `/etc/consul.d/consul.hcl` (overwriting the package default) and use `service-<id>.json` for services.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Consul Agent as Server or Client (Priority: P1)

Infrastructure operators need to install HashiCorp Consul on target Linux hosts and explicitly designate whether each host operates as a Consul Server (maintaining cluster state, participating in Raft consensus, and responding to queries) or a Consul Client (lightweight agent running alongside workload applications that forwards RPCs to servers).

**Why this priority**: Installing the Consul agent and running it in the desired operational mode (`server` or `client`) is the foundational capability required before any service registration or cluster discovery can take place.

**Independent Test**: Can be fully tested by provisioning a single host in `server` mode (bootstrapped as a single-node cluster) or `client` mode, verifying that the Consul service is enabled and running, and confirming that the local agent reports the configured operational mode and healthy member status.

**Acceptance Scenarios**:

1. **Given** a clean supported Linux host (Debian/Ubuntu or RHEL/Rocky/AlmaLinux), **When** the operator provisions the host with the role configured for `server` mode, **Then** HashiCorp Consul is installed, configured as a server agent, enabled at boot, started, and reports itself as an active server member of the datacenter.
2. **Given** a clean supported Linux host, **When** the operator provisions the host with the role configured for `client` mode (or using the default mode), **Then** HashiCorp Consul is installed, configured as a client agent (`server = false`), enabled at boot, and running cleanly.
3. **Given** an already provisioned Consul host, **When** the operator re-runs provisioning with identical parameters, **Then** no configuration files are modified, no service restarts or reloads occur, and the run completes with zero changes.

---

### User Story 2 - Advertise Node Services on Each Host (Priority: P2)

Infrastructure operators need to declare a per-host list of services (such as web servers, databases, caches, or custom application ports) so that each host automatically registers its local workloads with its Consul agent for service discovery and health monitoring.

**Why this priority**: Service discovery is the primary user-facing value of deploying Consul across an infrastructure fleet once the base agent is running.

**Independent Test**: Can be independently tested by providing a list of one or more service definitions on a node, converging the role, and querying the local Consul agent catalog/agent API to verify that every declared service (along with its port, tags, metadata, and health checks) is registered and advertised.

**Acceptance Scenarios**:

1. **Given** a host running Consul, **When** the operator defines one or more services (with name, port, optional tags, metadata, and health check parameters) for that host, **Then** dedicated service definition files are rendered, validated, and loaded so the services appear in the local Consul agent service catalog.
2. **Given** a host with existing advertised services managed by the role, **When** the operator modifies a service port/tag or removes a service from the host's service list, **Then** the outdated service configuration is updated or removed and the Consul agent reloads its configuration without requiring a full process restart.
3. **Given** a host where no services are defined (empty service list), **Then** the Consul agent runs normally without any role-managed service definition files present.

---

### User Story 3 - Configure Cluster Joining, Networking, and UI Access (Priority: P3)

Infrastructure operators deploying multi-node environments need to customize datacenter names, cluster peer join addresses (`retry_join`), network bind/client addresses, and optional Web UI availability so that client and server nodes can discover each other across a network and expose administration interfaces where appropriate.

**Why this priority**: While single-node defaults allow immediate testing, production deployments require customizable network bindings and peer join lists to form multi-node clusters across environments.

**Independent Test**: Can be tested by overriding network bind/client addresses, datacenter name, Web UI toggle, and `retry_join` targets in host/group variables, and verifying that the rendered baseline configuration reflects those settings and passes `consul validate`.

**Acceptance Scenarios**:

1. **Given** a host with custom datacenter, bind address, client address, and `retry_join` peer addresses specified, **When** the role is applied, **Then** the agent configuration reflects these network and cluster settings and passes configuration validation prior to service start.
2. **Given** a Consul node configured with the Web UI enabled, **When** the agent is running, **Then** the UI setting is active in the agent configuration and accessible on the configured client address and HTTP port.

---

### Edge Cases

- **Unsupported operating system family**: When executed against an unsupported OS family (outside Debian and RedHat families), the role fails immediately with a clear, descriptive assertion message before attempting any package or file changes.
- **Invalid operational mode or bootstrap settings**: When a user supplies an invalid mode (anything other than `server` or `client`) or a non-positive `bootstrap_expect` count in server mode, the role fails fast during input validation with an actionable error message.
- **Stale service definitions after removal**: When a previously defined service is removed from a node's service list, its orphaned service configuration file is automatically purged so the node no longer advertises a non-existent service.
- **Invalid configuration syntax**: If user-supplied parameters produce a configuration that fails `consul validate`, the validation step halts execution before reloading or restarting the live Consul service, preventing cluster disruption.
- **Port or service Definition without optional fields**: When a user defines a minimal service (e.g., only `name` and `port`), sensible defaults are applied for optional fields (`id`, `address`, `tags`, `meta`, `checks`) without error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The role MUST validate that the target host belongs to a supported OS family (`Debian` or `RedHat`) and fail immediately with a descriptive message on unsupported platforms.
- **FR-002**: The role MUST configure the official HashiCorp package repository (APT repository with GPG key on Debian/Ubuntu; YUM/DNF repository on RHEL/Rocky/AlmaLinux) and install the `consul` package at a configurable version or latest available package state.
- **FR-003**: The role MUST allow operators to select the agent operational mode per host via `consul_mode` (`"server"` or `"client"`, defaulting to `"client"`), and validate that only these two values are accepted.
- **FR-004**: When `consul_mode` is set to `"server"`, the role MUST configure server-specific settings including `server = true` and a configurable `consul_bootstrap_expect` value (defaulting to `1` for single-server convenience and overridable for multi-server Raft quorums).
- **FR-005**: When `consul_mode` is set to `"client"`, the role MUST configure `server = false` and omit `bootstrap_expect` from the agent configuration.
- **FR-006**: The role MUST provide user-tunable, `consul_`-prefixed variables in `defaults/main.yml` for core agent settings, including at minimum:
  - `consul_mode` (`"client"` or `"server"`)
  - `consul_datacenter` (default `"dc1"`)
  - `consul_node_name` (defaulting to the host's inventory/system hostname)
  - `consul_data_dir` (default `"/opt/consul"`)
  - `consul_config_dir` (default `"/etc/consul.d"`)
  - `consul_bind_addr` (default `"0.0.0.0"`)
  - `consul_advertise_addr` (default `"{{ ansible_default_ipv4.address | default('127.0.0.1') }}"`)
  - `consul_client_addr` (default `"127.0.0.1"`)
  - `consul_ui` (boolean, default `false`)
  - `consul_log_level` (default `"INFO"`)
  - `consul_retry_join` (list of peer addresses/hostnames, default `[]`)
  - `consul_encrypt` (optional gossip encryption key, default `""`)
  - `consul_extra_config` (optional dictionary of additional top-level Consul agent settings, default `{}`)
- **FR-007**: The role MUST allow operators to define a list of services to advertise on each host via `consul_services` (default `[]`), where each service entry supports:
  - `name` (required string: service name registered in Consul)
  - `id` (optional string: unique service instance ID, defaulting to `name` if omitted)
  - `port` (optional integer: service listening port)
  - `address` (optional string: service-specific IP/address override)
  - `tags` (optional list of strings for routing/filtering)
  - `meta` (optional dictionary of key-value metadata strings)
  - `checks` (optional list of health check definitions supporting `http`, `tcp`, `args`/`script`, `interval`, `timeout`, and `deregister_critical_service_after`)
- **FR-008**: The role MUST render the main agent configuration directly to `{{ consul_config_dir }}/consul.hcl` (overwriting the package default) and render each advertised service definition into `{{ consul_config_dir }}/service-<id>.json`, removing any unmanaged or previously rendered `service-*.json` files when `consul_services_purge` (default `true`) is enabled so removed services are no longer advertised.
- **FR-009**: The role MUST validate the complete Consul configuration directory using `consul validate` before reloading or restarting the Consul systemd service.
- **FR-010**: The role MUST validate and restart the `consul` systemd service when the main agent configuration (`consul.hcl`) changes, and validate and reload the `consul` systemd service when advertised service files (`service-<id>.json`) are added, modified, or removed, while ensuring the `consul` systemd unit is enabled and started.
- **FR-011**: All tasks in the role MUST be strictly idempotent, producing zero changes on a second consecutive run with unchanged variables across all supported distributions.

### Key Entities

- **Consul Node Agent**: Represents the HashiCorp Consul daemon running on a target host. Key attributes include operational mode (`server` or `client`), datacenter identifier, node name, network bind/advertise/client addresses, cluster join list (`retry_join`), bootstrap expectation (for servers), and UI availability.
- **Advertised Service (`consul_services` item)**: Represents a workload service registered on a specific node. Key attributes include service `name`, instance `id`, `port`, `address`, `tags` list, `meta` dictionary, and associated `checks`.
- **Service Health Check**: Represents an automated health probe attached to an advertised service, defined by check type (`tcp`, `http`, or `args`), probe `interval`, `timeout`, and optional critical deregistration timeout.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy either a Consul Server or a Consul Client on any supported distribution (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in a single execution, with the Consul agent service reaching an active/running state and responding to local member queries within 30 seconds.
- **SC-002**: 100% of services defined in `consul_services` on a host are registered and returned by the local Consul agent catalog API (`/v1/agent/services` or `consul catalog services`) immediately after role convergence.
- **SC-003**: Removing a service from `consul_services` and re-running the role removes the service from the local Consul agent catalog on 100% of runs without requiring manual file cleanup.
- **SC-004**: Re-running the role on an already converged host with identical inputs results in 0 changed tasks across all 5 target Linux distributions.
- **SC-005**: Any invalid Consul configuration or unsupported OS/mode input is caught during validation before disrupting an active service.

## Assumptions

- Target hosts are running systemd as their init system on Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) or RedHat-family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL) distributions.
- Target hosts have outbound network access to official HashiCorp package repositories (`apt.releases.hashicorp.com` for Debian/Ubuntu and `rpm.releases.hashicorp.com` for RHEL family) during installation.
- Default operational mode `consul_mode` is set to `"client"` so hosts join as lightweight agents unless explicitly designated as `"server"`, while `consul_bootstrap_expect` defaults to `1` when `"server"` mode is chosen so single-node server deployments and Molecule tests work out of the box without extra boilerplate.
- Configuration files are stored in `/etc/consul.d/` with the main agent configuration rendered directly to `consul.hcl` (overwriting the package-supplied default) and advertised service definitions rendered to `service-<id>.json` (for deterministic serialization of structured Ansible service dictionaries), owned by the `consul` system user/group with restricted permissions (`0640`).
- Firewall management and TLS certificate generation are out of scope for this role and handled by dedicated network/PKI roles if needed, though operators can pass TLS settings via `consul_extra_config`.
