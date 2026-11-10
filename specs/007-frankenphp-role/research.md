# Phase 0 Research: FrankenPHP Application Server Role (`frankenphp`)

**Feature**: `007-frankenphp-role`  
**Date**: 2026-11-09

## 1. Package Repository & Installation Strategy (`static-php` / `php-zts`)

- **Decision**:
  - Install FrankenPHP and its thread-safe PHP runtime (`php-zts`) using the official `static-php` repositories maintained by Marc Henderkes (`pkg.henderkes.com` and `rpm.henderkes.com`) as documented in the official FrankenPHP documentation (`frankenphp.dev/docs/`).
  - Support PHP versions `8.2`, `8.3`, `8.4` (default), and `8.5` via `frankenphp_php_version`.
  - **Debian / Ubuntu (`vars/Debian.yml` & `tasks/setup-Debian.yml`)**:
    - Convert `frankenphp_php_version` (e.g., `"8.4"`) to `frankenphp_php_version_nodot` (`"84"`).
    - Ensure `/etc/apt/keyrings` exists (`mode: '0755'`).
    - Download the repository signing key from `https://pkg.henderkes.com/api/packages/{{ frankenphp_php_version_nodot }}/debian/repository.key` to `/etc/apt/keyrings/static-php{{ frankenphp_php_version_nodot }}.asc` (`mode: '0644'`).
    - Configure `/etc/apt/sources.list.d/static-php{{ frankenphp_php_version_nodot }}.list` with `deb [signed-by=/etc/apt/keyrings/static-php{{ frankenphp_php_version_nodot }}.asc] https://pkg.henderkes.com/api/packages/{{ frankenphp_php_version_nodot }}/debian php-zts main` and update the APT cache when changed.
  - **RedHat / Rocky Linux (`vars/RedHat.yml` & `tasks/setup-RedHat.yml`)**:
    - Install the `static-php` repository RPM (`https://rpm.henderkes.com/static-php-1-1.noarch.rpm`, configurable in `vars/RedHat.yml`).
    - Enable the DNF module stream `php-zts:static-{{ frankenphp_php_version }}` idempotently (checking `dnf module list --enabled php-zts` first so the task only runs and reports `changed` when the desired stream is not yet enabled).
- **Rationale**:
  - Confirmed during clarification (Session 2026-11-09 Q2).
  - Unlike the single static binary, the `.deb` and `.rpm` packages provide dynamic extension loading (`php-zts-*`), standard `/etc/php-zts/conf.d/*.ini` configuration, and an upstream `frankenphp.service` systemd unit with a dedicated `frankenphp` user/group and `/var/lib/frankenphp` data directory.
  - Checking `dnf module list --enabled php-zts` before enabling `php-zts:static-{{ frankenphp_php_version }}` works seamlessly on both Rocky Linux 8 (where `ansible_python_interpreter` is `/usr/bin/python3.9` and native Python `dnf` bindings may only exist for platform-python) and Rocky Linux 9.
- **Alternatives Considered**:
  - *Single static binary from GitHub Releases*: Rejected because additional dynamic PHP extensions cannot be installed via `apt`/`dnf` or `pie-zts`, and systemd/user packaging would have to be maintained from scratch.
  - *Ondřej Surý / Remi repositories*: Rejected because `frankenphp` embeds `libphp-zts` and requires the matching `php-zts` build from `static-php`.

## 2. ZTS PHP Bundled vs. Installable Extensions & CLI Symlink

- **Decision**:
  - Inspecting the upstream `pkg.henderkes.com` and `rpm.henderkes.com` repository metadata shows:
    - `php-zts-cli` **already bundles and `Provides:`/`Conflicts:`** the following core extensions:
      `calendar`, `ctype`, `curl`, `dom`, `exif`, `fileinfo`, `filter`, `iconv`, `libxml`, `mbregex`, `mbstring`, `opcache`, `openssl`, `password-argon2` / ` password_argon2`, `pcntl`, `phar`, `posix`, `readline`, `session`, `simplexml`, `sockets`, `sodium`, `tokenizer`, `xml`, `xmlreader`, `xmlwriter`, `zlib`.
      Attempting to explicitly `apt-get install php-zts-curl` on Debian/Ubuntu when `php-zts-cli` is in the transaction or installed can trigger APT virtual package / conflict resolution warnings because `php-zts-cli` lists `Conflicts: php-zts-curl` alongside `Provides: php-zts-curl (= ...)`.
    - Separate installable extension packages in the repository include:
      `amqp`, `apcu`, `ast`, `bcmath`, `brotli`, `bz2`, `dba`, `decimal`, `ds`, `ffi`, `ftp`, `gd`, `gettext`, `gmp`, `grpc`, `igbinary`, `imagick`, `inotify`, `intl`, `ldap`, `lz4`, `maxminddb`, `memcache`, `memcached`, `mongodb`, `msgpack`, `mysqli`, `mysqlnd`, `odbc`, `opentelemetry`, `parallel`, `pcov`, `pdo`, `pdo-mysql` (Debian) / `pdo_mysql` (RedHat), `pdo-odbc` / `pdo_odbc`, `pdo-pgsql` / `pdo_pgsql`, `pdo-sqlite` / `pdo_sqlite`, `pdo-sqlsrv` / `pdo_sqlsrv`, `pgsql`, `protobuf`, `rdkafka`, `redis`, `shmop`, `simdjson`, `snappy`, `soap`, `sqlite3`, `sqlsrv`, `ssh2`, `swoole`, `sysvmsg`, `sysvsem`, `sysvshm`, `tidy`, `uuid`, `uv`, `xdebug`, `xhprof`, `xlswriter`, `xsl`, `xz`, `yac`, `yaml`, `zip`, `zstd`.
    - Furthermore, on Debian PDO driver packages use hyphens (`php-zts-pdo-mysql`, `php-zts-pdo-pgsql`, `php-zts-pdo-sqlite`), whereas on RedHat RPM filenames use underscores (`php-zts-pdo_mysql`, `php-zts-pdo_pgsql`, `php-zts-pdo_sqlite`), and shorthand `"mysql"` maps cleanly to `mysqlnd`, `mysqli`, and `pdo-mysql`/`pdo_mysql`.
  - Therefore:
    1. Define `frankenphp_bundled_extensions` in `vars/main.yml` (or `vars/<OS>.yml`) containing the extensions built into `php-zts-cli` (`curl`, `mbstring`, `opcache`, `pcntl`, `xml`, `dom`, `fileinfo`, `filter`, `iconv`, `openssl`, `phar`, `posix`, `readline`, `session`, `simplexml`, `sockets`, `sodium`, `tokenizer`, `xmlreader`, `xmlwriter`, `zlib`, `ctype`, `calendar`, `exif`) so that if a user includes any of them in `frankenphp_php_extensions`, the role skips redundant/conflicting package names while still guaranteeing they are present via `php-zts-cli`.
    2. Provide an OS-specific `frankenphp_extension_map` in `vars/Debian.yml` and `vars/RedHat.yml` that maps user-friendly names (e.g., `mysql` -> `['mysqlnd', 'mysqli', 'pdo-mysql']` on Debian and `['mysqlnd', 'mysqli', 'pdo_mysql']` on RedHat; `pdo_mysql` -> `pdo-mysql` on Debian; `sqlite3` -> `['sqlite3', 'pdo-sqlite']` on Debian and `['sqlite3', 'pdo_sqlite']` on RedHat; `pgsql` -> `['pgsql', 'pdo-pgsql']` on Debian and `['pgsql', 'pdo_pgsql']` on RedHat).
    3. Default `frankenphp_php_extensions` in `defaults/main.yml` to common Laravel / Octane extensions:
       `['bcmath', 'gd', 'intl', 'mysql', 'pdo', 'redis', 'sqlite3', 'zip']` (alongside the bundled `curl`, `mbstring`, `opcache`, `pcntl`, `xml` in `php-zts-cli`).
    4. When `frankenphp_manage_php_symlink: true` (default), create `/usr/bin/php -> /usr/bin/php-zts` (`state: link`, `force: false`) so `php` CLI commands (like `php artisan` and `composer`) work out of the box.
- **Rationale**:
  - Prevents APT `Conflicts` failures when users list `curl`, `mbstring`, `xml`, `opcache`, or `pcntl` in `frankenphp_php_extensions` while also normalizing `pdo_mysql` vs `pdo-mysql` across Debian and RedHat.
- **Alternatives Considered**:
  - *Blindly prefixing every item in `frankenphp_php_extensions` with `php-zts-`*: Rejected because `php-zts-cli` declares `Conflicts: php-zts-curl, php-zts-mbstring, ...` in the APT index, which would cause APT to fail if a user passes `curl` or `mbstring` as an extension name.

## 3. Custom Caddyfile & Drop-in Snippet Management (`Caddyfile` & `Caddyfile.d`)

- **Decision**:
  - Store the primary configuration at `frankenphp_caddyfile_path` (default `/etc/frankenphp/Caddyfile`, mode `'0644'`, owned by `root:{{ frankenphp_group }}`).
  - Provide `frankenphp_caddyfile` in `defaults/main.yml` as a multi-line string defaulting to a safe, working configuration that listens on `:80`, enables `frankenphp`, serves `/var/www/html/public` (or `/usr/share/frankenphp`), and imports `/etc/frankenphp/Caddyfile.d/*.caddyfile`.
  - Ensure `/etc/frankenphp/Caddyfile.d` exists (`mode: '0755'`, owned by `root:{{ frankenphp_group }}`).
  - Render each item in `frankenphp_caddyfile_d` (list of `{ name, content }` dicts) to `/etc/frankenphp/Caddyfile.d/{{ item.name }}.caddyfile`.
  - When `frankenphp_caddyfile_d_purge: true` (default), find existing `*.caddyfile` files in `/etc/frankenphp/Caddyfile.d` and remove any file not matching `[item.name ~ '.caddyfile' for item in frankenphp_caddyfile_d]`.
  - Validate the Caddyfile using `/usr/bin/frankenphp validate --config {{ frankenphp_caddyfile_path }}` before reloading or restarting the service.
- **Rationale**:
  - Confirmed during clarification (Session 2026-11-09 Q1).
  - Pre-validating configuration prevents syntax errors in custom Caddyfiles from taking down a running production FrankenPHP daemon.
  - Note on `frankenphp validate` with `import /etc/frankenphp/Caddyfile.d/*.caddyfile`: Drop-in files in `Caddyfile.d/` MUST be rendered (and purged) **before** running `frankenphp validate` on the main `/etc/frankenphp/Caddyfile` so that imported snippets exist when validation runs. Therefore, validation is best performed in the handler chain (`validate and reload frankenphp` / `validate and restart frankenphp`) and as an explicit verification step after both `Caddyfile` and `Caddyfile.d/` tasks complete.

## 4. Dual Daemon Execution Modes (`caddyfile` vs `octane`) & Systemd Drop-in Override

- **Decision**:
  - Support `frankenphp_daemon_mode` with two allowed values (`"caddyfile"` default, or `"octane"`), validated via `ansible.builtin.assert`.
  - The upstream `frankenphp` package installs `/usr/lib/systemd/system/frankenphp.service` with:
    - `Type=notify`
    - `User=frankenphp`, `Group=frankenphp`
    - `WorkingDirectory=/var/lib/frankenphp`
    - `ExecStartPre=/usr/bin/frankenphp validate --config /etc/frankenphp/Caddyfile`
    - `ExecStart=/usr/bin/frankenphp run --environ --config /etc/frankenphp/Caddyfile`
    - `ExecReload=/usr/bin/frankenphp reload --config /etc/frankenphp/Caddyfile --force`
  - Manage `/etc/systemd/system/frankenphp.service.d/override.conf` via template whenever:
    - `frankenphp_daemon_mode == 'octane'`, OR
    - `frankenphp_user != 'frankenphp'` or `frankenphp_group != 'frankenphp'`, OR
    - `frankenphp_caddyfile_path != '/etc/frankenphp/Caddyfile'`, OR
    - `frankenphp_env | length > 0`.
    (Or always render `/etc/systemd/system/frankenphp.service.d/override.conf` deterministically so any transition back to defaults is also idempotent and clean!)
  - Always rendering `/etc/systemd/system/frankenphp.service.d/override.conf` deterministically is cleaner and strictly idempotent:
    - **When `frankenphp_daemon_mode == 'caddyfile'`**:
      - `User={{ frankenphp_user }}`
      - `Group={{ frankenphp_group }}`
      - `WorkingDirectory={{ frankenphp_data_dir }}`
      - Clear and set `ExecStartPre=`, `ExecStart=`, `ExecReload=` using `{{ frankenphp_caddyfile_path }}`
      - Render `Environment="KEY=VALUE"` lines for each entry in `frankenphp_env`.
    - **When `frankenphp_daemon_mode == 'octane'`**:
      - `Type=simple` (since `php artisan octane:frankenphp` is a foreground CLI supervisor wrapper around FrankenPHP rather than sending `sd_notify` directly from the PHP wrapper)
      - `User={{ frankenphp_user }}`
      - `Group={{ frankenphp_group }}`
      - `WorkingDirectory={{ frankenphp_octane_app_dir }}`
      - Clear `ExecStartPre=` (or validate custom Caddyfile if `frankenphp_octane_use_custom_caddyfile` is `true`)
      - Clear `ExecStart=` and set:
        `ExecStart=/usr/bin/php-zts {{ frankenphp_octane_app_dir }}/artisan octane:frankenphp --host={{ frankenphp_octane_host }} --port={{ frankenphp_octane_port }} --admin-port={{ frankenphp_octane_admin_port }} --workers={{ frankenphp_octane_workers }} --max-requests={{ frankenphp_octane_max_requests }}{% if frankenphp_octane_use_custom_caddyfile %} --caddyfile={{ frankenphp_caddyfile_path }}{% endif %}{% for flag in frankenphp_octane_extra_flags %} {{ flag }}{% endfor %}`
      - Clear `ExecReload=` and set:
        `ExecReload=/usr/bin/php-zts {{ frankenphp_octane_app_dir }}/artisan octane:reload --server=frankenphp`
      - Render `Environment="XDG_CONFIG_HOME={{ frankenphp_data_dir }}/config"` and `Environment="XDG_DATA_HOME={{ frankenphp_data_dir }}/data"` plus any user-supplied `frankenphp_env` entries so Caddy state files are always written to `frankenphp_data_dir`.
  - Ensure `{{ frankenphp_data_dir }}` (`/var/lib/frankenphp`) exists with `owner: "{{ frankenphp_user }}"`, `group: "{{ frankenphp_group }}"`, `mode: '0750'`.
- **Rationale**:
  - Confirmed during clarification (Session 2026-11-09 Q3).
  - Always managing `/etc/systemd/system/frankenphp.service.d/override.conf` guarantees deterministic state transitions when switching between `"caddyfile"` and `"octane"` modes or updating `frankenphp_env` / `frankenphp_user`, and avoids modifying the package-owned `/usr/lib/systemd/system/frankenphp.service` file.
- **Alternatives Considered**:
  - *Editing `/usr/lib/systemd/system/frankenphp.service` in place*: Rejected because package upgrades overwrite `/usr/lib/systemd/system/frankenphp.service` and cause configuration drift.

## 5. Multi-Distro Molecule Verification Strategy

- **Decision**:
  - Scaffold the role via `ansible-galaxy role init --init-path roles frankenphp` and `molecule init scenario default` inside `roles/frankenphp/`.
  - Keep the RHEL 8 `python39` bootstrap at the top of `molecule/default/prepare.yml`.
  - In `molecule/default/prepare.yml`, create a sample PHP worker/application directory `/var/www/app/public/index.php` (serving a JSON/text response with `phpversion()`, `php_sapi_name()`, loaded extensions check, and worker request counter) so that `converge.yml` can test a custom `frankenphp_caddyfile` running as a daemon on all 5 supported distros (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`).
  - In `molecule/default/converge.yml`, apply `hifra01.utils.frankenphp` with:
    - `frankenphp_php_version: "8.4"`
    - `frankenphp_php_extensions`: `['bcmath', 'gd', 'intl', 'mysql', 'pdo', 'redis', 'sqlite3', 'zip']`
    - `frankenphp_php_ini`: `{'memory_limit': '256M', 'expose_php': 'Off'}`
    - `frankenphp_env`: `{'APP_ENV': 'production'}`
    - Custom `frankenphp_caddyfile` serving `/var/www/app/public` in worker mode (`worker /var/www/app/public/index.php 2`) on `:8080` and importing `/etc/frankenphp/Caddyfile.d/*.caddyfile`
    - Custom `frankenphp_caddyfile_d` entry defining an additional health check endpoint on `:8081`
  - In `molecule/default/verify.yml`, assert:
    1. `frankenphp` and `php-zts-cli` binaries exist and `/usr/bin/php` symlink points to `/usr/bin/php-zts`.
    2. `php-zts -m` reports all configured extensions (`bcmath`, `gd`, `intl`, `mysqli`, `mysqlnd`, `pdo_mysql`, `redis`, `sqlite3`, `zip`) and `php-zts -i` reflects `memory_limit => 256M`.
    3. `frankenphp validate --config /etc/frankenphp/Caddyfile` succeeds (`rc == 0`).
    4. `frankenphp.service` is active (`running`) and enabled.
    5. HTTP GET to `http://127.0.0.1:8080` returns HTTP 200 with output from the PHP worker script confirming PHP 8.4 ZTS and `APP_ENV=production`.
    6. HTTP GET to `http://127.0.0.1:8081/healthz` (from `Caddyfile.d`) returns HTTP 200.
    7. Idempotence check passes with `changed=0`.
- **Rationale**:
  - Exercises every user story (P1 installation & extensions, P2 custom Caddyfile with worker daemon + `Caddyfile.d`, P3 custom `php.ini` and daemon environment variables) across all 5 target distributions.
