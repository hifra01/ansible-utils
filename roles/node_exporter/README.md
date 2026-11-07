# Node Exporter Role (`hifra01.utils.node_exporter`)

Ansible role to install and configure Prometheus Node Exporter as a systemd service from official GitHub Release binaries, with unprivileged service account management, textfile collector support, and optional TLS / Basic Auth web security configuration.

## Supported Platforms

* **Debian Family**: Debian 12 (Bookworm), Ubuntu 22.04 (Jammy), Ubuntu 24.04 (Noble)
* **RedHat Family**: Rocky Linux 8 & 9, AlmaLinux 8 & 9, RHEL 8 & 9
* **Architectures**: `x86_64` (`amd64`), `aarch64` (`arm64`), `armv7l` (`armv7`)

## Requirements

* `ansible-core >= 2.21.0`
* Requires systemd init system on target hosts.
* Fact gathering (`gather_facts: true`) must be enabled.

## Role Variables

| Variable | Default | Description |
|---|---|---|
| `node_exporter_version` | `"1.8.2"` | Node Exporter release version (without leading 'v') |
| `node_exporter_checksum` | `""` | Optional explicit SHA256 checksum digest; when empty, auto-resolved from upstream `sha256sums.txt` |
| `node_exporter_arch_map` | `{x86_64: amd64, ...}` | Mapping from `ansible_architecture` to release archive naming |
| `node_exporter_download_url` | `https://github.com/...` | Official GitHub Release binary archive download URL |
| `node_exporter_checksums_url` | `https://github.com/...` | Official GitHub Release `sha256sums.txt` URL |
| `node_exporter_bin_dir` | `"/usr/local/bin"` | Directory where the `node_exporter` executable is installed |
| `node_exporter_config_dir` | `"/etc/node_exporter"` | Directory storing web security configuration (`config.yml`) |
| `node_exporter_textfile_dir` | `"/var/lib/node_exporter/textfile_collector"` | Local directory for custom `.prom` textfile metrics |
| `node_exporter_system_user` | `"node_exporter"` | Unprivileged system user executing the service |
| `node_exporter_system_group` | `"node_exporter"` | Unprivileged system group executing the service |
| `node_exporter_web_listen_address` | `"0.0.0.0:9100"` | Listening socket address |
| `node_exporter_web_telemetry_path` | `"/metrics"` | HTTP endpoint path for scraping metrics |
| `node_exporter_enabled_collectors` | `[]` | List of collectors to explicitly enable (`--collector.<name>`) |
| `node_exporter_disabled_collectors` | `[]` | List of collectors to explicitly disable (`--no-collector.<name>`) |
| `node_exporter_extra_flags` | `[]` | Raw extra CLI flags passed to the daemon |
| `node_exporter_web_config` | `{}` | Optional dictionary matching Prometheus exporter-toolkit web-config schema |

## Example Playbooks

### Basic Deployment

```yaml
---
- name: Deploy Prometheus Node Exporter
  hosts: all
  become: true
  roles:
    - role: hifra01.utils.node_exporter
```

### Custom Collectors and Basic Authentication

```yaml
---
- name: Deploy Node Exporter with Custom Collectors and Basic Auth
  hosts: monitored_nodes
  become: true
  roles:
    - role: hifra01.utils.node_exporter
      vars:
        node_exporter_web_listen_address: "0.0.0.0:9100"
        node_exporter_enabled_collectors:
          - processes
          - filesystem:
              mount-points-exclude: "^/(sys|proc|dev|host|etc)($|/)"
        node_exporter_disabled_collectors:
          - arp
        node_exporter_web_config:
          basic_auth_users:
            prometheus: "$2b$12$hNf2lSsxfm0.i4a.1k2SOVyBCf551VRWrB0324/MPQ.1yG6ia1kG"
```

## License

MIT-0

## Author Information

Hilman F. Rakhmad (`hifra.dev`)
