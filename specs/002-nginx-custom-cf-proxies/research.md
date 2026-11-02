# Phase 0 Research: Nginx Custom Site Configs, Cloudflare Geo/Real-IP Script, and Trusted Proxies (`nginx`)

**Feature**: `002-nginx-custom-cf-proxies`  
**Date**: 2026-11-02

## 1. Full-File Custom Site Configuration and Variable-Injected Custom Templates

- **Decision**:
  - Support two mutually exclusive custom configuration mechanisms on each item in `nginx_sites` (in addition to the built-in `type: static | proxy | php` archetypes):
    1. `custom_config` (string): Full raw Nginx configuration content rendered as the complete `{{ nginx_site_available_dir }}/{{ item.name }}.conf` file.
    2. `template` (string): Path to a custom Jinja2 template on the Ansible controller rendered as the complete `{{ nginx_site_available_dir }}/{{ item.name }}.conf` file.
    3. `vars` (dictionary, default `{}`): Optional per-site variables injected into the template rendering context when `template` or `custom_config` is evaluated.
  - Render all enabled sites through `roles/nginx/templates/site.conf.j2` (with `loop_control: { loop_var: item }`):
    - When `item.template is defined`: `site.conf.j2` delegates to `{{ lookup('ansible.builtin.template', item.template, template_vars=(item.vars | default({})) | combine({'item': item})) }}`.
    - When `item.custom_config is defined`: `site.conf.j2` outputs `{{ item.custom_config }}` (and if `item.vars` is provided, templates `item.custom_config` with those variables in scope).
    - Otherwise: `site.conf.j2` renders the built-in `static`, `proxy`, or `php` server block as before.
  - Add an upfront `ansible.builtin.assert` task verifying that no site in `nginx_sites` defines both `custom_config` and `template`.
- **Rationale**:
  - Using `lookup('ansible.builtin.template', item.template, template_vars=...)` in `ansible-core >= 2.21` injects every key in `item.vars` directly as a top-level template variable (e.g., `{{ upstream_port }}`) while also preserving `{{ item.name }}` and `{{ item.vars.upstream_port }}`, without triggering loop-level `vars:` evaluation order issues.
  - Keeping a single `Deploy enabled sites configurations` task preserves strict idempotency and single-handler notification (`"validate and reload nginx"`).
- **Alternatives Considered**:
  - *Using `include_tasks` per site with dynamic task-level `vars:`*: Rejected because `ansible-core 2.21` discourages dynamic dictionary expansion in static `vars:` blocks, whereas `lookup('ansible.builtin.template', ..., template_vars=...)` is the first-class built-in mechanism for scoped template variable dictionaries.
  - *Injecting `custom_config` only inside `server {}`*: Rejected during clarification (`Session 2026-11-02`) because operators need full control over top-level `upstream {}` blocks, multiple `server {}` blocks (e.g., HTTP-to-HTTPS redirects), and custom directives.

## 2. Updated Cloudflare IP Updater Script (`cloudflare.conf` & `allow-cloudflare-only.conf`)

- **Decision**:
  - Update `roles/nginx/templates/update_cloudflare_ips.sh.j2` (deployed to `/usr/local/bin/update_cloudflare_ips.sh`, mode `'0755'`) based on the reference gist (`update-cf-ips.sh`):
    - Fetch IPv4 ranges from `https://www.cloudflare.com/ips-v4/` and IPv6 ranges from `https://www.cloudflare.com/ips-v6/` using `curl -fsSL`, aborting if either response is empty.
    - Generate `{{ nginx_config_dir }}/conf.d/cloudflare.conf` (included inside `http {}` via `include {{ nginx_config_dir }}/conf.d/*.conf;`) containing:
      - `set_real_ip_from <ip>;` for each entry in `nginx_trusted_proxies` (defaulting to `['::1', '127.0.0.1']`) and each Cloudflare IPv4/IPv6 CIDR.
      - `real_ip_header CF-Connecting-IP;` and `real_ip_recursive {{ nginx_real_ip_recursive }};`.
      - `geo $realip_remote_addr $is_cloudflare` mapping `default 0;`, each entry in `nginx_trusted_proxies` to `1`, and each Cloudflare IPv4/IPv6 CIDR to `1`.
    - Generate `{{ nginx_config_dir }}/allow-cloudflare-only.conf` (included inside `server {}` blocks that restrict access) containing:
      ```nginx
      # Deny traffic not originating from Cloudflare or localhost
      if ($is_cloudflare = 0) {
          return 403;
      }
      ```
    - When Nginx is already active (`systemctl is-active --quiet nginx`), test and reload Nginx (`nginx -t && systemctl reload nginx`) without requiring `sudo` (since both Ansible `become: true` and the root cron job run as `root`, and minimal containers may not have `sudo` installed).
- **Rationale**:
  - Separating `conf.d/cloudflare.conf` (`http` context) from `allow-cloudflare-only.conf` (`server` context) allows `ngx_http_realip_module` and `ngx_http_geo_module` to be defined once at the `http` level while using `$realip_remote_addr` (the original connecting peer IP before real-IP rewriting) to evaluate `$is_cloudflare`.
  - Writing to temporary files or validating before reload prevents broken partial files if interrupted.
- **Alternatives Considered**:
  - *Legacy `allow <ip>;` / `deny all;` in `cloudflare_ips.conf`*: Replaced per user request because `allow`/`deny` evaluates the rewritten `$remote_addr` when `set_real_ip_from` is active, whereas `geo $realip_remote_addr $is_cloudflare` evaluates the actual connecting proxy/peer IP.

## 3. Decoupling Cloudflare Trusted Proxy from Cloudflare-Only Access Restriction

- **Decision**:
  - Separate the two concerns via distinct variables:
    1. **Trusting Cloudflare IPs as a reverse proxy (without blocking non-Cloudflare traffic)**:
       - Controlled globally by `nginx_cloudflare_enabled` (boolean, default `false`) or per-site by `cloudflare_real_ip` (boolean, default `false`).
       - Also automatically activated when any enabled site sets `cloudflare_filter: true`.
       - Computed fact `nginx_use_cloudflare` is `true` when `nginx_cloudflare_enabled | bool` OR any enabled site has `cloudflare_real_ip | default(false) | bool` OR any enabled site has `cloudflare_filter | default(false) | bool`.
       - When `nginx_use_cloudflare` is `true`, `conf.d/cloudflare.conf` and `allow-cloudflare-only.conf` are generated and kept updated via weekly cron, so all sites trust Cloudflare IPs for `CF-Connecting-IP` header resolution without blocking non-Cloudflare IPs.
    2. **Restricting site access to Cloudflare/trusted IPs only**:
       - Controlled per-site by `cloudflare_filter: true` (or by manually including `{{ nginx_config_dir }}/allow-cloudflare-only.conf` in a custom site config/template).
       - In `templates/site.conf.j2`, `include {{ nginx_config_dir }}/allow-cloudflare-only.conf;` is rendered **only** when `item.cloudflare_filter | default(false) | bool` is `true`.
- **Rationale**:
  - Directly fulfills the user requirement in `Session 2026-11-02`: operators can trust Cloudflare IPs to unwrap `CF-Connecting-IP` while still allowing direct traffic from non-Cloudflare IPs on sites with `cloudflare_filter: false`.
- **Alternatives Considered**:
  - *Coupling `cloudflare.conf` generation exclusively to `cloudflare_filter: true`*: Rejected because it prevented trusting Cloudflare IPs without also blocking non-Cloudflare traffic.

## 4. Trusted Proxies Configuration (`nginx_trusted_proxies`) & RedHat `conf.d` Cleanup Safety

- **Decision**:
  - Define `nginx_trusted_proxies: ['::1', '127.0.0.1']`, `nginx_real_ip_header: 'X-Forwarded-For'`, and `nginx_real_ip_recursive: 'on'` in `roles/nginx/defaults/main.yml`.
  - **When `nginx_use_cloudflare` is `true`**:
    - Inject `nginx_trusted_proxies` into `update_cloudflare_ips.sh.j2` so every entry in `nginx_trusted_proxies` is emitted as both `set_real_ip_from <ip>;` and `<ip> 1;` inside `geo $realip_remote_addr $is_cloudflare` in `{{ nginx_config_dir }}/conf.d/cloudflare.conf`.
    - Ensure `{{ nginx_config_dir }}/conf.d/trusted_proxies.conf` is absent so `real_ip_header` is not declared twice in `http {}`.
  - **When `nginx_use_cloudflare` is `false`**:
    - Ensure `{{ nginx_config_dir }}/conf.d/cloudflare.conf`, `{{ nginx_config_dir }}/allow-cloudflare-only.conf`, and legacy `{{ nginx_config_dir }}/cloudflare_ips.conf` are absent.
    - When `nginx_trusted_proxies | length > 0`, render `{{ nginx_config_dir }}/conf.d/trusted_proxies.conf` via `templates/trusted_proxies.conf.j2` with `set_real_ip_from` for each proxy, `real_ip_header {{ nginx_real_ip_header }};`, and `real_ip_recursive {{ nginx_real_ip_recursive }};` (and remove it if `nginx_trusted_proxies` is empty).
  - **RedHat `conf.d` cleanup safety**:
    - On RedHat-family systems, `nginx_site_enabled_dir` is `/etc/nginx/conf.d`. Update the `Clean up unused site configurations` task in `tasks/main.yml` to exclude reserved global configuration basenames (`['cloudflare.conf', 'trusted_proxies.conf']`) in addition to `nginx_enabled_sites`.
- **Rationale**:
  - Prevents duplicate `real_ip_header` directives in `http {}` while ensuring `nginx_trusted_proxies` works seamlessly whether Cloudflare mode is enabled or disabled, and prevents RedHat site cleanup from deleting `cloudflare.conf` or `trusted_proxies.conf`, maintaining 100% idempotency (`changed=0` on second run).
- **Alternatives Considered**:
  - *Putting `trusted_proxies.conf` and `cloudflare.conf` active at the same time*: Rejected because Nginx forbids duplicate `real_ip_header` and `real_ip_recursive` directives in the same `http {}` context (`"real_ip_header" directive is duplicate`).
