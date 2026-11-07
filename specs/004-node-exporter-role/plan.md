# Implementation Plan: Prometheus Node Exporter Role (`node_exporter`)

**Branch**: `004-node-exporter-role` | **Date**: 2026-11-07 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-node-exporter-role/spec.md`

## Summary

Create a new `hifra01.utils.node_exporter` Ansible role under `roles/node_exporter/` that installs Prometheus Node Exporter from official precompiled GitHub Release tarballs (with SHA256 verification against upstream `sha256sums.txt` or an explicit `node_exporter_checksum` override) on Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) and RedHat-family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL) distributions. The role provisions an unprivileged `node_exporter` system user/group, manages `/etc/systemd/system/node_exporter.service`, configures the textfile collector directory (`/var/lib/node_exporter/textfile_collector`), supports flexible collector toggles and collector-specific sub-flags (`node_exporter_enabled_collectors`, `node_exporter_disabled_collectors`, `node_exporter_extra_flags`), optionally renders `/etc/node_exporter/config.yml` for TLS/basic authentication (`node_exporter_web_config`), and includes full 5-distro Molecule test coverage.

## Technical Context

**Language/Version**: YAML / Ansible (`ansible-core >= 2.21.0`, tested with Python 3.9–3.14)

**Primary Dependencies**: `ansible.builtin` modules (`assert`, `include_vars`, `package`, `group`, `user`, `file`, `stat`, `command`, `get_url`, `unarchive`, `copy`, `template`, `systemd`, `service`, `uri`, `wait_for`); official Prometheus Node Exporter GitHub Releases (`github.com/prometheus/node_exporter/releases`)

**Storage**: Host filesystem binary at `/usr/local/bin/node_exporter`, systemd unit at `/etc/systemd/system/node_exporter.service`, textfile collector directory at `/var/lib/node_exporter/textfile_collector`, and optional web configuration at `/etc/node_exporter/config.yml`

**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]`) across 5 target distro images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`)

**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) running `systemd` on `x86_64` (`amd64`), `aarch64` (`arm64`), or `armv7l` (`armv7`)

**Project Type**: Ansible Collection role (`hifra01.utils.node_exporter`)

**Performance Goals**: Single-node convergence in `< 45s` (excluding initial network archive download); `changed=0` on second run with zero binary re-downloads and zero service restarts

**Constraints**: Must pass strict `yamllint` (2-space indent, max 160 chars, quoted octal modes) and `ansible-lint`; must work on Rocky Linux 8 where Python 3.6 requires the `python39` bootstrap without breaking `dnf` Python bindings

**Scale/Scope**: Single Ansible role (`roles/node_exporter/`), CI workflow registration in `.github/workflows/ci.yml` (4 locations), and documentation update in `AGENTS.md` and `roles/node_exporter/README.md`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | Following `speckit-specify` → `speckit-clarify` → `speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement` in `specs/004-node-exporter-role/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Role and Molecule scenario will be scaffolded using `ansible-galaxy role init --init-path roles node_exporter` and `molecule init scenario default`. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports both `Debian` and `RedHat` families; starts `tasks/main.yml` with an `ansible.builtin.assert` platform and architecture guard; all variables prefixed with `node_exporter_`; OS-specific variables isolated in `vars/Debian.yml` and `vars/RedHat.yml`; internal registered variables prefixed with `_node_exporter_`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | Uses FQCNs exclusively, quoted octal strings (`'0640'`, `'0644'`, `'0750'`, `'0755'`), `true`/`false` booleans, version check guard before archive download, and `listen: "validate and restart node_exporter"` handlers that reload systemd and verify the binary before restarting `node_exporter`. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | Full Molecule scenario (`molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`) planned and verified across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) plus `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | Plan includes registering `node_exporter` in all 4 places in `.github/workflows/ci.yml`, documenting `roles/node_exporter/README.md` and `roles/node_exporter/meta/main.yml`, and updating the roles table in `AGENTS.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/004-node-exporter-role/
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
    └── ci.yml                             # Register node_exporter in all 4 matrix/filter locations
AGENTS.md                                  # Add node_exporter to the Roles table
roles/
└── node_exporter/
    ├── README.md                          # Role documentation, variables, and examples
    ├── defaults/
    │   └── main.yml                       # User-tunable node_exporter_* default variables
    ├── handlers/
    │   └── main.yml                       # "validate and restart node_exporter" listener
    ├── meta/
    │   └── main.yml                       # Galaxy metadata (platforms: Debian, Ubuntu, EL 8/9)
    ├── tasks/
    │   ├── main.yml                       # Platform/input assertions & task orchestration
    │   ├── install.yml                    # Prerequisite packages, system user/group, binary download & install
    │   └── configure.yml                  # Textfile dir, optional config.yml, systemd unit & service state
    ├── templates/
    │   ├── config.yml.j2                  # Optional web configuration (TLS / Basic Auth)
    │   └── node_exporter.service.j2       # Systemd service unit template
    ├── tests/
    │   ├── inventory
    │   └── test.yml
    ├── vars/
    │   ├── Debian.yml                     # Debian/Ubuntu prerequisite packages, service name, & nologin shell
    │   └── RedHat.yml                     # RedHat/Rocky prerequisite packages, service name, & nologin shell
    └── molecule/
        └── default/
            ├── molecule.yml               # Docker systemd driver config for 5-distro matrix
            ├── prepare.yml                # RHEL 8 python39 bootstrap
            ├── converge.yml               # Converge role by FQCN (hifra01.utils.node_exporter)
            └── verify.yml                 # Assert binary, user, service, /metrics HTTP 200, textfile metrics, & web_config
```

**Structure Decision**: Follows the standard `hifra01.utils` role layout under `roles/node_exporter/` initialized via `ansible-galaxy role init --init-path roles node_exporter` and `molecule init scenario default`, separating installation (`tasks/install.yml`) and configuration/service management (`tasks/configure.yml`) with OS-specific variables in `vars/Debian.yml` and `vars/RedHat.yml`.

## Complexity Tracking

No Constitution violations exist.
