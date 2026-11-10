# Role Interface Contract: `hifra01.utils.frankenphp`

**Feature**: `007-frankenphp-role`  
**Date**: 2026-11-09

## 1. Public Role Variables (`roles/frankenphp/defaults/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# defaults file for frankenphp

# Target ZTS PHP version branch ("8.2", "8.3", "8.4", or "8.5")
frankenphp_php_version: "8.4"

# Package state ("present" or "latest")
frankenphp_package_state: present

# Install the ZTS PHP CLI binary (/usr/bin/php-zts)
frankenphp_install_php_cli: true

# Create /usr/bin/php -> /usr/bin/php-zts symlink if /usr/bin/php does not exist
frankenphp_manage_php_symlink: true

# Install pie-zts (PHP Installer for Extensions)
frankenphp_install_pie: false

# List of PHP extensions to ensure are installed for php-zts.
# Core extensions bundled in php-zts-cli (curl, mbstring, opcache, pcntl, xml)
# are automatically satisfied; additional extensions are installed as php-zts-<ext>.
frankenphp_php_extensions:
  - bcmath
  - curl
  - gd
  - intl
  - mbstring
  - mysql
  - opcache
  - pcntl
  - pdo
  - redis
  - sqlite3
  - xml
  - zip

# Custom php.ini directives rendered to /etc/php-zts/conf.d/99-frankenphp-custom.ini
frankenphp_php_ini: {}

# Daemon execution mode:
# - "caddyfile": runs `frankenphp run --environ --config <frankenphp_caddyfile_path>`
# - "octane": runs `/usr/bin/php-zts <frankenphp_octane_app_dir>/artisan octane:frankenphp ...`
frankenphp_daemon_mode: "caddyfile"

# FrankenPHP configuration paths
frankenphp_config_dir: "/etc/frankenphp"
frankenphp_caddyfile_path: "/etc/frankenphp/Caddyfile"

# Main Caddyfile configuration content (supports classic php_server or worker mode such as Laravel Octane)
frankenphp_caddyfile: |
  {
  	frankenphp
  }

  :80 {
  	root * /usr/share/frankenphp
  	encode zstd br gzip
  	php_server
  }

  import /etc/frankenphp/Caddyfile.d/*.caddyfile

# Additional modular Caddyfile snippets rendered to /etc/frankenphp/Caddyfile.d/<name>.caddyfile
# Example:
# frankenphp_caddyfile_d:
#   - name: octane-app
#     content: |
#       app.example.com {
#           root * /var/www/app/public
#           encode zstd br gzip
#           php_server {
#               worker /var/www/app/public/frankenphp-worker.php
#           }
#       }
frankenphp_caddyfile_d: []

# Purge unmanaged *.caddyfile files in /etc/frankenphp/Caddyfile.d/
frankenphp_caddyfile_d_purge: true

# Laravel Octane CLI daemon settings (used when frankenphp_daemon_mode == "octane")
frankenphp_octane_app_dir: "/var/www/html"
frankenphp_octane_host: "127.0.0.1"
frankenphp_octane_port: 8000
frankenphp_octane_admin_port: 2019
frankenphp_octane_workers: "auto"
frankenphp_octane_max_requests: 500
frankenphp_octane_use_custom_caddyfile: false
frankenphp_octane_extra_flags: []

# Systemd daemon identity, data directory, and environment variables
frankenphp_user: "frankenphp"
frankenphp_group: "frankenphp"
frankenphp_data_dir: "/var/lib/frankenphp"
frankenphp_env: {}

# Systemd service state
frankenphp_service_enabled: true
frankenphp_service_state: started
```

## 2. OS-Specific Variables (`roles/frankenphp/vars/<ansible_os_family>.yml`)

### `roles/frankenphp/vars/Debian.yml`

```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for frankenphp (Debian family)

frankenphp_pre_packages:
  - ca-certificates
  - curl
  - gnupg

frankenphp_php_version_nodot: "{{ frankenphp_php_version | replace('.', '') }}"

frankenphp_apt_key_url: "https://pkg.henderkes.com/api/packages/{{ frankenphp_php_version_nodot }}/debian/repository.key"
frankenphp_apt_key_path: "/etc/apt/keyrings/static-php{{ frankenphp_php_version_nodot }}.asc"
frankenphp_apt_repo: >-
  deb [signed-by=/etc/apt/keyrings/static-php{{ frankenphp_php_version_nodot }}.asc]
  https://pkg.henderkes.com/api/packages/{{ frankenphp_php_version_nodot }}/debian php-zts main
frankenphp_apt_repo_filename: "static-php{{ frankenphp_php_version_nodot }}"

frankenphp_service_name: frankenphp
frankenphp_php_ini_dir: /etc/php-zts/conf.d

frankenphp_bundled_extensions:
  - calendar
  - ctype
  - curl
  - dom
  - exif
  - fileinfo
  - filter
  - iconv
  - libxml
  - mbregex
  - mbstring
  - opcache
  - openssl
  - password-argon2
  - password_argon2
  - pcntl
  - phar
  - posix
  - readline
  - session
  - simplexml
  - sockets
  - sodium
  - tokenizer
  - xml
  - xmlreader
  - xmlwriter
  - zlib

frankenphp_extension_map:
  mysql:
    - mysqlnd
    - mysqli
    - pdo-mysql
  pdo_mysql:
    - pdo-mysql
  sqlite3:
    - sqlite3
    - pdo-sqlite
  pdo_sqlite:
    - pdo-sqlite
  pgsql:
    - pgsql
    - pdo-pgsql
  pdo_pgsql:
    - pdo-pgsql
  odbc:
    - odbc
    - pdo-odbc
  pdo_odbc:
    - pdo-odbc
  sqlsrv:
    - sqlsrv
    - pdo-sqlsrv
  pdo_sqlsrv:
    - pdo-sqlsrv
```

### `roles/frankenphp/vars/RedHat.yml`

```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for frankenphp (RedHat family)

frankenphp_pre_packages:
  - ca-certificates
  - curl

frankenphp_rpm_repo_url: "https://rpm.henderkes.com/static-php-1-1.noarch.rpm"
frankenphp_dnf_module_stream: "php-zts:static-{{ frankenphp_php_version }}"

frankenphp_service_name: frankenphp
frankenphp_php_ini_dir: /etc/php-zts/conf.d

frankenphp_bundled_extensions:
  - calendar
  - ctype
  - curl
  - dom
  - exif
  - fileinfo
  - filter
  - iconv
  - libxml
  - mbregex
  - mbstring
  - opcache
  - openssl
  - password-argon2
  - password_argon2
  - pcntl
  - phar
  - posix
  - readline
  - session
  - simplexml
  - sockets
  - sodium
  - tokenizer
  - xml
  - xmlreader
  - xmlwriter
  - zlib

frankenphp_extension_map:
  mysql:
    - mysqlnd
    - mysqli
    - pdo_mysql
  pdo-mysql:
    - pdo_mysql
  sqlite3:
    - sqlite3
    - pdo_sqlite
  pdo-sqlite:
    - pdo_sqlite
  pgsql:
    - pgsql
    - pdo_pgsql
  pdo-pgsql:
    - pdo_pgsql
  odbc:
    - odbc
    - pdo_odbc
  pdo-odbc:
    - pdo_odbc
  sqlsrv:
    - sqlsrv
    - pdo_sqlsrv
  pdo-sqlsrv:
    - pdo_sqlsrv
```

## 3. Handlers Contract (`roles/frankenphp/handlers/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# handlers file for frankenphp

- name: Reload systemd daemon
  ansible.builtin.systemd_service:
    daemon_reload: true
  listen:
    - "reload systemd and restart frankenphp"

- name: Validate frankenphp config for reload
  ansible.builtin.command:
    cmd: "/usr/bin/frankenphp validate --config {{ frankenphp_caddyfile_path }}"
  changed_when: false
  when: frankenphp_daemon_mode == 'caddyfile' or (frankenphp_octane_use_custom_caddyfile | bool)
  listen: "validate and reload frankenphp"

- name: Reload frankenphp
  ansible.builtin.service:
    name: "{{ frankenphp_service_name }}"
    state: reloaded
  when: frankenphp_service_state == 'started'
  listen: "validate and reload frankenphp"

- name: Validate frankenphp config for restart
  ansible.builtin.command:
    cmd: "/usr/bin/frankenphp validate --config {{ frankenphp_caddyfile_path }}"
  changed_when: false
  when: frankenphp_daemon_mode == 'caddyfile' or (frankenphp_octane_use_custom_caddyfile | bool)
  listen:
    - "validate and restart frankenphp"
    - "reload systemd and restart frankenphp"

- name: Restart frankenphp
  ansible.builtin.service:
    name: "{{ frankenphp_service_name }}"
    state: restarted
  when: frankenphp_service_state == 'started'
  listen:
    - "validate and restart frankenphp"
    - "reload systemd and restart frankenphp"
```
