# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

- **What**: Ansible Collection `hifra01.utils` — reusable Linux infrastructure roles.
- **Author**: Hilman F. Rakhmad (`hifra.dev`), license MIT.
- **Repo**: https://github.com/hifra01/ansible-utils
- **Requires**: `ansible-core >= 2.21.0` (see `meta/runtime.yml`); collection deps
  `ansible.posix >= 1.5.0`, `community.general >= 9.0.0` (see `galaxy.yml`).
- **Targets**: Debian/Ubuntu and RHEL family (Rocky/Alma). Some roles also support Alpine/Arch.

## Repository Layout

```
galaxy.yml              # Collection metadata (namespace, version, deps, build_ignore)
meta/runtime.yml        # requires_ansible
requirements.txt        # Python dev/test tooling (ansible-core, molecule, linters)
.ansible-lint           # profile: min, with a warn_list
.yamllint               # extends default, line-length 160, octal values forbidden
test-matrix.sh          # Parallel Molecule matrix runner (role x distro)
.github/workflows/ci.yml# Lint + Molecule matrix (role x distro)
.specify/               # GitHub Spec-Kit config, constitution, scripts, and templates
.agents/skills/         # Agent skills for the Spec-Kit workflow (speckit-*)
specs/                  # Feature specifications, plans, and task lists (specs/<NNN-feature>/)
plugins/                # Placeholder only (no custom plugins yet)
docs/                   # Empty
roles/<role>/           # One directory per role (see below)
scratchpad/             # GITIGNORED planning notes/prompts (mostly Indonesian)
.ansible/               # GITIGNORED – Molecule's installed copy of this collection; never edit
```

## Spec-Driven Development (Spec-Kit)

This project uses **Spec-Driven Development (SDD)** powered by [GitHub Spec-Kit](https://github.com/github/spec-kit)
(configured in `.specify/` with agent skills in `.agents/skills/speckit-*`).

### When to use SDD
- **Required**: Creating a new role, adding significant features/variables to an existing role,
  or making breaking/architectural changes across the collection.
- **Optional**: Trivial bug fixes, typo/documentation updates, or minor CI/linter adjustments
  (only skip SDD when the user explicitly requests a direct fix).

### SDD Lifecycle & Skills
Always read and follow the corresponding skill in `.agents/skills/<skill>/SKILL.md` at each phase,
and respect `.specify/memory/constitution.md` as the governing project principles:

1. **Constitution (`speckit-constitution`)** — Maintain project-wide governance principles in
   `.specify/memory/constitution.md`.
2. **Specify (`speckit-specify`)** — Run `.specify/scripts/bash/create-new-feature.sh` (via the skill)
   to create the feature branch (`<NNN-short-name>`) and `specs/<NNN-short-name>/spec.md`. Define
   supported OS families, role inputs/variables, expected system state, and idempotency guarantees.
3. **Clarify (`speckit-clarify`)** — Resolve underspecified requirements (e.g., OS support scope,
   default values, service reload vs. restart behavior, edge cases) before planning.
4. **Plan (`speckit-plan`)** — Generate `plan.md` covering role structure (`defaults/`, `vars/`,
   `tasks/`, `handlers/`, `templates/`), OS-specific dispatch (`Debian.yml`, `RedHat.yml`), and
   Molecule verification strategy across target distros.
5. **Tasks & Checklist (`speckit-tasks`, `speckit-checklist`)** — Generate dependency-ordered tasks
   in `tasks.md` (and optional quality checklists in `checklists/`).
6. **Analyze (`speckit-analyze`)** — Run cross-artifact consistency analysis across `spec.md`,
   `plan.md`, `tasks.md`, and `.specify/memory/constitution.md` before writing code.
7. **Implement & Converge (`speckit-implement`, `speckit-converge`)** — Execute tasks in order
   (scaffold role/scenario, implement tasks, register in CI, run linters and Molecule tests). Use
   `speckit-converge` to audit remaining unbuilt work against the spec if implementation is resumed.

### Roles

| Role | Purpose | OS families |
|---|---|---|
| `apt_mirror` | Override APT mirrors (legacy `.list` and DEB822 `.sources`) | Debian only |
| `consul` | HashiCorp Consul (server/client mode, advertised services) | Debian, RedHat |
| `datetime` | Install `tzdata`, set timezone (`datetime_tz`) | Debian, RedHat, Alpine, Archlinux |
| `disk_mount` | Partition, format, and persistently mount block devices via `/etc/fstab` | Debian, RedHat |
| `docker` | Docker CE/EE repo, install, `daemon.json`, docker group users, Compose stacks (`/srv/<name>`) | Debian, RedHat |
| `fluentbit` | Fluent Bit log processor (Laravel multiline, Nginx access/error, systemd, Graylog/Loki) | Debian, RedHat |
| `frankenphp` | FrankenPHP application server (Caddy + PHP-ZTS, extensions, Caddyfile, Laravel Octane) | Debian, RedHat |
| `linux_users` | Users/groups/SSH keys/sudo from a catalog + selection list | Debian, RedHat |
| `nginx` | Nginx + hardened config, dynamic sites (static/proxy/php), Cloudflare IP filter | Debian, RedHat |
| `nginx_exporter` | Prometheus NGINX Exporter (binary, systemd service, stub_status/NGINX Plus, web security) | Debian, RedHat |
| `node_exporter` | Prometheus Node Exporter (binary, systemd service, textfile collector, web security) | Debian, RedHat |
| `percona_mongodb` | Percona Server for MongoDB 8.0, replica set (single/multi-node), keyfile auth, users | Debian, RedHat |
| `percona_mysql` | Percona Server for MySQL (master/replica, GTID replication, users/dbs) | Debian, RedHat |
| `php` | Multi-version PHP + FPM (Ondřej Surý on Debian/Ubuntu, Remi on RHEL) | Debian, RedHat |
| `redis` | Redis Open Source (standalone, password auth, memory policies, RDB/AOF) | Debian, RedHat |

All roles live under `roles/` (never at the repo root or elsewhere). Each role follows the standard
`ansible-galaxy role init` skeleton plus a Molecule scenario:
`defaults/ vars/ tasks/ handlers/ meta/ templates/ tests/ molecule/default/ README.md`.

## Scaffolding (required)

**Never hand-create role or scenario skeletons.** Always generate them with the official tools,
then customize the generated files.

```bash
# 1. New role — run from the repo root; --init-path ensures it lands in roles/
ansible-galaxy role init --init-path roles <role>

# 2. New Molecule scenario — run from inside the role directory
cd roles/<role>
molecule init scenario default
```

After scaffolding:
- Start from an existing role's `molecule/default/molecule.yml` (e.g. `roles/datetime/molecule/default/molecule.yml`)
  as a baseline, and customize the scenario (`molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`) as needed
  for the role's requirements.
- Delete any generated `create.yml`/`destroy.yml` unless the role's scenario specifically requires custom instance
  lifecycle management (the Docker driver from `molecule-plugins[docker]` handles instance lifecycle by default).
- Write a `prepare.yml` tailored to the role's test scenario (prerequisites, fixtures, extra
  packages). Always keep the RHEL 8 Python bootstrap tasks from an existing role's `prepare.yml`
  at the top (see Testing), then add role-specific setup below them.
- Rewrite `converge.yml` to include the role by FQCN and write a role-specific `verify.yml` (see Testing).
- Remove unused generated directories/files (e.g. empty `files/`) and fill in placeholders in
  `meta/main.yml` and `README.md`.

## Setup & Commands

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Lint (exactly what CI runs, from repo root)
yamllint .
ansible-lint

# Molecule test via parallel matrix runner from repo root (recommended)
./test-matrix.sh -r <role>                      # Test one role across all supported distros in parallel
./test-matrix.sh -r <role> -o ubuntu2404        # Test one role on a specific distro
./test-matrix.sh                                # Test all roles across all supported distros

# Or run Molecule directly inside a role directory on ONE distro
# Default image when MOLECULE_DISTRO is unset: geerlingguy/docker-ubuntu2404-ansible
cd roles/<role>
MOLECULE_DISTRO=geerlingguy/docker-rockylinux9-ansible:latest molecule test
# To test ALL distros (the default when asked to test a role), see "Testing (Molecule)" below.

# Faster iteration
molecule converge && molecule verify && molecule destroy

# Build the collection
ansible-galaxy collection build
```

Always run `yamllint .` and `ansible-lint` before finishing a change.

## Coding Conventions

### YAML / Ansible style
- Start files with `---`. Role files typically begin with `# SPDX-License-Identifier: MIT-0`
  followed by `---` and a `# <type> file for <role>` comment. Keep this header on new files.
- **Always use FQCNs** (`ansible.builtin.package`, `community.general.timezone`, …).
- **Every task has a `name:`**, written in imperative/sentence case.
- 2-space indentation, max line length 160.
- **File modes must be quoted strings** (`mode: '0644'`) — yamllint forbids octal literals.
- Use `true`/`false` for booleans.
- `command`/`shell`/`raw` tasks must declare `changed_when` (and `failed_when` if relevant).
- Prefer idempotent modules; guard one-off commands with a `stat` check (see nginx DH params).

### Variables
- **Prefix all role variables with the role name** (`docker_users`, `nginx_sites`, `php_versions`).
- User-tunable values go in `defaults/main.yml` with a comment explaining each one.
- OS-specific values go in `vars/<ansible_os_family>.yml` (e.g. `vars/Debian.yml`, `vars/RedHat.yml`).
- Internal/temporary facts and registered vars use a leading underscore or role prefix
  (`_php_packages_to_install`, `nginx_dhparam_stat`).
- Loop variables in included task files use `loop_control.loop_var` (e.g. `php_ver`).

### Task structure patterns
- Begin `tasks/main.yml` with a platform guard:
  ```yaml
  - name: Validate supported platform
    ansible.builtin.assert:
      that:
        - ansible_os_family in ['Debian', 'RedHat']
      fail_msg: "This role only supports Debian and RedHat family systems."
  ```
- OS dispatch:
  `include_vars: "{{ ansible_os_family }}.yml"` and
  `include_tasks: "setup-{{ ansible_os_family }}.yml"`.
- Split large roles into focused task files included from `main.yml`
  (e.g. docker: `setup-repository.yml`, `install.yml`, `configure.yml`, `users.yml`).
- Handlers that touch service config should **validate before reload/restart**, grouped via
  `listen:` (see `roles/nginx/handlers/main.yml`: `"validate and reload nginx"`).

### Documentation
- Every role has a `README.md`: description, supported platforms, requirements,
  role variables (with defaults), example playbook, license. Update it when variables change.
- Keep `meta/main.yml` `galaxy_info` accurate (description, platforms, tags).

## Testing (Molecule)

### Default: test every distro

When asked to test a role with Molecule, **always run `molecule test` against all of these images**
(the same set as the CI matrix), unless the user explicitly asks for a single distro:

| Distro | Short key / Aliases | Image |
|---|---|---|
| Ubuntu 22.04 | `ubuntu2204` (`u22`) | `geerlingguy/docker-ubuntu2204-ansible:latest` |
| Ubuntu 24.04 | `ubuntu2404` (`u24`) | `geerlingguy/docker-ubuntu2404-ansible:latest` |
| Debian 12 | `debian12` (`deb12`) | `geerlingguy/docker-debian12-ansible:latest` |
| Rocky Linux 9 | `rockylinux9` (`el9`, `rocky9`) | `geerlingguy/docker-rockylinux9-ansible:latest` |
| Rocky Linux 8 | `rockylinux8` (`el8`, `rocky8`) | `geerlingguy/docker-rockylinux8-ansible:latest` |

- Prefer using `./test-matrix.sh` at the repo root, which isolates container names, Molecule
  ephemeral directories, and Ansible collection caches per `(role, distro)` worker so tests can
  run concurrently:
  ```bash
  ./test-matrix.sh -r <role>                      # All supported distros for <role> in parallel
  ./test-matrix.sh -r <role1>,<role2> -o u24,el9  # Filter specific roles and distros
  ./test-matrix.sh -c --lint                      # Lint + test all git-modified roles
  ./test-matrix.sh -l                             # Dry-run: list resolved matrix and exclusions
  ```
- Don't stop at the first failure — run every distro, then report a pass/fail summary per distro.
- Skip only distros the role doesn't support, matching the CI `exclude` list
  (e.g. `apt_mirror` → skip both Rocky images). `./test-matrix.sh` handles this automatically.
- If the user names a single distro ("test on Rocky 9 only"), run only that image
  (e.g. `./test-matrix.sh -r <role> -o rockylinux9`).

### Scenario files

- Each role has `molecule/default/` with `molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`
  (and optional extra scenarios if needed). New scenarios are created with `molecule init scenario <name>`
  from inside the role directory.
- **Scenarios are customizable per role.** `molecule.yml`, `prepare.yml`, `converge.yml`, and `verify.yml`
  can all be modified according to the role's specific requirements.
- Use an existing `molecule.yml` (Docker driver, privileged systemd container, `${MOLECULE_DISTRO}` image,
  `become_method: su`) as the baseline so the CI distro matrix works, then customize container settings,
  volumes, capabilities, environment, or test sequence if the role requires it.
- `prepare.yml` sets up anything the scenario needs before converge (e.g. nginx installs `cron`/`cronie`,
  test fixtures, pre-existing users/files to exercise idempotency or cleanup).
- `converge.yml` includes the role by FQCN (`hifra01.utils.<role>`) and sets scenario-specific vars.
- `verify.yml` must assert real, role-specific outcomes (service state, file content, command output,
  listening ports) — not just that converge succeeded.
- **Rocky/RHEL 8 quirk**: ansible-core ≥ 2.17 cannot use RHEL 8's Python 3.6. Every `prepare.yml`
  starts with tasks that install `python39` via `raw` and set `ansible_python_interpreter: /usr/bin/python3.9`
  for RHEL 8 hosts. Be careful: the `dnf` Python bindings are not available for 3.9, so package
  modules can break on Rocky 8. Check `prepare.yml` in an existing role before changing this logic.

## CI (`.github/workflows/ci.yml`)

- Triggers: push/PR to `main`, weekly cron (Sunday 00:00 UTC), manual dispatch.
- `lint` job → `yamllint .` + `ansible-lint` (Python 3.14).
- `molecule` job: matrix of role × {ubuntu2204, ubuntu2404, debian12, rockylinux9, rockylinux8};
  on push/PR only roles with changed files run (via `dorny/paths-filter`); scheduled/manual runs test all.
- `apt_mirror` is excluded from Rocky distros.

## Adding a New Role — Checklist

1. **Run the Spec-Kit workflow first**: use `speckit-specify` → `speckit-clarify` → `speckit-plan` →
   `speckit-tasks` → `speckit-analyze` to create `specs/<NNN-feature>/` (`spec.md`, `plan.md`, `tasks.md`)
   before scaffolding or writing role code.
2. Execute implementation via `speckit-implement`: from the repo root, run
   `ansible-galaxy role init --init-path roles <role>` (role must be in `roles/`).
   Keep the SPDX headers it generates.
3. Prefix variables with `<role>_`; add a platform `assert` at the top of `tasks/main.yml`.
4. Write `README.md` and fill in `meta/main.yml` (and add the role to the table in `AGENTS.md`).
5. From `roles/<role>/`, run `molecule init scenario default`, drop generated `create.yml`/`destroy.yml`
   (unless custom lifecycle tasks are needed), and configure `molecule.yml` (using an existing role's
   `molecule.yml` as baseline), `prepare.yml` (keeping the RHEL 8 bootstrap), `converge.yml`, and
   `verify.yml` according to the role's requirements.
6. Register it in `.github/workflows/ci.yml` in **all four** places:
   `detect-changes.outputs`, the `paths-filter` `filters`, `molecule.strategy.matrix.role`,
   and the `case` statement in the "Check if this role should be tested" step.
   Add `exclude` entries for unsupported distros.
7. Run `yamllint .`, `ansible-lint`, and `molecule test` on all five distro images (minus unsupported ones),
   marking completed tasks in `specs/<NNN-feature>/tasks.md`.

## Git Workflow

- Default branch: `main`.
- For Spec-Kit features, work on the sequential branch created by `.specify/scripts/bash/create-new-feature.sh`
  (`<NNN-short-name>`, matching `specs/<NNN-short-name>/`). For standalone non-SDD hotfixes, use `feature/<name>` or `fix/<name>`.
- Use Conventional Commits: `feat:`, `fix:`, `chore:`, optionally scoped — `feat(apt_mirror): …`.
- **Use the GitHub CLI (`gh`) for all GitHub interactions** — PRs, issues, releases, CI runs
  (e.g. `gh pr create`, `gh issue list`, `gh run watch`, `gh release create`).
  Never use `curl` against the API or ask the user to do something in the web UI.
- **Never `git commit` or `git push` unless the user explicitly instructs it.** Leave changes
  in the working tree; the user decides when and what to commit.

## Do / Don't

- ✅ Follow the Spec-Kit workflow (`specify` → `plan` → `tasks` → `implement`) for new roles and non-trivial changes.
- ✅ Keep changes idempotent and multi-OS; test on both Debian- and RHEL-family images.
- ✅ Bump `version` in `galaxy.yml` when releasing collection changes.
- ❌ Don't skip `spec.md`, `plan.md`, and `tasks.md` when building new roles or major role features.
- ❌ Don't hand-edit Spec-Kit engine files under `.specify/scripts/` or `.specify/templates/`; use `speckit-constitution` to update `.specify/memory/constitution.md`.
- ❌ Don't edit anything under `.ansible/` (generated) or commit `scratchpad/`, `.venv/`, `.vscode/`.
- ❌ Don't use short module names, unquoted octal modes, or unnamed tasks.
- ❌ Don't hand-craft role/scenario skeletons — use `ansible-galaxy role init --init-path roles` and
  `molecule init scenario`. Don't create roles outside `roles/`.
- ❌ Don't hardcode OS-specific package/service names in tasks — put them in `vars/<OS family>.yml`.
