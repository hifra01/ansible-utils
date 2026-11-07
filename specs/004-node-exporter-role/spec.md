# Feature Specification: Prometheus Node Exporter Role (`node_exporter`)

**Feature Branch**: `004-node-exporter-role`

**Created**: 2026-11-07

**Status**: Draft

**Input**: User description: "create ansible role to install node exporter. name the branch based on the speckit convention"

## Clarifications

### Session 2026-11-07

- Q: How should the role obtain and verify the Node Exporter binary during installation? (FR-002) → A: Download official precompiled tarball from GitHub Releases and verify against upstream `sha256sums.txt` (or user-provided checksum override).
- Q: How should collector-specific options be structured in `node_exporter_enabled_collectors` and `node_exporter_extra_flags`? (FR-006) → A: Support both plain strings (e.g., `"systemd"` → `--collector.systemd`) and single-key dictionaries mapping collector names to sub-flag key-value pairs (e.g., `{"filesystem": {"mount-points-exclude": "^/(sys|proc)"}}` → `--collector.filesystem --collector.filesystem.mount-points-exclude=...`).
- Q: How should the role manage the optional TLS and basic authentication web configuration file (`--web.config.file`)? (FR-008) → A: Render `node_exporter_web_config` to `/etc/node_exporter/config.yml` (mode `0640`, owned by `root:{{ node_exporter_system_group }}`) and pass `--web.config.file` when `node_exporter_web_config` is non-empty; remove the file and flag when empty.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy and Run Node Exporter on Target Hosts (Priority: P1)

Infrastructure operators and site reliability engineers need to install Prometheus Node Exporter as a managed background service on Linux hosts across the infrastructure fleet so that host-level hardware and OS metrics (CPU, memory, disk, network, system load) can be gathered continuously.

**Why this priority**: Installing the Node Exporter binary, provisioning a dedicated unprivileged service user, and managing the service lifecycle is the foundational requirement before any host monitoring or metric scraping can occur.

**Independent Test**: Can be fully tested by applying the role to a clean Linux host, verifying that the `node_exporter` binary is installed, the system service is active and enabled at boot, and an HTTP GET request to the metrics endpoint returns HTTP 200 with standard system metrics.

**Acceptance Scenarios**:

1. **Given** a clean supported Linux host (Debian/Ubuntu or RHEL/Rocky/AlmaLinux), **When** the operator applies the role with default settings, **Then** Node Exporter is downloaded, verified, installed, started as an unprivileged system service, enabled on boot, and exposes system metrics over the default port (9100).
2. **Given** an already provisioned host with Node Exporter running, **When** the operator re-runs the role with unchanged variables, **Then** no binaries are re-downloaded, configuration files remain unmodified, the service is not restarted, and the run completes with zero changes (idempotent).
3. **Given** an existing host with an older version of Node Exporter, **When** the operator updates the desired version variable and applies the role, **Then** the new version is downloaded and installed, the service is restarted with minimal interruption, and the metrics endpoint reflects the upgraded version.

---

### User Story 2 - Configure Network Binding and Service Access (Priority: P2)

Infrastructure operators need to configure the network address, port, and security settings on which Node Exporter listens so the metrics endpoint adheres to organizational network policies, multi-homed interfaces, or reverse proxy architectures.

**Why this priority**: Production servers typically bind monitoring services to internal management interfaces, private overlay networks, or non-default ports rather than listening indiscriminately on public interfaces.

**Independent Test**: Can be tested by setting a custom listen address and port, applying the role, and verifying that Node Exporter binds exclusively to the specified socket address and serves metrics on that endpoint.

**Acceptance Scenarios**:

1. **Given** a host configured with a custom bind address and port (e.g., `127.0.0.1:9100` or an internal network IP), **When** the role is applied, **Then** the service starts listening exclusively on that address and port, and rejects or ignores connection attempts on other interfaces.
2. **Given** optional web security configuration (such as TLS certificates or basic authentication) is supplied by the operator, **When** the role is applied, **Then** Node Exporter enforces the specified security controls before serving metric requests.

---

### User Story 3 - Manage Metric Collectors and Custom Textfile Metrics (Priority: P3)

Monitoring engineers need to enable or disable specific kernel/hardware collectors and configure a local textfile collector directory so that custom host scripts (e.g., backup status, batch jobs, RAID controller health) can expose Prometheus metrics alongside core OS statistics.

**Why this priority**: Tuning active collectors prevents metric bloat, optimizes CPU usage, and allows bespoke administrative scripts to push domain-specific node metrics into the Prometheus scrape loop.

**Independent Test**: Can be tested by enabling/disabling designated collectors, defining a textfile collector directory with a sample `.prom` file, and verifying that the scraped metrics endpoint includes the custom textfile metric and reflects the collector configuration.

**Acceptance Scenarios**:

1. **Given** a list of enabled and disabled collectors defined by the operator, **When** the role is applied, **Then** Node Exporter starts with the appropriate command-line flags reflecting the enabled and disabled collectors.
2. **Given** the textfile collector is enabled, **When** the role is applied, **Then** a dedicated directory with appropriate permissions is created and configured as the textfile collector path, and any valid `.prom` metric files within it are exported in subsequent scrapes.

---

### Edge Cases

- **Unsupported operating system family**: When executed on an OS family outside Debian and RedHat (e.g., Alpine or Archlinux without explicit role support), the role fails immediately with a clear, descriptive assertion message before downloading or creating files.
- **Unsupported CPU architecture**: When executed on an unsupported processor architecture (e.g., non-x86_64/arm64), the role fails during pre-flight checks with a clear message indicating the detected architecture is not supported by available binaries.
- **Network interruption during binary download**: If the binary download from the release repository fails or produces an incomplete archive, checksum verification fails, halting execution before replacing any existing binary or corrupting the service.
- **Port conflicts or socket unavailability**: If the configured listening port is already bound by another daemon, the service fails to start; the role surfaces the systemd service failure status clearly.
- **Missing or invalid security configuration**: If TLS or basic auth files are specified but not found on the target host or contain invalid syntax, the pre-start validation halts the task or surfaces a clear error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The role MUST validate that the target host belongs to a supported OS family (`Debian` or `RedHat`) and supported system architecture (`x86_64`/`amd64`, `aarch64`/`arm64`) at the beginning of execution, failing fast with an informative error message on unsupported platforms.
- **FR-002**: The role MUST download the official precompiled Prometheus Node Exporter release tarball (`node_exporter-<version>.linux-<arch>.tar.gz`) from GitHub Releases (or a configurable mirror URL) and verify its SHA256 checksum against the upstream release `sha256sums.txt` (or an explicit `node_exporter_checksum` override) before extraction.
- **FR-003**: The role MUST install the `node_exporter` executable into a configurable system binary directory (defaulting to `/usr/local/bin/node_exporter`) with executable permissions (`0755`) owned by `root:root`.
- **FR-004**: The role MUST create a dedicated unprivileged system user and group (defaulting to `node_exporter:node_exporter`) with a locked password and disabled interactive login shell to execute the daemon securely.
- **FR-005**: The role MUST configure and manage a systemd service unit (`node_exporter.service`) ensuring the daemon is enabled at system startup and maintained in an active running state.
- **FR-006**: The role MUST provide user-tunable, `node_exporter_`-prefixed variables in `defaults/main.yml` for all core configuration options, including at minimum:
  - `node_exporter_version` (Node Exporter release version, e.g., `"1.8.2"`)
  - `node_exporter_checksum` (optional explicit SHA256 checksum string; when empty `""`, automatically fetched from upstream `sha256sums.txt`)
  - `node_exporter_arch_map` (architecture mapping dictionary from `ansible_architecture` to release archive suffix: `x86_64: amd64`, `aarch64: arm64`, `armv7l: armv7`)
  - `node_exporter_download_url` (release archive download URL, defaulting to GitHub Releases)
  - `node_exporter_checksums_url` (upstream `sha256sums.txt` URL, defaulting to GitHub Releases)
  - `node_exporter_bin_dir` (binary installation path, default `"/usr/local/bin"`)
  - `node_exporter_system_user` (service system user, default `"node_exporter"`)
  - `node_exporter_system_group` (service system group, default `"node_exporter"`)
  - `node_exporter_web_listen_address` (listening socket, default `"0.0.0.0:9100"`)
  - `node_exporter_web_telemetry_path` (metrics HTTP endpoint path, default `"/metrics"`)
  - `node_exporter_textfile_dir` (directory for custom textfile metric files, default `"/var/lib/node_exporter/textfile_collector"`; when non-empty, automatically configures the `textfile` collector directory `--collector.textfile.directory`)
  - `node_exporter_enabled_collectors` (list of collectors to explicitly enable, supporting both plain collector name strings like `"systemd"` and single-key dictionaries mapping a collector name to its sub-flag options like `{"filesystem": {"mount-points-exclude": "^/(sys|proc)"}}`, default `[]`)
  - `node_exporter_disabled_collectors` (list of collector name strings to explicitly disable via `--no-collector.<name>`, default `[]`)
  - `node_exporter_extra_flags` (list of raw CLI argument strings passed directly to the daemon, default `[]`)
  - `node_exporter_config_dir` (directory for web configuration file, default `"/etc/node_exporter"`)
  - `node_exporter_web_config` (optional dictionary defining web config, such as `tls_server_config` or `basic_auth_users` settings, default `{}`)
- **FR-007**: The role MUST create and manage the textfile collector directory (`node_exporter_textfile_dir`) with directory permissions (`0755` or configurable) owned by the `node_exporter` user/group so local scripts can safely write `.prom` metric files.
- **FR-008**: When `node_exporter_web_config` is non-empty, the role MUST render `{{ node_exporter_config_dir }}/config.yml` with mode `'0640'` owned by `root:{{ node_exporter_system_group }}` and pass `--web.config.file={{ node_exporter_config_dir }}/config.yml` to the daemon flags; when `node_exporter_web_config` is empty (`{}`), the role MUST ensure `{{ node_exporter_config_dir }}/config.yml` is absent and omit `--web.config.file` from the daemon flags.
- **FR-009**: The role MUST trigger a systemd daemon reload and restart the `node_exporter` service whenever the service unit file, binary, or web configuration file changes.
- **FR-010**: Isolate OS-specific package dependencies (such as `tar`, `curl`, or `bzip2` prerequisites) in `vars/Debian.yml` and `vars/RedHat.yml`.
- **FR-011**: All tasks in the role MUST be strictly idempotent, resulting in zero changed tasks and zero service restarts on a second consecutive run with unchanged variables across all supported distributions.

### Key Entities

- **Node Exporter Daemon**: The standalone Prometheus metrics exporter running on the host as a systemd service. Attributes include binary version, architecture, listening socket, telemetry path, and configured collectors.
- **Service Account**: The dedicated system user and group (`node_exporter`) under which the daemon executes with minimal OS privileges.
- **Collector Set**: The collection of enabled and disabled kernel/subsystem metric probes (e.g., cpu, meminfo, diskstats, textfile) exposed by the daemon.
- **Textfile Metric Store**: A local filesystem directory monitored by the textfile collector for `.prom` metric files emitted by external automation or scripts.
- **Web Security Configuration**: Optional configuration for TLS certificates, private keys, and basic authentication credentials securing HTTP access to the metrics endpoint.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy and start Node Exporter across all supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in a single execution, with the service reporting active (running) and serving metrics on port 9100 within 30 seconds.
- **SC-002**: 100% of HTTP metric scrape requests to the configured listen address and telemetry path return HTTP status 200 and standard Prometheus text-format metrics.
- **SC-003**: 100% of `.prom` metric files placed in the configured textfile collector directory appear in the `/metrics` scrape output on the next request.
- **SC-004**: Executing the role a second time on an already converged host produces 0 changed tasks and zero service restarts across all supported distributions.
- **SC-005**: Deployments on unsupported operating systems or architectures are rejected before any binary download or system modification occurs.

## Assumptions

- Target hosts use `systemd` as their service manager across supported Debian-family (Debian 12, Ubuntu 22.04, 24.04) and RedHat-family (Rocky Linux 8, 9) distributions.
- Target hosts have network access (direct or through an outbound proxy) to download official release archives from GitHub (`github.com/prometheus/node_exporter/releases/download/...`), or an internal mirror override variable is provided.
- Node Exporter executes as a dedicated unprivileged user (`node_exporter`) rather than `root` to comply with standard security and least-privilege principles.
- Default metric listening socket is `0.0.0.0:9100` with the standard `/metrics` endpoint path.
- Firewall port opening (e.g., `ufw` or `firewalld`) and Prometheus server scrape job configurations are external responsibilities and out of scope for this role.
