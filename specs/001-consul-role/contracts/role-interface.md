# Role Interface Contract: `hifra01.utils.consul`

**Feature**: `001-consul-role`  
**Date**: 2026-10-18

## 1. Public Role Variables (`roles/consul/defaults/main.yml`)

```yaml
# Operational mode for this Consul node: "server" or "client"
consul_mode: "client"

# Number of expected server nodes for Raft cluster bootstrap (only used when consul_mode == "server")
consul_bootstrap_expect: 1

# Consul datacenter name
consul_datacenter: "dc1"

# Node name registered in the Consul catalog
consul_node_name: "{{ inventory_hostname }}"

# Directories and system ownership
consul_config_dir: "/etc/consul.d"
consul_data_dir: "/opt/consul"
consul_user: "consul"
consul_group: "consul"

# Network bindings
consul_bind_addr: "0.0.0.0"
consul_advertise_addr: "{{ ansible_default_ipv4.address | default('127.0.0.1') }}"
consul_client_addr: "127.0.0.1"

# UI & logging
consul_ui: false
consul_log_level: "INFO"

# Cluster join & security
consul_retry_join: []
consul_encrypt: ""

# Additional arbitrary top-level Consul configuration (rendered to /etc/consul.d/extra.json when non-empty)
consul_extra_config: {}

# Services to advertise on this host
consul_services: []

# Remove unmanaged service-*.json files from consul_config_dir
consul_services_purge: true

# Package & repository settings
consul_package_name: "consul"
consul_package_state: "present"
consul_apt_repo_url: "https://apt.releases.hashicorp.com"
consul_apt_gpg_url: "https://apt.releases.hashicorp.com/gpg"
consul_apt_arch_map:
  x86_64: amd64
  aarch64: arm64
  armv7l: armhf
consul_apt_arch: "{{ consul_apt_arch_map[ansible_architecture] | default(ansible_architecture) }}"
consul_rhel_repo_url: "https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo"
```

## 2. OS-Specific Variables (`roles/consul/vars/<ansible_os_family>.yml`)

### `roles/consul/vars/Debian.yml`
```yaml
consul_prerequisite_packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
consul_service_name: "consul"
```

### `roles/consul/vars/RedHat.yml`
```yaml
consul_prerequisite_packages:
  - yum-utils
consul_service_name: "consul"
```

## 3. Generated File Contracts

### `/etc/consul.d/consul.hcl`
- **Owner/Group**: `consul:consul`
- **Mode**: `'0640'`
- **Structure**:
  ```hcl
  # Managed by Ansible (hifra01.utils.consul)
  datacenter = "dc1"
  node_name = "node-1"
  data_dir = "/opt/consul"
  log_level = "INFO"
  server = true
  bootstrap_expect = 1
  bind_addr = "0.0.0.0"
  advertise_addr = "10.0.0.10"
  client_addr = "127.0.0.1"

  ui_config {
    enabled = true
  }
  ```

### `/etc/consul.d/service-<id>.json`
- **Owner/Group**: `consul:consul`
- **Mode**: `'0640'`
- **Structure**:
  ```json
  {
    "service": {
      "checks": [
        {
          "interval": "10s",
          "tcp": "127.0.0.1:80",
          "timeout": "2s"
        }
      ],
      "id": "web-http",
      "meta": {
        "env": "production"
      },
      "name": "web",
      "port": 80,
      "tags": [
        "http",
        "frontend"
      ]
    }
  }
  ```

## 4. Handler Contract (`roles/consul/handlers/main.yml`)

- **Listener `"validate and reload consul"`**:
  1. `Validate consul configuration for reload`: runs `consul validate {{ consul_config_dir }}` (`changed_when: false`)
  2. `Reload consul`: reloads `{{ consul_service_name }}` (`state: reloaded`)
- **Listener `"validate and restart consul"`**:
  1. `Validate consul configuration for restart`: runs `consul validate {{ consul_config_dir }}` (`changed_when: false`)
  2. `Restart consul`: restarts `{{ consul_service_name }}` (`state: restarted`)
