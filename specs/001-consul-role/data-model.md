# Data Model: HashiCorp Consul Role (`consul`)

**Feature**: `001-consul-role`  
**Date**: 2026-10-18

## Entities

### 1. Consul Node Agent Configuration (`consul_*` top-level variables)

Represents the per-host HashiCorp Consul daemon configuration rendered to `{{ consul_config_dir }}/consul.hcl` (and optionally `{{ consul_config_dir }}/extra.json`).

| Field / Variable | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `consul_mode` | `string` | `"client"` | Yes | Must be `"server"` or `"client"` |
| `consul_bootstrap_expect` | `integer` | `1` | When `consul_mode == 'server'` | Integer `>= 1`; omitted from config when `consul_mode == 'client'` |
| `consul_datacenter` | `string` | `"dc1"` | Yes | Non-empty string |
| `consul_node_name` | `string` | `"{{ inventory_hostname }}"` | Yes | Non-empty string |
| `consul_data_dir` | `string` | `"/opt/consul"` | Yes | Absolute path |
| `consul_config_dir` | `string` | `"/etc/consul.d"` | Yes | Absolute path |
| `consul_bind_addr` | `string` | `"0.0.0.0"` | Yes | Valid IPv4/IPv6 address or Go-sockaddr template |
| `consul_advertise_addr` | `string` | `"{{ ansible_default_ipv4.address \| default('127.0.0.1') }}"` | No | Valid routable/private IPv4/IPv6 address |
| `consul_client_addr` | `string` | `"127.0.0.1"` | Yes | Valid IPv4/IPv6 address list |
| `consul_ui` | `boolean` | `false` | Yes | Boolean (`true` / `false`) |
| `consul_log_level` | `string` | `"INFO"` | Yes | One of `"TRACE"`, `"DEBUG"`, `"INFO"`, `"WARN"`, `"ERR"` |
| `consul_retry_join` | `list[string]` | `[]` | No | List of peer IPs, DNS names, or cloud auto-join expressions |
| `consul_encrypt` | `string` | `""` | No | Optional 32-byte base64-encoded gossip key |
| `consul_extra_config` | `dict` | `{}` | No | Arbitrary top-level Consul configuration key-value map |
| `consul_package_state` | `string` | `"present"` | Yes | `"present"` or `"latest"` |

---

### 2. Advertised Service Definition (`consul_services` list item)

Represents a service advertised by the local Consul node, rendered to `{{ consul_config_dir }}/service-{{ item.id | default(item.name) }}.json`.

| Field | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `name` | `string` | — | **Yes** | Non-empty service name (`[a-zA-Z0-9_-]+`) |
| `id` | `string` | `item.name` | No | Unique service instance ID on this host; safe filename characters (`[a-zA-Z0-9_-]+`) |
| `port` | `integer` | Omitted | No | Integer between `1` and `65535` if specified |
| `address` | `string` | Omitted | No | Optional IP/hostname override for the service |
| `tags` | `list[string]` | `[]` | No | List of string tags |
| `meta` | `dict[string, string]` | `{}` | No | Key-value metadata strings |
| `checks` | `list[HealthCheck]` | `[]` | No | List of health check dictionaries (see Entity 3) |

---

### 3. Service Health Check (`consul_services[].checks` list item)

Represents a health probe attached to an advertised service.

| Field | Type | Default | Required | Validation Rules |
|---|---|---|---|---|
| `id` | `string` | Omitted | No | Optional check identifier |
| `name` | `string` | Omitted | No | Optional human-readable check name |
| `http` | `string` | Omitted | Conditional | Full HTTP/HTTPS URL to probe (mutually exclusive with `tcp` / `args`) |
| `tcp` | `string` | Omitted | Conditional | `host:port` TCP socket to probe |
| `args` | `list[string]` | Omitted | Conditional | Command and arguments for script check |
| `interval` | `string` | `"10s"` | Yes (for active checks) | Duration string (e.g. `"10s"`, `"30s"`) |
| `timeout` | `string` | `"2s"` | No | Duration string (e.g. `"2s"`, `"5s"`) |
| `deregister_critical_service_after` | `string` | Omitted | No | Duration string (e.g. `"1m"`, `"10m"`) |

## Relationships & Lifecycle Transitions

1. **Consul Node Agent (1) ──> (0..N) Advertised Service Definitions**:
   - Each node runs one Consul agent instance (`consul.service`) reading all `.hcl` and `.json` files inside `{{ consul_config_dir }}`.
   - Each item in `consul_services` produces exactly one `service-<id>.json` file in `{{ consul_config_dir }}`.
2. **Advertised Service Definition (1) ──> (0..N) Service Health Checks**:
   - Health checks are embedded within the `checks` array of their parent `service` JSON object.
3. **State Transitions**:
   - **Initial Provisioning**: Repository added -> `consul` package installed -> `consul.hcl` and `service-*.json` rendered -> `consul validate` executed -> `consul.service` enabled and started.
   - **Service Catalog Update**: `consul_services` item added/modified/removed -> `service-*.json` created/updated or purged (when `consul_services_purge: true`) -> handler runs `consul validate /etc/consul.d` -> handler reloads `consul.service` (`state: reloaded`).
   - **Core Agent Mode/Network Update**: `consul_mode` or `consul.hcl` parameters modified -> `consul.hcl` updated -> handler runs `consul validate /etc/consul.d` -> handler restarts `consul.service` (`state: restarted`).
