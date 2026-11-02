# hifra01.utils Ansible Collection Constitution

## Core Principles

### I. Spec-Driven Role Development
Every new role, significant feature or variable addition, or breaking change across the
collection MUST follow the Spec-Kit workflow (`speckit-specify` → `speckit-clarify` →
`speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement`) with design
artifacts tracked in `specs/<NNN-feature>/` before scaffolding or writing role code. Only
trivial bug fixes, documentation typos, or minor CI/linter adjustments MAY bypass the full
Spec-Kit lifecycle when explicitly requested by the user. Rationale: upfront specification
prevents variable naming drift, unspoken OS assumptions, and incomplete verification across
roles.

### II. Official CLI Scaffolding & Role Isolation
All roles MUST reside under `roles/<role>/` and MUST be initialized using the official CLI
tools (`ansible-galaxy role init --init-path roles <role>` and `molecule init scenario default`)
before customization. Role or scenario skeletons MUST NOT be hand-crafted. Generated collection
copies under `.ansible/` and Spec-Kit engine files under `.specify/scripts/` and
`.specify/templates/` MUST NOT be manually edited. Rationale: standardized scaffolding
guarantees consistent directory layout, SPDX headers, and Galaxy metadata across the collection.

### III. Multi-OS Portability & Variable Discipline
Roles MUST support both Debian-family (Ubuntu/Debian) and RedHat-family (Rocky/Alma) systems
unless the role is inherently OS-specific (e.g., `apt_mirror`), and `tasks/main.yml` MUST begin
with an `ansible.builtin.assert` platform guard. All role variables MUST be prefixed with
`<role>_`, user-tunable defaults MUST be documented in `defaults/main.yml`, and OS-specific
package or service names MUST be isolated in `vars/<ansible_os_family>.yml` rather than
hardcoded in tasks. Internal or registered variables MUST use a leading underscore or the
`<role>_` prefix, and included task loops MUST define `loop_control.loop_var`. Rationale:
strict variable namespacing and OS dispatch prevent collisions when roles are composed in
playbooks across heterogeneous Linux fleets.

### IV. Idempotency & Strict Ansible/YAML Hygiene
All tasks MUST be idempotent, use Fully Qualified Collection Names (FQCNs), and declare a
descriptive `name:` in imperative sentence case. YAML files MUST start with `---` (preserving
`# SPDX-License-Identifier: MIT-0` headers on role files), use 2-space indentation, keep lines
within 160 characters, use `true`/`false` for booleans, and quote octal file modes as strings
(e.g., `mode: '0644'`). Tasks invoking `command`, `shell`, or `raw` MUST declare `changed_when`
(and `failed_when` where applicable) or guard one-off commands with `stat` checks. Service
configuration handlers MUST validate configuration before reloading or restarting, grouped via
`listen:`. Rationale: deterministic, lint-clean tasks prevent unintended service restarts and
configuration drift in production.

### V. Linter & Multi-Distro Molecule Verification (NON-NEGOTIABLE)
Every change MUST pass `yamllint .` and `ansible-lint` from the repository root without errors.
Every role MUST maintain a Molecule scenario under `roles/<role>/molecule/default/` (customized
from an existing role's baseline `molecule.yml`, `prepare.yml` with the RHEL 8 Python 3.9
bootstrap, `converge.yml` using the role FQCN `hifra01.utils.<role>`, and `verify.yml` asserting
real system state such as services, files, ports, and command output). When testing a role,
`molecule test` MUST be executed sequentially across all supported CI matrix images (Ubuntu
22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) unless the user explicitly scopes
a run to a single distribution. Rationale: multi-distro container verification is the only
reliable proof that packaging, systemd units, and Python interpreters work across target OS
families.

## Technical Stack & Collection Constraints

- **Runtime & Dependencies**: Requires `ansible-core >= 2.21.0` (`meta/runtime.yml`) and
  collection dependencies `ansible.posix >= 1.5.0` and `community.general >= 9.0.0`
  (`galaxy.yml`). Python development and testing tooling MUST match `requirements.txt`
  (`ansible-core >= 2.21.0`, `molecule >= 26.8.0`, `molecule-plugins[docker] >= 26.7.15`,
  `ansible-lint >= 8.5.0`, `yamllint >= 1.35.0`).
- **Role Documentation**: Every role MUST maintain an up-to-date `README.md` (description,
  supported platforms, requirements, role variables with defaults, example playbook, license)
  and accurate `meta/main.yml` `galaxy_info`, and MUST be listed in the roles table in
  `AGENTS.md`.
- **CI Matrix Registration**: Every new role MUST be registered in `.github/workflows/ci.yml` in
  all four required locations (`detect-changes.outputs`, `paths-filter` `filters`,
  `molecule.strategy.matrix.role`, and the role-check `case` statement), with explicit `exclude`
  entries for any unsupported distributions.

## Development Workflow & Quality Gates

- **Branching**: Spec-Kit features MUST use the sequential branch created by
  `.specify/scripts/bash/create-new-feature.sh` (`<NNN-short-name>`, matching
  `specs/<NNN-short-name>/`). Standalone non-SDD hotfixes MUST use `feature/<name>` or
  `fix/<name>` off `main`.
- **Commits & Git Control**: Commit messages MUST follow Conventional Commits (`feat:`, `fix:`,
  `chore:`, optionally scoped such as `feat(nginx): ...`). Coding agents MUST NOT run
  `git commit` or `git push` unless the user explicitly instructs it; changes MUST remain in the
  working tree for user review.
- **GitHub Interactions**: All GitHub operations (PRs, issues, releases, workflow runs) MUST use
  the GitHub CLI (`gh`), never raw API `curl` calls or manual web UI instructions.
- **Artifact Hygiene**: Scratch notes (`scratchpad/`), virtual environments (`.venv/`), editor
  configs (`.vscode/`), and generated collection directories (`.ansible/`) MUST NOT be committed.

## Governance

This Constitution supersedes ad-hoc practices within the `hifra01.utils` repository. All feature
specifications (`spec.md`), implementation plans (`plan.md`), task lists (`tasks.md`), and pull
requests MUST verify compliance with these principles during `/speckit-plan` and
`/speckit-analyze` gates. Runtime agent guidance is maintained in `AGENTS.md` and MUST stay
synchronized with this Constitution.

Amendments to this Constitution MUST be executed via `/speckit-constitution`, documented with a
Sync Impact Report, and versioned according to Semantic Versioning:
- **MAJOR**: Backward-incompatible removal or redefinition of a Core Principle or quality gate.
- **MINOR**: Addition of a new Core Principle, section, or materially expanded governance rule.
- **PATCH**: Wording clarifications, typo fixes, or non-semantic refinements.

**Version**: 1.1.0 | **Ratified**: 2026-10-17 | **Last Amended**: 2026-11-01
