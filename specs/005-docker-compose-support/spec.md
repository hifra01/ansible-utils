# Feature Specification: Docker Compose Stack Management (`docker`)

**Feature Branch**: `005-docker-compose-support`

**Created**: 2026-11-07

**Status**: Draft

**Input**: User description: "update role docker to allow user to add and run docker compose file. docker compose file by default saved in \"/srv/<name>\" directory. name branch based on speckit convention"

## Clarifications

### Session 2026-11-07

- Q: When a Docker Compose project is set to `state: absent`, how should the role handle its `/srv/<name>` directory and Docker volumes? (FR-003) → A: Remove only the managed Compose and `.env` files by default; add optional `remove_volumes: true` (`-v`) and `remove_dir: true` flags for full data/directory purge.
- Q: How should the role handle pre-existing subdirectories in `/srv` that are not listed in `docker_compose_projects`? (FR-002) → A: Only manage projects listed in `docker_compose_projects`; leave any other directories in `/srv` untouched.
- Q: What filesystem ownership (`owner` and `group`) should be applied to the project directory (`/srv/<name>`), Compose file, and `.env` file? (FR-005) → A: Default to `root:root` with optional per-project `owner` and `group` attributes on each `docker_compose_projects` item.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy and Start Docker Compose Stacks via Inline Content or Templates (Priority: P1)

Infrastructure operators need to declaratively define one or more Docker Compose projects on a target host, have each project's Compose file placed in `/srv/<name>` by default, and have the Compose services started automatically as part of applying the `docker` role.

**Why this priority**: The primary purpose of this feature is to let operators deploy and run multi-container workloads using Docker Compose directly from their Ansible inventory/playbook variables without creating separate custom playbooks or manually copying Compose files to `/srv/<name>`.

**Independent Test**: Can be fully tested by configuring `docker_compose_projects` with an entry defining `name: myapp` and inline Compose content (or a template/source file), running the role, and verifying that `/srv/myapp/compose.yml` exists with the expected content and the Compose project's services are running.

**Acceptance Scenarios**:

1. **Given** a target host with the `docker` role applied and a Compose project entry with `name: "webapp"` and inline Compose content (`content`), **When** the role executes, **Then** the directory `/srv/webapp` is created, `/srv/webapp/compose.yml` is written with the specified content, and the Compose stack is started (`up -d`).
2. **Given** a Compose project entry specifying a custom Jinja2 template (`template`) or static file (`src`) along with optional per-project variables (`vars`) or environment variables (`env`), **When** the role executes, **Then** the Compose file (and optional `.env` file) is rendered in `/srv/<name>` and the stack is running.
3. **Given** an already converged host where the Compose file and `.env` file have not changed and the containers are running, **When** the role is re-run with identical variables, **Then** the run completes with zero changed tasks (strict idempotency).

---

### User Story 2 - Update or Restart Running Docker Compose Stacks When Configuration Changes (Priority: P2)

Infrastructure operators need changes to a project's Docker Compose definition or environment configuration to automatically reconcile and recreate affected services when the role is re-applied, and to support overriding the project directory path or filename when needed.

**Why this priority**: Day-2 operations require updating image tags, environment variables, ports, or volumes and having the running Compose stack reflect those updates deterministically, as well as accommodating hosts that store stacks in custom paths.

**Independent Test**: Can be independently tested by modifying the Compose definition or environment variables of an already-running project in `docker_compose_projects` (or specifying a custom `path`), re-running the role, and verifying that the updated Compose file is written and affected services are recreated/updated cleanly.

**Acceptance Scenarios**:

1. **Given** an existing running Compose project in `/srv/<name>`, **When** the operator updates the project's Compose definition or environment variables and re-runs the role, **Then** the updated configuration is written to disk and `docker compose up -d` reconciles the running containers to match the new configuration.
2. **Given** a Compose project entry with a custom directory `path` (or custom global base directory `docker_compose_base_dir`), **When** the role executes, **Then** the Compose project directory and file are created at the overridden path instead of `/srv/<name>` and the stack is started from that directory.

---

### User Story 3 - Stop or Remove Docker Compose Stacks (Priority: P3)

Infrastructure operators need the ability to stop or tear down a managed Docker Compose project (and optionally remove its project directory and volumes) by changing its desired state in the role variables, without leaving orphaned containers running or accidentally destroying persistent data.

**Why this priority**: Lifecycle management of Compose workloads requires a clean way to decommission or temporarily stop stacks via Ansible state declarations rather than manual SSH intervention.

**Independent Test**: Can be independently tested by changing a running project's `state` from `present` (or `started`) to `stopped` or `absent`, re-running the role, and verifying that the project's containers are stopped or removed as requested.

**Acceptance Scenarios**:

1. **Given** a running Compose project in `/srv/<name>`, **When** its entry in `docker_compose_projects` is set to `state: stopped`, **Then** the role stops the running Compose services while preserving `/srv/<name>` and the Compose file on disk.
2. **Given** a running Compose project in `/srv/<name>`, **When** its entry in `docker_compose_projects` is set to `state: absent`, **Then** the role brings the Compose stack down (`docker compose down --remove-orphans`, adding `-v` only when `remove_volumes: true`), removes the managed Compose and `.env` files by default, and deletes `/srv/<name>` only when `remove_dir: true` is set.

---

### Edge Cases

- **No Compose projects configured (default)**: When `docker_compose_projects` is empty (`[]`), the role completes its existing Docker installation, daemon configuration, and user group management without creating anything in `/srv` or running any Compose commands.
- **Pre-existing or unlisted subdirectories in `/srv`**: The role strictly manages only the projects explicitly listed in `docker_compose_projects` and never modifies, stops, or deletes unlisted directories in `docker_compose_base_dir` (`/srv`).
- **Invalid Compose configuration syntax**: Before attempting to bring up a Compose stack, the role validates the rendered Compose file (`docker compose config -q`) so syntax or schema errors fail fast with a clear error message before disrupting running containers.
- **Multiple mutually exclusive source options**: If a single Compose project entry defines more than one of `content`, `src`, or `template` (or none of them when `state` is `present`/`started`), the role fails fast during input validation with a clear assertion message.
- **Invalid or empty project `name`**: If a project entry omits `name` or contains path traversal characters (such as `/` or `..`), the role fails immediately during assertion validation.
- **Idempotent check when stack is already running vs. manually stopped**: If a container in a `present`/`started` project was stopped outside of Ansible, re-running the role detects that the service is not in the desired running state and starts it (reporting `changed`), whereas if all services in the project are already running and configurations are unchanged, the role reports `ok` (`changed: false`).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The role MUST maintain platform validation at the start of `tasks/main.yml` ensuring the target host belongs to a supported OS family (`Debian` or `RedHat`) and ensure `docker-compose-plugin` (`docker compose` CLI v2) is installed as part of Docker package installation.
- **FR-002**: The role MUST provide user-tunable defaults in `defaults/main.yml` prefixed with `docker_`, and MUST only manage projects explicitly listed in `docker_compose_projects` (leaving any other directories in `docker_compose_base_dir` untouched):
  - `docker_compose_base_dir` (string, default `"/srv"` — base parent directory for Compose projects)
  - `docker_compose_projects` (list of dictionaries, default `[]` — list of Docker Compose projects to manage)
- **FR-003**: Each item in `docker_compose_projects` MUST support the following attributes:
  - `name` (required string): Unique identifier for the Compose project, used to derive the default directory `{{ docker_compose_base_dir }}/{{ item.name }}` (i.e., `/srv/<name>`).
  - `path` (optional string, default `"{{ docker_compose_base_dir }}/{{ item.name }}"`): Target directory on the remote host where the Compose file is stored.
  - `filename` (optional string, default `"compose.yml"`): Name of the Docker Compose file inside the project directory.
  - Source definition (mutually exclusive, required when `state` is `present`, `started`, or `stopped` if not already present):
    - `content` (optional string/YAML): Inline Docker Compose configuration content (either a YAML string or an Ansible dictionary serialized to YAML).
    - `template` (optional string): Path to a Jinja2 template on the Ansible controller to render as the Compose file.
    - `src` (optional string): Path to a static Compose file on the Ansible controller to copy to the target host.
  - `vars` (optional dictionary, default `{}`): Per-project variables exposed when rendering `template` or `content`.
  - `env` (optional dictionary or string): Environment variables to write to `.env` inside the project directory (`0600` permissions) for Compose variable interpolation.
  - `state` (optional string, default `"present"`): Desired lifecycle state of the Compose stack:
    - `"present"` or `"started"`: Ensure the project directory and Compose file exist and run the Compose stack (`docker compose up -d --remove-orphans`).
    - `"stopped"`: Ensure the project directory and Compose file exist and stop running services (`docker compose stop`).
    - `"absent"`: Tear down the Compose stack (`docker compose down --remove-orphans`, appending `-v` when `remove_volumes: true`), remove the managed Compose file and `.env` file by default, and remove the project directory (`{{ item.path | default(docker_compose_base_dir ~ '/' ~ item.name) }}`) only when `remove_dir: true`.
  - `remove_volumes` (optional boolean, default `false`): When `state: absent`, whether to pass `-v` to `docker compose down` to remove named volumes declared in the Compose file.
  - `remove_dir` (optional boolean, default `false`): When `state: absent`, whether to delete the entire project directory (`/srv/<name>`) instead of only removing the managed Compose and `.env` files.
  - `owner` (optional string, default `"root"`): Filesystem owner for the project directory, Compose file, and `.env` file.
  - `group` (optional string, default `"root"`): Filesystem group for the project directory, Compose file, and `.env` file.
  - `pull` (optional boolean, default `false`): Whether to pull images before starting or updating the stack (`--pull always` when true).
  - `build` (optional boolean, default `false`): Whether to build images when starting or updating the stack (`--build` when true).
- **FR-004**: The role MUST validate all entries in `docker_compose_projects` via `ansible.builtin.assert` before making changes, checking that:
  - `name` is defined, non-empty, and does not contain `/` or `..`.
  - `state` (if specified) is one of `present`, `started`, `stopped`, or `absent`.
  - For projects with `state` in `['present', 'started', 'stopped']`, exactly one of `content`, `template`, or `src` is provided.
- **FR-005**: For each non-absent project in `docker_compose_projects`, the role MUST create the target directory (`/srv/<name>` by default) with mode `'0755'`, write the Compose file (`compose.yml` by default) with mode `'0644'`, write the `.env` file with mode `'0600'` when `env` is defined (all owned by `item.owner | default('root')` and `item.group | default('root')`), and validate the resulting Compose configuration using `docker compose -f <file> config -q` before applying state changes.
- **FR-006**: When a project's `state` is `present` or `started`, the role MUST ensure all services defined in the Compose file are started and reconciled when the Compose file or `.env` file changes or when any service in the stack is not currently running, and MUST report `changed: false` on subsequent runs when no configuration changed and the stack is already running.
- **FR-007**: All tasks in the role MUST comply with collection standards (FQCNs, descriptive task names, quoted file modes, `loop_control.loop_var` on included task loops, strict idempotency, and zero `yamllint` / `ansible-lint` warnings or errors).

### Key Entities

- **Compose Project (`docker_compose_projects` item)**: Represents a managed Docker Compose application stack identified by `name`, stored by default in `/srv/<name>/compose.yml`, with a source definition (`content`, `template`, or `src`), optional `.env` variables (`env`), and lifecycle state (`present`/`started`, `stopped`, `absent`).
- **Project Directory (`/srv/<name>`)**: The host filesystem directory holding the project's Compose file (`compose.yml`) and optional `.env` file, defaulting to `{{ docker_compose_base_dir }}/{{ item.name }}` where `docker_compose_base_dir` is `/srv`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can define one or more Docker Compose stacks in `docker_compose_projects` and have the role create `/srv/<name>/compose.yml` and start the containers across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in a single playbook run.
- **SC-002**: Re-running the role on a host with active Compose stacks and unchanged variables produces 0 changed tasks across 100% of tested distributions.
- **SC-003**: Updating a project's Compose definition or changing its `state` to `stopped` or `absent` accurately updates, stops, or removes the corresponding containers and files on the first run and reports 0 changed tasks on the immediate follow-up run.
- **SC-004**: 100% of YAML and Ansible files in the repository pass `yamllint .` and `ansible-lint` with 0 errors.

## Assumptions

- Target hosts run Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) or RedHat-family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL) distributions and have access to container registries referenced by user-supplied Compose files (or local images during offline tests).
- The `docker-compose-plugin` package (already included in `docker_packages_ce` and `docker_packages_ee`) provides the `docker compose` v2 subcommand used to validate and manage Compose stacks, avoiding external Python library dependencies (`PyYAML` / `docker` SDK on remote hosts) so it works out-of-the-box on all supported distros including Rocky Linux 8 with Python 3.9.
- By default, each Compose project is stored in `/srv/<name>/compose.yml` (customizable globally via `docker_compose_base_dir: "/srv"` and per project via `path` and `filename`).
- If `content` is provided as a YAML dictionary/mapping rather than a string, the role serializes it with `to_nice_yaml(indent=2)` so users can write native YAML structures directly in Ansible variables as well as raw multi-line YAML strings.
