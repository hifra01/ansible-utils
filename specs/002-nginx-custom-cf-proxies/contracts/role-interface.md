# Role Interface Contract: `hifra01.utils.nginx`

**Feature**: `002-nginx-custom-cf-proxies`  
**Date**: 2026-11-02

## 1. Public Role Variables (`roles/nginx/defaults/main.yml`)

```yaml
---
# Global Nginx hardening and buffer parameters
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

# Cloudflare & Trusted Proxies configuration
# Set nginx_cloudflare_enabled: true to add Cloudflare IPs as trusted proxies (conf.d/cloudflare.conf)
# without forcing sites to block non-Cloudflare traffic.
nginx_cloudflare_enabled: false
nginx_trusted_proxies:
  - "::1"
  - "127.0.0.1"
nginx_real_ip_header: "X-Forwarded-For"
nginx_real_ip_recursive: "on"

# Dynamic site configuration structure
nginx_sites:
  - name: default
    domains:
      - "_"
    listen: 80
    root: /var/www/html
    type: static
    index:
      - index.html
      - index.htm
    try_files: "$uri $uri/ =404"
    cloudflare_real_ip: false
    cloudflare_filter: false

# List of site names that should be enabled on the host
nginx_enabled_sites:
  - default
```

## 2. Custom Site & Template Schema (`nginx_sites` items)

```yaml
nginx_sites:
  # 1. Inline full custom configuration
  - name: custom_inline
    custom_config: |
      server {
          listen {{ listen_port }};
          server_name {{ server_domain }};
          location / {
              return 200 "inline custom ok\n";
          }
      }
    vars:
      listen_port: 8081
      server_domain: "inline.example.local"

  # 2. Controller-side custom Jinja2 template with variable injection
  - name: custom_templated
    template: "custom_site.conf.j2"
    vars:
      listen_port: 8082
      upstream_backend: "http://127.0.0.1:8081"
      enable_cf_guard: true
```

## 3. Generated File Contracts

### `/usr/local/bin/update_cloudflare_ips.sh`
- **Owner/Group**: `root:root`
- **Mode**: `'0755'`
- **Behavior**:
  - Fetches `https://www.cloudflare.com/ips-v4/` and `https://www.cloudflare.com/ips-v6/`.
  - Writes `/etc/nginx/conf.d/cloudflare.conf`:
    ```nginx
    # Local / Trusted Proxies
    set_real_ip_from ::1;
    set_real_ip_from 127.0.0.1;
    # https://www.cloudflare.com/ips

    # IPv4
    set_real_ip_from 173.245.48.0/20;
    ...

    # IPv6
    set_real_ip_from 2400:cb00::/32;
    ...

    # Real IP Configuration
    real_ip_header CF-Connecting-IP;
    real_ip_recursive on;

    # Geo IP mapping based on original connecting TCP IP
    geo $realip_remote_addr $is_cloudflare {
        default 0;
        ::1 1;
        127.0.0.1 1;
        173.245.48.0/20 1;
        ...
        2400:cb00::/32 1;
        ...
    }

    # Generated at <UTC timestamp>
    ```
  - Writes `/etc/nginx/allow-cloudflare-only.conf`:
    ```nginx
    # Deny traffic not originating from Cloudflare or localhost
    if ($is_cloudflare = 0) {
        return 403;
    }
    ```
  - Runs `nginx -t` and reloads Nginx if `nginx.service` is active.

### `/etc/nginx/conf.d/trusted_proxies.conf` (When Cloudflare mode is disabled)
- **Owner/Group**: `root:root`
- **Mode**: `'0644'`
- **Structure**:
  ```nginx
  # Managed by Ansible (hifra01.utils.nginx)
  set_real_ip_from ::1;
  set_real_ip_from 127.0.0.1;
  real_ip_header X-Forwarded-For;
  real_ip_recursive on;
  ```

## 4. Handler Contract (`roles/nginx/handlers/main.yml`)

- **Listener `"validate and reload nginx"`**:
  1. `Validate nginx config for reload`: runs `nginx -t` (`changed_when: false`)
  2. `Reload nginx`: reloads `nginx` (`state: reloaded`)
- **Listener `"validate and restart nginx"`**:
  1. `Validate nginx config for restart`: runs `nginx -t` (`changed_when: false`)
  2. `Restart nginx`: restarts `nginx` (`state: restarted`)
