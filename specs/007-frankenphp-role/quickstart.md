# Quickstart & Validation Guide: `hifra01.utils.frankenphp`

**Feature**: `007-frankenphp-role`  
**Date**: 2026-11-09

## Prerequisites

- Python virtual environment with collection test dependencies installed:
  ```bash
  source .venv/bin/activate
  pip install -r requirements.txt
  ```
- Running Docker daemon (for Molecule multi-distro container verification).

---

## Scenario 1: Static Analysis & Linting

From the repository root, run `yamllint` and `ansible-lint`:

```bash
yamllint .
ansible-lint
```

**Expected Outcome**: Both linters exit `0` with zero warnings or errors.

---

## Scenario 2: Single-Distro Molecule Verification

Test the `frankenphp` role on Ubuntu 24.04:

```bash
./test-matrix.sh -r frankenphp -o ubuntu2404
```

Or run Molecule steps interactively from inside `roles/frankenphp`:

```bash
cd roles/frankenphp
molecule converge
molecule verify
molecule idempotence
molecule destroy
```

**Expected Outcome**:
- `prepare`: Bootstraps Python 3.9 on RHEL/Rocky 8 if applicable, and creates a sample PHP worker application in `/var/www/app/public/index.php`.
- `converge`: Configures the `static-php` (`php-zts`) repository, installs `frankenphp`, `php-zts-cli`, and configured `php-zts-*` extensions, creates the `/usr/bin/php` symlink, renders `/etc/php-zts/conf.d/99-frankenphp-custom.ini`, `/etc/systemd/system/frankenphp.service.d/override.conf`, `/etc/frankenphp/Caddyfile`, and `/etc/frankenphp/Caddyfile.d/*.caddyfile`, validates the Caddyfile, and starts/enables `frankenphp.service`.
- `verify`:
  1. Verifies `frankenphp` and `php-zts` binaries and `/usr/bin/php` symlink exist.
  2. Verifies configured PHP extensions (`bcmath`, `gd`, `intl`, `mysqli`, `mysqlnd`, `pdo_mysql`, `redis`, `sqlite3`, `zip`) and custom `php.ini` settings (`memory_limit = 256M`) are loaded.
  3. Verifies `frankenphp validate --config /etc/frankenphp/Caddyfile` passes.
  4. Verifies `frankenphp.service` is active (`running`) and enabled at boot.
  5. Verifies HTTP GET requests to the custom worker-mode Caddyfile endpoint (`http://127.0.0.1:8080`) and drop-in snippet (`http://127.0.0.1:8081/healthz`) return HTTP 200 with expected PHP runtime output.
- `idempotence`: Re-running `converge` produces `changed=0` and 0 service reloads/restarts.

---

## Scenario 3: Full 5-Distro CI Matrix Verification

Execute Molecule tests across all five supported distributions in parallel using the repository's matrix runner:

```bash
./test-matrix.sh -r frankenphp
```

**Expected Outcome**: All 5 distributions (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) pass with zero failures.

---

## Example Playbook Usage

### 1. Default FrankenPHP Server with PHP 8.4

```yaml
---
- name: Deploy FrankenPHP with default configuration
  hosts: web_servers
  become: true
  roles:
    - role: hifra01.utils.frankenphp
```

### 2. Laravel Octane in Production (Custom Caddyfile Worker Daemon Mode)

```yaml
---
- name: Deploy FrankenPHP running Laravel Octane worker via custom Caddyfile
  hosts: app_servers
  become: true
  roles:
    - role: hifra01.utils.frankenphp
      vars:
        frankenphp_php_version: "8.4"
        frankenphp_user: "www-data"
        frankenphp_group: "www-data"
        frankenphp_php_ini:
          memory_limit: "512M"
          upload_max_filesize: "64M"
          post_max_size: "64M"
          opcache.enable: 1
        frankenphp_env:
          APP_ENV: "production"
        frankenphp_caddyfile: |
          {
              frankenphp {
                  num_threads 4
                  max_requests 500
              }
          }

          app.example.com {
              root * /var/www/laravel/public
              encode zstd br gzip

              php_server {
                  try_files {path} index.php
                  worker {
                      file /var/www/laravel/public/frankenphp-worker.php
                      num 4
                      env APP_BASE_PATH /var/www/laravel
                      env APP_PUBLIC_PATH /var/www/laravel/public
                  }
              }
          }
```

### 3. Laravel Octane in Production (`artisan octane:frankenphp` Daemon Mode with Custom Caddyfile)

```yaml
---
- name: Deploy FrankenPHP daemon via php artisan octane:frankenphp
  hosts: octane_servers
  become: true
  roles:
    - role: hifra01.utils.frankenphp
      vars:
        frankenphp_php_version: "8.4"
        frankenphp_daemon_mode: "octane"
        frankenphp_user: "www-data"
        frankenphp_group: "www-data"
        frankenphp_octane_app_dir: "/var/www/laravel"
        frankenphp_octane_host: "0.0.0.0"
        frankenphp_octane_port: 8000
        frankenphp_octane_workers: 4
        frankenphp_octane_max_requests: 500
        frankenphp_octane_use_custom_caddyfile: true
        frankenphp_caddyfile_path: "/etc/frankenphp/Caddyfile"
        frankenphp_caddyfile: |
          {
              frankenphp
              admin localhost:2019
          }

          :8000 {
              root * /var/www/laravel/public
              encode zstd br gzip
              php_server {
                  worker /var/www/laravel/public/frankenphp-worker.php 4
              }
          }
```
