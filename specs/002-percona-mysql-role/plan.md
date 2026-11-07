# Implementation Plan: Percona Server for MySQL Role (`percona_mysql`)

**Branch**: `hifra01/feat-percona-mysql-role` | **Date**: 2026-10-30 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-percona-mysql-role/spec.md`

## Summary

Create a new `hifra01.utils.percona_mysql` Ansible role under `roles/percona_mysql/` that installs and manages Percona Server for MySQL (defaulting to Percona Server 8.4 LTS / `ps-84-lts`) from official Percona repositories across Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) and RedHat-family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL) distributions. Operators can configure each node as either a writable primary (`percona_mysql_role: "master"`) or a read-only replica (`percona_mysql_role: "replica"`) with GTID auto-positioned replication (`SOURCE_AUTO_POSITION = 1`), declarative database and user management via native idempotent `mysql` CLI checks, drop-in configuration management (`99-percona-managed.cnf`) validated via `mysqld --validate-config`, and a two-container (`mysql-master` + `mysql-replica`) Molecule test scenario verified across all 5 CI distributions.

## Technical Context

**Language/Version**: YAML / Ansible (`ansible-core >= 2.15`, tested with Python 3.9–3.14)

**Primary Dependencies**: `ansible.builtin` modules (`apt`, `dnf`, `package`, `get_url`, `template`, `lineinfile`, `file`, `stat`, `service`, `command`, `assert`); official Percona release repositories (`repo.percona.com` via `percona-release`)

**Storage**: Host filesystem drop-in configuration files (`/etc/mysql/conf.d/99-percona-managed.cnf` on Debian, `/etc/my.cnf.d/99-percona-managed.cnf` on RedHat), admin client credentials (`/root/.my.cnf`), and MySQL data directory (`/var/lib/mysql`)

**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]`) with a 2-container topology (`mysql-master` + `mysql-replica`) across 5 target distro images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`)

**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) running `systemd`

**Project Type**: Ansible Collection role (`hifra01.utils.percona_mysql`)

**Performance Goals**: Two-node convergence in `< 120s` (excluding initial package download); `changed=0` on second run across both `master` and `replica` nodes

**Constraints**: Must pass strict `yamllint` (2-space indent, max 160 chars, quoted octal modes) and `ansible-lint`; must not require `community.mysql` or target-host Python MySQL libraries; must work on Rocky Linux 8 where Python 3.6 requires the `python39` bootstrap without breaking `dnf` Python bindings

**Scale/Scope**: Single Ansible role (`roles/percona_mysql/`), CI workflow registration in `.github/workflows/ci.yml` (4 locations), and documentation update in `AGENTS.md` and `roles/percona_mysql/README.md`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | Following `speckit-specify` → `speckit-clarify` → `speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement` in `specs/002-percona-mysql-role/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Role and Molecule scenario will be scaffolded using `ansible-galaxy role init --init-path roles percona_mysql` and `molecule init scenario default`. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports both `Debian` and `RedHat` families; starts `tasks/main.yml` with an `ansible.builtin.assert` platform guard; all variables prefixed with `percona_mysql_`; OS-specific variables isolated in `vars/Debian.yml` and `vars/RedHat.yml`; task loops define `loop_control.loop_var`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | Uses FQCNs exclusively, quoted octal strings (`'0600'`, `'0644'`, `'0755'`), `true`/`false` booleans, `changed_when` on all `command` tasks, and `listen:` handlers that run `mysqld --validate-config` before restarting `mysql`/`mysqld`. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | Full 2-container Molecule scenario (`molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`) planned and verified across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) plus `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | Plan includes registering `percona_mysql` in all 4 places in `.github/workflows/ci.yml`, documenting `roles/percona_mysql/README.md` and `roles/percona_mysql/meta/main.yml`, and updating the roles table in `AGENTS.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/002-percona-mysql-role/
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
.github/
└── workflows/
    └── ci.yml                             # Register percona_mysql in all 4 matrix/filter locations
AGENTS.md                                  # Add percona_mysql to the Roles table
roles/
└── percona_mysql/
    ├── README.md                          # Role documentation, variables, and master/replica examples
    ├── defaults/
    │   └── main.yml                       # User-tunable percona_mysql_* default variables
    ├── handlers/
    │   └── main.yml                       # "validate and restart mysql" listener
    ├── meta/
    │   └── main.yml                       # Galaxy metadata (platforms: Debian, Ubuntu, EL 8/9)
    ├── tasks/
    │   ├── main.yml                       # Platform/input assertions & task orchestration
    │   ├── setup-Debian.yml               # Official percona-release DEB install & repo enable
    │   ├── setup-RedHat.yml               # Official percona-release RPM install, dnf module disable, & repo enable
    │   ├── install.yml                    # Package installation & initial service start
    │   ├── configure.yml                  # Drop-in 99-percona-managed.cnf & root/.my.cnf security bootstrap
    │   ├── databases.yml                  # Idempotent database creation/removal on master
    │   ├── users.yml                      # Idempotent user & privilege management on master
    │   └── replication.yml                # Master replication user creation & replica GTID channel setup
    ├── templates/
    │   ├── 99-percona-managed.cnf.j2      # Managed [mysqld] drop-in configuration template
    │   └── root-my.cnf.j2                 # Root client credentials template (/root/.my.cnf)
    ├── tests/
    │   ├── inventory
    │   └── test.yml
    ├── vars/
    │   ├── Debian.yml                     # Debian/Ubuntu packages, service name, paths
    │   └── RedHat.yml                     # RedHat/Rocky packages, service name, paths
    └── molecule/
        └── default/
            ├── molecule.yml               # 2-container (mysql-master + mysql-replica) Docker systemd config
            ├── prepare.yml                # RHEL 8 python39 bootstrap on both containers
            ├── converge.yml               # Converge master and replica using hifra01.utils.percona_mysql
            └── verify.yml                 # Assert services, read_only state, DB/users, and live GTID replication
```

**Structure Decision**: Follows the standard `hifra01.utils` role layout under `roles/percona_mysql/` initialized via `ansible-galaxy role init --init-path roles percona_mysql` and `molecule init scenario default`, combining OS-specific repository setup (`setup-Debian.yml`, `setup-RedHat.yml`) with focused task files (`install.yml`, `configure.yml`, `databases.yml`, `users.yml`, `replication.yml`).

## Complexity Tracking

No Constitution violations exist.
