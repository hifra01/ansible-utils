# Phase 0 Research: Docker Compose Stack Management (`docker`)

**Feature**: `005-docker-compose-support`  
**Date**: 2026-11-07

## 1. Docker Compose Execution Engine (`docker compose` CLI v2 vs `community.docker` Collection)

- **Decision**:
  - Implement Docker Compose project lifecycle management using `ansible.builtin` modules (`file`, `copy`, `template`, `stat`, `command`, `assert`) driving the `docker compose` CLI v2 (`docker-compose-plugin`, which is already installed by `roles/docker/tasks/install.yml`).
  - Do **not** add `community.docker` as a collection dependency in `galaxy.yml`.
- **Rationale**:
  - `galaxy.yml` currently depends only on `ansible.posix >= 1.5.0` and `community.general >= 9.0.0`. Adding a new external collection dependency when `docker-compose-plugin` is already installed on every target host is unnecessary.
  - Using `docker compose` CLI v2 directly via `ansible.builtin.command` works out-of-the-box across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8), including Rocky Linux 8 where Ansible runs under `/usr/bin/python3.9` without extra remote Python packages.
  - Gives explicit control over `docker compose config -q` pre-validation before modifying running stacks.
- **Alternatives Considered**:
  - *`community.docker.docker_compose_v2`*: Rejected because it requires adding `community.docker` to `galaxy.yml` and `requirements.txt`, whereas `docker compose` CLI v2 is already guaranteed present by `docker_packages_ce` / `docker_packages_ee`.

## 2. Flexible Compose File Sources (`content`, `template`, `src`) & `.env` File Rendering

- **Decision**:
  - Support three mutually exclusive source options on each item in `docker_compose_projects`:
    1. `content` (string or YAML mapping): Inline Compose content. If `content` is a mapping (`content is mapping`), serialize it with `content | to_nice_yaml(indent=2)`; if `content` is a string, render it directly (supporting Jinja2 interpolation with `vars` via `lookup('ansible.builtin.template', ...)` or `roles/docker/templates/compose.yml.j2`).
    2. `template` (string): Controller-side Jinja2 template path rendered via `lookup('ansible.builtin.template', compose_project.template, template_vars=(compose_project.vars | default({})) | combine({'item': compose_project, 'compose_project': compose_project}))`.
    3. `src` (string): Controller-side static Compose file copied via `ansible.builtin.copy`.
  - Support an optional `env` attribute on each project:
    - When `env` is a mapping (`env is mapping`), render `KEY=VALUE` lines sorted by key to `<project_dir>/.env` with mode `'0600'`.
    - When `env` is a string (`env is string`), write the string content to `<project_dir>/.env` with mode `'0600'`.
    - When `env` is omitted, do not create or overwrite `<project_dir>/.env`.
- **Rationale**:
  - Mirrors the proven `lookup('ansible.builtin.template', ..., template_vars=...)` pattern used in `roles/nginx/templates/site.conf.j2` (`002-nginx-custom-cf-proxies`), allowing per-project `vars` to be referenced both as top-level variables (`{{ app_port }}`) and via `{{ item.vars.app_port }}`.
  - Allowing `content` to be either a raw multi-line YAML string or a native YAML dictionary in Ansible host/group vars provides ergonomic flexibility for playbook authors.
- **Alternatives Considered**:
  - *Only supporting static `src` files*: Rejected because operators frequently want inline Compose definitions in `group_vars`/`host_vars` or parameterized Jinja2 templates.

## 3. Idempotent Lifecycle & State Detection (`present`/`started`, `stopped`, `absent`)

- **Decision**:
  - Split per-project execution into `roles/docker/tasks/compose.yml` (validation + loop) and `roles/docker/tasks/compose-project.yml` (per-project tasks with `loop_control: { loop_var: compose_project }`).
  - Before managing Compose stacks, flush handlers (`ansible.builtin.meta: flush_handlers`) so any pending `Restart docker` from `daemon.json` changes completes before `docker compose` commands run.
  - **For `state: present` (default) or `state: started`**:
    1. Ensure project directory (`{{ compose_project.path | default(docker_compose_base_dir ~ '/' ~ compose_project.name) }}`, i.e., `/srv/<name>`) exists with mode `'0755'`, `owner: "{{ compose_project.owner | default('root') }}"`, `group: "{{ compose_project.group | default('root') }}"`.
    2. Write Compose file (`{{ compose_project.filename | default('compose.yml') }}`, mode `'0644'`) and optional `.env` file (mode `'0600'`), registering `_docker_compose_file_result` and `_docker_compose_env_result`.
    3. Validate configuration using `docker compose -f <compose_file> config -q` (`changed_when: false`).
    4. Query current service state using:
       - `docker compose -f <compose_file> config --services` (lists defined services)
       - `docker compose -f <compose_file> ps --services --status running` (lists currently running services)
       Both tasks run with `changed_when: false`.
    5. Run `docker compose -f <compose_file> up -d --remove-orphans` (with optional `--pull always` when `compose_project.pull | default(false) | bool` and `--build` when `compose_project.build | default(false) | bool`) **when**:
       - `_docker_compose_file_result is changed`, OR
       - `_docker_compose_env_result is changed`, OR
       - the set of running services does not include all defined services (`(_docker_compose_defined_services.stdout_lines | difference(_docker_compose_running_services.stdout_lines)) | length > 0`), OR
       - `compose_project.pull | default(false) | bool` or `compose_project.build | default(false) | bool` is enabled (in which case check output for actual container recreation).
  - **For `state: stopped`**:
    1. Ensure project directory, Compose file, and optional `.env` file exist and pass `docker compose config -q`.
    2. Check running services with `docker compose -f <compose_file> ps --services --status running` (`changed_when: false`).
    3. Run `docker compose -f <compose_file> stop` only when `_docker_compose_running_services.stdout_lines | length > 0`.
  - **For `state: absent`**:
    1. Stat the Compose file (`<project_dir>/<filename>`).
    2. If the Compose file exists, check if any project containers/networks exist (`docker compose -f <compose_file> ps -a -q` or `docker network ls`) and run `docker compose -f <compose_file> down --remove-orphans{{ ' -v' if (compose_project.remove_volumes | default(false) | bool) else '' }}`.
    3. Remove `<project_dir>/<filename>` and `<project_dir>/.env` via `ansible.builtin.file: state: absent`.
    4. When `compose_project.remove_dir | default(false) | bool` is `true`, remove `<project_dir>` (`state: absent`); otherwise preserve `<project_dir>` and any other files inside it.
- **Rationale**:
  - Checking config changes + comparing `config --services` against `ps --services --status running` guarantees 100% deterministic idempotency (`changed=0` on second run) without relying on fragile stderr string parsing across different `docker compose` v2 releases.
  - Flushing handlers before Compose tasks prevents a race condition where `daemon.json` notifies `Restart docker` at the end of the play and stops containers that were started during `compose.yml`.
- **Alternatives Considered**:
  - *Always running `docker compose up -d` and parsing stderr for `"Started"`/`"Recreated"`*: Considered as secondary check, but skipping `up -d` altogether when neither config changed nor any service is stopped is faster, cleaner, and avoids unnecessary registry metadata calls on second runs.

## 4. Molecule Docker-in-Docker (DinD) Verification Strategy Across 5 Distros

- **Decision**:
  - In `roles/docker/molecule/default/`:
    - Keep `molecule.yml` privileged with `/sys/fs/cgroup:/sys/fs/cgroup:rw` and `cgroupns_mode: host`.
    - Configure `docker_daemon_config` in `converge.yml` (or default test vars) with `"storage-driver": "vfs"` (or let Docker select `vfs`/`overlay2` appropriately inside privileged container) if needed so nested `dockerd` inside Molecule's Docker container can start inner containers reliably across all 5 distros (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`).
    - Test all user stories in `converge.yml` and `verify.yml`:
      1. Project 1 (`webapp` in default `/srv/webapp/compose.yml`): inline `content` + `.env` (`env`), `state: present` -> verify `/srv/webapp/compose.yml`, `/srv/webapp/.env` (`0600`), and running container.
      2. Project 2 (`templated_app` in custom `path: /srv/custom-stack` with `template` + `vars` + `owner`/`group`) -> verify rendered template, ownership, and running container.
      3. Project 3 (`stopped_app` with `state: stopped`) -> verify `/srv/stopped_app/compose.yml` exists and no containers are running.
      4. Pre-existing unmanaged directory `/srv/unmanaged-data` created in `prepare.yml` -> verify it remains completely untouched.
      5. Teardown (`state: absent`) verified in `verify.yml` (both default file-only removal and `remove_dir: true` + `remove_volumes: true` cleanup).
- **Rationale**:
  - Nested Docker inside a Docker container (DinD) often fails to mount `overlay2` on top of an outer `overlay2` filesystem unless `/var/lib/docker` is a Docker volume or `storage-driver: vfs` is used in Molecule. Adding `/var/lib/docker` as a volume in `molecule.yml` or setting `storage-driver: vfs` in Molecule `converge.yml` ensures reliable container creation across all 5 Linux distributions.
- **Alternatives Considered**:
  - *Mounting host `/var/run/docker.sock` into the Molecule container*: Rejected because the role installs and starts the target distro's own `docker` systemd service and `daemon.json`, which would conflict with the host's Docker socket.
