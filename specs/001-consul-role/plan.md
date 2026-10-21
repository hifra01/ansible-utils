# Implementation Plan: HashiCorp Consul Role (`consul`)

**Branch**: `001-consul-role` | **Date**: 2026-10-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-consul-role/spec.md`

## Summary

Create a new `hifra01.utils.consul` Ansible role under `roles/consul/` that installs HashiCorp Consul from official HashiCorp APT and YUM/DNF repositories on Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) and RedHat-family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL) distributions. Operators can configure each host to run in either `server` or `client` mode (`consul_mode`) and define a list of services (`consul_services`) to be advertised on each node, complete with automatic orphan service cleanup (`consul_services_purge`), configuration validation (`consul validate`) prior to reload/restart, and full 5-distro Molecule test coverage.

## Technical Context

**Language/Version**: YAML / Ansible (`ansible-core >= 2.15`, tested with Python 3.9–3.14)

**Primary Dependencies**: `ansible.builtin` modules (`apt`, `apt_repository`, `get_url`, `package`, `template`, `file`, `find`, `service`, `command`, `assert`); official HashiCorp Linux repositories (`apt.releases.hashicorp.com`, `rpm.releases.hashicorp.com`)

**Storage**: Host filesystem configuration files under `/etc/consul.d/` (`consul.hcl`, `extra.json`, `service-<id>.json`) and Raft/agent state directory `/opt/consul`

**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]`) across 5 target distro images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`)

**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) running `systemd`

**Project Type**: Ansible Collection role (`hifra01.utils.consul`)

**Performance Goals**: Single-node convergence in `< 60s` (excluding initial network package download); zero unnecessary service restarts on service catalog updates (uses SIGHUP reload via `state: reloaded`); `changed=0` on second run

**Constraints**: Must pass strict `yamllint` (2-space indent, max 160 chars, quoted octal modes) and `ansible-lint`; must work on Rocky Linux 8 where Python 3.6 requires the `python39` bootstrap without breaking `dnf` Python bindings

**Scale/Scope**: Single Ansible role (`roles/consul/`), CI workflow registration in `.github/workflows/ci.yml` (4 locations), and documentation update in `AGENTS.md` and `roles/consul/README.md`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | Following `speckit-specify` → `speckit-clarify` → `speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement` in `specs/001-consul-role/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Role and Molecule scenario will be scaffolded using `ansible-galaxy role init --init-path roles consul` and `molecule init scenario default`. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports both `Debian` and `RedHat` families; starts `tasks/main.yml` with an `ansible.builtin.assert` platform guard; all variables prefixed with `consul_`; OS-specific variables isolated in `vars/Debian.yml` and `vars/RedHat.yml`; task loops define `loop_control.loop_var`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | Uses FQCNs exclusively, quoted octal strings (`'0640'`, `'0644'`, `'0750'`, `'0755'`), `true`/`false` booleans, and `listen:` handlers that run `consul validate` before reloading or restarting `consul`. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | Full Molecule scenario (`molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`) planned and verified across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) plus `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | Plan includes registering `consul` in all 4 places in `.github/workflows/ci.yml`, documenting `roles/consul/README.md` and `roles/consul/meta/main.yml`, and updating the roles table in `AGENTS.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/001-consul-role/
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
    └── ci.yml                       # Register consul in all 4 matrix/filter locations
AGENTS.md                            # Add consul to the Roles table
roles/
└── consul/
    ├── README.md                    # Role documentation, variables, and examples
    ├── defaults/
    │   └── main.yml                 # User-tunable consul_* default variables
    ├── handlers/
    │   └── main.yml                 # "validate and reload consul" & "validate and restart consul"
    ├── meta/
    │   └── main.yml                 # Galaxy metadata (platforms: Debian, Ubuntu, EL 8/9)
    ├── tasks/
    │   ├── main.yml                 # Platform/input assertions & task orchestration
    │   ├── setup-Debian.yml         # Official HashiCorp APT repo & GPG setup
    │   ├── setup-RedHat.yml         # Official HashiCorp YUM/DNF repo setup
    │   ├── install.yml              # Package installation & directory ownership
    │   ├── configure.yml            # Main consul.hcl and optional extra.json rendering
    │   └── services.yml             # Per-service JSON rendering & orphan service purge
    ├── templates/
    │   ├── consul.hcl.j2            # Main Consul agent HCL configuration template
    │   └── service.json.j2          # Advertised service JSON template
    ├── tests/
    │   ├── inventory
    │   └── test.yml
    ├── vars/
    │   ├── Debian.yml               # Debian/Ubuntu prerequisite packages & service name
    │   └── RedHat.yml               # RedHat/Rocky prerequisite packages & service name
    └── molecule/
        └── default/
            ├── molecule.yml         # Docker systemd driver config for 5-distro matrix
            ├── prepare.yml          # RHEL 8 python39 bootstrap + stale service fixture
            ├── converge.yml         # Converge role by FQCN (hifra01.utils.consul)
            └── verify.yml           # Assert service state, mode, catalog API, purge, & client config
```

**Structure Decision**: Follows the standard `hifra01.utils` role layout under `roles/consul/` initialized via `ansible-galaxy role init --init-path roles consul` and `molecule init scenario default`, combining OS-specific repository setup (`setup-Debian.yml`, `setup-RedHat.yml`) with modular lifecycle task files (`install.yml`, `configure.yml`, `services.yml`).

## Complexity Tracking

No Constitution violations exist.
