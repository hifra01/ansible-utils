FrankenPHP Role
===============

This role installs and configures FrankenPHP along with its embedded thread-safe PHP runtime (`php-zts`), CLI binary (`php-zts-cli`), and configurable extensions (`php-zts-*`) across Debian-family and RedHat-family Linux distributions using the official `static-php` repositories.

It supports rendering custom Caddyfiles, modular `Caddyfile.d` snippets with purge management, dual daemon modes (native Caddyfile or Laravel Octane CLI supervisor), systemd service drop-in overrides, custom `php.ini` directives, and syntax pre-validation before service reload or restart.

Supported Platforms
-------------------

This role is compatible with:
* **Debian / Ubuntu**: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Debian 12 (Bookworm)
* **RedHat / Rocky Linux**: Rocky Linux 8, Rocky Linux 9, AlmaLinux 8/9, RHEL 8/9

Requirements
------------

* Ansible Core >= 2.21.0
* Target system with `systemd` init and root/sudo privileges (`become: true`)
* `gather_facts: true` (relies on `ansible_os_family` and distribution details)

Role Variables
--------------

### Core Runtime & Versioning

| Variable | Type | Default | Description |
|---|---|---|---|
| `frankenphp_php_version` | String | `"8.4"` | Target PHP ZTS branch (`"8.2"`, `"8.3"`, `"8.4"`, or `"8.5"`). |
| `frankenphp_package_state` | String | `"present"` | Package installation state (`"present"` or `"latest"`). |
| `frankenphp_install_php_cli` | Boolean | `true` | Install the `/usr/bin/php-zts` CLI binary package (`php-zts-cli`). |
| `frankenphp_manage_php_symlink` | Boolean | `true` | Create `/usr/bin/php -> /usr/bin/php-zts` symlink if `/usr/bin/php` does not exist. |
| `frankenphp_install_pie` | Boolean | `false` | Install `pie-zts` (PHP Installer for Extensions). |
| `frankenphp_php_extensions` | List | `[bcmath, curl, gd, intl, mbstring, mysql, opcache, pcntl, pdo, redis, sqlite3, xml, zip]` | List of PHP extensions to ensure are installed for `php-zts`. Core extensions bundled in `php-zts-cli` are automatically resolved. |
| `frankenphp_php_ini` | Dictionary | `{}` | Key-value dictionary of custom directives rendered to `/etc/php-zts/conf.d/99-frankenphp-custom.ini`. |

### Daemon Execution Mode

| Variable | Type | Default | Description |
|---|---|---|---|
| `frankenphp_daemon_mode` | String | `"caddyfile"` | Execution mode: `"caddyfile"` (runs `frankenphp run --environ --config <caddyfile>`) or `"octane"` (runs `php-zts artisan octane:frankenphp`). |

### Caddyfile Configuration

| Variable | Type | Default | Description |
|---|---|---|---|
| `frankenphp_config_dir` | String | `"/etc/frankenphp"` | Directory where FrankenPHP configuration files reside. |
| `frankenphp_caddyfile_path` | String | `"/etc/frankenphp/Caddyfile"` | Primary Caddyfile configuration destination path. |
| `frankenphp_caddyfile` | String | Multi-line string | Raw Caddyfile content rendered to `frankenphp_caddyfile_path`. |
| `frankenphp_caddyfile_d` | List of dicts | `[]` | Modular configuration snippets rendered to `/etc/frankenphp/Caddyfile.d/<name>.caddyfile`. Items must have `name` and `content`. |
| `frankenphp_caddyfile_d_purge` | Boolean | `true` | Purge unmanaged `*.caddyfile` files from `/etc/frankenphp/Caddyfile.d/`. |

### Laravel Octane CLI Settings (`frankenphp_daemon_mode: "octane"`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `frankenphp_octane_app_dir` | String | `"/var/www/html"` | Application directory containing the Laravel `artisan` script. |
| `frankenphp_octane_host` | String | `"127.0.0.1"` | Host/IP address for Octane worker binding. |
| `frankenphp_octane_port` | Integer | `8000` | Port for Octane HTTP server. |
| `frankenphp_octane_admin_port` | Integer | `2019` | Admin port for Caddy management. |
| `frankenphp_octane_workers` | String / Integer | `"auto"` | Number of worker processes to spawn. |
| `frankenphp_octane_max_requests` | Integer | `500` | Maximum requests a worker handles before restarting. |
| `frankenphp_octane_use_custom_caddyfile` | Boolean | `false` | Append `--caddyfile=<path>` to the `octane:frankenphp` command. |
| `frankenphp_octane_extra_flags` | List | `[]` | Additional CLI flags passed to `octane:frankenphp`. |

### Systemd Service & Process Environment

| Variable | Type | Default | Description |
|---|---|---|---|
| `frankenphp_user` | String | `"frankenphp"` | User account owning the daemon process. |
| `frankenphp_group` | String | `"frankenphp"` | Group owning the daemon process. |
| `frankenphp_data_dir` | String | `"/var/lib/frankenphp"` | Data directory for FrankenPHP and Caddy storage (`mode: '0750'`). |
| `frankenphp_env` | Dictionary | `{}` | Environment variables injected into the systemd service via `Environment="KEY=VAL"`. |
| `frankenphp_service_enabled` | Boolean | `true` | Whether the systemd service is enabled on boot. |
| `frankenphp_service_state` | String | `"started"` | Desired state of `frankenphp.service` (`"started"`, `"stopped"`). |

Example Playbooks
-----------------

### Example 1: Default Baseline Installation

```yaml
- hosts: webservers
  become: true
  roles:
    - role: hifra01.utils.frankenphp
```

### Example 2: Custom Caddyfile with Laravel Octane Worker Mode

```yaml
- hosts: webservers
  become: true
  roles:
    - role: hifra01.utils.frankenphp
      vars:
        frankenphp_php_version: "8.4"
        frankenphp_php_ini:
          memory_limit: 512M
          upload_max_filesize: 64M
          post_max_size: 64M
        frankenphp_env:
          APP_ENV: production
        frankenphp_caddyfile: |
          {
          	frankenphp
          }

          app.example.com {
          	root * /var/www/app/public
          	encode zstd br gzip
          	php_server {
          		worker /var/www/app/public/frankenphp-worker.php 4
          	}
          }

          import /etc/frankenphp/Caddyfile.d/*.caddyfile
        frankenphp_caddyfile_d:
          - name: metrics
            content: |
              :2020 {
              	metrics
              }
```

### Example 3: Laravel Octane Daemon Mode via Artisan Supervisor

```yaml
- hosts: webservers
  become: true
  roles:
    - role: hifra01.utils.frankenphp
      vars:
        frankenphp_php_version: "8.4"
        frankenphp_daemon_mode: "octane"
        frankenphp_octane_app_dir: "/var/www/my-laravel-app"
        frankenphp_octane_host: "0.0.0.0"
        frankenphp_octane_port: 8000
        frankenphp_octane_workers: 4
        frankenphp_octane_max_requests: 1000
        frankenphp_user: "www-data"
        frankenphp_group: "www-data"
        frankenphp_env:
          APP_ENV: production
          DB_CONNECTION: mysql
```

License
-------

MIT-0
