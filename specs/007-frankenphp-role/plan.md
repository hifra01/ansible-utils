# Implementation Plan: FrankenPHP Application Server Role (`frankenphp`)

**Branch**: `007-frankenphp-role` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-frankenphp-role/spec.md`

## Summary

Create a new `hifra01.utils.frankenphp` Ansible role under `roles/frankenphp/` that installs and configures FrankenPHP along with its embedded ZTS PHP runtime (`php-zts`), CLI (`php-zts-cli`), and configurable extensions (`php-zts-<ext>`) across Debian-family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat-family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) systems. The role configures the official `static-php` (`pkg.henderkes.com` / `rpm.henderkes.com`) repository for the selected PHP branch (`8.2`–`8.5`, default `8.4`), allows operators to define custom `Caddyfile` configurations (`frankenphp_caddyfile`) and modular drop-in snippets (`frankenphp_caddyfile_d`), supports both native Caddyfile daemon mode (`frankenphp_daemon_mode: "caddyfile"`) and Laravel Octane CLI daemon mode (`frankenphp_daemon_mode: "octane"`), manages systemd service drop-in overrides and custom `php.ini` settings, validates configuration via `frankenphp validate` prior to service reload/restart, and verifies functionality across all 5 CI matrix distributions via Molecule.

## Technical Context

**Language/Version**: YAML / Jinja2 / Ansible (`ansible-core >= 2.21.0`, Python 3.9–3.14)

**Primary Dependencies**: `ansible.builtin` modules (`assert`, `include_vars`, `include_tasks`, `apt`, `apt_repository`, `dnf`, `package`, `get_url`, `file`, `find`, `template`, `command`, `systemd_service`, `service`, `uri`, `stat`), official `static-php` (`pkg.henderkes.com` DEB and `rpm.henderkes.com` RPM) repositories

**Storage**: Main configuration at `/etc/frankenphp/Caddyfile`, drop-ins at `/etc/frankenphp/Caddyfile.d/*.caddyfile`, custom PHP INI at `/etc/php-zts/conf.d/99-frankenphp-custom.ini`, systemd drop-in override at `/etc/systemd/system/frankenphp.service.d/override.conf`, data directory at `/var/lib/frankenphp`

**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]` / `./test-matrix.sh -r frankenphp`) across all 5 target distros (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`)

**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) with `systemd` init

**Project Type**: Ansible Collection role (`hifra01.utils.frankenphp`)

**Performance Goals**: Single-node convergence in `< 60s`; `changed=0` on second run with 0 service reloads or restarts

**Constraints**: Must satisfy strict `yamllint` (2-space indent, max 160 chars, quoted octal file modes) and `ansible-lint`; variable namespacing with `frankenphp_`; pre-reload/restart validation using `frankenphp validate`; Rocky 8 `python39` bootstrap compatibility (using idempotent `dnf` CLI checks where Python `dnf` bindings are unavailable on Python 3.9)

**Scale/Scope**: Single Ansible role (`roles/frankenphp/`), registration in `.github/workflows/ci.yml` (4 locations), documentation in `AGENTS.md` and `roles/frankenphp/README.md`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | Follows Spec-Kit workflow (`specify` → `clarify` → `plan` → `tasks` → `analyze` → `implement`) with design artifacts in `specs/007-frankenphp-role/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Scaffolding role and Molecule scenario will strictly use `ansible-galaxy role init --init-path roles frankenphp` and `molecule init scenario default` from inside `roles/frankenphp/`. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports `Debian` and `RedHat` families; starts `tasks/main.yml` with platform and input guard `ansible.builtin.assert`; variables prefixed with `frankenphp_`; OS-specific repo URLs and extension mappings isolated in `vars/Debian.yml` and `vars/RedHat.yml`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | Uses FQCNs exclusively, quoted octal strings (`'0644'`, `'0755'`, `'0750'`), `true`/`false` booleans, and validation-guarded handlers via `listen:` (`"validate and reload frankenphp"`, `"validate and restart frankenphp"`, `"reload systemd and restart frankenphp"`). |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | Full Molecule scenario (`molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`) verified across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) plus `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | Role will be registered in all 4 required locations in `.github/workflows/ci.yml`, documented in `roles/frankenphp/README.md`, `roles/frankenphp/meta/main.yml`, and added to the roles table in `AGENTS.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/007-frankenphp-role/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── role-interface.md
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit-specify command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    └── ci.yml                                   # Register frankenphp in all 4 matrix/filter locations
AGENTS.md                                        # Add frankenphp to the Roles table
roles/
└── frankenphp/
    ├── README.md                                # Role documentation, variables, and examples (incl. Laravel Octane)
    ├── defaults/
    │   └── main.yml                             # User-tunable frankenphp_* default variables
    ├── handlers/
    │   └── main.yml                             # Validation-guarded reload/restart and daemon-reload listeners
    ├── meta/
    │   └── main.yml                             # Galaxy metadata (platforms: Debian, Ubuntu, EL 8/9)
    ├── tasks/
    │   ├── main.yml                             # Platform & input guard, OS vars dispatch, task orchestration
    │   ├── setup-Debian.yml                     # static-php APT key & repository setup for target PHP version
    │   ├── setup-RedHat.yml                     # static-php RPM repo & DNF module stream php-zts:static-<ver>
    │   ├── install.yml                          # Install frankenphp, php-zts-cli, extensions, pie-zts, /usr/bin/php symlink
    │   └── configure.yml                        # PHP INI, systemd drop-in override, data dir, Caddyfile & Caddyfile.d, service state
    ├── templates/
    │   ├── Caddyfile.j2                         # Renders frankenphp_caddyfile to /etc/frankenphp/Caddyfile
    │   ├── caddyfile-d.j2                       # Renders frankenphp_caddyfile_d items to /etc/frankenphp/Caddyfile.d/<name>.caddyfile
    │   ├── 99-frankenphp-custom.ini.j2          # Renders frankenphp_php_ini to /etc/php-zts/conf.d/99-frankenphp-custom.ini
    │   └── override.conf.j2                     # Renders systemd drop-in override for caddyfile/octane mode, user/group, and env
    ├── tests/
    │   ├── inventory
    │   └── test.yml
    ├── vars/
    │   ├── main.yml                             # Shared internal constants if any
    │   ├── Debian.yml                           # Debian/Ubuntu repo URLs, key paths, and extension mappings
    │   └── RedHat.yml                           # RedHat/Rocky RPM repo URL, module stream, and extension mappings
    └── molecule/
        └── default/
            ├── molecule.yml                     # Docker systemd driver config for 5-distro matrix
            ├── prepare.yml                      # RHEL 8 python39 bootstrap + sample PHP worker app fixture
            ├── converge.yml                     # Converge role by FQCN (hifra01.utils.frankenphp) with custom Caddyfile & PHP extensions
            └── verify.yml                       # Assert binaries, extensions, php.ini, Caddyfile validation, service state, HTTP responses
```

**Structure Decision**: Standard `hifra01.utils` role layout under `roles/frankenphp/` initialized via official CLI tools (`ansible-galaxy role init --init-path roles frankenphp` and `molecule init scenario default`). Repository setup is dispatched per OS family (`tasks/setup-Debian.yml` and `tasks/setup-RedHat.yml`), while package installation (`tasks/install.yml`) and configuration/daemon management (`tasks/configure.yml`) are cleanly modularized and included from `tasks/main.yml`.

## Complexity Tracking

No Constitution violations exist.
