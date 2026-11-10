---
description: "Task list for FrankenPHP Application Server Role (frankenphp) implementation"
---

# Tasks: FrankenPHP Application Server Role (`frankenphp`)

**Input**: Design documents from `/specs/007-frankenphp-role/`

**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule container verification (`molecule test` across all 5 CI matrix images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Ansible role**: `roles/frankenphp/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)
- **CI workflow**: `.github/workflows/ci.yml`
- **Repository documentation**: `AGENTS.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the role and Molecule scenario using official CLI tools per Constitution Principle II

- [X] T001 Scaffold the `frankenphp` role skeleton using `ansible-galaxy role init --init-path roles frankenphp` to create `roles/frankenphp/`
- [X] T002 Remove the unused generated `roles/frankenphp/files/` directory and initialize the default Molecule scenario using `molecule init scenario default` inside `roles/frankenphp/`
- [X] T003 Remove any generated `roles/frankenphp/molecule/default/create.yml` or `roles/frankenphp/molecule/default/destroy.yml` and configure the Docker systemd driver in `roles/frankenphp/molecule/default/molecule.yml` using `roles/datetime/molecule/default/molecule.yml` as baseline
- [X] T004 [P] Create `roles/frankenphp/molecule/default/prepare.yml` with the RHEL 8 `python39` bootstrap tasks and create a sample PHP worker application fixture in `/var/www/app/public/index.php`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core metadata, OS variables, user-tunable defaults, and service handlers that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Populate Galaxy metadata (`author: "Hilman F. Rakhmad"`, `description`, `license: "MIT"`, `min_ansible_version: "2.21.0"`, `platforms` for Debian/Ubuntu/EL 8-9, and `galaxy_tags`) in `roles/frankenphp/meta/main.yml`
- [X] T006 [P] Define Debian-family variables (`frankenphp_pre_packages`, `frankenphp_php_version_nodot`, `frankenphp_apt_key_url`, `frankenphp_apt_key_path`, `frankenphp_apt_repo`, `frankenphp_apt_repo_filename`, `frankenphp_service_name`, `frankenphp_php_ini_dir`, `frankenphp_bundled_extensions`, and `frankenphp_extension_map`) in `roles/frankenphp/vars/Debian.yml`
- [X] T007 [P] Define RedHat-family variables (`frankenphp_pre_packages`, `frankenphp_rpm_repo_url`, `frankenphp_dnf_module_stream`, `frankenphp_service_name`, `frankenphp_php_ini_dir`, `frankenphp_bundled_extensions`, and `frankenphp_extension_map`) in `roles/frankenphp/vars/RedHat.yml`
- [X] T008 Define all `frankenphp_*` user-tunable default variables in `roles/frankenphp/defaults/main.yml` adhering to `data-model.md` constraints: `frankenphp_php_version: "8.4"`, `frankenphp_package_state: "present"`, `frankenphp_install_php_cli: true`, `frankenphp_manage_php_symlink: true`, `frankenphp_install_pie: false`, `frankenphp_php_extensions`, `frankenphp_php_ini: {}`, `frankenphp_daemon_mode: "caddyfile"`, `frankenphp_config_dir: "/etc/frankenphp"`, `frankenphp_caddyfile_path: "/etc/frankenphp/Caddyfile"`, `frankenphp_caddyfile`, `frankenphp_caddyfile_d: []`, `frankenphp_caddyfile_d_purge: true`, `frankenphp_octane_app_dir: "/var/www/html"`, `frankenphp_octane_host: "127.0.0.1"`, `frankenphp_octane_port: 8000`, `frankenphp_octane_admin_port: 2019`, `frankenphp_octane_workers: "auto"`, `frankenphp_octane_max_requests: 500`, `frankenphp_octane_use_custom_caddyfile: false`, `frankenphp_octane_extra_flags: []`, `frankenphp_user: "frankenphp"`, `frankenphp_group: "frankenphp"`, `frankenphp_data_dir: "/var/lib/frankenphp"`, `frankenphp_env: {}`, `frankenphp_service_enabled: true`, and `frankenphp_service_state: "started"`
- [X] T009 [P] Implement validation-guarded service reload and restart handlers (`reload systemd and restart frankenphp`, `validate and reload frankenphp`, `validate and restart frankenphp`) in `roles/frankenphp/handlers/main.yml`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Install FrankenPHP and PHP Runtime as a Managed Daemon (Priority: P1) 🎯 MVP

**Goal**: Configure the official `static-php` repository, install `frankenphp`, `php-zts-cli`, and configured `php-zts-*` extension packages across Debian and RedHat distributions, create `/usr/bin/php -> /usr/bin/php-zts` symlink, render baseline `Caddyfile`, and manage `frankenphp.service` lifecycle idempotently.

**Independent Test**: Apply the role to a clean Linux host with default settings, verify `frankenphp` and `php-zts-cli` packages are installed, verify `/usr/bin/php` symlink exists, verify `frankenphp.service` is active and enabled, confirm HTTP requests to port 80 return a valid response, and verify a second run produces `changed=0`.

### Implementation for User Story 1

- [X] T010 [P] [US1] Implement Debian repository setup in `roles/frankenphp/tasks/setup-Debian.yml` (install `frankenphp_pre_packages`, ensure `/etc/apt/keyrings` exists, download repository signing key to `{{ frankenphp_apt_key_path }}`, configure `{{ frankenphp_apt_repo }}` in `/etc/apt/sources.list.d/`, and update APT cache)
- [X] T011 [P] [US1] Implement RedHat repository setup in `roles/frankenphp/tasks/setup-RedHat.yml` (install `frankenphp_pre_packages`, install static-php RPM repo from `{{ frankenphp_rpm_repo_url }}`, check active stream via `dnf module list --enabled php-zts`, and enable `{{ frankenphp_dnf_module_stream }}` idempotently)
- [X] T012 [US1] Implement package installation tasks in `roles/frankenphp/tasks/install.yml` to filter out extensions bundled in `php-zts-cli`, resolve mapped extension package names, install `frankenphp`, `php-zts-cli`, and extension packages (and optional `pie-zts`), and manage `/usr/bin/php -> /usr/bin/php-zts` symlink
- [X] T013 [P] [US1] Create the primary baseline Caddyfile template in `roles/frankenphp/templates/Caddyfile.j2` to render `{{ frankenphp_caddyfile }}` to `{{ frankenphp_caddyfile_path }}` with permissions `'0644'` owned by `root:{{ frankenphp_group }}`
- [X] T014 [US1] Implement main task orchestration in `roles/frankenphp/tasks/main.yml` with platform assertions (`ansible_os_family in ['Debian', 'RedHat']`), input validation assertions (`frankenphp_php_version in ['8.2', '8.3', '8.4', '8.5']`, `frankenphp_daemon_mode in ['caddyfile', 'octane']`), OS variable inclusion, and inclusion of `setup-{{ ansible_os_family }}.yml`, `install.yml`, and `configure.yml`
- [X] T015 [US1] Configure baseline `roles/frankenphp/molecule/default/converge.yml` and `roles/frankenphp/molecule/default/verify.yml` to converge `hifra01.utils.frankenphp` and assert binary installation, `/usr/bin/php` symlink, active `frankenphp.service`, and HTTP response on `:80`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Configure a Custom Caddyfile and Daemon Mode for Production Workloads (e.g., Laravel Octane) (Priority: P2)

**Goal**: Allow operators to supply a custom `Caddyfile` (including persistent worker mode for Laravel Octane), configure modular drop-in `.caddyfile` snippets in `Caddyfile.d/` with purge support, and switch `frankenphp_daemon_mode` between `"caddyfile"` and `"octane"` via a managed systemd drop-in override with pre-validation.

**Independent Test**: Supply a custom `frankenphp_caddyfile` with worker mode on port 8080 and a drop-in health endpoint snippet in `frankenphp_caddyfile_d` on port 8081, apply the role, verify `frankenphp validate --config /etc/frankenphp/Caddyfile` succeeds, verify `frankenphp.service` reloads/restarts cleanly, and verify HTTP GET requests to port 8080 and port 8081 return expected responses.

### Implementation for User Story 2

- [X] T016 [P] [US2] Create drop-in Caddyfile template in `roles/frankenphp/templates/caddyfile-d.j2` to render modular configuration snippets to `/etc/frankenphp/Caddyfile.d/<name>.caddyfile` with permissions `'0644'` owned by `root:{{ frankenphp_group }}`
- [X] T017 [P] [US2] Create systemd service drop-in override template in `roles/frankenphp/templates/override.conf.j2` supporting `"caddyfile"` daemon mode (`frankenphp run --environ --config ...`) and `"octane"` daemon mode (`php-zts artisan octane:frankenphp` with `--host`, `--port`, `--admin-port`, `--workers`, `--max-requests`, and optional `--caddyfile`)
- [X] T018 [US2] Implement configuration and Caddyfile management in `roles/frankenphp/tasks/configure.yml` to create `{{ frankenphp_config_dir }}/Caddyfile.d`, render `{{ frankenphp_caddyfile_path }}`, render `Caddyfile.d/*.caddyfile` items, purge unmanaged `.caddyfile` files when `frankenphp_caddyfile_d_purge: true`, and notify `validate and reload frankenphp`
- [X] T019 [US2] Update `roles/frankenphp/tasks/configure.yml` to manage `/etc/systemd/system/frankenphp.service.d/override.conf`, ensure `{{ frankenphp_data_dir }}` exists with owner `{{ frankenphp_user }}` and group `{{ frankenphp_group }}` (`mode: '0750'`), notify `reload systemd and restart frankenphp`, and flush handlers
- [X] T020 [US2] Extend `roles/frankenphp/molecule/default/converge.yml` and `roles/frankenphp/molecule/default/verify.yml` to configure a custom worker Caddyfile on `:8080` and `Caddyfile.d` health check on `:8081`, asserting that both endpoints return HTTP 200 and custom Caddyfile validation passes

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Customize Daemon Environment, Service User, and PHP Runtime Settings (Priority: P3)

**Goal**: Support customizing the systemd daemon user/group (`frankenphp_user`/`frankenphp_group`), injecting environment variables (`frankenphp_env`), and applying custom `php.ini` directives (`frankenphp_php_ini`) to `/etc/php-zts/conf.d/99-frankenphp-custom.ini`.

**Independent Test**: Configure `frankenphp_php_ini: {'memory_limit': '256M', 'expose_php': 'Off'}` and `frankenphp_env: {'APP_ENV': 'production'}`, apply the role, verify `php-zts -i` reflects `memory_limit => 256M` and `expose_php => Off`, and verify the worker process reports `APP_ENV=production``.

### Implementation for User Story 3

- [X] T021 [P] [US3] Create custom PHP INI template in `roles/frankenphp/templates/99-frankenphp-custom.ini.j2` to render directives from `frankenphp_php_ini` to `/etc/php-zts/conf.d/99-frankenphp-custom.ini` (`mode: '0644'`, `owner: root`, `group: root`), and remove the file when `frankenphp_php_ini` is empty
- [X] T022 [US3] Update `roles/frankenphp/tasks/configure.yml` to render `/etc/php-zts/conf.d/99-frankenphp-custom.ini` notifying `validate and restart frankenphp`, and verify that `override.conf.j2` renders all `frankenphp_env` environment variables
- [X] T023 [US3] Extend `roles/frankenphp/molecule/default/verify.yml` to assert that custom `php.ini` directives are active via `php-zts -i` and that the running daemon responds with environment variables configured in `frankenphp_env`

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Role documentation, CI matrix registration, linting, and full 5-distro Molecule verification

- [X] T024 [P] Write comprehensive role documentation (description, supported platforms, requirements, role variables with defaults, example playbooks for default install, custom Caddyfile worker mode, and Laravel Octane daemon mode, license) in `roles/frankenphp/README.md`
- [X] T025 [P] Add the `frankenphp` role to the Roles table in `AGENTS.md`
- [X] T026 [P] Register `frankenphp` in all four required locations (`detect-changes.outputs`, `paths-filter` `filters`, `molecule.strategy.matrix.role`, and the role-check `case` statement) in `.github/workflows/ci.yml`
- [X] T027 Run `yamllint .` and `ansible-lint` from the repository root and fix any warnings or errors across `roles/frankenphp/`, `AGENTS.md`, and `.github/workflows/ci.yml`
- [X] T028 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from `roles/frankenphp/` (or via `./test-matrix.sh -r frankenphp`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational (Phase 2) completion
  - User Story 1 (Phase 3) provides base repository configuration, package installation, and baseline daemon execution (MVP)
  - User Story 2 (Phase 4) builds on User Story 1 by adding custom Caddyfile, drop-ins, and daemon mode switching
  - User Story 3 (Phase 5) builds on User Stories 1 & 2 by adding custom `php.ini` tuning and daemon environment variables
- **Polish (Phase 6)**: Depends on all user stories (Phase 3-5) being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Depends on US1 package installation to validate and run Caddyfile configurations
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Extends configuration tasks in US2 to add PHP INI and environment overrides

### Parallel Opportunities

- Within Phase 1: `T004` [P] (`prepare.yml`) can run in parallel with `T003` (`molecule.yml`).
- Within Phase 2: `T005` [P] (`meta/main.yml`), `T006` [P] (`vars/Debian.yml`), `T007` [P] (`vars/RedHat.yml`), and `T009` [P] (`handlers/main.yml`) can be developed in parallel.
- Within Phase 3: `T010` [P] (`setup-Debian.yml`), `T011` [P] (`setup-RedHat.yml`), and `T013` [P] (`Caddyfile.j2`) can run in parallel.
- Within Phase 4: `T016` [P] (`caddyfile-d.j2`) and `T017` [P] (`override.conf.j2`) can be created in parallel.
- Within Phase 5: `T021` [P] (`99-frankenphp-custom.ini.j2`) can be created in parallel.
- Within Phase 6: `T024` [P] (`README.md`), `T025` [P] (`AGENTS.md`), and `T026` [P] (`ci.yml`) can be edited in parallel before running linters (`T027`) and Molecule tests (`T028`).

---

## Parallel Example: User Story 1 & Foundational

```bash
# Foundational tasks that can run in parallel:
Task: "Populate Galaxy metadata in roles/frankenphp/meta/main.yml"
Task: "Define Debian-family variables in roles/frankenphp/vars/Debian.yml"
Task: "Define RedHat-family variables in roles/frankenphp/vars/RedHat.yml"
Task: "Implement validation-guarded service reload and restart handlers in roles/frankenphp/handlers/main.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001` - `T004`)
2. Complete Phase 2: Foundational (`T005` - `T009`)
3. Complete Phase 3: User Story 1 (`T010` - `T015`)
4. **STOP and VALIDATE**: Run `molecule converge && molecule verify` to test User Story 1 independently.

### Incremental Delivery

1. Setup + Foundational → Role skeleton, metadata, OS vars, handlers ready.
2. User Story 1 → Repository configured, packages & extensions installed, baseline daemon running on `:80` (MVP).
3. User Story 2 → Custom Caddyfile worker mode, `Caddyfile.d` snippets, and `caddyfile`/`octane` daemon modes.
4. User Story 3 → Custom `php.ini` directives and daemon environment variables.
5. Polish → Documentation (`README.md`, `AGENTS.md`), CI matrix registration, lint clean, and 5-distro container verification.
