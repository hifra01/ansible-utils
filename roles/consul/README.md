# Consul Role (`hifra01.utils.consul`)

Ansible role to install and configure HashiCorp Consul in either `server` or `client` mode from official HashiCorp repositories, with per-node advertised service definitions, automatic stale service purging, and pre-reload configuration validation.

## Supported Platforms

* **Debian Family**: Debian 12 (Bookworm), Ubuntu 22.04 (Jammy), Ubuntu 24.04 (Noble)
* **RedHat Family**: Rocky Linux 8 & 9, AlmaLinux 8 & 9, RHEL 8 & 9

## Requirements

* `ansible-core >= 2.21.0`
* Requires systemd init system on target hosts.
* Fact gathering (`gather_facts: true`) must be enabled.

## Role Variables

| Variable | Default | Description |
|---|---|---|
| `consul_mode` | `"client"` | Operational mode: `"server"` or `"client"` |
| `consul_bootstrap_expect` | `1` | Number of expected server nodes for Raft bootstrap (only used when `consul_mode == "server"`) |
| `consul_datacenter` | `"dc1"` | Datacenter identifier |
| `consul_node_name` | `"{{ inventory_hostname }}"` | Node name in Consul catalog |
| `consul_config_dir` | `"/etc/consul.d"` | Path to Consul configuration directory |
| `consul_data_dir` | `"/opt/consul"` | Path to Consul data directory |
| `consul_user` | `"consul"` | System user owning Consul directories |
| `consul_group` | `"consul"` | System group owning Consul directories |
| `consul_bind_addr` | `"0.0.0.0"` | Network bind address |
| `consul_advertise_addr` | `"{{ ansible_default_ipv4.address \| default('127.0.0.1') }}"` | Advertised cluster address |
| `consul_client_addr` | `"127.0.0.1"` | Client interface address |
| `consul_ui` | `false` | Enable Consul Web UI |
| `consul_log_level` | `"INFO"` | Logging verbosity (`"TRACE"`, `"DEBUG"`, `"INFO"`, `"WARN"`, `"ERR"`) |
| `consul_retry_join` | `[]` | List of cluster peer addresses for auto-join |
| `consul_encrypt` | `""` | Optional gossip encryption key |
| `consul_extra_config` | `{}` | Optional dictionary rendered to `/etc/consul.d/extra.json` |
| `consul_services` | `[]` | List of advertised services on this host |
| `consul_services_purge` | `true` | Purge unmanaged `service-*.json` files from config directory |
| `consul_package_name` | `"consul"` | Package name to install |
| `consul_package_state` | `"present"` | Package installation state (`"present"` or `"latest"`) |

### Service Definition Structure (`consul_services`)

Each item in `consul_services` supports:
* `name`: Service name (required string)
* `id`: Service instance ID (optional string, defaults to `name`)
* `port`: Service listening port (optional integer)
* `address`: Service IP/host override (optional string)
* `tags`: List of string tags (optional)
* `meta`: Dictionary of key-value metadata strings (optional)
* `checks`: List of health check definitions (optional, supporting `http`, `tcp`, `args`, `interval`, `timeout`, `deregister_critical_service_after`)

## Example Playbooks

### Deploy a Bootstrap Consul Server

```yaml
---
- name: Deploy Consul Server
  hosts: consul_servers
  become: true
  roles:
    - role: hifra01.utils.consul
      vars:
        consul_mode: "server"
        consul_bootstrap_expect: 1
        consul_ui: true
        consul_client_addr: "0.0.0.0"
```

### Deploy a Consul Client Node Advertising Services

```yaml
---
- name: Deploy Consul Client with Advertised Services
  hosts: app_servers
  become: true
  roles:
    - role: hifra01.utils.consul
      vars:
        consul_mode: "client"
        consul_retry_join:
          - "10.0.0.10"
        consul_services:
          - name: "web"
            id: "web-80"
            port: 80
            tags:
              - "http"
              - "production"
            meta:
              version: "1.0.0"
            checks:
              - id: "web-tcp"
                name: "TCP Port 80"
                tcp: "127.0.0.1:80"
                interval: "10s"
                timeout: "2s"
```

## License

MIT-0

## Author Information

Hilman F. Rakhmad (`hifra.dev`)
