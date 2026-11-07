# Implementation Plan: Docker Compose Stack Management (`docker`)

**Branch**: `005-docker-compose-support` | **Date**: 2026-11-07 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/005-docker-compose-support/spec.md`

## Summary

Update the `hifra01.utils.docker` Ansible role under `roles/docker/` to allow users to declaratively add, validate, and manage Docker Compose projects via `docker_compose_projects`, saving each project's Compose file in `/srv/<name>/compose.yml` by default (configurable via `docker_compose_base_dir: "/srv"`, per-project `path`, and `filename`). Each project supports mutually exclusive `content` (YAML string or dictionary), `template` (controller Jinja2 template with `vars`), or `src` (controller static file), optional `.env` file generation (`env`), custom `owner`/`group` (defaulting to `root:root`), pre-validation via `docker compose config -q`, and full lifecycle management (`present`/`started`, `stopped`, and safe `absent` teardown with opt-in `remove_volumes` and `remove_dir` flags) while leaving unlisted `/srv/*` directories untouched.

## Technical Context

**Language/Version**: YAML / Ansible (`ansible-core >= 2.21.0`, tested with Python 3.9–3.14)  
**Primary Dependencies**: `ansible.builtin` modules (`assert`, `include_tasks`, `file`, `copy`, `template`, `stat`, `command`, `meta`), `docker-compose-plugin` (`docker compose` CLI v2 installed by the role)  
**Storage**: Host filesystem under `/etc/docker/daemon.json` and `{{ docker_compose_base_dir }}/{{ compose_project.name }}` (`/srv/<name>/compose.yml` and `/srv/<name>/.env` by default)  
**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]`) across all 5 target distro images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`)  
**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) running `systemd`  
**Project Type**: Ansible Collection role (`hifra01.utils.docker`)  
**Performance Goals**: Single-node convergence in `< 60s`; zero changes (`changed=0`) on second consecutive run when Compose definitions and container states are unchanged  
**Constraints**: Must pass `yamllint .` and `ansible-lint` with zero errors; must not require extra Python libraries on remote hosts (works on Rocky Linux 8 `/usr/bin/python3.9`); must never touch unlisted subdirectories in `/srv`  
**Scale/Scope**: Existing `roles/docker/` role (`defaults/main.yml`, `tasks/main.yml`, new `tasks/compose.yml` and `tasks/compose-project.yml`, `templates/compose.yml.j2`, `templates/compose.env.j2`, `README.md`, `AGENTS.md`, and `molecule/default/*`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | Following `speckit-specify` → `speckit-clarify` → `speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement` in `specs/005-docker-compose-support/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Extending the existing scaffolded `roles/docker/` role; no manual edits to `.ansible/` or `.specify/` engine files. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports both `Debian` and `RedHat` families; starts `tasks/main.yml` with an `ansible.builtin.assert` platform guard; all role variables prefixed with `docker_` (`docker_compose_base_dir`, `docker_compose_projects`); included task loops define `loop_control.loop_var: compose_project`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | Uses FQCNs exclusively, `# SPDX-License-Identifier: MIT-0` headers, quoted octal file modes (`'0755'`, `'0644'`, `'0600'`), `true`/`false` booleans, explicit `changed_when` on all `command` tasks, and `docker compose config -q` validation before state changes. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | `roles/docker/molecule/default/` (`prepare.yml`, `converge.yml`, `verify.yml`) will verify Compose deployment in `/srv/<name>`, custom templates + `vars`, `.env` rendering, `stopped` and `absent` lifecycle states, and preservation of unmanaged `/srv` directories across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) plus `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | `docker` is already registered in `.github/workflows/ci.yml`; `roles/docker/README.md` (currently a placeholder template) will be completely written and `AGENTS.md` updated to note Compose support. |

## Project Structure

### Documentation (this feature)

```text
specs/005-docker-compose-support/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── role-interface.md
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit-specify command)
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code (repository root)

```text
roles/
└── docker/
    ├── README.md                              # Complete role documentation & Compose examples
    ├── defaults/
    │   └── main.yml                           # Add docker_compose_base_dir ("/srv") & docker_compose_projects ([])
    ├── handlers/
    │   └── main.yml                           # Restart docker handler
    ├── meta/
    │   └── main.yml                           # Role metadata
    ├── tasks/
    │   ├── main.yml                           # Platform assert, repo, install, configure, users, and compose include
    │   ├── setup-repository.yml               # Docker CE/EE apt/yum repo setup
    │   ├── install.yml                        # Package installation (includes docker-compose-plugin)
    │   ├── configure.yml                      # /etc/docker/daemon.json & service enable/start
    │   ├── users.yml                          # Docker group user membership
    │   ├── compose.yml                        # Assert validation & loop over docker_compose_projects
    │   └── compose-project.yml                # Per-project directory, compose.yml/.env render, config -q, up/stop/down
    ├── templates/
    │   ├── compose.yml.j2                     # Renders inline content (string/dict) or controller template with vars
    │   └── compose.env.j2                     # Renders .env file from dict or string
    ├── vars/
    │   └── main.yml
    └── molecule/
        └── default/
            ├── molecule.yml                   # 5-distro Docker systemd matrix config
            ├── prepare.yml                    # RHEL 8 python39 bootstrap + /srv/unmanaged-data fixture
            ├── converge.yml                   # Converge docker role with inline, templated, and stopped Compose projects
            ├── verify.yml                     # Verify running containers, file modes, idempotency, and absent teardown
            └── templates/
                └── custom-compose.yml.j2      # Test fixture template for Molecule verification of template + vars
```

**Structure Decision**: Extends the existing `roles/docker/` role modularly by adding `tasks/compose.yml` and `tasks/compose-project.yml` (included from `tasks/main.yml` when `docker_compose_projects | length > 0`), `templates/compose.yml.j2` and `templates/compose.env.j2` for Compose and `.env` rendering, and comprehensive Molecule tests under `roles/docker/molecule/default/`.

## Complexity Tracking

No Constitution violations exist.
