# Implementation Plan: Redis Open Source Role (`redis`)

**Branch**: `006-redis-role` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/006-redis-role/spec.md`

## Summary

Create a new `hifra01.utils.redis` Ansible role under `roles/redis/` that installs and configures Redis Open Source on Debian-family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat-family (`Rocky Linux 8`, `Rocky Linux 9`, `AlmaLinux`, `RHEL`) distributions. The role installs packages using standard OS distribution repositories by default (`redis_install_repo: false`) or optionally configures official `packages.redis.io` upstream repositories (`redis_install_repo: true`), provides full password authentication support (`requirepass {{ redis_password | quote }}`) protected with restricted configuration permissions (`0640`) and log suppression (`redis_no_log: true`), manages systemd service lifecycle with restart handlers, supports optional host kernel parameter tuning (`redis_sysctl: true`), and includes full 5-distro Molecule test coverage.

## Technical Context

**Language/Version**: YAML / Jinja2 / Ansible (`ansible-core >= 2.21.0`, Python 3.9–3.14)

**Primary Dependencies**: `ansible.builtin` modules (`assert`, `include_vars`, `package`, `service`, `template`, `file`, `wait_for`, `command`), `ansible.posix.sysctl` (from collection dependency `ansible.posix >= 1.5.0`), distribution repositories (`apt`, `dnf`/AppStream) or official `packages.redis.io` repos

**Storage**: Configuration at `/etc/redis/redis.conf`, data persistence store at `/var/lib/redis`, log files at `/var/log/redis/redis-server.log` (Debian) or `/var/log/redis/redis.log` (RedHat)

**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]`) across all 5 target distros (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`)

**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) with systemd init

**Project Type**: Ansible Collection role (`hifra01.utils.redis`)

**Performance Goals**: Single-node convergence in `< 30s`; `changed=0` on second run with 0 service restarts and zero unexpected diffs

**Constraints**: Must satisfy strict `yamllint` (2-space indent, max 160 chars, quoted octal file modes) and `ansible-lint`; variable namespacing with `redis_`; credential suppression via `redis_no_log: true`; Rocky 8 `python39` bootstrap compatibility

**Scale/Scope**: Single Ansible role (`roles/redis/`), registration in `.github/workflows/ci.yml` (4 locations), documentation in `AGENTS.md` and `roles/redis/README.md`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | Follows Spec-Kit workflow (`specify` → `clarify` → `plan` → `tasks` → `analyze` → `implement`) with design artifacts in `specs/006-redis-role/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Scaffolding role and Molecule scenario will strictly use `ansible-galaxy role init --init-path roles redis` and `molecule init scenario default` from inside `roles/redis/`. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports `Debian` and `RedHat` families; starts `tasks/main.yml` with platform guard `ansible.builtin.assert`; variables prefixed with `redis_`; OS-specific names isolated in `vars/Debian.yml` and `vars/RedHat.yml`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | Uses FQCNs exclusively, quoted octal strings (`'0640'`, `'0750'`), `true`/`false` booleans, and grouped restart handlers via `listen: "restart redis"`. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | Full Molecule scenario (`molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`) verified across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) plus `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | Role will be registered in all 4 required locations in `.github/workflows/ci.yml`, documented in `roles/redis/README.md`, `roles/redis/meta/main.yml`, and added to the roles table in `AGENTS.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/006-redis-role/
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
    └── ci.yml                             # Register redis in all 4 matrix/filter locations
AGENTS.md                                  # Add redis to the Roles table
roles/
└── redis/
    ├── README.md                          # Role documentation, variables, and examples
    ├── defaults/
    │   └── main.yml                       # User-tunable redis_* default variables
    ├── handlers/
    │   └── main.yml                       # "restart redis" listener
    ├── meta/
    │   └── main.yml                       # Galaxy metadata (platforms: Debian, Ubuntu, EL 8/9)
    ├── tasks/
    │   ├── main.yml                       # Platform guard, OS variable dispatch, task orchestration
    │   ├── sysctl.yml                     # Optional host kernel tuning (vm.overcommit_memory, somaxconn)
    │   ├── repo-Debian.yml                # Optional upstream packages.redis.io APT repo setup
    │   ├── repo-RedHat.yml                # Optional upstream packages.redis.io RPM repo setup
    │   ├── install.yml                    # Package installation and filesystem directories
    │   └── configure.yml                  # redis.conf template, permissions (0640), service state
    ├── templates/
    │   └── redis.conf.j2                  # Redis configuration template with requirepass support
    ├── tests/
    │   ├── inventory
    │   └── test.yml
    ├── vars/
    │   ├── Debian.yml                     # Debian/Ubuntu package name, service name, file paths
    │   └── RedHat.yml                     # RedHat/Rocky package name, service name, file paths
    └── molecule/
        └── default/
            ├── molecule.yml               # Docker systemd driver config for 5-distro matrix
            ├── prepare.yml                # RHEL 8 python39 bootstrap
            ├── converge.yml               # Converge role by FQCN (hifra01.utils.redis)
            └── verify.yml                 # Assert package, service, port 6379, auth rejection & acceptance
```

**Structure Decision**: Standard `hifra01.utils` role layout under `roles/redis/` initialized via official CLI tools (`ansible-galaxy role init --init-path roles redis` and `molecule init scenario default`). Installation and configuration are separated into dedicated task files (`tasks/install.yml`, `tasks/configure.yml`, `tasks/sysctl.yml`) included from `tasks/main.yml`, with OS divergence isolated in `vars/Debian.yml` and `vars/RedHat.yml`.

## Complexity Tracking

No Constitution violations exist.
