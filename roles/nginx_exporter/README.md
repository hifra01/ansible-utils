# NGINX Exporter Role (`hifra01.utils.nginx_exporter`)

Ansible role to install and configure Prometheus NGINX Exporter (`nginx-prometheus-exporter`) as a systemd service from official GitHub Release binaries, with unprivileged service account management, single or multi-target scrape URI support, NGINX Plus / SSL flags, and optional TLS / Basic Auth web security configuration.

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
| `nginx_exporter_version` | `"1.4.1"` | Prometheus NGINX Exporter release version (without leading 'v') |
| `nginx_exporter_checksum` | `""` | Optional explicit SHA256 checksum digest; when empty, auto-resolved from upstream `checksums.txt` |
| `nginx_exporter_arch_map` | `{x86_64: amd64, ...}` | Mapping from `ansible_architecture` to release archive naming |
| `nginx_exporter_download_url` | `https://github.com/...` | Official GitHub Release binary archive download URL |
| `nginx_exporter_checksums_url` | `https://github.com/...` | Official GitHub Release checksums URL |
| `nginx_exporter_bin_dir` | `"/usr/local/bin"` | Directory where the `nginx-prometheus-exporter` executable is installed |
| `nginx_exporter_config_dir` | `"/etc/nginx_exporter"` | Directory storing web security configuration (`config.yml`) |
| `nginx_exporter_system_user` | `"nginx_exporter"` | Unprivileged system user executing the service |
| `nginx_exporter_system_group` | `"nginx_exporter"` | Unprivileged system group executing the service |
| `nginx_exporter_web_listen_address` | `"0.0.0.0:9113"` | Listening socket address |
| `nginx_exporter_web_telemetry_path` | `"/metrics"` | HTTP endpoint path for scraping metrics |
| `nginx_exporter_scrape_uri` | `"http://127.0.0.1:8080/stub_status"` | Target NGINX status URI(s), string or list of strings |
| `nginx_exporter_nginx_plus` | `false` | Enable NGINX Plus API scraping mode (`--nginx.plus`) |
| `nginx_exporter_ssl_verify` | `true` | Verify SSL certificates when scraping HTTPS targets |
| `nginx_exporter_timeout` | `"5s"` | Scrape timeout duration |
| `nginx_exporter_extra_flags` | `[]` | Raw extra CLI flags passed to the daemon |
| `nginx_exporter_web_config` | `{}` | Optional dictionary matching Prometheus exporter-toolkit web-config schema |
| `nginx_exporter_service_enabled` | `true` | Enable `nginx_exporter.service` at boot |
| `nginx_exporter_service_state` | `"started"` | Desired service state |

## Example Playbooks

### Basic Deployment with NGINX stub_status

```yaml
---
- name: Deploy NGINX with stub_status and NGINX Exporter
  hosts: web_servers
  become: true
  roles:
    - role: hifra01.utils.nginx
      vars:
        nginx_stub_status_enabled: true
        nginx_stub_status_host: "127.0.0.1"
        nginx_stub_status_port: 8080
        nginx_stub_status_path: "/stub_status"

    - role: hifra01.utils.nginx_exporter
      vars:
        nginx_exporter_scrape_uri: "http://127.0.0.1:8080/stub_status"
```

### Multiple Scrape Targets and Basic Authentication

```yaml
---
- name: Deploy NGINX Exporter with Multiple Scrape Targets and Basic Auth
  hosts: monitored_nodes
  become: true
  roles:
    - role: hifra01.utils.nginx_exporter
      vars:
        nginx_exporter_web_listen_address: "0.0.0.0:9113"
        nginx_exporter_scrape_uri:
          - "http://127.0.0.1:8080/stub_status"
          - "http://127.0.0.1:8081/stub_status"
        nginx_exporter_extra_flags:
          - "--log.level=info"
        nginx_exporter_web_config:
          basic_auth_users:
            prometheus: "$2b$12$xZ7zEaVjOgF6mGHmDSMcRuMz5Zvp2o4ysMEau1sCcfzgI.r4Ktsd6"
```

## License

MIT-0

## Author Information

Hilman F. Rakhmad (`hifra.dev`)
