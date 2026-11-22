# Ansible Collection - `hifra01.utils`

An Ansible Collection of reusable Linux infrastructure roles targeting Debian/Ubuntu and RHEL-family (Rocky Linux / AlmaLinux) systems.

> [!NOTE]
> This repository is **vibe-coded** (built with AI coding assistants) and is **mainly created and maintained for personal use**. Feel free to browse, reuse, or adapt anything here, but please review the roles and test them thoroughly before running them in your own environments.

## Included Roles

Each role has its own `README.md` documenting variables, defaults, and playbook examples.

| Role | Description | Supported OS Families |
| --- | --- | --- |
| [`apt_mirror`](roles/apt_mirror/README.md) | Override APT mirrors (legacy `.list` and DEB822 `.sources`) | Debian |
| [`consul`](roles/consul/README.md) | HashiCorp Consul (server/client mode and advertised services) | Debian, RedHat |
| [`datetime`](roles/datetime/README.md) | Install `tzdata` and configure system timezone | Debian, RedHat, Alpine, Archlinux |
| [`disk_mount`](roles/disk_mount/README.md) | Partition, format, and persistently mount block devices via `/etc/fstab` | Debian, RedHat |
| [`docker`](roles/docker/README.md) | Docker CE/EE repository, installation, `daemon.json`, user groups, and Compose stacks | Debian, RedHat |
| [`fluentbit`](roles/fluentbit/README.md) | Fluent Bit log processor (Laravel multiline, Nginx, systemd, Graylog/Loki) | Debian, RedHat |
| [`frankenphp`](roles/frankenphp/README.md) | FrankenPHP application server (Caddy + PHP-ZTS, extensions, Caddyfile, Laravel Octane) | Debian, RedHat |
| [`linux_users`](roles/linux_users/README.md) | Manage Linux users, groups, SSH keys, and sudo privileges from a catalog | Debian, RedHat |
| [`nginx`](roles/nginx/README.md) | Nginx with hardened config, dynamic sites (static/proxy/PHP), and Cloudflare IP filtering | Debian, RedHat |
| [`nginx_exporter`](roles/nginx_exporter/README.md) | Prometheus NGINX Exporter (`stub_status` / NGINX Plus, systemd service, web security) | Debian, RedHat |
| [`node_exporter`](roles/node_exporter/README.md) | Prometheus Node Exporter (binary install, systemd service, textfile collector, web security) | Debian, RedHat |
| [`percona_mongodb`](roles/percona_mongodb/README.md) | Percona Server for MongoDB 8.0, replica set (single/multi-node), keyfile auth, and users | Debian, RedHat |
| [`percona_mysql`](roles/percona_mysql/README.md) | Percona Server for MySQL (primary/replica, GTID replication, users, and databases) | Debian, RedHat |
| [`php`](roles/php/README.md) | Multi-version PHP + FPM (Ondřej Surý on Debian/Ubuntu, Remi on RHEL) | Debian, RedHat |
| [`redis`](roles/redis/README.md) | Redis Open Source (standalone, password auth, memory policies, RDB/AOF persistence) | Debian, RedHat |

## Requirements

- **Ansible**: `ansible-core >= 2.21.0`
- **Collection dependencies** (declared in [`galaxy.yml`](galaxy.yml)):
  - `ansible.posix >= 1.5.0`
  - `community.general >= 9.0.0`

## Installation

Install directly from GitHub using `ansible-galaxy`:

```bash
ansible-galaxy collection install git+https://github.com/hifra01/ansible-utils.git
```

Or add it to your project's `requirements.yml`:

```yaml
---
collections:
  - name: https://github.com/hifra01/ansible-utils.git
    type: git
    version: main
```

Then run:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Usage

Reference any role by its fully qualified collection name (FQCN), `hifra01.utils.<role>`:

```yaml
---
- name: Configure server basics
  hosts: all
  become: true
  roles:
    - role: hifra01.utils.datetime
      vars:
        datetime_tz: Asia/Jakarta
    - role: hifra01.utils.docker
```

## Local Development & Testing

Roles are tested with [Molecule](https://ansible.readthedocs.io/projects/molecule/) and Docker across Ubuntu (22.04, 24.04, 26.04), Debian (12, 13), and Rocky Linux (8, 9, 10).

### Prerequisites

1. Docker Engine / Docker Daemon running locally.
2. Python 3.12+ (matching `ansible-core >= 2.21.0`).

### Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Linting

```bash
yamllint .
ansible-lint
```

### Running Molecule Tests

Use the included parallel matrix runner [`test-matrix.sh`](test-matrix.sh) from the repository root:

```bash
# Test one role across all supported distros in parallel
./test-matrix.sh -r datetime

# Test one role on a specific distro
./test-matrix.sh -r datetime -o ubuntu2404

# Lint and test only git-modified roles
./test-matrix.sh -c --lint

# List the full resolved test matrix without running tests
./test-matrix.sh -l
```

Or run Molecule directly inside a role directory (defaults to `geerlingguy/docker-ubuntu2404-ansible`):

```bash
cd roles/datetime
molecule test

# Override the target distro image
MOLECULE_DISTRO=geerlingguy/docker-rockylinux9-ansible:latest molecule test
```

## License

MIT — see [`galaxy.yml`](galaxy.yml).

## Author

Hilman F. Rakhmad ([hifra.dev](https://hifra.dev))
