# Implementation Plan: Percona Server for MongoDB Role (`percona_mongodb`)

**Branch**: `003-percona-mongodb-role` | **Date**: 2026-11-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-percona-mongodb-role/spec.md`

## Summary

Create the `hifra01.utils.percona_mongodb` Ansible role to install and configure Percona Server for MongoDB (defaulting to series `8.0` / `psmdb-80`) across Debian-family (Ubuntu 22.04/24.04, Debian 12) and RedHat-family (Rocky Linux 8/9, AlmaLinux, RHEL) distributions. The role enables replica set mode by default (`percona_mongodb_replset_enabled: true`) and automatically initializes a **single-instance replica set** (when `percona_mongodb_replset_members: []`) or a **multi-instance replica set** (when `percona_mongodb_replset_members` is populated), manages keyfile security (`0400`) and root admin bootstrap via MongoDB's localhost exception without requiring double service restarts, reconciles `rs.reconfig()` and application users (`percona_mongodb_users`) idempotently via `mongosh`, and supports standalone deployments (`percona_mongodb_replset_enabled: false`).

## Technical Context

**Language/Version**: YAML / Ansible (`ansible-core >= 2.21.0`), Jinja2 templates, `mongosh` JavaScript expressions  
**Primary Dependencies**: `ansible.builtin`, `ansible.posix >= 1.5.0`, `community.general >= 9.0.0`, official `percona-release` repository package (`percona-server-mongodb` + `percona-mongodb-mongosh`)  
**Storage**: WiredTiger storage engine at `/var/lib/mongodb` (Debian-family) or `/var/lib/mongo` (RedHat-family), configuration at `/etc/mongod.conf`, keyfile at `/etc/mongod.keyfile`  
**Testing**: `yamllint >= 1.35.0`, `ansible-lint >= 8.5.0`, `molecule >= 26.8.0` with `molecule-plugins[docker] >= 26.7.15` across 5 distro images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`)  
**Target Platform**: Linux (`Debian` and `RedHat` OS families with `systemd`, 64-bit)  
**Project Type**: Ansible Collection Role (`roles/percona_mongodb/`)  
**Performance Goals**: Single-node replica set reaches `PRIMARY` state (`myState: 1`) and accepts authenticated multi-document transactions within 60 seconds of convergence  
**Constraints**: Zero target-host Python MongoDB driver (`pymongo`) dependencies (must work cleanly on Rocky Linux 8 with `/usr/bin/python3.9`); strict idempotency (`0` changed tasks on second run); FQCNs, 2-space YAML indentation, max 160 chars per line, quoted octal file modes  
**Scale/Scope**: 1 Ansible role (`roles/percona_mongodb/`), 1 Molecule default scenario, CI workflow matrix registration in `.github/workflows/ci.yml`, and documentation in `AGENTS.md` and `roles/percona_mongodb/README.md`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | `spec.md`, `checklists/requirements.md`, clarifications, and Phase 0/1 design artifacts (`research.md`, `data-model.md`, `contracts/role-interface.md`, `quickstart.md`, `plan.md`) completed in `specs/003-percona-mongodb-role/` prior to scaffolding. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Role will be initialized via `ansible-galaxy role init --init-path roles percona_mongodb` and `molecule init scenario default` inside `roles/percona_mongodb/`. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports both `Debian` and `RedHat` OS families; starts `tasks/main.yml` with an `ansible.builtin.assert` platform guard; prefixes all variables with `percona_mongodb_` or `_percona_mongodb_`; isolates OS-specific paths/packages in `vars/Debian.yml` and `vars/RedHat.yml`; uses `loop_control.loop_var: mongodb_user` in user loops. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | All tasks use FQCNs, quoted octal modes (`'0644'`, `'0400'`), `# SPDX-License-Identifier: MIT-0` headers, and explicit `changed_when`/`failed_when` on `mongosh` / `percona-release` command tasks; handler validates YAML config before restarting `mongod` via `listen: "restart mongod"`. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | Will be verified with `yamllint .`, `ansible-lint`, and `molecule test` across Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, and Rocky Linux 8, and registered in all 4 locations in `.github/workflows/ci.yml`. |

**Post-Design Re-Check**: PASS — All 5 Constitution principles and Technical Stack constraints are satisfied without exceptions.

## Project Structure

### Documentation (this feature)

```text
specs/003-percona-mongodb-role/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── role-interface.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    └── ci.yml                             # Register percona_mongodb in all 4 matrix/filter locations

AGENTS.md                                  # Add percona_mongodb to the Roles table

roles/
└── percona_mongodb/
    ├── README.md                          # Role documentation (variables, single/multi-node examples)
    ├── defaults/
    │   └── main.yml                       # User-tunable percona_mongodb_* default variables
    ├── handlers/
    │   └── main.yml                       # "restart mongod" listener (validate YAML + restart service)
    ├── meta/
    │   └── main.yml                       # Galaxy metadata (platforms: Debian/Ubuntu/EL, tags)
    ├── tasks/
    │   ├── main.yml                       # Platform & input assertions, OS dispatch, task orchestration
    │   ├── setup-Debian.yml               # percona-release .deb + enable-only psmdb-XX on Debian/Ubuntu
    │   ├── setup-RedHat.yml               # percona-release .rpm + enable-only psmdb-XX on RHEL/Rocky
    │   ├── install.yml                    # Install percona-server-mongodb packages & ensure directories
    │   ├── configure.yml                  # Keyfile generation/deployment, /etc/mongod.conf, service start
    │   ├── replicaset.yml                 # rs.initiate() (1-node or multi-node), PRIMARY wait, rs.reconfig()
    │   ├── users.yml                      # Admin user bootstrap + loop over percona_mongodb_users
    │   └── user-item.yml                  # Idempotent createUser / updateUser / dropUser via mongosh
    ├── templates/
    │   └── mongod.conf.j2                 # Structured YAML configuration template for /etc/mongod.conf
    ├── tests/
    │   ├── inventory
    │   └── test.yml
    ├── vars/
    │   ├── main.yml                       # Internal version-to-repo mapping (_percona_mongodb_repo_map)
    │   ├── Debian.yml                     # Debian/Ubuntu packages, mongod user/group, /var/lib/mongodb paths
    │   └── RedHat.yml                     # RedHat/Rocky packages, mongod user/group, /var/lib/mongo paths
    └── molecule/
        └── default/
            ├── molecule.yml               # Privileged systemd Docker container configuration
            ├── prepare.yml                # RHEL/Rocky 8 Python 3.9 bootstrap via raw
            ├── converge.yml               # Converge hifra01.utils.percona_mongodb (1-node RS + auth + users)
            └── verify.yml                 # Assert service, keyfile, auth rejection, PRIMARY RS, and transactions
```

**Structure Decision**: Follows the standard `hifra01.utils` role layout under `roles/percona_mongodb/` initialized via `ansible-galaxy role init --init-path roles percona_mongodb` and `molecule init scenario default`, combining OS-specific repository setup (`setup-Debian.yml`, `setup-RedHat.yml`) with focused task files (`install.yml`, `configure.yml`, `replicaset.yml`, `users.yml`, `user-item.yml`).

## Complexity Tracking

No Constitution violations exist.
