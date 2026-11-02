# Data Model: Nginx Custom Site Configs, Cloudflare Geo/Real-IP Script, and Trusted Proxies (`nginx`)

**Feature**: `002-nginx-custom-cf-proxies`  
**Date**: 2026-11-02

## Entities

### 1. Global Nginx Role Configuration (`nginx_*` variables in `defaults/main.yml`)

Represents host-wide Nginx parameters, Cloudflare real-IP/geo settings, and trusted proxy settings.

| Field / Variable | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `nginx_server_tokens` | `string` | `"off"` | Yes | `"on"` or `"off"` |
| `nginx_client_max_body_size` | `string` | `"10m"` | Yes | Valid Nginx size string |
| `nginx_client_body_buffer_size` | `string` | `"128k"` | Yes | Valid Nginx size string |
| `nginx_client_header_buffer_size` | `string` | `"1k"` | Yes | Valid Nginx size string |
| `nginx_large_client_header_buffers` | `string` | `"4 4k"` | Yes | Valid Nginx buffer count and size |
| `nginx_security_headers_enabled` | `boolean` | `true` | Yes | Boolean (`true` / `false`) |
| `nginx_ssl_protocols` | `string` | `"TLSv1.2 TLSv1.3"` | Yes | Space-separated TLS protocol versions |
| `nginx_ssl_ciphers` | `string` | `ECDHE-ECDSA-AES128-GCM-SHA256:...` | Yes | Valid OpenSSL cipher list |
| `nginx_ssl_prefer_server_ciphers` | `string` | `"on"` | Yes | `"on"` or `"off"` |
| `nginx_cloudflare_enabled` | `boolean` | `false` | Yes | Boolean (`true` / `false`); enables Cloudflare trusted proxy (`conf.d/cloudflare.conf`) globally without forcing sites to block non-Cloudflare IPs |
| `nginx_trusted_proxies` | `list[string]` | `['::1', '127.0.0.1']` | Yes | List of valid IPv4/IPv6 addresses or CIDR blocks |
| `nginx_real_ip_header` | `string` | `"X-Forwarded-For"` | Yes | Non-empty HTTP header name used in `conf.d/trusted_proxies.conf` when Cloudflare mode is disabled |
| `nginx_real_ip_recursive` | `string` | `"on"` | Yes | `"on"` or `"off"` |
| `nginx_sites` | `list[SiteDefinition]` | `[default, app_proxy, php_app]` | Yes | List of site definitions (see Entity 2) |
| `nginx_enabled_sites` | `list[string]` | `['default']` | Yes | List of site `name` values to deploy and enable |

---

### 2. Site Definition (`nginx_sites` list item)

Represents an individual virtual host configuration rendered to `{{ nginx_site_available_dir }}/{{ item.name }}.conf`.

| Field | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `name` | `string` | — | **Yes** | Unique site identifier used as `<name>.conf` filename |
| `type` | `string` | `"static"` | No | `"static"`, `"proxy"`, or `"php"` (ignored when `custom_config` or `template` is set) |
| `custom_config` | `string` | Omitted | Conditional | Full raw Nginx site configuration content; **mutually exclusive** with `template` |
| `template` | `string` | Omitted | Conditional | Controller-side Jinja2 template path; **mutually exclusive** with `custom_config` |
| `vars` | `dict` | `{}` | No | Per-site variables injected into `template` (or `custom_config`) rendering context |
| `cloudflare_real_ip` | `boolean` | `false` | No | When `true`, enables Cloudflare trusted proxy configuration (`conf.d/cloudflare.conf`) without blocking non-Cloudflare traffic on this site |
| `cloudflare_filter` | `boolean` | `false` | No | When `true`, enables Cloudflare trusted proxy configuration AND includes `allow-cloudflare-only.conf` inside this site's `server {}` block to return `403` for non-Cloudflare/non-trusted IPs |
| `domains` | `list[string]` | `['_']` | No | List of `server_name` domains (for built-in types) |
| `listen` | `int \| string` | `80` | No | Listen port/directive (for built-in types) |
| `root` | `string` | `"/var/www/html"` | No | Document root path (for `static` and `php` types) |
| `index` | `list[string]` | `['index.html', 'index.htm']` | No | Index filenames (for `static` and `php` types) |
| `try_files` | `string` | `"$uri $uri/ =404"` | No | `try_files` directive expression (for `static` and `php` types) |
| `proxy_pass` | `string` | — | When `type == 'proxy'` | Upstream URL for `proxy_pass` |
| `proxy_set_headers` | `boolean` | `true` | No | Whether to emit standard `X-Real-IP` / `X-Forwarded-*` proxy headers |
| `fastcgi_pass` | `string` | `"unix:/run/php/php-fpm.sock"` | No | FastCGI socket or TCP address (for `php` type) |
| `custom_headers` | `list[Header]` | Omitted | No | Optional list of `{ name, value, always }` headers (for built-in types) |

---

### 3. Cloudflare & Trusted Proxy Configuration Files

Represents the host-level configuration files managed under `{{ nginx_config_dir }}`.

| File Path | Context | Active When | Purpose |
|---|---|---|---|
| `{{ nginx_config_dir }}/conf.d/cloudflare.conf` | `http {}` | `nginx_use_cloudflare == true` | Declares `set_real_ip_from` for `nginx_trusted_proxies` + Cloudflare IPv4/IPv6 ranges, `real_ip_header CF-Connecting-IP;`, `real_ip_recursive`, and `geo $realip_remote_addr $is_cloudflare` |
| `{{ nginx_config_dir }}/allow-cloudflare-only.conf` | `server {}` (via `include`) | `nginx_use_cloudflare == true` | Returns `403` when `$is_cloudflare = 0`; only included by sites with `cloudflare_filter: true` or explicit `include` in custom configs |
| `{{ nginx_config_dir }}/conf.d/trusted_proxies.conf` | `http {}` | `nginx_use_cloudflare == false` and `nginx_trusted_proxies \| length > 0` | Declares `set_real_ip_from` for `nginx_trusted_proxies`, `real_ip_header {{ nginx_real_ip_header }};`, and `real_ip_recursive {{ nginx_real_ip_recursive }};` |

## Relationships & Lifecycle Transitions

1. **Cloudflare Mode Resolution (`nginx_use_cloudflare`)**:
   - `nginx_use_cloudflare = true` if `nginx_cloudflare_enabled | bool` OR any enabled site in `nginx_sites` has `cloudflare_real_ip: true` OR any enabled site in `nginx_sites` has `cloudflare_filter: true`.
   - When `nginx_use_cloudflare == true`:
     - `conf.d/trusted_proxies.conf` is removed (`state: absent`).
     - `/usr/local/bin/update_cloudflare_ips.sh` is rendered with `nginx_trusted_proxies` and executed if the script changed or `conf.d/cloudflare.conf` / `allow-cloudflare-only.conf` is missing.
     - Weekly cron job `Update Cloudflare IP ranges for Nginx` is present.
   - When `nginx_use_cloudflare == false`:
     - `conf.d/cloudflare.conf`, `allow-cloudflare-only.conf`, legacy `cloudflare_ips.conf`, and the weekly cron job are removed (`state: absent`).
     - `conf.d/trusted_proxies.conf` is rendered when `nginx_trusted_proxies` is non-empty (or removed if `nginx_trusted_proxies` is empty).
2. **Site Rendering & Cleanup**:
   - Enabled sites (`item.name in nginx_enabled_sites`) are rendered to `{{ nginx_site_available_dir }}/{{ item.name }}.conf` (and symlinked into `{{ nginx_site_enabled_dir }}` on Debian-family hosts).
   - Unused `.conf` files in `{{ nginx_site_enabled_dir }}` are removed, explicitly preserving `cloudflare.conf` and `trusted_proxies.conf` on RedHat-family systems where `nginx_site_enabled_dir` is `/etc/nginx/conf.d`.
