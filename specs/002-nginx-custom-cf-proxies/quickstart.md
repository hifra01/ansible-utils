# Quickstart & Validation Guide: `hifra01.utils.nginx`

**Feature**: `002-nginx-custom-cf-proxies`  
**Date**: 2026-11-02

## Prerequisites

- Python virtual environment with collection test dependencies installed:
  ```bash
  source .venv/bin/activate
  pip install -r requirements.txt
  ```
- Running Docker daemon (for Molecule multi-distro container verification).

---

## Scenario 1: Static Analysis & Linting

From the repository root, run `yamllint` and `ansible-lint`:

```bash
.venv/bin/yamllint .
.venv/bin/ansible-lint
```

**Expected Outcome**: Both linters exit `0` with zero errors.

---

## Scenario 2: Single-Distro Molecule Iteration

Run the Molecule scenario against the default Ubuntu 24.04 container:

```bash
cd roles/nginx
../../.venv/bin/molecule converge
../../.venv/bin/molecule verify
../../.venv/bin/molecule idempotence
../../.venv/bin/molecule destroy
```

**Expected Outcome**:
- `converge` installs Nginx and deploys:
  1. A built-in `static` site (`default`) with `cloudflare_real_ip: true` and `cloudflare_filter: false` (trusting Cloudflare IPs without blocking non-Cloudflare traffic).
  2. A built-in site with `cloudflare_filter: true` (including `/etc/nginx/allow-cloudflare-only.conf`).
  3. A site using inline `custom_config` with injected `vars`.
  4. A site using a custom `template` with injected `vars`.
  5. Custom `nginx_trusted_proxies` (e.g. `['::1', '127.0.0.1', '10.10.0.0/16']`).
- `idempotence` re-runs `converge` with `changed=0`.
- `verify` confirms:
  1. `nginx` service is enabled and active, and `nginx -t` exits `0`.
  2. `/etc/nginx/conf.d/cloudflare.conf` and `/etc/nginx/allow-cloudflare-only.conf` exist and contain `set_real_ip_from`, `real_ip_header CF-Connecting-IP;`, `real_ip_recursive on;`, and `geo $realip_remote_addr $is_cloudflare` with all `nginx_trusted_proxies` and Cloudflare ranges.
  3. Built-in site with `cloudflare_filter: false` does NOT include `allow-cloudflare-only.conf`, while the site with `cloudflare_filter: true` DOES include `allow-cloudflare-only.conf`.
  4. Both the `custom_config` site and the `template` + `vars` site respond with the expected HTTP status and body containing the injected variable values.
  5. Standalone `trusted_proxies.conf` mode (`nginx_cloudflare_enabled: false` and no Cloudflare sites) renders `/etc/nginx/conf.d/trusted_proxies.conf` cleanly and passes `nginx -t`.

---

## Scenario 3: Full 5-Distro Matrix Verification

Run the mandatory 5-distro verification loop from `roles/nginx/`:

```bash
cd roles/nginx
for img in \
  geerlingguy/docker-ubuntu2204-ansible:latest \
  geerlingguy/docker-ubuntu2404-ansible:latest \
  geerlingguy/docker-debian12-ansible:latest \
  geerlingguy/docker-rockylinux9-ansible:latest \
  geerlingguy/docker-rockylinux8-ansible:latest; do
  echo "=== $img"
  MOLECULE_DISTRO="$img" ../../.venv/bin/molecule test && echo "PASS $img" || echo "FAIL $img"
done
```

**Expected Outcome**: All 5 distributions report `PASS`.

---

## Example Playbook Usage

See [contracts/role-interface.md](contracts/role-interface.md) and [data-model.md](data-model.md) for the complete variable schema.

```yaml
---
- name: Configure Nginx with Cloudflare Trusted Proxies and Custom Sites
  hosts: web_servers
  become: true
  roles:
    - role: hifra01.utils.nginx
      vars:
        # Trust Cloudflare IPs + internal load balancer CIDR for real-IP resolution
        nginx_cloudflare_enabled: true
        nginx_trusted_proxies:
          - "::1"
          - "127.0.0.1"
          - "10.0.0.0/8"

        nginx_sites:
          # Site 1: Trusts Cloudflare real-IP (via global nginx_cloudflare_enabled)
          # but still allows non-Cloudflare direct traffic
          - name: public_site
            listen: 80
            domains: ["public.example.com"]
            type: static
            root: /var/www/html
            cloudflare_filter: false

          # Site 2: Restricts access to Cloudflare and trusted proxies only (403 otherwise)
          - name: protected_site
            listen: 80
            domains: ["protected.example.com"]
            type: proxy
            proxy_pass: "http://127.0.0.1:8080"
            cloudflare_filter: true

          # Site 3: Full inline custom site config with variable injection
          - name: custom_inline
            custom_config: |
              server {
                  listen {{ custom_port }};
                  server_name {{ custom_domain }};
                  location /healthz {
                      return 200 "ok\n";
                  }
              }
            vars:
              custom_port: 8081
              custom_domain: "inline.example.com"

          # Site 4: Custom Jinja2 template with variable injection
          - name: custom_templated
            template: "templates/my_vhost.conf.j2"
            vars:
              app_port: 9000
              server_name: "templated.example.com"

        nginx_enabled_sites:
          - public_site
          - protected_site
          - custom_inline
          - custom_templated
```
