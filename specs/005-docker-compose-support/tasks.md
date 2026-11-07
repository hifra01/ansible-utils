---
description: "Task list for Docker Compose Stack Management (docker)"
---

# Tasks: Docker Compose Stack Management (`docker`)

**Input**: Design documents from `/specs/005-docker-compose-support/`
**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule verification (`molecule test` across all 5 CI images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Ansible role**: `roles/docker/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare role template directories, Molecule DinD configuration, and test fixture structure per `plan.md`

- [X] T001 Create Molecule test templates directory and custom Compose Jinja2 test fixture in `roles/docker/molecule/default/templates/custom-compose.yml.j2`
- [X] T002 [P] Update `roles/docker/molecule/default/prepare.yml` to preserve the RHEL/Rocky 8 `python39` bootstrap and create a pre-existing unmanaged directory `/srv/unmanaged-data` with a marker file `/srv/unmanaged-data/keep.txt` to verify non-destructive `/srv` behavior (FR-002)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core role defaults, task inclusion wiring, handler flushing, and input validation assertions that MUST be complete before user stories are implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Update `roles/docker/defaults/main.yml` to define all role defaults and constraints from `data-model.md`: `docker_edition: "ce"` (`"ce" or "ee"`), `docker_daemon_config` (`Valid JSON dictionary written to /etc/docker/daemon.json`), `docker_users: []` (`List of existing Linux usernames to append to the docker group`), `docker_compose_base_dir: "/srv"` (`Absolute path on target host used as default parent directory for Compose projects (/srv/<name>)`), and `docker_compose_projects: []` (`List of Docker Compose project definitions (see Entity 2); unlisted directories in docker_compose_base_dir are never modified or deleted`)
- [X] T004 Update `roles/docker/tasks/main.yml` to flush pending handlers (`ansible.builtin.meta: flush_handlers` so any `Restart docker` from `daemon.json` finishes before Compose commands execute) and include `compose.yml` when `docker_compose_projects | length > 0`
- [X] T005 Create `roles/docker/tasks/compose.yml` with `ansible.builtin.assert` validation for `docker_compose_base_dir` and each entry in `docker_compose_projects` enforcing `data-model.md` constraints: `name` (`Non-empty string; must not contain / or ..; used to compute default directory {{ docker_compose_base_dir }}/{{ compose_project.name }} (/srv/<name>)`), `path` (`Absolute path on target host where the Compose file and .env file are stored`, default `"{{ docker_compose_base_dir }}/{{ compose_project.name }}"`), `filename` (`Non-empty filename for the Compose file inside path (e.g., compose.yml, docker-compose.yml)`, default `"compose.yml"`), `state` (`One of "present", "started", "stopped", or "absent" ("present" and "started" are equivalent)`, default `"present"`), `owner` (`Filesystem owner applied to <path>, <path>/<filename>, and <path>/.env`, default `"root"`), `group` (`Filesystem group applied to <path>, <path>/<filename>, and <path>/.env`, default `"root"`), `vars` (`Per-project variables injected into the rendering context when template or string content is evaluated`, default `{}`), `pull` (`When true, passes --pull always to docker compose up -d`, default `false`), `build` (`When true, passes --build to docker compose up -d`, default `false`), `remove_volumes` (`When state == 'absent' and true, passes -v to docker compose down to remove named volumes`, default `false`), `remove_dir` (`When state == 'absent' and true, removes the entire <path> directory (/srv/<name>) after tearing down the stack`, default `false`), and mutual exclusivity of `content` (`Inline Compose configuration (multi-line YAML string or YAML dictionary); mutually exclusive with template and src`), `template` (`Controller-side Jinja2 template path; mutually exclusive with content and src`), and `src` (`Controller-side static Compose file path; mutually exclusive with content and template`) when `state in ['present', 'started', 'stopped']`, followed by `ansible.builtin.include_tasks: compose-project.yml` with `loop_control: { loop_var: compose_project }`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Deploy and Start Docker Compose Stacks via Inline Content or Templates (Priority: P1) 🎯 MVP

**Goal**: Allow operators to declaratively define Docker Compose projects in `docker_compose_projects` using `content`, `template` (with `vars`), or `src` and optional `env` (`dict | string`), saved by default in `/srv/<name>/compose.yml`, validated via `docker compose config -q`, and started idempotently (`docker compose up -d --remove-orphans`).

**Independent Test**: Configure `docker_compose_projects` with an inline `content` project (`webapp` in default `/srv/webapp/compose.yml` with `.env`) and a `template` project (`templated_app` using `custom-compose.yml.j2` and `vars`), run the role twice, and verify that files exist with expected permissions (`'0755'`, `'0644'`, `'0600'`), containers are running, and the second run reports `changed=0`.

### Implementation for User Story 1

- [X] T006 [P] [US1] Create `roles/docker/templates/compose.yml.j2` to render `compose_project.template` via `lookup('ansible.builtin.template', compose_project.template, template_vars=(compose_project.vars | default({})) | combine({'item': compose_project, 'compose_project': compose_project}))` when `compose_project.template is defined`, serialize `compose_project.content | to_nice_yaml(indent=2)` when `compose_project.content is mapping`, and render `compose_project.content` (evaluating any Jinja2 expressions with `compose_project.vars`) when `compose_project.content is string`
- [X] T007 [P] [US1] Create `roles/docker/templates/compose.env.j2` to render `compose_project.env` (`Optional environment variables written to <path>/.env (mode: '0600'); if dict, rendered as KEY=VALUE lines` sorted by key, or raw string if `compose_project.env is string`)
- [X] T008 [US1] Create `roles/docker/tasks/compose-project.yml` implementing `state in ['present', 'started']`: create `{{ compose_project.path | default(docker_compose_base_dir ~ '/' ~ compose_project.name) }}` (`/srv/<name>`, mode `'0755'`, owner `{{ compose_project.owner | default('root') }}`, group `{{ compose_project.group | default('root') }}`), render/copy `{{ compose_project.filename | default('compose.yml') }}` (mode `'0644'`) from `compose.yml.j2` or `compose_project.src`, render `.env` (mode `'0600'`) when `compose_project.env is defined`, validate via `docker compose -f <file> config -q` (`changed_when: false`), inspect defined vs running services (`config --services` vs `ps --services --status running`), and execute `docker compose -f <file> up -d --remove-orphans` (with `--pull always` when `compose_project.pull | default(false) | bool` and `--build` when `compose_project.build | default(false) | bool`) when configuration changed or any defined service is not running
- [X] T009 [US1] Update `roles/docker/molecule/default/converge.yml` and `roles/docker/molecule/default/verify.yml` to deploy and verify User Story 1 (`webapp` in default `/srv/webapp/compose.yml` with `env`, and `templated_app` using `templates/custom-compose.yml.j2` with `vars`), asserting directory/file modes, ownership, running containers, and preservation of `/srv/unmanaged-data/keep.txt`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Update or Restart Running Docker Compose Stacks When Configuration Changes (Priority: P2)

**Goal**: Reconcile and recreate affected services automatically when a project's Compose definition or `.env` configuration changes, and support custom project directory `path`, custom `filename`, and custom `owner`/`group` overrides.

**Independent Test**: Deploy a Compose project with custom `path` (`/srv/custom-stack`), custom `filename` (`docker-compose.yml`), and custom `owner`/`group`, then update its Compose configuration or `.env` variables and verify that `docker compose up -d --remove-orphans` updates the running container and subsequent runs report `changed=0`.

### Implementation for User Story 2

- [X] T010 [US2] Enhance `roles/docker/tasks/compose-project.yml` so changes to either the rendered Compose file (`_docker_compose_file_result is changed`) or `.env` file (`_docker_compose_env_result is changed`) trigger `docker compose -f <file> up -d --remove-orphans --force-recreate` (or `up -d --remove-orphans`) to reconcile running containers with the updated configuration, while preserving custom `path`, `filename`, `owner`, and `group` attributes
- [X] T011 [US2] Extend `roles/docker/molecule/default/converge.yml` and `roles/docker/molecule/default/verify.yml` to test custom `path` (`/srv/custom-stack`), custom `filename` (`docker-compose.yml`), custom `owner`/`group`, and configuration update reconciliation (verifying updated container state and follow-up idempotency)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Stop or Remove Docker Compose Stacks (Priority: P3)

**Goal**: Support `state: stopped` (stopping running services while keeping `/srv/<name>` and `compose.yml` on disk) and `state: absent` (running `docker compose down --remove-orphans`, removing `compose.yml` and `.env` by default, and optionally removing volumes via `remove_volumes: true` and the project directory via `remove_dir: true`).

**Independent Test**: Configure a project with `state: stopped` and verify its `compose.yml` exists in `/srv/<name>` while no containers are running; then run the role in `verify.yml` with a project set to `state: absent` (testing both default file-only removal and `remove_volumes: true` + `remove_dir: true`) and verify containers, files, and directories are cleaned up as specified with `changed=0` on repeat runs.

### Implementation for User Story 3

- [X] T012 [US3] Implement `state == 'stopped'` and `state == 'absent'` lifecycle branches in `roles/docker/tasks/compose-project.yml`: for `stopped`, ensure `/srv/<name>`, Compose file, and `.env` exist and pass `config -q`, then run `docker compose -f <file> stop` only when running services exist; for `absent`, check if `<path>/<filename>` exists, tear down active resources via `docker compose -f <file> down --remove-orphans` (appending `-v` when `compose_project.remove_volumes | default(false) | bool`), remove `<path>/<filename>` and `<path>/.env`, and remove `<path>` only when `compose_project.remove_dir | default(false) | bool` is `true`
- [X] T013 [US3] Extend `roles/docker/molecule/default/converge.yml` and `roles/docker/molecule/default/verify.yml` to test `state: stopped` (`stopped_app` in `/srv/stopped_app/compose.yml`) and `state: absent` (both default file-only teardown preserving `/srv/<name>` and full teardown with `remove_volumes: true` and `remove_dir: true`)

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, collection metadata alignment, linting, and full 5-distro Molecule verification per Constitution Principle V

- [X] T014 [P] Replace placeholder content in `roles/docker/README.md`, update `roles/docker/meta/main.yml` (`min_ansible_version: "2.21.0"`), and update the `docker` role description in `AGENTS.md` to document `docker_compose_base_dir`, `docker_compose_projects`, and all project attributes (`name`, `path`, `filename`, `content`, `template`, `src`, `vars`, `env`, `state`, `owner`, `group`, `pull`, `build`, `remove_volumes`, `remove_dir`)
- [X] T015 Run `.venv/bin/yamllint .` and `.venv/bin/ansible-lint` from the repository root and resolve any lint warnings or errors across `roles/docker/` and `specs/005-docker-compose-support/`
- [X] T016 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from `roles/docker/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational phase completion
  - User Story 1 (P1): Deploy and start Compose stacks in `/srv/<name>` via `content`, `template` + `vars`, or `src` with `.env`
  - User Story 2 (P2): Reconcile configuration updates and support custom `path`, `filename`, and `owner`/`group`
  - User Story 3 (P3): Stop (`state: stopped`) or tear down (`state: absent` with `remove_volumes` / `remove_dir`) Compose stacks
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Starts immediately after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Builds on `roles/docker/tasks/compose-project.yml` from US1 to verify config update reconciliation and custom path/filename/ownership overrides
- **User Story 3 (P3)**: Extends `roles/docker/tasks/compose-project.yml` with `stopped` and `absent` lifecycle states

### Parallel Opportunities

- In **Phase 1 (Setup)**: `T001` (`molecule/default/templates/custom-compose.yml.j2`) and `T002` (`molecule/default/prepare.yml`) touch independent files and can run in parallel.
- In **Phase 3 (User Story 1)**: `T006` (`roles/docker/templates/compose.yml.j2`) and `T007` (`roles/docker/templates/compose.env.j2`) touch separate template files and can be created in parallel before `T008`.
- In **Phase 6 (Polish)**: `T014` (`roles/docker/README.md`, `roles/docker/meta/main.yml`, `AGENTS.md`) can be completed in parallel with or prior to `T015` (linters) and `T016` (5-distro Molecule test loop).

---

## Parallel Example: User Story 1 Templates

```bash
# Launch both Jinja2 templates for User Story 1 together:
Task: "T006 [P] [US1] Create roles/docker/templates/compose.yml.j2"
Task: "T007 [P] [US1] Create roles/docker/templates/compose.env.j2"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`–`T002`)
2. Complete Phase 2: Foundational (`T003`–`T005`)
3. Complete Phase 3: User Story 1 (`T006`–`T009`)
4. **STOP and VALIDATE**: Verify Compose stacks deploy to `/srv/<name>/compose.yml`, start containers, and pass idempotence

### Incremental Delivery

1. Complete Setup + Foundational → Defaults, handler flush, and input assertions ready
2. Add User Story 1 → Inline `content`, `template` + `vars`, `src`, and `.env` deployment and startup working → Verify (MVP!)
3. Add User Story 2 → Configuration update reconciliation and custom `path`/`filename`/`owner`/`group` working → Verify
4. Add User Story 3 → `state: stopped` and `state: absent` (`remove_volumes`, `remove_dir`) working → Verify
5. Complete Polish → `README.md`, `AGENTS.md`, `yamllint .`, `ansible-lint`, and full 5-distro Molecule verification

---

## Phase 7: Convergence

**Purpose**: Close remaining implementation and verification gaps identified by `/speckit.converge`

- [X] T017 [P] [US2] Expand input validation assertions in `roles/docker/tasks/compose.yml` to enforce all `data-model.md` constraints on optional project fields when defined (`path` starting with `/`, non-empty `filename`/`owner`/`group` strings, `vars is mapping`, and boolean types for `pull`, `build`, `remove_volumes`, `remove_dir`)
- [X] T018 [US2] Extend `roles/docker/molecule/default/prepare.yml`, `roles/docker/molecule/default/converge.yml`, and `roles/docker/molecule/default/verify.yml` to test custom `owner`/`group` ownership on a Compose project and verify configuration-update reconciliation (updating `.env` or `compose.yml`, asserting the running container reflects the updated configuration, and asserting idempotency on a repeat run)
- [X] T019 Configure local collection/role resolution and DinD storage driver settings in `roles/docker/molecule/default/molecule.yml` and `roles/docker/molecule/default/converge.yml`, then run `.venv/bin/yamllint .`, `.venv/bin/ansible-lint`, and `.venv/bin/molecule test` across all 5 target Linux distributions (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) to verify SC-001 through SC-005
