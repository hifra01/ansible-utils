# Implementation Plan: Fluent Bit Log Collector and Forwarder Role (`fluentbit`)

**Branch**: `008-fluentbit-role` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/008-fluentbit-role/spec.md`

## Summary

Create a new `hifra01.utils.fluentbit` Ansible role under `roles/fluentbit/` that installs and configures Fluent Bit (`fluent-bit`) from official upstream repositories (`https://packages.fluentbit.io`) across Debian-family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat-family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) systems. The role manages classic INI-style `/etc/fluent-bit/fluent-bit.conf` and `/etc/fluent-bit/parsers.conf` files along with persistent tail offset tracking in `/var/lib/fluent-bit/`, configures built-in pipelines for Laravel multiline application logs (`[MULTILINE_PARSER]` `laravel_multiline` + regex `parser` filter), Nginx access and error logs (`nginx_access` and `nginx_error` parsers + `modify` normalization), and Linux host system logs (`systemd` journal and/or OS-specific `syslog` files), forwards structured records to Graylog (`gelf` over UDP/TCP/TLS), Grafana Loki (`loki` over HTTP/HTTPS with stream labels), or both simultaneously, validates configuration via `/opt/fluent-bit/bin/fluent-bit --dry-run` prior to service restarts, and verifies functionality across all 5 CI matrix distributions via Molecule.

## Technical Context

**Language/Version**: YAML / Jinja2 / Ansible (`ansible-core >= 2.21.0`, Python 3.9–3.14)  
**Primary Dependencies**: `ansible.builtin` modules (`assert`, `include_vars`, `include_tasks`, `apt`, `apt_repository`, `yum_repository`, `package`, `get_url`, `file`, `template`, `command`, `service`, `uri`, `stat`, `slurp`, `wait_for`), official Fluent Bit repository (`https://packages.fluentbit.io`)  
**Storage**: Main configuration at `/etc/fluent-bit/fluent-bit.conf`, parser definitions at `/etc/fluent-bit/parsers.conf`, persistent SQLite tail state databases at `/var/lib/fluent-bit/*.db`  
**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]` / `./test-matrix.sh -r fluentbit`) across all 5 target distros (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`)  
**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) with `systemd` init  
**Project Type**: Ansible Collection role (`hifra01.utils.fluentbit`)  
**Performance Goals**: Single-node convergence in `< 60s`; `changed=0` on second run with 0 service restarts  
**Constraints**: Must satisfy strict `yamllint` (2-space indent, max 160 chars, quoted octal file modes) and `ansible-lint`; variable namespacing with `fluentbit_`; pre-restart validation using `/opt/fluent-bit/bin/fluent-bit --dry-run`; Rocky 8 `python39` bootstrap compatibility  
**Scale/Scope**: Single Ansible role (`roles/fluentbit/`), registration in `.github/workflows/ci.yml` (4 locations), documentation in `AGENTS.md` and `roles/fluentbit/README.md`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | Follows Spec-Kit workflow (`specify` → `clarify` → `plan` → `tasks` → `analyze` → `implement`) with design artifacts in `specs/008-fluentbit-role/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Scaffolding role and Molecule scenario will strictly use `ansible-galaxy role init --init-path roles fluentbit` and `molecule init scenario default` from inside `roles/fluentbit/`. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports `Debian` and `RedHat` families; starts `tasks/main.yml` with platform and input guard `ansible.builtin.assert`; variables prefixed with `fluentbit_`; OS-specific repo URLs, package names, and default syslog paths isolated in `vars/Debian.yml` and `vars/RedHat.yml`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | Uses FQCNs exclusively, quoted octal strings (`'0640'`, `'0644'`, `'0755'`, `'0750'`), `true`/`false` booleans, and validation-guarded handlers via `listen: "validate and restart fluent-bit"`. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | Full Molecule scenario (`molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`) verified across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) plus `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | Role will be registered in all 4 required locations in `.github/workflows/ci.yml`, documented in `roles/fluentbit/README.md`, `roles/fluentbit/meta/main.yml`, and added to the roles table in `AGENTS.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/008-fluentbit-role/
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
    └── ci.yml                                   # Register fluentbit in all 4 matrix/filter locations
AGENTS.md                                        # Add fluentbit to the Roles table
roles/
└── fluentbit/
    ├── README.md                                # Role documentation, variables, and playbooks (Graylog & Loki)
    ├── defaults/
    │   └── main.yml                             # User-tunable fluentbit_* default variables
    ├── handlers/
    │   └── main.yml                             # Validation-guarded restart listener ("validate and restart fluent-bit")
    ├── meta/
    │   └── main.yml                             # Galaxy metadata (platforms: Debian, Ubuntu, EL 8/9)
    ├── tasks/
    │   ├── main.yml                             # Platform & input guard, OS vars dispatch, task orchestration
    │   ├── setup-Debian.yml                     # Fluent Bit APT GPG key & repository setup
    │   ├── setup-RedHat.yml                     # Fluent Bit YUM/DNF repository setup
    │   ├── install.yml                          # Install fluent-bit package
    │   └── configure.yml                        # Manage directories, parsers.conf, fluent-bit.conf, dry-run validation, service state
    ├── templates/
    │   ├── parsers.conf.j2                      # Renders [MULTILINE_PARSER] laravel_multiline, laravel, nginx_access, nginx_error, syslog-rfc3164
    │   └── fluent-bit.conf.j2                   # Renders [SERVICE], [INPUT], [FILTER], and [OUTPUT] (gelf, loki, stdout, custom)
    ├── tests/
    │   ├── inventory
    │   └── test.yml
    ├── vars/
    │   ├── main.yml                             # Shared internal constants if any
    │   ├── Debian.yml                           # Debian/Ubuntu repo URLs, key paths, and default syslog paths
    │   └── RedHat.yml                           # RedHat/Rocky YUM repo URL and default syslog paths
    └── molecule/
        └── default/
            ├── molecule.yml                     # Docker systemd driver config for 5-distro matrix
            ├── prepare.yml                      # RHEL 8 python39 bootstrap + log directories + mock Graylog/Loki listeners
            ├── converge.yml                     # Converge role by FQCN (hifra01.utils.fluentbit) with Laravel, Nginx, System, Graylog & Loki enabled
            └── verify.yml                       # Inject multiline Laravel, Nginx access/error, and system logs; assert parsed records & delivery
```

**Structure Decision**: Standard `hifra01.utils` role layout under `roles/fluentbit/` initialized via official CLI tools (`ansible-galaxy role init --init-path roles fluentbit` and `molecule init scenario default`). Repository setup is dispatched per OS family (`tasks/setup-Debian.yml` and `tasks/setup-RedHat.yml`), while package installation (`tasks/install.yml`) and configuration/service management (`tasks/configure.yml`) are modularized and included from `tasks/main.yml`.

## Complexity Tracking

No Constitution violations exist.
