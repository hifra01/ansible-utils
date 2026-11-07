# Phase 0 Research: Percona Server for MongoDB Role (`percona_mongodb`)

**Feature**: `003-percona-mongodb-role`  
**Date**: 2026-11-05

## 1. Official Percona Repository & Package Setup Across Debian & RedHat Families

- **Decision**:
  - **Repository Bootstrap (`percona-release`)**:
    - **Debian Family (Ubuntu 22.04, Ubuntu 24.04, Debian 12)**: Install prerequisite packages (`ca-certificates`, `curl`, `gnupg`, `lsb-release`), check `/usr/bin/percona-release` via `ansible.builtin.stat`, download `https://repo.percona.com/apt/percona-release_latest.generic_all.deb` to `/tmp/percona-release_latest.generic_all.deb` when absent, install via `ansible.builtin.apt: deb: ...`, and remove the temporary `.deb` file.
    - **RedHat Family (Rocky Linux 8, Rocky Linux 9, AlmaLinux, RHEL)**: Install prerequisite packages (`ca-certificates`, `curl`, `gnupg2`, `openssl`), check `/usr/bin/percona-release` via `ansible.builtin.stat`, and install `https://repo.percona.com/yum/percona-release-latest.noarch.rpm` via `ansible.builtin.dnf` with `disable_gpg_check: true` when absent.
  - **Version Mapping & `percona-release enable-only`**:
    - Map user-friendly `percona_mongodb_version` (`"8.0"` -> `psmdb-80`, `"7.0"` -> `psmdb-70`, `"6.0"` -> `psmdb-60`, or pass through `psmdb-*` codes directly).
    - Check whether the target repository file exists (`/etc/apt/sources.list.d/percona-{{ _percona_mongodb_repo_product }}-release.list` on Debian-family or `/etc/yum.repos.d/percona-{{ _percona_mongodb_repo_product }}-release.repo` on RedHat-family) using `ansible.builtin.stat`.
    - When absent, run `percona-release enable-only {{ _percona_mongodb_repo_product }} release` (followed by `ansible.builtin.apt: update_cache: true` on Debian-family).
  - **Packages & Service Names**:
    - Install the meta-package `percona-server-mongodb` (which pulls `percona-server-mongodb-server`, `percona-server-mongodb-mongos`, `percona-server-mongodb-shell`, `percona-server-mongodb-tools`, and `percona-mongodb-mongosh` on both Debian and RedHat families).
    - Systemd unit name: `mongod` on both Debian and RedHat families.
- **Rationale**:
  - Follows the exact pattern proven in `roles/percona_mysql` across all 5 CI distributions (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`).
  - Guarding `percona-release enable-only` with `stat` on the generated repository file guarantees `changed=0` on subsequent runs without invoking network repository re-enable commands.
- **Alternatives Considered**:
  - *Running `percona-release setup psmdb-80` unconditionally*: Rejected because it modifies repository state and runs package cache refreshes on every execution, breaking idempotency.

## 2. OS-Specific Paths, Daemon User/Group, and `/etc/mongod.conf` Management

- **Decision**:
  - Isolate OS-specific defaults in `vars/Debian.yml` and `vars/RedHat.yml`:
    - **Daemon User & Group**: Unlike upstream `mongodb-org` (which uses `mongodb:mongodb` on Debian/Ubuntu), Percona Server for MongoDB (`percona-server-mongodb`) creates and runs as `mongod:mongod` on **both** Debian/Ubuntu and RHEL/Rocky.
    - **Default `dbPath`**: `/var/lib/mongodb` on Debian-family; `/var/lib/mongo` on RedHat-family (overridable via `percona_mongodb_db_path`).
    - **Default `systemLog.path`**: `/var/log/mongodb/mongod.log` on Debian-family; `/var/log/mongo/mongod.log` on RedHat-family (overridable via `percona_mongodb_log_path`).
    - **Process Management**: Inspect or align `processManagement` with the package-provided systemd unit (`mongod.service`). On RedHat-family (and Percona packages using `PIDFile=/var/run/mongod.pid` with `Type=forking`), preserve `fork: true` and `pidFilePath: /var/run/mongod.pid`; on distributions where `mongod.service` runs in foreground or uses `fork: true`, match the distro's `vars/<os_family>.yml` process management settings (or inspect `/lib/systemd/system/mongod.service` / `/usr/lib/systemd/system/mongod.service` `Type=forking`).
  - Render `/etc/mongod.conf` from `templates/mongod.conf.j2` (owned by `root:root`, mode `'0644'`), merging structured sections (`storage`, `systemLog`, `processManagement`, `net`, optional `security`, optional `replication`) with `percona_mongodb_extra_config` via the Jinja2 `combine(recursive=True)` filter and serializing clean YAML via `to_nice_yaml(indent=2)`.
- **Rationale**:
  - Building a structured dictionary in Jinja2 and rendering with `to_nice_yaml(indent=2)` guarantees valid YAML syntax in `/etc/mongod.conf` and allows `percona_mongodb_extra_config` to cleanly override or extend any top-level section (`setParameter`, `operationProfiling`, `auditLog`, `net.tls`, etc.) without duplicate YAML keys.
- **Alternatives Considered**:
  - *Line-by-line regex editing of `/etc/mongod.conf`*: Rejected because YAML indentation and multi-line sections (`security`, `replication`, `storage.wiredTiger`) are fragile with `lineinfile`/`blockinfile`.

## 3. Zero-Restart Localhost Exception Bootstrap for Single-Node & Multi-Node Replica Sets

- **Decision**:
  - Leverage MongoDB 8.0's documented **localhost exception** order of operations so that `/etc/mongod.conf` is rendered in its final target state **once** (with `security.authorization: enabled`, `security.keyFile` when replica set is enabled, and `replication.replSetName` when replica set is enabled) without requiring a two-phase config rewrite and service restart:
    1. **Keyfile Preparation**: When `percona_mongodb_replset_enabled: true` and `percona_mongodb_auth_enabled: true`:
       - If `percona_mongodb_keyfile_content` is non-empty, write it to `percona_mongodb_keyfile_path` (`/etc/mongod.keyfile`, owner `mongod:mongod`, mode `'0400'`).
       - If `percona_mongodb_keyfile_content` is empty and `percona_mongodb_replset_members | length <= 1` (single-instance replica set mode), check `stat` on `percona_mongodb_keyfile_path` and generate a 756-byte base64 keyfile via `openssl rand -base64 756` only when the file does not yet exist, then enforce owner `mongod:mongod` and mode `'0400'`.
    2. **Start `mongod`**: Render `/etc/mongod.conf`, ensure `mongod` is enabled and started, flush handlers if `/etc/mongod.conf` or the keyfile changed, and wait for TCP port `{{ percona_mongodb_port }}` on `127.0.0.1`.
    3. **Probe Admin Authentication**: When `percona_mongodb_auth_enabled: true`, test whether `mongosh --quiet --host 127.0.0.1 --port {{ percona_mongodb_port }} -u {{ percona_mongodb_admin_user }} -p {{ percona_mongodb_admin_password }} --authenticationDatabase admin --eval "db.runCommand({ connectionStatus: 1 }).ok"` succeeds (`changed_when: false`, `failed_when: false`).
    4. **Replica Set Initialization (`rs.initiate`)**: When `percona_mongodb_replset_enabled: true` and `percona_mongodb_replset_init: true`:
       - Build the desired member list: if `percona_mongodb_replset_members` is empty (`[]`), default to `[{ '_id': 0, 'host': percona_mongodb_replset_advertise_host ~ ':' ~ (percona_mongodb_port | string) }]`; otherwise normalize each item in `percona_mongodb_replset_members` with sequential `_id` (`0..N-1`), `host`, and optional `priority`, `arbiterOnly`, `hidden`, `votes`.
       - Connect via `127.0.0.1` (using admin credentials if step 3 succeeded, or unauthenticated localhost exception if step 3 failed because no admin user exists yet) to check `rs.status().ok`.
       - If the replica set is not yet initialized (`codeName == 'NotYetInitialized'` or `code == 94`), execute `rs.initiate({ _id: percona_mongodb_replset_name, members: ... })` and poll `db.hello().isWritablePrimary` until `true` (up to 60 seconds).
    5. **Admin User Bootstrap**: When `percona_mongodb_auth_enabled: true` and (`percona_mongodb_replset_init: true` or not `percona_mongodb_replset_enabled`) and step 3 showed the admin user was not yet created:
       - While connected to `127.0.0.1` (now `PRIMARY` if replica set is enabled, with localhost exception still active because `admin.system.users` is empty), execute `db.getSiblingDB('admin').createUser({ user: ..., pwd: ..., roles: [{ role: 'root', db: 'admin' }, { role: 'userAdminAnyDatabase', db: 'admin' }, { role: 'clusterAdmin', db: 'admin' }] })`.
       - Creating this first user immediately and permanently closes the MongoDB localhost exception without requiring a `mongod` restart.
- **Rationale**:
  - In MongoDB, when `security.keyFile` is configured on a fresh replica set node, `security.authorization` is implicitly enabled, and the localhost exception allows `rs.initiate()`, `rs.status()`, `db.hello()`, and creating the first user in `admin` over `127.0.0.1` once the node is elected `PRIMARY`.
  - Avoiding a temporary "unauthenticated" `/etc/mongod.conf` followed by a "secured" `/etc/mongod.conf` ensures `/etc/mongod.conf` never changes during a single run or across repeat runs, preserving strict idempotency.
- **Alternatives Considered**:
  - *Starting `mongod` without `security`, initializing RS + creating user, then rewriting `/etc/mongod.conf` with `security` and restarting `mongod`*: Rejected because it forces two service restarts on initial convergence and complicates handler flushing.

## 4. Idempotent Replica Set Reconfiguration (`rs.reconfig`) & User Management via `mongosh`

- **Decision**:
  - **Replica Set Reconfiguration (`FR-006`)**:
    - When the replica set was already initialized prior to the current run (`percona_mongodb_replset_enabled: true` and `percona_mongodb_replset_init: true`), run a `mongosh` script that compares the normalized desired members (`host`, `priority`, `arbiterOnly`, `hidden`, `votes`) against `rs.conf().members`.
    - Only if a difference is detected, increment `cfg.version`, assign the updated `members` array, run `rs.reconfig(cfg)`, and print `"CHANGED"`; otherwise print `"UNCHANGED"`. Set `changed_when: "'CHANGED' in _percona_mongodb_rs_reconfig.stdout"`.
  - **Application User Provisioning (`FR-008`)**:
    - On `percona_mongodb_replset_init: true` or standalone (`percona_mongodb_replset_enabled: false`), iterate over `percona_mongodb_users` (`loop_control.loop_var: mongodb_user`).
    - Pass user credentials safely via environment variables (`MONGO_ADMIN_USER`, `MONGO_ADMIN_PASS`, `MONGO_TARGET_USER`, `MONGO_TARGET_PASS`, `MONGO_TARGET_DB`, `MONGO_TARGET_ROLES_JSON`, `MONGO_TARGET_STATE`) to a `mongosh --quiet` evaluation block (`no_log: true`).
    - For `state: "present"` (default): inspect `db.getSiblingDB(targetDb).getUser(targetUser)`. If missing, call `createUser(...)` and output `"CHANGED"`. If present, compare existing roles with desired roles (and optionally test password authentication via `db.getSiblingDB(targetDb).auth(targetUser, targetPass)`): if either roles or password differ, call `updateUser(...)` and output `"CHANGED"`, else output `"UNCHANGED"`.
    - For `state: "absent"`: if `getUser(targetUser)` is non-null, call `dropUser(targetUser)` and output `"CHANGED"`, else output `"UNCHANGED"`.
- **Rationale**:
  - Using native `mongosh` with JSON-normalized role comparison and `db.auth()` verification provides full idempotency for user creation, role updates, password rotation, and user removal without requiring `community.mongodb` or `pymongo` on target hosts (especially important on Rocky Linux 8 where Python 3.9 is used).
- **Alternatives Considered**:
  - *`community.mongodb.mongodb_user` / `mongodb_replicaset`*: Rejected because `community.mongodb` is not in `galaxy.yml` dependencies and requires `pymongo` installed for the target Python interpreter.

## 5. Multi-Distro Molecule Verification Strategy

- **Decision**:
  - Configure `roles/percona_mongodb/molecule/default/` to test the role's primary single-instance replica set workflow across all 5 supported CI distributions (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`):
    - `molecule.yml`: Privileged systemd Docker container using `${MOLECULE_DISTRO:-geerlingguy/docker-ubuntu2404-ansible}`.
    - `prepare.yml`: Standard RHEL/Rocky 8 Python 3.9 bootstrap via `raw`.
    - `converge.yml`: Apply `hifra01.utils.percona_mongodb` with:
      - `percona_mongodb_replset_enabled: true`
      - `percona_mongodb_replset_name: "rs0"`
      - `percona_mongodb_replset_members: []` (exercising the single-instance replica set auto-initialization and auto-keyfile generation)
      - `percona_mongodb_auth_enabled: true`
      - `percona_mongodb_admin_user: "admin"`
      - `percona_mongodb_admin_password: "MoleculeAdminPass!2026"`
      - `percona_mongodb_oplog_size_mb: 256`
      - `percona_mongodb_users`: a sample application user (`app_user` on `app_db` with `readWrite` role)
    - `verify.yml`:
      1. Assert `mongod` systemd service is enabled and active (`running`).
      2. Assert `/etc/mongod.conf` (`0644`) and `/etc/mongod.keyfile` (`0400`, owned by `mongod:mongod`) exist with expected permissions.
      3. Assert TCP port `27017` is listening.
      4. Assert unauthenticated `rs.status()` command is rejected with `Unauthorized` (`SC-003`).
      5. Assert authenticated `rs.status()` reports `ok: 1`, `set: "rs0"`, `members.length === 1`, and `myState === 1` (`PRIMARY`) (`SC-001`).
      6. Assert `app_user` can authenticate against `app_db` and execute a multi-document ACID transaction (proving single-instance replica set oplog functionality, `SC-002` & `SC-003`).
- **Rationale**:
  - Directly validates every success criterion (`SC-001` through `SC-005`) including single-instance replica set initialization, multi-document transactions, keyfile security, authentication enforcement, and idempotency across all 5 Linux distributions.
- **Alternatives Considered**:
  - *Testing only standalone mode in Molecule*: Rejected because single-instance replica set creation is the primary user requirement.
