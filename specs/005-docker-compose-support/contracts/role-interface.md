# Role Interface Contract: `hifra01.utils.docker`

**Feature**: `005-docker-compose-support`  
**Date**: 2026-11-07

## 1. Public Role Variables (`roles/docker/defaults/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# defaults file for docker

docker_edition: "ce"

# Base configuration for Docker daemon.json
docker_daemon_config:
  log-driver: "json-file"
  log-opts:
    max-size: "10m"

# List of users to add to the docker group
docker_users: []

# Base parent directory where Docker Compose projects are saved by default (/srv/<name>)
docker_compose_base_dir: "/srv"

# List of Docker Compose projects to deploy and manage
docker_compose_projects: []

# Repository configuration
docker_repo_url_ce: "https://download.docker.com/linux"
docker_repo_url_ee: "https://repos.mirantis.com"
docker_repo_url: "{{ docker_repo_url_ce if docker_edition == 'ce' else docker_repo_url_ee }}"

# CentOS repository is used for RHEL-based systems (CentOS, RedHat, Rocky, Alma)
docker_rhel_repo_dist: "centos"

# APT architecture mapping for Debian/Ubuntu
docker_apt_arch_map:
  x86_64: amd64
  aarch64: arm64
  armv7l: armhf
docker_apt_arch: "{{ docker_apt_arch_map[ansible_architecture] | default(ansible_architecture) }}"

# Packages to install based on edition
docker_packages_ce:
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - docker-buildx-plugin
  - docker-compose-plugin

docker_packages_ee:
  - docker-ee
  - docker-ee-cli
  - containerd.io
  - docker-buildx-plugin
  - docker-compose-plugin

docker_packages: "{{ docker_packages_ce if docker_edition == 'ce' else docker_packages_ee }}"
```

## 2. `docker_compose_projects` Schema & Examples

```yaml
docker_compose_projects:
  # 1. Inline YAML string (saved to /srv/webapp/compose.yml by default)
  - name: webapp
    state: present
    env:
      APP_PORT: "8080"
      APP_ENV: "production"
    content: |
      services:
        web:
          image: busybox:latest
          command: ["sh", "-c", "httpd -f -p ${APP_PORT:-8080}"]
          restart: unless-stopped

  # 2. Inline YAML dictionary (serialized to YAML automatically)
  - name: cache
    state: present
    content:
      services:
        redis:
          image: redis:7-alpine
          restart: unless-stopped

  # 3. Controller-side Jinja2 template with variable injection and custom path/ownership
  - name: monitoring
    path: "/srv/monitoring-stack"
    filename: "docker-compose.yml"
    owner: "root"
    group: "docker"
    template: "templates/monitoring-compose.yml.j2"
    vars:
      scrape_interval: "15s"
      listen_port: 9090
    pull: false
    build: false
    state: present

  # 4. Stopped stack (files deployed & validated in /srv/maintenance, containers stopped)
  - name: maintenance
    state: stopped
    content: |
      services:
        worker:
          image: busybox:latest
          command: ["sh", "-c", "sleep 3600"]

  # 5. Teardown stack (brings stack down and removes compose.yml + .env; optionally removes volumes & directory)
  - name: legacy_app
    state: absent
    remove_volumes: true
    remove_dir: true
```

## 3. Generated Host Filesystem Contract

### Project Directory (`{{ item.path | default(docker_compose_base_dir ~ '/' ~ item.name) }}`)
- **Default Path**: `/srv/<name>`
- **Owner/Group**: `{{ item.owner | default('root') }}:{{ item.group | default('root') }}`
- **Mode**: `'0755'`
- **Cleanup Behavior**:
  - Unlisted subdirectories in `docker_compose_base_dir` (`/srv`) are never modified or deleted.
  - On `state: absent`, `/srv/<name>` is preserved by default (only the managed Compose file and `.env` file are removed), or deleted completely when `remove_dir: true` is set.

### Compose File (`{{ project_dir }}/{{ item.filename | default('compose.yml') }}`)
- **Default Path**: `/srv/<name>/compose.yml`
- **Owner/Group**: `{{ item.owner | default('root') }}:{{ item.group | default('root') }}`
- **Mode**: `'0644'`
- **Validation**: Validated via `docker compose -f <file> config -q` prior to running `up` or `stop`.

### Environment File (`{{ project_dir }}/.env`)
- **Default Path**: `/srv/<name>/.env` (created only when `item.env` is defined)
- **Owner/Group**: `{{ item.owner | default('root') }}:{{ item.group | default('root') }}`
- **Mode**: `'0600'`
