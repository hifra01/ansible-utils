# Implementation Plan: Prometheus NGINX Exporter Role (`nginx_exporter`)

**Branch**: `009-nginx-exporter-role` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/009-nginx-exporter-role/spec.md`

## Summary

Create a new `hifra01.utils.nginx_exporter` Ansible role under `roles/nginx_exporter/` that installs Prometheus NGINX Exporter (`nginx-prometheus-exporter`) from official GitHub Release tarballs (with SHA256 verification against upstream `nginx-prometheus-exporter_<version>_checksums.txt` or an explicit `nginx_exporter_checksum` override) on Debian-family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat-family (`Rocky Linux 8`, `Rocky Linux 9`, `AlmaLinux`, `RHEL`) distributions. The role provisions an unprivileged `nginx_exporter` system user/group, manages `/etc/systemd/system/nginx_exporter.service`, supports flexible scrape URI configuration (`nginx_exporter_scrape_uri` as either a single URI string or list of URI strings), NGINX Plus / SSL verify / timeout / extra CLI flags, and optional TLS / HTTP Basic Authentication (`nginx_exporter_web_config` rendered to `/etc/nginx_exporter/config.yml`).

Additionally, add a first-class, opt-in `stub_status` toggle (`nginx_stub_status_enabled: false`, `nginx_stub_status_host: "127.0.0.1"`, `nginx_stub_status_port: 8080`, `nginx_stub_status_path: "/stub_status"`, `nginx_stub_status_allow: ["127.0.0.1", "::1"]`, `nginx_stub_status_access_log: "off"`) to `roles/nginx` that manages `/etc/nginx/conf.d/stub_status.conf` and preserves it during unused site cleanup across both Debian and RedHat families. Both roles are verified across all 5 CI matrix distributions via Molecule.

## Technical Context

**Language/Version**: YAML / Ansible (`ansible-core >= 2.21.0`, tested with Python 3.9–3.14)

**Primary Dependencies**: `ansible.builtin` modules (`assert`, `include_vars`, `include_tasks`, `apt`, `package`, `group`, `user`, `file`, `stat`, `command`, `set_fact`, `tempfile`, `get_url`, `unarchive`, `copy`, `template`, `meta`, `systemd`, `service`, `uri`, `slurp`, `getent`); official NGINX Prometheus Exporter GitHub Releases (`github.com/nginx/nginx-prometheus-exporter/releases`)

**Storage**:
- `roles/nginx_exporter`: Host binary at `/usr/local/bin/nginx-prometheus-exporter`, systemd unit at `/etc/systemd/system/nginx_exporter.service`, and optional web configuration at `/etc/nginx_exporter/config.yml`
- `roles/nginx`: Optional `/etc/nginx/conf.d/stub_status.conf` when `nginx_stub_status_enabled: true`

**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]`) across 5 target distro images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) for both `roles/nginx_exporter` and `roles/nginx`

**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) running `systemd` on `x86_64` (`amd64`), `aarch64` (`arm64`), or `armv7l` (`armv7`)

**Project Type**: Ansible Collection role (`hifra01.utils.nginx_exporter`) + companion enhancement in `hifra01.utils.nginx`

**Performance Goals**: Single-node convergence in `< 45s` (excluding initial network archive download); `changed=0` on second run with zero binary re-downloads and zero service restarts

**Constraints**: Must pass strict `yamllint` (2-space indent, max 160 chars, quoted octal modes) and `ansible-lint`; must work on Rocky Linux 8 where Python 3.6 requires the `python39` bootstrap without breaking `dnf` Python bindings; must not conflict with `roles/nginx`'s unused site configuration cleanup on RedHat where `nginx_site_enabled_dir` is `/etc/nginx/conf.d`

**Scale/Scope**: New Ansible role (`roles/nginx_exporter/`), companion `stub_status` feature in `roles/nginx/`, CI workflow registration in `.github/workflows/ci.yml` (4 locations), and documentation updates in `AGENTS.md`, `roles/nginx_exporter/README.md`, and `roles/nginx/README.md`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | Following `speckit-specify` → `speckit-clarify` → `speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement` in `specs/009-nginx-exporter-role/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Role and Molecule scenario will be scaffolded using `ansible-galaxy role init --init-path roles nginx_exporter` and `molecule init scenario default`. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports both `Debian` and `RedHat` families; starts `tasks/main.yml` with an `ansible.builtin.assert` platform, architecture, and input guard; all variables prefixed with `nginx_exporter_` (and `nginx_` in `roles/nginx`); OS-specific variables isolated in `vars/Debian.yml` and `vars/RedHat.yml`; internal registered variables prefixed with `_nginx_exporter_`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | Uses FQCNs exclusively, quoted octal strings (`'0640'`, `'0644'`, `'0750'`, `'0755'`), `true`/`false` booleans, version check guard before archive download, and `listen: "validate and restart nginx_exporter"` handlers that reload systemd and verify the binary (`--version`) before restarting `nginx_exporter`. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | Full Molecule scenario (`molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`) planned and verified across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) plus `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | Plan includes registering `nginx_exporter` in all 4 places in `.github/workflows/ci.yml`, documenting `roles/nginx_exporter/README.md`, `roles/nginx_exporter/meta/main.yml`, `roles/nginx/README.md`, and updating the roles table in `AGENTS.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/009-nginx-exporter-role/
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
    └── ci.yml                             # Register nginx_exporter in all 4 matrix/filter locations
AGENTS.md                                  # Add nginx_exporter to the Roles table and update nginx description
roles/
├── nginx/
│   ├── README.md                          # Document nginx_stub_status_* variables and example
│   ├── defaults/
│   │   └── main.yml                       # Add nginx_stub_status_* default variables
│   ├── tasks/
│   │   └── main.yml                       # Assert nginx_stub_status_*, template/remove stub_status.conf, exclude from cleanup
│   ├── templates/
│   │   └── stub_status.conf.j2            # NGINX stub_status server block template
│   └── molecule/
│       └── default/
│           ├── converge.yml               # Enable nginx_stub_status_enabled on port 8085 (avoiding port 8080 test vhost)
│           └── verify.yml                 # Assert /etc/nginx/conf.d/stub_status.conf and HTTP 200 Active connections
└── nginx_exporter/
    ├── README.md                          # Role documentation, variables, and examples
    ├── defaults/
    │   └── main.yml                       # User-tunable nginx_exporter_* default variables
    ├── handlers/
    │   └── main.yml                       # "validate and restart nginx_exporter" listener
    ├── meta/
    │   └── main.yml                       # Galaxy metadata (platforms: Debian, Ubuntu, EL 8/9)
    ├── tasks/
    │   ├── main.yml                       # Platform/arch/input assertions & task orchestration
    │   ├── install.yml                    # Prerequisite packages, system user/group, binary download & install
    │   └── configure.yml                  # Optional config.yml, systemd unit & service state
    ├── templates/
    │   ├── config.yml.j2                  # Optional web configuration (TLS / Basic Auth)
    │   └── nginx_exporter.service.j2      # Systemd service unit template
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
            ├── converge.yml               # Converge hifra01.utils.nginx (stub_status) + hifra01.utils.nginx_exporter
            └── verify.yml                 # Assert binary, user, service, /metrics HTTP 200, nginx_up 1, & web_config
```

**Structure Decision**: Follows the standard `hifra01.utils` role layout under `roles/nginx_exporter/` initialized via `ansible-galaxy role init --init-path roles nginx_exporter` and `molecule init scenario default`, separating installation (`tasks/install.yml`) and configuration/service management (`tasks/configure.yml`) with OS-specific variables in `vars/Debian.yml` and `vars/RedHat.yml`, plus a minimal template/task addition in `roles/nginx/` for `/etc/nginx/conf.d/stub_status.conf`.

## Complexity Tracking

No Constitution violations exist.
