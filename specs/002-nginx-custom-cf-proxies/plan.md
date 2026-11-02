# Implementation Plan: Nginx Custom Site Configs, Cloudflare Geo/Real-IP Script, and Trusted Proxies (`nginx`)

**Branch**: `002-nginx-custom-cf-proxies` | **Date**: 2026-11-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-nginx-custom-cf-proxies/spec.md`

## Summary

Update the `hifra01.utils.nginx` Ansible role under `roles/nginx/` to:
1. Support full-file custom site configurations (`custom_config`) and custom Jinja2 site templates (`template`) with per-site variable injection (`vars`) in `nginx_sites` alongside existing `static`, `proxy`, and `php` archetypes.
2. Update the Cloudflare IP updater script (`templates/update_cloudflare_ips.sh.j2`) based on the reference `update-cf-ips.sh` gist to generate `/etc/nginx/conf.d/cloudflare.conf` (`set_real_ip_from`, `real_ip_header CF-Connecting-IP;`, `real_ip_recursive on;`, and `geo $realip_remote_addr $is_cloudflare`) and `/etc/nginx/allow-cloudflare-only.conf` (`if ($is_cloudflare = 0) { return 403; }`).
3. Decouple adding Cloudflare IPs as trusted proxies (`nginx_cloudflare_enabled: true` globally or `cloudflare_real_ip: true` per site) from restricting non-Cloudflare access (`cloudflare_filter: true` per site).
4. Allow configuring trusted proxies (`nginx_trusted_proxies`, `nginx_real_ip_header`, `nginx_real_ip_recursive`) injected into `cloudflare.conf` when Cloudflare mode is active or rendered to `/etc/nginx/conf.d/trusted_proxies.conf` when Cloudflare mode is inactive, while preserving global `conf.d` files during RedHat site cleanup.

## Technical Context

**Language/Version**: YAML / Ansible (`ansible-core >= 2.21.0`, tested with Python 3.9–3.14)  
**Primary Dependencies**: `ansible.builtin` modules (`assert`, `include_vars`, `include_tasks`, `file`, `stat`, `command`, `set_fact`, `template`, `cron`, `find`, `service`, `uri`), `curl` (for Cloudflare IPv4/IPv6 list retrieval)  
**Storage**: Host filesystem configuration files under `/etc/nginx/` (`nginx.conf`, `conf.d/cloudflare.conf`, `conf.d/trusted_proxies.conf`, `allow-cloudflare-only.conf`, `sites-available/*.conf`, `sites-enabled/*.conf`) and `/usr/local/bin/update_cloudflare_ips.sh`  
**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]`) across all 5 target distro images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`)  
**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`) running `systemd`  
**Project Type**: Ansible Collection role (`hifra01.utils.nginx`)  
**Performance Goals**: Single-node convergence in `< 60s`; zero changes (`changed=0`) on second consecutive run; reload-only (`state: reloaded`) on site/Cloudflare/trusted-proxy configuration updates after `nginx -t` validation  
**Constraints**: Must pass `yamllint .` and `ansible-lint` with zero errors; must preserve `cloudflare.conf` and `trusted_proxies.conf` in `/etc/nginx/conf.d` on RedHat-family distributions during unused site cleanup  
**Scale/Scope**: Existing `roles/nginx/` role (`defaults/main.yml`, `tasks/main.yml`, `templates/site.conf.j2`, `templates/update_cloudflare_ips.sh.j2`, `templates/trusted_proxies.conf.j2`, `README.md`, and `molecule/default/*`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Verification Notes |
|---|---|---|
| **I. Spec-Driven Role Development** | PASS | Following `speckit-specify` → `speckit-clarify` → `speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement` in `specs/002-nginx-custom-cf-proxies/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | Modifying existing scaffolded role under `roles/nginx/`; no manual edits to `.ansible/` or `.specify/` engine files. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | Supports both `Debian` and `RedHat` families; starts `tasks/main.yml` with an `ansible.builtin.assert` platform guard; all role variables prefixed with `nginx_`; OS-specific variables isolated in `vars/Debian.yml` and `vars/RedHat.yml`; task loops define `loop_control.loop_var`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | Uses FQCNs exclusively, `# SPDX-License-Identifier: MIT-0` headers, quoted octal file modes (`'0644'`, `'0755'`), `true`/`false` booleans, and `listen:` handlers validating via `nginx -t` before reload/restart. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | `roles/nginx/molecule/default/` (`converge.yml` and `verify.yml`) will verify built-in sites, `custom_config`, `template` + `vars`, Cloudflare trusted-proxy vs access-restriction separation, and `nginx_trusted_proxies` across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) plus `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | `nginx` is already registered in `.github/workflows/ci.yml` and `AGENTS.md`; `roles/nginx/README.md` will be updated with complete documentation for all new variables and examples. |

## Project Structure

### Documentation (this feature)

```text
specs/002-nginx-custom-cf-proxies/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── role-interface.md
├── checklists/
│   └── requirements.md  # Spec quality checklist (/speckit-specify command)
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code (repository root)

```text
roles/
└── nginx/
    ├── README.md                              # Complete role documentation & variable examples
    ├── defaults/
    │   └── main.yml                           # Add nginx_cloudflare_enabled, nginx_trusted_proxies, nginx_real_ip_*
    ├── handlers/
    │   └── main.yml                           # Existing "validate and reload nginx" & "validate and restart nginx"
    ├── meta/
    │   └── main.yml                           # Role metadata
    ├── tasks/
    │   ├── main.yml                           # OS/input assertions, Cloudflare & trusted_proxies tasks, site deploy & safe cleanup
    │   ├── setup-Debian.yml                   # Debian/Ubuntu package install
    │   └── setup-RedHat.yml                   # RedHat/Rocky package install
    ├── templates/
    │   ├── nginx.conf.j2                      # Main /etc/nginx/nginx.conf template
    │   ├── site.conf.j2                       # Built-in (static/proxy/php), custom_config, and template+vars renderer
    │   ├── trusted_proxies.conf.j2            # Standalone /etc/nginx/conf.d/trusted_proxies.conf template
    │   └── update_cloudflare_ips.sh.j2        # Updated Cloudflare real-IP & geo script based on reference gist
    ├── vars/
    │   ├── Debian.yml                         # Debian/Ubuntu paths & packages
    │   ├── RedHat.yml                         # RedHat/Rocky paths & packages
    │   └── main.yml
    └── molecule/
        └── default/
            ├── molecule.yml                   # 5-distro Docker systemd matrix config
            ├── prepare.yml                    # RHEL 8 python39 bootstrap + curl prerequisite
            ├── converge.yml                   # Converge role exercising static, CF real-IP, CF filter, custom_config, template+vars, trusted_proxies
            ├── verify.yml                     # Verify files, geo/real_ip directives, HTTP responses, 403 guard, and standalone trusted_proxies
            └── templates/
                └── custom_vhost.conf.j2       # Test fixture template for Molecule verification of template + vars
```

**Structure Decision**: Extends the existing `roles/nginx/` structure in-place, adding `templates/trusted_proxies.conf.j2` for standalone trusted proxy support and `molecule/default/templates/custom_vhost.conf.j2` to test controller-side custom template rendering with variable injection.

## Complexity Tracking

No Constitution violations exist.
