# Feature Specification: FrankenPHP Application Server Role (`frankenphp`)

**Feature Branch**: `007-frankenphp-role`

**Created**: 2026-11-09

**Status**: Draft

**Input**: User description: "create ansible role to install and configure frankenphp along with its php, make user able to define custom caddyfile to run as daemon (such in case of running laravel octane in production). name branch based on convention"

## Clarifications

### Session 2026-11-09

- Q: How should users provide custom Caddyfile configurations to run FrankenPHP as a daemon? (FR-006, FR-007) → A: Single raw string variable (`frankenphp_caddyfile`) for `/etc/frankenphp/Caddyfile` plus an optional drop-in list (`frankenphp_caddyfile_d`, items with `name` and `content`) rendered to `/etc/frankenphp/Caddyfile.d/<name>.caddyfile`.
- Q: How should FrankenPHP and its ZTS PHP runtime be installed across Debian/Ubuntu and RHEL/Rocky Linux? (FR-003, FR-004) → A: Official `static-php` (`pkg.henderkes.com` DEB and `rpm.henderkes.com` RPM) repositories installing `frankenphp`, `php-zts-cli`, and `php-zts-*` extension packages for the target `frankenphp_php_version`.
- Q: How should the role run FrankenPHP as a daemon when serving production workloads such as Laravel Octane? (FR-006, FR-008) → A: Support both modes via a daemon mode switch variable (`frankenphp_daemon_mode`: `"caddyfile"` default running `frankenphp run --environ --config {{ frankenphp_caddyfile_path }}`, or `"octane"` running `php artisan octane:frankenphp` with configurable app directory, host, port, workers, max-requests, and `--caddyfile` option).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install FrankenPHP and PHP Runtime as a Managed Daemon (Priority: P1)

Infrastructure operators and platform engineers need to install FrankenPHP along with its bundled ZTS PHP runtime (`php-zts`), CLI, and required PHP extensions on Linux servers, and run FrankenPHP as a managed systemd background daemon so that modern PHP applications can be served reliably without needing a separate PHP-FPM process pool.

**Why this priority**: Installing the FrankenPHP server, its ZTS PHP runtime and extensions, and ensuring the systemd daemon is enabled and active is the foundational capability required before any custom application or worker configurations can be served.

**Independent Test**: Can be fully tested by applying the `frankenphp` role to a clean Linux host with default settings, verifying that the `frankenphp` and `php-zts` packages and configured extensions are installed, the `frankenphp` systemd service is enabled at boot and actively running, and HTTP requests to the configured default listener receive a valid response.

**Acceptance Scenarios**:

1. **Given** a clean supported Linux host (Debian/Ubuntu or RHEL/Rocky/AlmaLinux), **When** the operator applies the `frankenphp` role with default settings, **Then** the official FrankenPHP/static-php repository for the selected PHP version is configured, `frankenphp`, the ZTS PHP CLI (`php-zts-cli`), and the configured ZTS PHP extensions are installed, a baseline `/etc/frankenphp/Caddyfile` is rendered, and the `frankenphp` systemd service is enabled and started.
2. **Given** an already provisioned host with FrankenPHP running, **When** the operator re-runs the role with unchanged variables, **Then** no packages are reinstalled, configuration files remain unmodified, the `frankenphp` service is not restarted or reloaded, and the playbook run completes with zero changes (idempotent).
3. **Given** a target host where the operator specifies a list of PHP extensions (e.g., `bcmath`, `curl`, `gd`, `intl`, `mbstring`, `mysql`, `opcache`, `pdo`, `redis`, `sqlite3`, `xml`, `zip`) and optional `php.ini` tuning directives, **When** the role is applied, **Then** the corresponding `php-zts-<extension>` packages are installed, custom PHP INI settings are rendered to `/etc/php-zts/conf.d/`, and the PHP runtime inside FrankenPHP loads those extensions and settings.

---

### User Story 2 - Configure a Custom Caddyfile and Daemon Mode for Production Workloads (e.g., Laravel Octane) (Priority: P2)

Platform and DevOps engineers deploying production PHP applications—such as Laravel Octane in FrankenPHP worker mode, Symfony worker mode, or custom multi-site PHP deployments—need to define a custom `Caddyfile` (as raw multi-line configuration or drop-in `.caddyfile` fragments) and choose whether the systemd daemon executes `frankenphp run --config` directly (`frankenphp_daemon_mode: "caddyfile"`) or invokes `php artisan octane:frankenphp` (`frankenphp_daemon_mode: "octane"`, optionally passing `--caddyfile`).

**Why this priority**: Defining a custom `Caddyfile` and supporting both native FrankenPHP daemon mode and Laravel Octane CLI daemon mode in production is an explicit primary requirement from the user.

**Independent Test**: Can be independently tested by supplying a custom `frankenphp_caddyfile` (and testing both `frankenphp_daemon_mode: "caddyfile"` and `frankenphp_daemon_mode: "octane"`), applying the role, and verifying that `frankenphp validate --config /etc/frankenphp/Caddyfile` passes, the daemon reloads or restarts cleanly, and HTTP requests to the custom site/worker endpoint are served by the persistent FrankenPHP worker process.

**Acceptance Scenarios**:

1. **Given** a host where `frankenphp_caddyfile` is set to a custom Caddyfile configuration in `"caddyfile"` daemon mode (for example, configuring `frankenphp` worker threads or `php_server` with `worker /var/www/app/public/frankenphp-worker.php`), **When** the role is applied, **Then** the custom configuration is written to `/etc/frankenphp/Caddyfile`, validated via `frankenphp validate` prior to applying, and the `frankenphp` daemon reloads/restarts to serve requests using the custom Caddyfile.
2. **Given** a host where `frankenphp_daemon_mode` is set to `"octane"` with a target Laravel application directory (`frankenphp_octane_app_dir`) and optional custom `frankenphp_caddyfile`, **When** the role is applied, **Then** the systemd service override configures `frankenphp.service` to run `/usr/bin/php-zts artisan octane:frankenphp` (passing `--caddyfile={{ frankenphp_caddyfile_path }}` when configured along with host/port/workers/max-requests flags) from the application directory as a managed background daemon.
3. **Given** a host where additional per-site or modular Caddyfile snippets are defined in `frankenphp_caddyfile_d` (rendered into `/etc/frankenphp/Caddyfile.d/*.caddyfile`), **When** the role is applied, **Then** each snippet is rendered (and stale unmanaged files are purged when configured), validated, and loaded by the FrankenPHP daemon.
4. **Given** a running FrankenPHP daemon in production, **When** the operator updates `frankenphp_caddyfile` with a syntax error or invalid directive, **Then** the pre-reload validation check (`frankenphp validate`) fails fast and halts the play before restarting or breaking the currently running FrankenPHP daemon.

---

### User Story 3 - Customize Daemon Environment, Service User, and PHP Runtime Settings (Priority: P3)

Infrastructure operators running Laravel Octane or other production PHP apps need to customize the systemd daemon's execution environment—such as running under an application-specific user/group (e.g., `www-data` or `deploy`), injecting environment variables (e.g., `APP_ENV`, `SERVER_NAME`, `FRANKENPHP_CONFIG`), or tuning PHP memory and OPcache limits—so that the daemon has appropriate filesystem access and runtime behavior.

**Why this priority**: In production Laravel Octane and PHP deployments, the web server daemon must match the file ownership of the deployed application directory and often requires environment variables or PHP INI overrides (`memory_limit`, `upload_max_filesize`, `opcache`) without modifying package-owned systemd unit files directly.

**Independent Test**: Can be tested by overriding `frankenphp_user`, `frankenphp_group`, `frankenphp_env`, and `frankenphp_php_ini` settings, applying the role, and verifying that a systemd drop-in override and `/etc/php-zts/conf.d/99-frankenphp-custom.ini` are created, ownership of `/var/lib/frankenphp` matches the configured user/group, and the running daemon process reflects the custom user, environment variables, and PHP configuration values.

**Acceptance Scenarios**:

1. **Given** custom daemon parameters (`frankenphp_user`, `frankenphp_group`, `frankenphp_working_dir`, or `frankenphp_env` key-value pairs), **When** the role is applied, **Then** a systemd drop-in override (`/etc/systemd/system/frankenphp.service.d/override.conf`) and/or environment file is rendered, `/var/lib/frankenphp` ownership is updated accordingly, `systemctl daemon-reload` is executed, and the service runs under the specified identity and environment.
2. **Given** custom PHP runtime directives in `frankenphp_php_ini` (such as `memory_limit = 512M` or `opcache.enable = 1`), **When** the role is applied, **Then** the custom INI file is written to `/etc/php-zts/conf.d/` and the `frankenphp` service is restarted so the embedded ZTS PHP runtime applies the new settings.

---

### Edge Cases

- **Unsupported operating system family**: When executed on an OS family outside `Debian` and `RedHat` (e.g., Alpine or Archlinux), the role fails immediately at the top of `tasks/main.yml` with a clear assertion error message before modifying repositories or packages.
- **Unsupported PHP version format or release**: When a user provides an unsupported `frankenphp_php_version` (outside supported ZTS branches such as `8.2`, `8.3`, `8.4`, `8.5`), the role fails fast during input validation with a clear error message.
- **Invalid custom Caddyfile syntax**: If a user supplies a malformed `frankenphp_caddyfile` or `frankenphp_caddyfile_d` entry, the role validates the configuration (`frankenphp validate --config /etc/frankenphp/Caddyfile`) and fails before reloading or restarting the active service, protecting production uptime.
- **Custom service user permission on Caddy data directory**: When `frankenphp_user` / `frankenphp_group` is changed from the default `frankenphp` user (e.g., to `www-data`), the role ensures `/var/lib/frankenphp` (where Caddy stores certificates and state) and `/etc/frankenphp` have matching ownership/permissions so the daemon does not fail to start with permission denied errors.
- **PHP extension name normalization across OS families**: If a user specifies common extension names (such as `mysql` vs `mysqlnd`, or `pdo_mysql` which is bundled in `pdo`/`mysqlnd` in `php-zts`), the role maps or normalizes extension names cleanly across Debian and RedHat package repositories so users can pass a consistent extension list.
- **Symlink for standard `php` CLI command**: Since the upstream static-php repository installs `/usr/bin/php-zts` (from `php-zts-cli`), operators running `php artisan octane:install` or Composer commands expect `/usr/bin/php` to exist; the role optionally manages a `/usr/bin/php -> /usr/bin/php-zts` symlink (enabled by default when `/usr/bin/php` is not already provided by another package, or controlled via `frankenphp_manage_php_symlink`).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The role MUST validate at the beginning of `tasks/main.yml` that the target host belongs to a supported OS family (`Debian` or `RedHat`) and that required input variables (such as `frankenphp_php_version`, `frankenphp_daemon_mode`, and `frankenphp_caddyfile`) are valid, failing immediately with a descriptive error message otherwise.
- **FR-002**: The role MUST isolate OS-specific repository URLs, prerequisite packages, GPG key paths, and extension package mappings in `vars/Debian.yml` and `vars/RedHat.yml`.
- **FR-003**: The role MUST configure the official FrankenPHP / `static-php` (`php-zts`) package repository for the target OS family and desired PHP version (`frankenphp_php_version`, e.g., `"8.4"` -> `84` on Debian/Ubuntu APT repository `https://pkg.henderkes.com/api/packages/<ver_nodot>/debian` with its GPG key; and `https://rpm.henderkes.com/static-php-1-0.noarch.rpm` with DNF module stream `php-zts:static-<ver>` enabled on RedHat/Rocky Linux).
- **FR-004**: The role MUST install the `frankenphp` package along with its ZTS PHP CLI package (`php-zts-cli`, configurable via `frankenphp_install_php_cli: true`), optional `pie-zts` extension installer (`frankenphp_install_pie: false`), and all ZTS PHP extensions listed in `frankenphp_php_extensions` (`php-zts-<ext>`).
- **FR-005**: The role MUST optionally create a `/usr/bin/php` symlink pointing to `/usr/bin/php-zts` when `frankenphp_manage_php_symlink` is `true` (default `true`), using `force: false` by default so existing non-ZTS `/usr/bin/php` binaries are not overwritten unless explicitly requested, allowing CLI workflows like `php artisan` to work out of the box.
- **FR-006**: The role MUST provide user-tunable, `frankenphp_`-prefixed variables in `defaults/main.yml` with explanatory comments, including at minimum:
  - `frankenphp_php_version` (ZTS PHP major.minor version string, default `"8.4"`, supporting `"8.2"`, `"8.3"`, `"8.4"`, `"8.5"`)
  - `frankenphp_package_state` (package state for `frankenphp` and PHP packages, default `"present"`)
  - `frankenphp_install_php_cli` (boolean to install `php-zts-cli`, default `true`)
  - `frankenphp_manage_php_symlink` (boolean to symlink `/usr/bin/php` to `/usr/bin/php-zts`, default `true`)
  - `frankenphp_install_pie` (boolean to install `pie-zts`, default `false`)
  - `frankenphp_php_extensions` (list of PHP extension short names to install as `php-zts-<ext>`, defaulting to common Laravel/Octane extensions: `bcmath`, `curl`, `gd`, `intl`, `mbstring`, `mysql`, `opcache`, `pcntl`, `pdo`, `redis`, `xml`, `zip` — mapped cleanly to available `php-zts-*` packages)
  - `frankenphp_php_ini` (dictionary of key-value `php.ini` directives rendered to `/etc/php-zts/conf.d/99-frankenphp-custom.ini`, default `{}`)
  - `frankenphp_daemon_mode` (daemon execution mode: `"caddyfile"` to run `frankenphp run --environ --config {{ frankenphp_caddyfile_path }}`, or `"octane"` to run `php-zts artisan octane:frankenphp`, default `"caddyfile"`)
  - `frankenphp_config_dir` (configuration directory path, default `"/etc/frankenphp"`)
  - `frankenphp_caddyfile_path` (main Caddyfile path, default `"/etc/frankenphp/Caddyfile"`)
  - `frankenphp_caddyfile` (multi-line string containing the complete `Caddyfile` content to render to `frankenphp_caddyfile_path`; defaults to a working baseline Caddyfile with global `frankenphp` block, `:80` default listener, and `import /etc/frankenphp/Caddyfile.d/*.caddyfile`, and can be overridden with any custom Caddyfile such as a Laravel Octane worker daemon config)
  - `frankenphp_caddyfile_d` (list of drop-in `.caddyfile` snippet dictionaries, each with `name` and `content`, rendered into `/etc/frankenphp/Caddyfile.d/<name>.caddyfile`, default `[]`)
  - `frankenphp_caddyfile_d_purge` (boolean to remove unmanaged `.caddyfile` files in `/etc/frankenphp/Caddyfile.d/`, default `true`)
  - `frankenphp_octane_app_dir` (path to the Laravel application root directory when `frankenphp_daemon_mode == "octane"`, default `"/var/www/html"`)
  - `frankenphp_octane_host` (bind host for `octane:frankenphp`, default `"127.0.0.1"`)
  - `frankenphp_octane_port` (bind port for `octane:frankenphp`, default `8000`)
  - `frankenphp_octane_admin_port` (Caddy admin port for `octane:frankenphp`, default `2019`)
  - `frankenphp_octane_workers` (worker count for `octane:frankenphp`, default `"auto"`)
  - `frankenphp_octane_max_requests` (max requests per worker before reload in `octane:frankenphp`, default `500`)
  - `frankenphp_octane_use_custom_caddyfile` (boolean to pass `--caddyfile={{ frankenphp_caddyfile_path }}` to `octane:frankenphp`, default `false`)
  - `frankenphp_octane_extra_flags` (list of additional CLI flags for `octane:frankenphp`, default `[]`)
  - `frankenphp_user` (system user running the `frankenphp` daemon, default `"frankenphp"`)
  - `frankenphp_group` (system group running the `frankenphp` daemon, default `"frankenphp"`)
  - `frankenphp_data_dir` (working and state directory for FrankenPHP/Caddy, default `"/var/lib/frankenphp"`)
  - `frankenphp_env` (dictionary of environment variables passed to the `frankenphp` systemd service via systemd drop-in/environment file, default `{}`)
  - `frankenphp_service_enabled` (boolean to enable `frankenphp` systemd service at boot, default `true`)
  - `frankenphp_service_state` (desired `frankenphp` systemd service state, default `"started"`)
- **FR-007**: The role MUST render `frankenphp_caddyfile` to `{{ frankenphp_caddyfile_path }}` and any `frankenphp_caddyfile_d` entries to `{{ frankenphp_config_dir }}/Caddyfile.d/`, and MUST validate the resulting configuration using `frankenphp validate --config {{ frankenphp_caddyfile_path }}` (via task `validate:` or handler chain) when `frankenphp_daemon_mode == "caddyfile"` or `frankenphp_octane_use_custom_caddyfile` is `true` before reloading or restarting the `frankenphp` service.
- **FR-008**: The role MUST support customizing the systemd daemon execution context (when `frankenphp_daemon_mode == "octane"`, or when `frankenphp_user`, `frankenphp_group`, or `frankenphp_env` are customized) via a managed systemd drop-in `/etc/systemd/system/frankenphp.service.d/override.conf`, ensuring `{{ frankenphp_data_dir }}` ownership matches `{{ frankenphp_user }}:{{ frankenphp_group }}` and running `systemctl daemon-reload` when unit overrides change.
- **FR-009**: The role MUST manage the `frankenphp` systemd service lifecycle, triggering a validation and reload (`validate and reload frankenphp`) when only Caddyfile configuration changes, and triggering a validation and full restart (`validate and restart frankenphp`) when packages, PHP INI files, or systemd unit overrides change.
- **FR-010**: All tasks in the role MUST adhere to collection coding conventions (FQCNs, descriptive task names in imperative case, quoted octal file modes, `frankenphp_` variable prefixing, and OS family vars dispatch) and be strictly idempotent across all 5 supported CI matrix distributions.

### Key Entities

- **FrankenPHP Daemon (`frankenphp.service`)**: The Caddy-based modern PHP application server running under systemd supervision with an embedded ZTS PHP runtime. Attributes include listening addresses/ports, worker processes, service user/group, working directory (`/var/lib/frankenphp`), and environment variables.
- **ZTS PHP Runtime (`php-zts`)**: The thread-safe PHP interpreter and extension set (`php-zts-cli`, `php-zts-<ext>`) required by FrankenPHP, configured via `/etc/php-zts/php.ini` and `/etc/php-zts/conf.d/*.ini`.
- **Caddyfile Configuration (`/etc/frankenphp/Caddyfile` & `/etc/frankenphp/Caddyfile.d/*.caddyfile`)**: The declarative configuration defining global FrankenPHP thread/worker settings, virtual hosts, document roots, and persistent worker scripts (such as Laravel Octane's `frankenphp-worker.php`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy FrankenPHP along with its ZTS PHP runtime and extensions across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in a single Ansible run, with `frankenphp.service` reaching an active (running) state within 30 seconds.
- **SC-002**: 100% of user-defined custom `Caddyfile` configurations (including persistent worker mode / Laravel Octane daemon configurations) are validated with `frankenphp validate` before being applied to the running service, and 100% of HTTP requests to the configured PHP/worker endpoint return HTTP 200 with expected PHP execution output.
- **SC-003**: 100% of PHP extensions specified in `frankenphp_php_extensions` and custom directives in `frankenphp_php_ini` are reported as active by both `/usr/bin/php-zts -m` / `php -i` and the running FrankenPHP HTTP runtime.
- **SC-004**: Re-running the role on an already converged host with identical variables produces 0 changed tasks and 0 service reloads or restarts across all 5 supported distributions.
- **SC-005**: Executing the role on an unsupported OS family, with an unsupported PHP version, or with an invalid Caddyfile configuration halts execution with a clear error message before corrupting or stopping an active service.

## Assumptions

- Target hosts run `systemd` as their init and service manager across supported Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) and RedHat-family (Rocky Linux 8, Rocky Linux 9) distributions.
- Target hosts have outbound network access to the official FrankenPHP / `static-php` package repositories (`pkg.henderkes.com` for Debian/Ubuntu `.deb` packages and `rpm.henderkes.com` for RHEL/Rocky `.rpm` packages) documented at `frankenphp.dev/docs/`.
- Installing via the official `.deb` and `.rpm` `php-zts` repositories is used rather than the single static binary so that operators can install standard dynamic ZTS PHP extensions (`php-zts-*`), customize `php.ini` in `/etc/php-zts/conf.d/`, and leverage the upstream systemd service layout.
- For running Laravel Octane in production as a FrankenPHP daemon, the role manages the FrankenPHP daemon and its custom `Caddyfile` (which can either run FrankenPHP's native `worker /path/to/public/frankenphp-worker.php` block directly under `frankenphp.service` or configure a custom Caddyfile passed to the daemon), while deploying the Laravel application source code itself (`git clone`, `composer install`, `php artisan octane:install`) is handled by the user's application deployment workflow or playbook tasks.
- Default HTTP listening in the baseline `Caddyfile` uses `:80` (with automatic HTTPS disabled on bare ports or local testing unless a domain name is configured by the user in `frankenphp_caddyfile`) so that default deployments and container-based Molecule tests start cleanly without requiring public DNS or Let's Encrypt ACME reachability.
