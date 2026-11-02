# Ansible Role: `hifra01.utils.nginx`

Ansible role for installing, hardening, and configuring Nginx with dynamic virtual hosts, custom site configurations, variable-injected Jinja2 site templates, Cloudflare real-IP and geo blocking, and configurable trusted upstream proxies.

## Supported Platforms

- Ubuntu 22.04 (Jammy)
- Ubuntu 24.04 (Noble)
- Debian 12 (Bookworm)
- Rocky Linux 8 / RHEL 8 / AlmaLinux 8
- Rocky Linux 9 / RHEL 9 / AlmaLinux 9

## Requirements

- `ansible-core >= 2.21.0`
- Target hosts must run `systemd`

## Role Variables

Settable variables with default values (defined in `defaults/main.yml`):

### Global Hardening & Performance Parameters

```yaml
nginx_server_tokens: "off"
nginx_client_max_body_size: "10m"
nginx_client_body_buffer_size: "128k"
nginx_client_header_buffer_size: "1k"
nginx_large_client_header_buffers: "4 4k"

nginx_security_headers_enabled: true

# SSL/TLS global configuration
nginx_ssl_protocols: "TLSv1.2 TLSv1.3"
nginx_ssl_ciphers: >-
  ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
nginx_ssl_prefer_server_ciphers: "on"
```

### Cloudflare & Trusted Proxies

```yaml
# Set true to add Cloudflare IPs as trusted proxies (conf.d/cloudflare.conf) globally
# without forcing sites to block non-Cloudflare traffic
nginx_cloudflare_enabled: false

# Upstream proxy IP addresses or CIDR blocks trusted for real-IP resolution
nginx_trusted_proxies:
  - "::1"
  - "127.0.0.1"

# Real IP header used in standalone trusted_proxies.conf (when Cloudflare is inactive)
nginx_real_ip_header: "X-Forwarded-For"

# Real IP recursive resolution ("on" or "off")
nginx_real_ip_recursive: "on"
```

### Virtual Hosts (`nginx_sites`)

Each item in `nginx_sites` supports:

- **Built-in archetypes**: `type: static | proxy | php`
  - `domains`: list of server names (default `["_"]`)
  - `listen`: port or listen directive (default `80`)
  - `root`: web root directory (for `static` and `php`, default `/var/www/html`)
  - `index`: index files list
  - `try_files`: try_files directive
  - `proxy_pass`: upstream URL (when `type: proxy`)
  - `proxy_set_headers`: boolean (default `true`)
  - `fastcgi_pass`: FastCGI socket or address (when `type: php`)
  - `custom_headers`: list of `{ name, value, always }`
- **Inline Custom Configuration**:
  - `custom_config`: raw Nginx configuration string rendered as the entire virtual host `.conf` file
  - `vars`: optional dictionary of variables injected into template context
- **Custom Template File**:
  - `template`: path to a controller-side Jinja2 template rendered as the entire virtual host `.conf` file
  - `vars`: optional dictionary of variables injected into template context
- **Cloudflare Directives**:
  - `cloudflare_real_ip`: boolean (default `false`). When `true`, enables Cloudflare trusted proxy configuration (`conf.d/cloudflare.conf`) without blocking non-Cloudflare traffic on this site.
  - `cloudflare_filter`: boolean (default `false`). When `true`, enables Cloudflare trusted proxy configuration AND includes `allow-cloudflare-only.conf` inside the site's `server {}` block to return HTTP `403` for non-Cloudflare/non-trusted IPs.

```yaml
nginx_enabled_sites:
  - default
```

## Example Playbook

```yaml
---
- name: Deploy hardened Nginx with custom templates and Cloudflare integration
  hosts: web_servers
  become: true
  roles:
    - role: hifra01.utils.nginx
      vars:
        # Trust Cloudflare IPs globally for real-IP resolution
        nginx_cloudflare_enabled: true

        # Trust local and internal load balancer networks
        nginx_trusted_proxies:
          - "::1"
          - "127.0.0.1"
          - "10.0.0.0/8"

        nginx_sites:
          # 1. Public static site (unwraps CF-Connecting-IP, allows direct traffic)
          - name: public_portal
            listen: 80
            domains: ["portal.example.com"]
            type: static
            root: /var/www/portal
            cloudflare_filter: false

          # 2. Protected backend (blocks non-Cloudflare / non-trusted traffic with 403)
          - name: admin_app
            listen: 80
            domains: ["admin.example.com"]
            type: proxy
            proxy_pass: "http://127.0.0.1:8080"
            cloudflare_filter: true

          # 3. Custom inline virtual host with variable interpolation
          - name: custom_inline
            custom_config: |
              server {
                  listen {{ listen_port }};
                  server_name {{ server_name }};
                  location /healthz {
                      return 200 "ok\n";
                  }
              }
            vars:
              listen_port: 8081
              server_name: "health.example.com"

          # 4. Custom Jinja2 template with per-site variables
          - name: custom_templated
            template: "templates/my_vhost.conf.j2"
            vars:
              app_port: 9000
              backend_service: "http://127.0.0.1:9000"

        nginx_enabled_sites:
          - public_portal
          - admin_app
          - custom_inline
          - custom_templated
```

## License

MIT-0 / MIT

## Author Information

Hilman F. Rakhmad (hifra.dev)
