# Feature Specification: Nginx Custom Site Configs, Cloudflare Geo/Real-IP Script, and Trusted Proxies (`nginx`)

**Feature Branch**: `002-nginx-custom-cf-proxies`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "update role nginx to allow custom site config or custom site config template that can be injected with variables, also update cloudflare script based on https://gist.githubusercontent.com/hifra01/1efa7870fdfb9d7003c6db1a1aa85825/raw/2f9ae5a1a8d5b6529d0f9a6e29ba8a5a9cff0a50/update-cf-ips.sh , and allow configuring trusted proxies"

## Clarifications

### Session 2026-11-02

- Q: When a site in `nginx_sites` uses `custom_config` or `template`, should it define the entire site `.conf` file or only the directives inside the existing `server {}` block? (FR-002) → A: Entire `.conf` file (full control over `server` and `upstream` blocks, with per-site `vars` injected).
- Q: How should `nginx_trusted_proxies` be applied across Nginx and the Cloudflare updater script? (FR-004, FR-005, FR-007) → A: Inject into the Cloudflare script (both `set_real_ip_from` and `$is_cloudflare` geo allowlist) when Cloudflare is enabled, and render `conf.d/trusted_proxies.conf` when Cloudflare is disabled.
- Q: When should the role deploy and execute the Cloudflare IP updater script? (FR-005) → A: When any enabled site sets `cloudflare_filter: true` OR when `nginx_cloudflare_enabled: true` is set globally (so custom templates can also include `allow-cloudflare-only.conf`).
- Q: How should adding Cloudflare IPs as trusted proxies be separated from restricting access to Cloudflare-only IPs? (FR-004, FR-005, FR-006) → A: Decouple trusting Cloudflare IPs (`nginx_cloudflare_enabled: true` globally or `cloudflare_real_ip: true` per site, which deploys `conf.d/cloudflare.conf` for `set_real_ip_from` and `$is_cloudflare` geo mapping without blocking traffic) from restricting non-Cloudflare access (`cloudflare_filter: true` per site, which includes `allow-cloudflare-only.conf` in the site's `server {}` block to return `403` when `$is_cloudflare = 0`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Sites with Custom Configuration or Variable-Injected Custom Templates (Priority: P1)

Infrastructure operators need to deploy Nginx virtual hosts that go beyond the built-in `static`, `proxy`, and `php` site archetypes by supplying either a full raw custom Nginx site configuration or a custom configuration template path along with a dictionary of site-specific variables to inject during rendering.

**Why this priority**: Production workloads frequently require bespoke Nginx directives (such as multiple `server` or `location` blocks, `upstream` definitions, websocket upgrades, or custom rewrite rules) that require full control over the entire `.conf` file.

**Independent Test**: Can be fully tested by provisioning a host with one site using an inline custom configuration string (`custom_config`) and another site using a custom template file (`template`) populated with per-site variables (`vars`), then verifying that both complete site `.conf` files are rendered accurately, pass `nginx -t`, and serve requests as configured.

**Acceptance Scenarios**:

1. **Given** an enabled site entry in `nginx_sites` configured with an inline custom configuration (`custom_config`) and optional `vars`, **When** the role is applied, **Then** the entire site `.conf` file in the host's site directory is rendered from `custom_config` (with `vars` and `item` interpolated), passes configuration validation, and is active in Nginx.
2. **Given** an enabled site entry in `nginx_sites` configured with a custom template path (`template`) and a dictionary of per-site variables (`vars`), **When** the role is applied, **Then** the custom template is rendered as the entire site `.conf` file with access to both the injected `vars` dictionary and the site `item` attributes, validated via `nginx -t`, and loaded by Nginx.
3. **Given** existing sites using the built-in `static`, `proxy`, or `php` types without `custom_config` or `template`, **When** the role is applied, **Then** those sites continue to render using the default `site.conf.j2` template without regression.

---

### User Story 2 - Separate Cloudflare Trusted Proxy (Real-IP) from Cloudflare-Only Access Restriction (Priority: P2)

Infrastructure operators running sites behind Cloudflare need to independently control:
1. **Trusting Cloudflare IPs as a reverse proxy** (`nginx_cloudflare_enabled: true` globally or `cloudflare_real_ip: true` on a site) so Nginx unwraps the visitor's real IP from `CF-Connecting-IP` via `/etc/nginx/conf.d/cloudflare.conf` **without** blocking direct requests from non-Cloudflare IPs; and
2. **Restricting site access to Cloudflare IPs only** (`cloudflare_filter: true` on a site, or including `/etc/nginx/allow-cloudflare-only.conf` in a custom site config) so Nginx returns HTTP `403` when `$is_cloudflare = 0`.

**Why this priority**: Some deployments route public traffic through Cloudflare (requiring `set_real_ip_from` for Cloudflare ranges to log/forward accurate client IPs) while still needing to accept direct connections from external monitors, health checks, or non-Cloudflare clients on certain or all sites.

**Independent Test**: Can be independently tested by enabling `nginx_cloudflare_enabled: true` with two sites — one with `cloudflare_filter: false` (default) and one with `cloudflare_filter: true` — and verifying that `/etc/nginx/conf.d/cloudflare.conf` and `/etc/nginx/allow-cloudflare-only.conf` are generated, the first site unwraps `CF-Connecting-IP` while still allowing non-Cloudflare IPs, and the second site includes `allow-cloudflare-only.conf` and blocks non-Cloudflare/non-trusted IPs with `403`.

**Acceptance Scenarios**:

1. **Given** `nginx_cloudflare_enabled: true` (or a site with `cloudflare_real_ip: true`) and all enabled sites have `cloudflare_filter: false`, **When** the role runs, **Then** `/etc/nginx/conf.d/cloudflare.conf` and `/etc/nginx/allow-cloudflare-only.conf` are generated so Cloudflare IPs are trusted for `CF-Connecting-IP` real-IP resolution, while no site includes `allow-cloudflare-only.conf` and traffic from non-Cloudflare IPs is still permitted.
2. **Given** a built-in site with `cloudflare_filter: true` (or a custom site config that includes `/etc/nginx/allow-cloudflare-only.conf`), **When** the role runs, **Then** the Cloudflare updater script automatically runs to populate `/etc/nginx/conf.d/cloudflare.conf` and `/etc/nginx/allow-cloudflare-only.conf`, and that specific site includes `/etc/nginx/allow-cloudflare-only.conf` to deny requests where `$is_cloudflare = 0` with HTTP `403`.
3. **Given** a RedHat-family or Debian-family host with `/etc/nginx/conf.d/cloudflare.conf` present, **When** the role cleans up unused site configurations, **Then** `/etc/nginx/conf.d/cloudflare.conf` (and any non-site global configuration files) are preserved and not mistakenly deleted as an unlisted site.

---

### User Story 3 - Configure Additional Trusted Proxies (Priority: P3)

Infrastructure operators running Nginx behind local or internal reverse proxies, load balancers, or container networks need to configure a list of trusted proxy IP addresses or CIDR ranges (`nginx_trusted_proxies`) so that Nginx trusts forwarded client IP headers from those proxies and permits them alongside Cloudflare and loopback addresses.

**Why this priority**: In multi-tier architectures (e.g., HAProxy, internal L4/L7 load balancers, or local sidecars in front of Nginx), operators must be able to declare additional trusted proxy CIDRs without manually editing generated configuration files or scripts.

**Independent Test**: Can be independently tested by setting `nginx_trusted_proxies` to a list of custom IP/CIDR entries, applying the role in both Cloudflare-enabled and Cloudflare-disabled modes, and verifying that `set_real_ip_from` directives (and `$is_cloudflare` allowlist entries when Cloudflare real-IP is active, or `conf.d/trusted_proxies.conf` when Cloudflare real-IP is inactive) include every configured trusted proxy CIDR.

**Acceptance Scenarios**:

1. **Given** `nginx_trusted_proxies` is configured with one or more IP addresses or CIDR subnets (defaulting to `['::1', '127.0.0.1']`), **When** Cloudflare real-IP mode is enabled (`nginx_use_cloudflare: true`) and the updater script runs, **Then** every configured trusted proxy is written as both a `set_real_ip_from <ip>;` entry and a `<ip> 1;` entry inside the `geo $realip_remote_addr $is_cloudflare` block in `/etc/nginx/conf.d/cloudflare.conf`.
2. **Given** `nginx_trusted_proxies` is configured with custom proxy CIDRs and Cloudflare real-IP mode is disabled (`nginx_use_cloudflare: false`), **When** the role is applied, **Then** Nginx renders `/etc/nginx/conf.d/trusted_proxies.conf` with `set_real_ip_from` for each entry in `nginx_trusted_proxies`, sets `real_ip_header` (configurable via `nginx_real_ip_header`, defaulting to `X-Forwarded-For`), and sets `real_ip_recursive on;` so upstream proxy real-IP resolution works independently of Cloudflare.
3. **Given** an already converged host with custom site configs, Cloudflare updater script, and trusted proxies configured, **When** the role is re-run with identical variables, **Then** the run completes with zero changed tasks (strict idempotency).

---

### Edge Cases

- **Both `custom_config` and `template` specified on the same site**: If an operator specifies both `custom_config` and `template` on a single site entry, the role fails fast during validation with a clear assertion error explaining that `custom_config` and `template` are mutually exclusive per site.
- **Custom template variable collision or missing `vars`**: When a site uses `template` or `custom_config` without defining `vars`, rendering succeeds cleanly with `item` and an empty `vars` dictionary (`{}`) without failing on undefined `item.vars` references.
- **Trusted Cloudflare IPs without blocking non-Cloudflare IPs**: When `nginx_cloudflare_enabled: true` (or `cloudflare_real_ip: true` on a site) is set while `cloudflare_filter` is `false` (or omitted), `/etc/nginx/conf.d/cloudflare.conf` is loaded in `http {}` to trust Cloudflare IPs for `set_real_ip_from`, while `allow-cloudflare-only.conf` is NOT included in the site's `server {}` block, ensuring non-Cloudflare clients are not blocked.
- **RedHat `/etc/nginx/conf.d` shared directory cleanup**: Because RedHat-family distributions store both global `http` configs (such as `cloudflare.conf` and `trusted_proxies.conf`) and site configs in `/etc/nginx/conf.d`, the unused-site cleanup task must exclude role-managed global config files (`cloudflare.conf`, `trusted_proxies.conf`) so they are never purged during site cleanup.
- **Cloudflare IP endpoint unreachable or returning empty output**: If `curl` fails or returns an empty IPv4/IPv6 list during `update_cloudflare_ips.sh` execution, the script aborts (`set -e` / non-zero exit) before overwriting `/etc/nginx/conf.d/cloudflare.conf` with an invalid or empty configuration, preserving existing working configuration.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The role MUST validate that the target host belongs to a supported OS family (`Debian` or `RedHat`) at the start of `tasks/main.yml` and fail immediately with a descriptive assertion message on unsupported platforms.
- **FR-002**: Each site entry in `nginx_sites` MUST support defining the entire site `.conf` file through two mutually exclusive custom options in addition to the existing `static`, `proxy`, and `php` types:
  - `custom_config` (optional string): Full raw Nginx site configuration content (including `server {}` and any `upstream {}` blocks) rendered directly to `{{ nginx_site_available_dir }}/{{ item.name }}.conf`.
  - `template` (optional string): Path to a custom Jinja2 template file on the Ansible controller rendered as the full site `.conf` file at `{{ nginx_site_available_dir }}/{{ item.name }}.conf`.
  - `vars` (optional dictionary, default `{}`): Per-site variables injected into the rendering context of `template` or `custom_config` (accessible both as top-level variables in the template and via `item.vars.<key>`).
- **FR-003**: The role MUST assert that no enabled site in `nginx_sites` defines both `custom_config` and `template` simultaneously, failing fast with a descriptive error if both are provided.
- **FR-004**: The role MUST provide user-tunable Cloudflare and trusted proxy variables in `defaults/main.yml` that separate trusting Cloudflare IPs from blocking non-Cloudflare traffic:
  - `nginx_cloudflare_enabled` (boolean, default `false` — adds Cloudflare IPs as trusted proxies in `conf.d/cloudflare.conf` and maintains `allow-cloudflare-only.conf` via the updater script without forcing sites to block non-Cloudflare traffic)
  - `nginx_trusted_proxies` (list of IP addresses or CIDR ranges, defaulting to `['::1', '127.0.0.1']`)
  - `nginx_real_ip_header` (string, defaulting to `'X-Forwarded-For'` when standalone trusted proxies are used, while Cloudflare mode uses `'CF-Connecting-IP'`)
  - `nginx_real_ip_recursive` (string `'on'` or `'off'`, defaulting to `'on'`)
  - Per-site `cloudflare_real_ip` (optional boolean on `nginx_sites` items, default `false` — enables Cloudflare trusted proxy configuration when true, without blocking non-Cloudflare IPs)
  - Per-site `cloudflare_filter` (optional boolean on `nginx_sites` items, default `false` — both enables Cloudflare trusted proxy configuration AND includes `allow-cloudflare-only.conf` in that site's `server {}` block to block non-Cloudflare/non-trusted-proxy access)
- **FR-005**: When `nginx_cloudflare_enabled` is `true`, OR any enabled site sets `cloudflare_real_ip: true`, OR any enabled site sets `cloudflare_filter: true` (`nginx_use_cloudflare: true`), the role MUST deploy `/usr/local/bin/update_cloudflare_ips.sh` based on the reference gist (`update-cf-ips.sh`), which:
  - Fetches Cloudflare IPv4 ranges from `https://www.cloudflare.com/ips-v4/` and IPv6 ranges from `https://www.cloudflare.com/ips-v6/` using `curl -fsSL` (failing safely if either list is empty or unreachable).
  - Writes `{{ nginx_config_dir }}/conf.d/cloudflare.conf` (loaded globally in `http {}` to trust Cloudflare and `nginx_trusted_proxies` for real-IP resolution without blocking traffic) containing:
    - `set_real_ip_from <ip>;` for each address/subnet in `nginx_trusted_proxies` (defaulting to `::1` and `127.0.0.1`) and each Cloudflare IPv4 and IPv6 CIDR.
    - `real_ip_header CF-Connecting-IP;` and `real_ip_recursive {{ nginx_real_ip_recursive }};`.
    - `geo $realip_remote_addr $is_cloudflare` block with `default 0;`, `<ip> 1;` for each address/subnet in `nginx_trusted_proxies`, and `<ip> 1;` for each Cloudflare IPv4 and IPv6 CIDR.
  - Writes `{{ nginx_config_dir }}/allow-cloudflare-only.conf` (included only in `server {}` blocks that opt into restricting access) containing:
    ```nginx
    # Deny traffic not originating from Cloudflare or localhost
    if ($is_cloudflare = 0) {
        return 403;
    }
    ```
  - Re-runs when `/usr/local/bin/update_cloudflare_ips.sh` changes (e.g., when `nginx_trusted_proxies` is updated) or when `{{ nginx_config_dir }}/conf.d/cloudflare.conf` / `{{ nginx_config_dir }}/allow-cloudflare-only.conf` does not yet exist, and validates/reloads Nginx cleanly.
- **FR-006**: In `templates/site.conf.j2`, `include {{ nginx_config_dir }}/allow-cloudflare-only.conf;` MUST ONLY be rendered inside a site's `server {}` block when `item.cloudflare_filter | default(false) | bool` is `true` on that site; sites with `cloudflare_filter: false` (even when `nginx_cloudflare_enabled: true` or `item.cloudflare_real_ip: true`) MUST NOT include `allow-cloudflare-only.conf`.
- **FR-007**: When `nginx_use_cloudflare` is `false` and `nginx_trusted_proxies` contains one or more entries, the role MUST render `{{ nginx_config_dir }}/conf.d/trusted_proxies.conf` containing `set_real_ip_from <ip>;` for each entry in `nginx_trusted_proxies`, `real_ip_header {{ nginx_real_ip_header }};`, and `real_ip_recursive {{ nginx_real_ip_recursive }};`, and remove `trusted_proxies.conf` when `nginx_use_cloudflare` is `true` or `nginx_trusted_proxies` is empty.
- **FR-008**: When `nginx_use_cloudflare` is `false`, the role MUST ensure `{{ nginx_config_dir }}/conf.d/cloudflare.conf`, `{{ nginx_config_dir }}/allow-cloudflare-only.conf`, and legacy `{{ nginx_config_dir }}/cloudflare_ips.conf` (plus the weekly Cloudflare cron job) are absent so disabled Cloudflare configurations do not linger.
- **FR-009**: The unused site configuration cleanup task MUST preserve reserved global `conf.d` files (`cloudflare.conf` and `trusted_proxies.conf`) when `nginx_site_enabled_dir` points to `{{ nginx_config_dir }}/conf.d` (RedHat family).
- **FR-010**: All tasks in the role MUST be strictly idempotent, producing zero changes on a second consecutive run across all supported distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8).

### Key Entities

- **Site Definition (`nginx_sites` item)**: Represents a virtual host managed by the role. Supports built-in archetypes (`type: static | proxy | php`), full-file custom site configuration (`custom_config` or `template` with `vars`), optional `cloudflare_real_ip` (trust Cloudflare IPs without blocking), and optional `cloudflare_filter` (trust Cloudflare IPs AND restrict access to Cloudflare/trusted IPs only).
- **Cloudflare Real-IP & Geo Configuration (`conf.d/cloudflare.conf`)**: Represents the `http`-level real-IP (`set_real_ip_from`, `real_ip_header CF-Connecting-IP`, `real_ip_recursive`) and `geo $realip_remote_addr $is_cloudflare` configuration that trusts Cloudflare IPs as a reverse proxy without blocking non-Cloudflare traffic.
- **Cloudflare Access Restriction Snippet (`allow-cloudflare-only.conf`)**: Represents the opt-in `server`-level `403` access control snippet (`if ($is_cloudflare = 0) { return 403; }`) included only on sites that restrict access to Cloudflare/trusted proxies.
- **Trusted Proxies List (`nginx_trusted_proxies`)**: Represents the list of upstream proxy IP addresses and CIDR blocks trusted to supply client IP headers (`set_real_ip_from`) and permitted through the `$is_cloudflare` geo check (or rendered to `conf.d/trusted_proxies.conf` when Cloudflare mode is inactive).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy Nginx sites using built-in types (`static`, `proxy`, `php`), inline custom configurations (`custom_config`), and variable-injected custom templates (`template` + `vars`) across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) with 100% of enabled sites passing `nginx -t` and serving expected responses.
- **SC-002**: Enabling `nginx_cloudflare_enabled: true` (or `cloudflare_real_ip: true` on a site) with `cloudflare_filter: false` generates `/etc/nginx/conf.d/cloudflare.conf` (trusting Cloudflare IPv4/IPv6 ranges and `nginx_trusted_proxies` for `set_real_ip_from`) while allowing requests from non-Cloudflare IPs to succeed (`200 OK`) without being blocked.
- **SC-003**: Enabling `cloudflare_filter: true` on a site includes `/etc/nginx/allow-cloudflare-only.conf` in that site's `server {}` block so requests from IPs in `nginx_trusted_proxies` or Cloudflare ranges receive `200 OK` while requests from untrusted IPs (`$is_cloudflare = 0`) receive `403 Forbidden`.
- **SC-004**: Re-running the role on an already converged host with identical variables produces 0 changed tasks across all 5 supported Linux distributions.

## Assumptions

- Target hosts run Debian-family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) or RedHat-family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL) distributions with `ngx_http_realip_module` and `ngx_http_geo_module` available in the installed Nginx package (already provided by `nginx-extras` on Debian/Ubuntu and `nginx` / `nginx-all-modules` on RedHat).
- Target hosts with Cloudflare mode enabled have outbound HTTPS connectivity to `https://www.cloudflare.com/ips-v4/` and `https://www.cloudflare.com/ips-v6/` and `curl` installed.
- `nginx_trusted_proxies` defaults to `['::1', '127.0.0.1']` to match the reference gist's local IP defaults while allowing operators to append or override with internal load balancer / reverse proxy CIDRs (e.g., `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`).
- When a site defines `template` or `custom_config`, any `vars` dictionary on that site item is exposed both as `item.vars` and as top-level template variables (via task-level `vars:` scoping) so custom templates can naturally reference `{{ my_var }}` as well as `{{ item.name }}`.
- Initial generation of `/etc/nginx/conf.d/cloudflare.conf` and `/etc/nginx/allow-cloudflare-only.conf` during an Ansible run occurs before `nginx.conf` and site configurations are validated/reloaded so `include {{ nginx_config_dir }}/allow-cloudflare-only.conf;` never fails on a missing file during initial convergence.
