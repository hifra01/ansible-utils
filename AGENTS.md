# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

- **What**: Ansible Collection `hifra01.utils` — reusable Linux infrastructure roles.
- **Author**: Hilman F. Rakhmad (`hifra.dev`), license MIT.
- **Repo**: https://github.com/hifra01/ansible-utils
- **Requires**: `ansible-core >= 2.15` (see `meta/runtime.yml`); collection deps
  `ansible.posix >= 1.5.0`, `community.general >= 9.0.0` (see `galaxy.yml`).
- **Targets**: Debian/Ubuntu and RHEL family (Rocky/Alma). Some roles also support Alpine/Arch.

## Repository Layout

```
galaxy.yml              # Collection metadata (namespace, version, deps, build_ignore)
meta/runtime.yml        # requires_ansible
requirements.txt        # Python dev/test tooling (ansible-core, molecule, linters)
.ansible-lint           # profile: min, with a warn_list
.yamllint               # extends default, line-length 160, octal values forbidden
.github/workflows/ci.yml# Lint + Molecule matrix (role x distro)
plugins/                # Placeholder only (no custom plugins yet)
docs/                   # Empty
roles/<role>/           # One directory per role (see below)
scratchpad/             # GITIGNORED planning notes/prompts (mostly Indonesian)
.ansible/               # GITIGNORED – Molecule's installed copy of this collection; never edit
```

### Roles

| Role | Purpose | OS families |
|---|---|---|
| `apt_mirror` | Override APT mirrors (legacy `.list` and DEB822 `.sources`) | Debian only |
| `datetime` | Install `tzdata`, set timezone (`datetime_tz`) | Debian, RedHat, Alpine, Archlinux |
| `docker` | Docker CE/EE repo, install, `daemon.json`, docker group users | Debian, RedHat |
| `linux_users` | Users/groups/SSH keys/sudo from a catalog + selection list | Debian, RedHat |
| `nginx` | Nginx + hardened config, dynamic sites (static/proxy/php), Cloudflare IP filter | Debian, RedHat |
| `php` | Multi-version PHP + FPM (Ondřej Surý on Debian/Ubuntu, Remi on RHEL) | Debian, RedHat |

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
- Replace the generated `molecule/default/molecule.yml` with the shared one from an existing role
  (e.g. `roles/datetime/molecule/default/molecule.yml`) — it must stay identical across roles.
- Delete any generated `create.yml`/`destroy.yml`
  (the Docker driver from `molecule-plugins[docker]` handles instance lifecycle).
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

# Molecule test a role on ONE distro (requires a running Docker daemon)
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

| Distro | Image |
|---|---|
| Ubuntu 22.04 | `geerlingguy/docker-ubuntu2204-ansible:latest` |
| Ubuntu 24.04 | `geerlingguy/docker-ubuntu2404-ansible:latest` |
| Debian 12 | `geerlingguy/docker-debian12-ansible:latest` |
| Rocky Linux 9 | `geerlingguy/docker-rockylinux9-ansible:latest` |
| Rocky Linux 8 | `geerlingguy/docker-rockylinux8-ansible:latest` |

- Run them one after another from `roles/<role>/` by setting `MOLECULE_DISTRO` per run.
  Don't stop at the first failure — run every distro, then report a pass/fail summary per distro.
- Skip only distros the role doesn't support, matching the CI `exclude` list
  (e.g. `apt_mirror` → skip both Rocky images). Say which ones were skipped and why.
- If the user names a single distro ("test on Rocky 9 only"), run only that image.

```bash
cd roles/<role>
for img in \
  geerlingguy/docker-ubuntu2204-ansible:latest \
  geerlingguy/docker-ubuntu2404-ansible:latest \
  geerlingguy/docker-debian12-ansible:latest \
  geerlingguy/docker-rockylinux9-ansible:latest \
  geerlingguy/docker-rockylinux8-ansible:latest; do
  echo "=== $img"
  MOLECULE_DISTRO="$img" molecule test && echo "PASS $img" || echo "FAIL $img"
done
```

### Scenario files

- Each role has `molecule/default/` with `molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`.
  New scenarios are created with `molecule init scenario <name>` from inside the role directory.
- **Only `molecule.yml` is shared.** `prepare.yml`, `converge.yml`, and `verify.yml` are
  role- and scenario-specific; write them to fit what the role does and what the scenario tests.
- `molecule.yml` is **identical across all roles** (Docker driver, privileged systemd container,
  `${MOLECULE_DISTRO}` image, `become_method: su`). Keep it in sync; overwrite the generated one for new roles.
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

1. From the repo root, run `ansible-galaxy role init --init-path roles <role>` (role must be in `roles/`).
   Keep the SPDX headers it generates.
2. Prefix variables with `<role>_`; add a platform `assert` at the top of `tasks/main.yml`.
3. Write `README.md` and fill in `meta/main.yml`.
4. From `roles/<role>/`, run `molecule init scenario default`, then replace `molecule.yml` with the
   shared version, drop generated `create.yml`/`destroy.yml`, and write role-specific `prepare.yml`
   (keeping the RHEL 8 bootstrap), `converge.yml`, and `verify.yml` for the test scenario.
5. Register it in `.github/workflows/ci.yml` in **all four** places:
   `detect-changes.outputs`, the `paths-filter` `filters`, `molecule.strategy.matrix.role`,
   and the `case` statement in the "Check if this role should be tested" step.
   Add `exclude` entries for unsupported distros.
6. Run `yamllint .`, `ansible-lint`, and `molecule test` on all five distro images (minus unsupported ones).

## Git Workflow

- Default branch: `main`. Work on `feature/<name>` branches and open PRs.
- Use Conventional Commits: `feat:`, `fix:`, `chore:`, optionally scoped — `feat(apt_mirror): …`.

## Do / Don't

- ✅ Keep changes idempotent and multi-OS; test on both Debian- and RHEL-family images.
- ✅ Bump `version` in `galaxy.yml` when releasing collection changes.
- ❌ Don't edit anything under `.ansible/` (generated) or commit `scratchpad/`, `.venv/`, `.vscode/`.
- ❌ Don't use short module names, unquoted octal modes, or unnamed tasks.
- ❌ Don't hand-craft role/scenario skeletons — use `ansible-galaxy role init --init-path roles` and
  `molecule init scenario`. Don't create roles outside `roles/`.
- ❌ Don't hardcode OS-specific package/service names in tasks — put them in `vars/<OS family>.yml`.
