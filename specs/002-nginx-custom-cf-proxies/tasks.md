---

description: "Task list for Nginx Custom Site Configs, Cloudflare Geo/Real-IP Script, and Trusted Proxies (nginx)"
---

# Tasks: Nginx Custom Site Configs, Cloudflare Geo/Real-IP Script, and Trusted Proxies (`nginx`)

**Input**: Design documents from `/specs/002-nginx-custom-cf-proxies/`
**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule verification (`molecule test` across all 5 CI images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Ansible role**: `roles/nginx/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `templates/`, `meta/`, `molecule/default/`, `README.md`)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare role directories and Molecule test fixture structure per `plan.md`

- [X] T001 Create Molecule test templates directory and custom vhost test fixture template in `roles/nginx/molecule/default/templates/custom_vhost.conf.j2`
- [X] T002 [P] Update `roles/nginx/vars/Debian.yml` and `roles/nginx/vars/RedHat.yml` (and `roles/nginx/tasks/setup-RedHat.yml`) so `nginx_packages` installs `curl` and `cron`/`cronie` alongside `nginx` and modules

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core role defaults, OS/input validation assertions, and RedHat `conf.d` cleanup safety that MUST be complete before user stories are implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Update `roles/nginx/defaults/main.yml` to define all role defaults and constraints from `data-model.md`: `nginx_server_tokens: "off"` (`"on" or "off"`), `nginx_client_max_body_size: "10m"` (`Valid Nginx size string`), `nginx_client_body_buffer_size: "128k"` (`Valid Nginx size string`), `nginx_client_header_buffer_size: "1k"` (`Valid Nginx size string`), `nginx_large_client_header_buffers: "4 4k"` (`Valid Nginx buffer count and size`), `nginx_security_headers_enabled: true` (`Boolean (true / false)`), `nginx_ssl_protocols: "TLSv1.2 TLSv1.3"` (`Space-separated TLS protocol versions`), `nginx_ssl_ciphers` (`Valid OpenSSL cipher list`), `nginx_ssl_prefer_server_ciphers: "on"` (`"on" or "off"`), `nginx_cloudflare_enabled: false` (`Boolean (true / false); enables Cloudflare trusted proxy (conf.d/cloudflare.conf) globally without forcing sites to block non-Cloudflare IPs`), `nginx_trusted_proxies: ['::1', '127.0.0.1']` (`List of valid IPv4/IPv6 addresses or CIDR blocks`), `nginx_real_ip_header: "X-Forwarded-For"` (`Non-empty HTTP header name used in conf.d/trusted_proxies.conf when Cloudflare mode is disabled`), `nginx_real_ip_recursive: "on"` (`"on" or "off"`), `nginx_sites` (`List of site definitions (see Entity 2)` including `cloudflare_real_ip: false` and `cloudflare_filter: false`), and `nginx_enabled_sites: ['default']` (`List of site name values to deploy and enable`)
- [X] T004 Add platform guard (`ansible_os_family in ['Debian', 'RedHat']`) and variable/site validation assertions at the beginning of `roles/nginx/tasks/main.yml` enforcing `data-model.md` constraints: `nginx_server_tokens in ['on', 'off']`, `nginx_ssl_prefer_server_ciphers in ['on', 'off']`, `nginx_real_ip_recursive in ['on', 'off']`, `nginx_real_ip_header | length > 0`, `nginx_trusted_proxies is sequence`, `item.name` (`Unique site identifier used as <name>.conf filename`), `item.type` (`"static", "proxy", or "php" (ignored when custom_config or template is set)`), `item.proxy_pass` (`Upstream URL for proxy_pass` required `When type == 'proxy'` and neither `custom_config` nor `template` is set), and mutual exclusivity of `custom_config` (`Full raw Nginx site configuration content; mutually exclusive with template`) and `template` (`Controller-side Jinja2 template path; mutually exclusive with custom_config`)
- [X] T005 Update the unused site configuration cleanup task in `roles/nginx/tasks/main.yml` to preserve reserved global `conf.d` files (`cloudflare.conf` and `trusted_proxies.conf`) when `nginx_site_enabled_dir` is `/etc/nginx/conf.d` on RedHat-family systems (FR-009)

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Deploy Sites with Custom Configuration or Variable-Injected Custom Templates (Priority: P1) 🎯 MVP

**Goal**: Allow operators to deploy full-file custom Nginx site configurations via inline `custom_config` or controller-side `template` paths with per-site variable injection via `vars`, while preserving built-in `static`, `proxy`, and `php` site archetypes.

**Independent Test**: Provision a host with built-in `static` site, an inline `custom_config` site with `vars`, and a `template` site (`custom_vhost.conf.j2`) with `vars`, then verify that all site `.conf` files render accurately, pass `nginx -t`, and serve expected HTTP responses.

### Implementation for User Story 1

- [X] T006 [US1] Update `roles/nginx/templates/site.conf.j2` to render full-file custom templates via `lookup('ansible.builtin.template', item.template, template_vars=(item.vars | default({})) | combine({'item': item}))` when `item.template is defined`, render `item.custom_config` (evaluating any Jinja2 expressions with `item.vars` injected) when `item.custom_config is defined`, and render built-in `static`, `proxy`, or `php` server blocks otherwise
- [X] T007 [US1] Update `roles/nginx/molecule/default/converge.yml` and `roles/nginx/molecule/default/verify.yml` to deploy and verify an inline `custom_config` site (with `vars`) and a custom `template` site (`custom_vhost.conf.j2` with `vars`) alongside the default `static` site

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Separate Cloudflare Trusted Proxy (Real-IP) from Cloudflare-Only Access Restriction (Priority: P2)

**Goal**: Update `/usr/local/bin/update_cloudflare_ips.sh` based on the reference `update-cf-ips.sh` gist to generate `/etc/nginx/conf.d/cloudflare.conf` (`set_real_ip_from`, `real_ip_header CF-Connecting-IP;`, `real_ip_recursive`, `geo $realip_remote_addr $is_cloudflare`) and `/etc/nginx/allow-cloudflare-only.conf` (`if ($is_cloudflare = 0) { return 403; }`), and decouple trusting Cloudflare IPs (`nginx_cloudflare_enabled` or per-site `cloudflare_real_ip`) from restricting non-Cloudflare access (`cloudflare_filter: true` per site).

**Independent Test**: Converge with one site using `cloudflare_real_ip: true` (`cloudflare_filter: false`) and another site using `cloudflare_filter: true`, verify `/etc/nginx/conf.d/cloudflare.conf` and `/etc/nginx/allow-cloudflare-only.conf` are generated with live Cloudflare IPv4/IPv6 ranges, confirm the first site does NOT include `allow-cloudflare-only.conf`, and confirm the second site DOES include `allow-cloudflare-only.conf`.

### Implementation for User Story 2

- [X] T008 [P] [US2] Update `roles/nginx/templates/update_cloudflare_ips.sh.j2` based on the reference `update-cf-ips.sh` gist to fetch IPv4/IPv6 lists from `https://www.cloudflare.com/ips-v4/` and `https://www.cloudflare.com/ips-v6/`, write `{{ nginx_config_dir }}/conf.d/cloudflare.conf` (with `set_real_ip_from`, `real_ip_header CF-Connecting-IP;`, `real_ip_recursive {{ nginx_real_ip_recursive }};`, and `geo $realip_remote_addr $is_cloudflare`), write `{{ nginx_config_dir }}/allow-cloudflare-only.conf`, and validate/reload Nginx safely
- [X] T009 [US2] Update `roles/nginx/templates/site.conf.j2` so built-in site types include `include {{ nginx_config_dir }}/allow-cloudflare-only.conf;` only when `item.cloudflare_filter | default(false) | bool` is `true` (replacing the legacy `cloudflare_ips.conf` and `real_ip_header` lines inside `server {}`)
- [X] T010 [US2] Update `roles/nginx/tasks/main.yml` to compute `nginx_use_cloudflare` (`true` when `nginx_cloudflare_enabled | bool` or any enabled site has `cloudflare_real_ip: true` or `cloudflare_filter: true`), deploy `/usr/local/bin/update_cloudflare_ips.sh` before `nginx.conf` and site templates, execute it when `cloudflare.conf` or `allow-cloudflare-only.conf` is missing or when `/usr/local/bin/update_cloudflare_ips.sh` changed, and remove `conf.d/cloudflare.conf`, `allow-cloudflare-only.conf`, legacy `cloudflare_ips.conf`, and the weekly cron job when `nginx_use_cloudflare` is `false`
- [X] T011 [US2] Extend `roles/nginx/molecule/default/converge.yml` and `roles/nginx/molecule/default/verify.yml` to test both a site with `cloudflare_real_ip: true` (`cloudflare_filter: false`) and a site with `cloudflare_filter: true`, verifying `cloudflare.conf` contents, `allow-cloudflare-only.conf` inclusion separation, and `200 OK` vs `403 Forbidden` behavior

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Configure Additional Trusted Proxies (Priority: P3)

**Goal**: Allow operators to configure `nginx_trusted_proxies` (along with `nginx_real_ip_header` and `nginx_real_ip_recursive`) so trusted proxy IPs/CIDRs are injected into `conf.d/cloudflare.conf` (`set_real_ip_from` and `$is_cloudflare` geo block) when Cloudflare mode is enabled, or rendered to `conf.d/trusted_proxies.conf` when Cloudflare mode is disabled.

**Independent Test**: Configure `nginx_trusted_proxies` with custom CIDRs (e.g., `['::1', '127.0.0.1', '10.10.0.0/16']`), verify they appear in `cloudflare.conf` (`set_real_ip_from` and `geo $realip_remote_addr $is_cloudflare`) when Cloudflare mode is active, and verify `/etc/nginx/conf.d/trusted_proxies.conf` is rendered and validated when Cloudflare mode is inactive.

### Implementation for User Story 3

- [X] T012 [P] [US3] Create `roles/nginx/templates/trusted_proxies.conf.j2` rendering `set_real_ip_from {{ ip }};` for each entry in `nginx_trusted_proxies`, `real_ip_header {{ nginx_real_ip_header }};`, and `real_ip_recursive {{ nginx_real_ip_recursive }};`
- [X] T013 [US3] Update `roles/nginx/tasks/main.yml` to render `{{ nginx_config_dir }}/conf.d/trusted_proxies.conf` (mode `'0644'`, notifying `"validate and reload nginx"`) when `not (nginx_use_cloudflare | bool)` and `nginx_trusted_proxies | length > 0`, and remove `{{ nginx_config_dir }}/conf.d/trusted_proxies.conf` when `nginx_use_cloudflare | bool` or `nginx_trusted_proxies | length == 0`
- [X] T014 [US3] Extend `roles/nginx/molecule/default/converge.yml` and `roles/nginx/molecule/default/verify.yml` to configure custom `nginx_trusted_proxies` (`['::1', '127.0.0.1', '10.10.0.0/16']`), verify their presence in `cloudflare.conf`, and verify standalone `trusted_proxies.conf` rendering when Cloudflare mode is disabled

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, linting, and full 5-distro Molecule verification per Constitution Principle V

- [X] T015 [P] Update `roles/nginx/README.md` and `roles/nginx/meta/main.yml` (`min_ansible_version: "2.21.0"`) with complete documentation for `custom_config`, `template`, `vars`, `nginx_cloudflare_enabled`, `cloudflare_real_ip`, `cloudflare_filter`, `nginx_trusted_proxies`, `nginx_real_ip_header`, and `nginx_real_ip_recursive`
- [X] T016 Run `.venv/bin/yamllint .` and `.venv/bin/ansible-lint` from the repository root and fix any warnings or errors across `roles/nginx/`
- [X] T017 Execute `molecule test` sequentially across all 5 target distro images (`geerlingguy/docker-ubuntu2204-ansible:latest`, `geerlingguy/docker-ubuntu2404-ansible:latest`, `geerlingguy/docker-debian12-ansible:latest`, `geerlingguy/docker-rockylinux9-ansible:latest`, `geerlingguy/docker-rockylinux8-ansible:latest`) from `roles/nginx/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational phase completion
  - User Story 1 (P1): Custom site configs (`custom_config`) and custom templates (`template` + `vars`)
  - User Story 2 (P2): Updated Cloudflare script (`cloudflare.conf` & `allow-cloudflare-only.conf`) and separation of trusted proxy vs access restriction
  - User Story 3 (P3): Configurable trusted proxies (`nginx_trusted_proxies` and `trusted_proxies.conf`)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start immediately after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2); updates `update_cloudflare_ips.sh.j2`, `site.conf.j2`, and `tasks/main.yml`
- **User Story 3 (P3)**: Can start after Foundational (Phase 2); adds `trusted_proxies.conf.j2` and integrates with `tasks/main.yml`

### Parallel Opportunities

- In **Phase 1 (Setup)**: `T001` (`molecule/default/templates/custom_vhost.conf.j2`) and `T002` (`vars/Debian.yml`, `vars/RedHat.yml`, `tasks/setup-RedHat.yml`) touch independent files and can run in parallel.
- Across **User Stories**: `T008` (`templates/update_cloudflare_ips.sh.j2`) and `T012` (`templates/trusted_proxies.conf.j2`) touch distinct template files and can be developed in parallel after Phase 2.
- In **Phase 6 (Polish)**: `T015` (`roles/nginx/README.md` & `meta/main.yml`) can be completed prior to running `T016` (linters) and `T017` (5-distro Molecule matrix).

---

## Parallel Example: Templates Across Stories

```bash
# Launch independent template tasks in parallel after Phase 2:
Task: "T008 [P] [US2] Update roles/nginx/templates/update_cloudflare_ips.sh.j2"
Task: "T012 [P] [US3] Create roles/nginx/templates/trusted_proxies.conf.j2"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`–`T002`)
2. Complete Phase 2: Foundational (`T003`–`T005`)
3. Complete Phase 3: User Story 1 (`T006`–`T007`)
4. **STOP and VALIDATE**: Verify `custom_config` and `template` + `vars` sites render and pass `nginx -t`

### Incremental Delivery

1. Complete Setup + Foundational → Defaults, assertions, and RedHat `conf.d` cleanup safety ready
2. Add User Story 1 → Full-file `custom_config` and `template` + `vars` working → Verify (MVP!)
3. Add User Story 2 → Cloudflare `cloudflare.conf` + `allow-cloudflare-only.conf` and real-IP/filter separation working → Verify
4. Add User Story 3 → Custom `nginx_trusted_proxies` and standalone `trusted_proxies.conf` working → Verify
5. Complete Polish → `README.md`, `yamllint .`, `ansible-lint`, and full 5-distro Molecule test loop
