# Data Model: Docker Compose Stack Management (`docker`)

**Feature**: `005-docker-compose-support`  
**Date**: 2026-11-07

## Entities

### 1. Global Docker Role Configuration (`docker_*` variables in `roles/docker/defaults/main.yml`)

Represents host-wide Docker installation, daemon configuration, user access, and Compose project defaults.

| Field / Variable | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `docker_edition` | `string` | `"ce"` | Yes | `"ce"` or `"ee"` |
| `docker_daemon_config` | `dict` | `{"log-driver": "json-file", "log-opts": {"max-size": "10m"}}` | Yes | Valid JSON dictionary written to `/etc/docker/daemon.json` |
| `docker_users` | `list[string]` | `[]` | Yes | List of existing Linux usernames to append to the `docker` group |
| `docker_compose_base_dir` | `string` | `"/srv"` | Yes | Absolute path on target host used as default parent directory for Compose projects (`/srv/<name>`) |
| `docker_compose_projects` | `list[ComposeProject]` | `[]` | Yes | List of Docker Compose project definitions (see Entity 2); unlisted directories in `docker_compose_base_dir` are never modified or deleted |

---

### 2. Compose Project Definition (`docker_compose_projects` list item)

Represents a single Docker Compose stack managed on the target host.

| Field | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `name` | `string` | — | **Yes** | Non-empty string; must not contain `/` or `..`; used to compute default directory `{{ docker_compose_base_dir }}/{{ compose_project.name }}` (`/srv/<name>`) |
| `path` | `string` | `"{{ docker_compose_base_dir }}/{{ compose_project.name }}"` | No | Absolute path on target host where the Compose file and `.env` file are stored |
| `filename` | `string` | `"compose.yml"` | No | Non-empty filename for the Compose file inside `path` (e.g., `compose.yml`, `docker-compose.yml`) |
| `content` | `string \| dict` | Omitted | Conditional | Inline Compose configuration (multi-line YAML string or YAML dictionary); **mutually exclusive** with `template` and `src` |
| `template` | `string` | Omitted | Conditional | Controller-side Jinja2 template path; **mutually exclusive** with `content` and `src` |
| `src` | `string` | Omitted | Conditional | Controller-side static Compose file path; **mutually exclusive** with `content` and `template` |
| `vars` | `dict` | `{}` | No | Per-project variables injected into the rendering context when `template` or string `content` is evaluated |
| `env` | `dict \| string` | Omitted | No | Optional environment variables written to `<path>/.env` (`mode: '0600'`); if `dict`, rendered as `KEY=VALUE` lines |
| `state` | `string` | `"present"` | No | One of `"present"`, `"started"`, `"stopped"`, or `"absent"` (`"present"` and `"started"` are equivalent) |
| `owner` | `string` | `"root"` | No | Filesystem owner applied to `<path>`, `<path>/<filename>`, and `<path>/.env` |
| `group` | `string` | `"root"` | No | Filesystem group applied to `<path>`, `<path>/<filename>`, and `<path>/.env` |
| `pull` | `boolean` | `false` | No | When `true`, passes `--pull always` to `docker compose up -d` |
| `build` | `boolean` | `false` | No | When `true`, passes `--build` to `docker compose up -d` |
| `remove_volumes` | `boolean` | `false` | No | When `state == 'absent'` and `true`, passes `-v` to `docker compose down` to remove named volumes |
| `remove_dir` | `boolean` | `false` | No | When `state == 'absent'` and `true`, removes the entire `<path>` directory (`/srv/<name>`) after tearing down the stack |

---

### 3. Host Filesystem Artifacts (per Compose Project)

| Path | Mode | Owner / Group | Active When | Purpose |
|---|---|---|---|---|
| `{{ path }}` (default `/srv/{{ name }}`) | `'0755'` | `{{ owner }}:{{ group }}` (`root:root`) | `state in ['present', 'started', 'stopped']` (or `state == 'absent'` with `remove_dir: false`) | Project working directory on target host |
| `{{ path }}/{{ filename }}` (default `/srv/{{ name }}/compose.yml`) | `'0644'` | `{{ owner }}:{{ group }}` (`root:root`) | `state in ['present', 'started', 'stopped']` | Rendered Docker Compose file validated by `docker compose config -q` |
| `{{ path }}/.env` (default `/srv/{{ name }}/.env`) | `'0600'` | `{{ owner }}:{{ group }}` (`root:root`) | `env is defined` and `state in ['present', 'started', 'stopped']` | Environment file automatically loaded by `docker compose` |

## Relationships & State Transitions

1. **Input Validation (`tasks/compose.yml`)**:
   - Before touching the filesystem or containers, every entry in `docker_compose_projects` is validated:
     - `name` is defined, non-empty string, and matches `^[^/]+$` without `..`.
     - `state | default('present') in ['present', 'started', 'stopped', 'absent']`.
     - When `state | default('present') in ['present', 'started', 'stopped']`, `[compose_project.content is defined, compose_project.template is defined, compose_project.src is defined] | select('equalto', true) | list | length == 1`.

2. **Lifecycle Transitions (`tasks/compose-project.yml`)**:
   - **`present` / `started`**:
     - Create `{{ path }}` (`'0755'`).
     - Render/copy `{{ path }}/{{ filename }}` (`'0644'`) and optional `{{ path }}/.env` (`'0600'`).
     - Validate via `docker compose -f {{ path }}/{{ filename }} config -q`.
     - Compare defined services (`config --services`) with running services (`ps --services --status running`).
     - Run `docker compose -f {{ path }}/{{ filename }} up -d --remove-orphans` (plus `--pull always` / `--build` if enabled) if the Compose file changed, `.env` changed, or any defined service is not running.
   - **`stopped`**:
     - Create `{{ path }}` (`'0755'`), render/copy `{{ path }}/{{ filename }}` (`'0644'`) and optional `{{ path }}/.env` (`'0600'`), and validate via `config -q`.
     - Check running services (`ps --services --status running`).
     - If any service is running, execute `docker compose -f {{ path }}/{{ filename }} stop`.
   - **`absent`**:
     - If `{{ path }}/{{ filename }}` exists on disk, inspect active/stopped project resources (`ps -a -q` or networks) and run `docker compose -f {{ path }}/{{ filename }} down --remove-orphans` (with `-v` if `remove_volumes: true`).
     - Remove `{{ path }}/{{ filename }}` and `{{ path }}/.env` (`state: absent`).
     - If `remove_dir: true`, remove `{{ path }}` (`state: absent`); otherwise leave `{{ path }}` intact.
