Docker Role (`hifra01.utils.docker`)
====================================

Ansible role to install and configure Docker (CE/EE) with multi-distro repository setup, `daemon.json` configuration, docker group user management, and Docker Compose stack management (`/srv/<name>/compose.yml`).

Supported Platforms
-------------------

- Debian 12 (Bookworm)
- Ubuntu 22.04 (Jammy Jellyfish)
- Ubuntu 24.04 (Noble Numbat)
- Rocky Linux 8 / AlmaLinux 8 / RHEL 8
- Rocky Linux 9 / AlmaLinux 9 / RHEL 9

Requirements
------------

- `ansible-core >= 2.21.0`

Role Variables
--------------

### Docker Installation & Daemon

| Variable | Default | Description |
|---|---|---|
| `docker_edition` | `"ce"` | Docker edition to install (`"ce"` or `"ee"`). |
| `docker_daemon_config` | `{"log-driver": "json-file", "log-opts": {"max-size": "10m"}}` | Dictionary rendered to `/etc/docker/daemon.json`. |
| `docker_users` | `[]` | List of system usernames to add to the `docker` group. |
| `docker_compose_base_dir` | `"/srv"` | Default base parent directory where Docker Compose projects are stored (`/srv/<name>`). |
| `docker_compose_projects` | `[]` | List of Docker Compose projects to deploy and manage. |

### Docker Compose Project Definition (`docker_compose_projects`)

Each item in `docker_compose_projects` supports the following attributes:

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | **required** | Unique name of the project. Used to derive default path `{{ docker_compose_base_dir }}/{{ name }}` (`/srv/<name>`). |
| `path` | string | `"/srv/<name>"` | Target directory where the Compose file and `.env` are stored. |
| `filename` | string | `"compose.yml"` | Name of the Docker Compose file inside `path`. |
| `content` | string / dict | optional | Inline Compose configuration (multi-line YAML string or mapping). Mutually exclusive with `template` and `src`. |
| `template` | string | optional | Path to a controller-side Jinja2 template rendered as the Compose file. Mutually exclusive with `content` and `src`. |
| `src` | string | optional | Path to a controller-side static Compose file copied to the host. Mutually exclusive with `content` and `template`. |
| `vars` | dict | `{}` | Variables exposed during template rendering. |
| `env` | dict / string | optional | Environment variables written to `<path>/.env` (`0600`). |
| `state` | string | `"present"` | Lifecycle state: `"present"`, `"started"`, `"stopped"`, or `"absent"`. |
| `owner` | string | `"root"` | Filesystem owner for project directory and files. |
| `group` | string | `"root"` | Filesystem group for project directory and files. |
| `pull` | boolean | `false` | When `true`, passes `--pull always` to `docker compose up -d`. |
| `build` | boolean | `false` | When `true`, passes `--build` to `docker compose up -d`. |
| `remove_volumes` | boolean | `false` | When `state: absent`, passes `-v` to remove named volumes. |
| `remove_dir` | boolean | `false` | When `state: absent`, deletes the entire project directory. |

Dependencies
------------

None.

Example Playbook
----------------

```yaml
---
- hosts: servers
  become: true
  roles:
    - role: hifra01.utils.docker
      vars:
        docker_users:
          - deploy
        docker_compose_projects:
          - name: webapp
            env:
              APP_PORT: "8080"
            content: |
              services:
                web:
                  image: busybox:latest
                  command: ["sh", "-c", "httpd -f -p ${APP_PORT:-8080}"]
                  restart: unless-stopped
```

License
-------

MIT

Author Information
------------------

Hilman F. Rakhmad (me@hifra.dev)
