---
description: "Task list for Disk Partitioning, Formatting, and Persistent Mount Role (disk_mount)"
---

# Tasks: Disk Partitioning, Formatting, and Persistent Mount Role (`disk_mount`)

**Input**: Design documents from `/specs/010-disk-mount-role/`

**Prerequisites**: [plan.md](plan.md) (required), [spec.md](spec.md) (required for user stories), [research.md](research.md), [data-model.md](data-model.md), [contracts/role-interface.md](contracts/role-interface.md), [quickstart.md](quickstart.md)

**Tests**: Linting (`yamllint .`, `ansible-lint`) and multi-distro Molecule verification (`molecule test` across all 5 CI images) are mandatory per Constitution Principle V.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., `US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## Path Conventions

- **New Ansible role**: `roles/disk_mount/` (`defaults/`, `vars/`, `tasks/`, `handlers/`, `meta/`, `tests/`, `molecule/default/`, `README.md`)
- **CI workflow**: `.github/workflows/ci.yml`
- **Repository documentation**: `AGENTS.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the `disk_mount` role and default Molecule scenario using official CLI tools per Constitution Principle II

- [X] T001 Scaffold the `disk_mount` role skeleton using `ansible-galaxy role init --init-path roles disk_mount` to create `roles/disk_mount/`
- [X] T002 Remove unused generated `roles/disk_mount/files/` and `roles/disk_mount/templates/` directories and initialize the default Molecule scenario using `molecule init scenario default` inside `roles/disk_mount/molecule/default/`
- [X] T003 Remove any generated `roles/disk_mount/molecule/default/create.yml` or `roles/disk_mount/molecule/default/destroy.yml` and configure the privileged Docker systemd driver (`privileged: true`, `/sys/fs/cgroup:/sys/fs/cgroup:rw`, `cgroupns_mode: host`, `become_method: su`, `${MOLECULE_DISTRO}` image) in `roles/disk_mount/molecule/default/molecule.yml` using `roles/nginx_exporter/molecule/default/molecule.yml` as baseline
- [X] T004 [P] Create `roles/disk_mount/molecule/default/prepare.yml` with the mandatory RHEL/Rocky 8 `python39` bootstrap tasks at the top, followed by idempotent setup of 4 sparse 320 MB backing files (`/var/tmp/disk1.img`–`/var/tmp/disk4.img` via `truncate -s 320M` to satisfy XFS's >=300 MB minimum) and `losetup -P` loopback block devices (`disk1`–`disk3` for `converge.yml`, `disk4` for isolated `verify.yml` safety/lifecycle tests) persisted to `/var/tmp/molecule-loop-devices.yml`
- [X] T005 [P] Create `roles/disk_mount/molecule/default/cleanup.yml` to cleanly unmount any test mount points and detach loopback block devices recorded in `/var/tmp/molecule-loop-devices.yml` so host loop slots are never leaked

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core metadata, OS-family variables, public defaults, systemd reload handler, input validation/normalization, and on-demand package installation that MUST be complete before any user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 [P] Populate Galaxy metadata (`author`, `description`, `license`, `min_ansible_version: "2.21.0"`, `platforms` for Debian, Ubuntu, and EL 8/9, and storage/disk `galaxy_tags`) in `roles/disk_mount/meta/main.yml`
- [X] T007 [P] Define Debian-family storage variables in `roles/disk_mount/vars/Debian.yml`: `disk_mount_base_packages` (`parted`, `util-linux`, `e2fsprogs`), `disk_mount_fs_packages` (`ext4: [e2fsprogs]`, `ext3: [e2fsprogs]`, `xfs: [xfsprogs]`, `btrfs: [btrfs-progs]`, `vfat: [dosfstools]`), and `disk_mount_label_flags` (`ext4: "-L"`, `ext3: "-L"`, `xfs: "-L"`, `btrfs: "-L"`, `vfat: "-n"`)
- [X] T008 [P] Define RedHat-family storage variables in `roles/disk_mount/vars/RedHat.yml`: `disk_mount_base_packages` (`parted`, `util-linux`, `e2fsprogs`), `disk_mount_fs_packages` (`ext4: [e2fsprogs]`, `ext3: [e2fsprogs]`, `xfs: [xfsprogs]`, `btrfs: [btrfs-progs]`, `vfat: [dosfstools]`), and `disk_mount_label_flags` (`ext4: "-L"`, `ext3: "-L"`, `xfs: "-L"`, `btrfs: "-L"`, `vfat: "-n"`)
- [X] T009 [P] Define all user-tunable `disk_mount_*` default variables with explanatory comments in `roles/disk_mount/defaults/main.yml` adhering to `data-model.md` and `contracts/role-interface.md`: `disk_mount_disks: []`, `disk_mount_default_fstype: "ext4"` (one of `["ext4", "xfs", "btrfs", "ext3", "vfat"]`), `disk_mount_default_partition: true` (boolean), `disk_mount_default_partition_table: "gpt"` (one of `["gpt", "msdos"]`), `disk_mount_default_auto_mount: true` (boolean), `disk_mount_default_opts: "defaults,nofail"` (non-empty string), `disk_mount_default_fstab_src_type: "uuid"` (one of `["uuid", "partuuid", "label", "device"]`), `disk_mount_default_allow_non_empty: false` (boolean), `disk_mount_fstab_path: "/etc/fstab"` (absolute path), and `disk_mount_backup_fstab: true` (boolean)
- [X] T010 [P] Implement systemd daemon reload handler (`listen: "reload systemd daemon"`, executing `ansible.builtin.systemd: daemon_reload: true` when `ansible_facts['service_mgr'] == 'systemd'`) in `roles/disk_mount/handlers/main.yml`
- [X] T011 Implement pre-flight validation and entry normalization in `roles/disk_mount/tasks/validate.yml` validating role-level defaults and every item in `disk_mount_disks` per `data-model.md`: required `device` (non-empty starting with `/dev/`) and `path` (non-empty absolute path, not in `['/', '/boot', '/dev', '/proc', '/sys', '/run']`), `fstype in ['ext4', 'xfs', 'btrfs', 'ext3', 'vfat']`, `state in ['mounted', 'present', 'unmounted', 'absent']`, `auto_mount` boolean (rejecting `state == 'present'` when `auto_mount == false`), `partition` boolean, `partition_table in ['gpt', 'msdos']`, `partition_number | int >= 1` (and `partition_number | int <= 4` when `partition_table == 'msdos'`), non-empty `partition_start` and `partition_end`, `partition_name` empty unless `partition_table == 'gpt'`, `partition_flags` sequence, `partition_align in ['optimal', 'minimal', 'cylinder', 'none']`, `label` non-empty when `fstab_src_type == 'label'`, non-empty `opts`, `dump in [0, 1]`, `passno in [0, 1, 2]`, `fstab_src_type in ['uuid', 'partuuid', 'label', 'device']`, `allow_non_empty` and `force` booleans; compute normalized `_disk_mount_entries` (with `normalized_path`, letter- vs digit-ending `target_device`, and `effective_mkfs_opts` using `disk_mount_label_flags`); and enforce cross-entry uniqueness of `normalized_path`, uniqueness of `target_device`, no mixed `partition: true`/`false` on the same parent `device`, and consistent `partition_table` across multi-partition entries sharing a parent `device`
- [X] T012 Implement on-demand package installation in `roles/disk_mount/tasks/packages.yml` updating apt cache on `Debian` family (`cache_valid_time: 3600`) and installing `disk_mount_base_packages` plus only the `disk_mount_fs_packages[entry.fstype]` required by active entries (`state in ['mounted', 'present']`) in `_disk_mount_entries`

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 - Partition, Format, and Mount a Disk to a Target Directory (Priority: P1) 🎯 MVP

**Goal**: Provision a raw block device with default GPT full-disk partitioning (`0%`–`100%`), format it as `ext4`, create the target mount directory, and mount the volume idempotently, while treating an empty `disk_mount_disks: []` list as a zero-change no-op.

**Independent Test**: Apply `hifra01.utils.disk_mount` on a clean Linux host with a raw loopback block device configured for `/mnt/data` (default options), verify GPT partition table, partition node, `ext4` filesystem, active writable mount, zero changes on a second run with preserved data, and zero changes when `disk_mount_disks: []`.

### Implementation for User Story 1

- [X] T013 [US1] Implement initial block-device partitioning and kernel/container partition node refresh in `roles/disk_mount/tasks/partition.yml` using `community.general.parted` (`state: present`, `label`, `number`, `part_start`, `part_end`, `align`), refreshing kernel partition tables (`partprobe` with `partx -u` fallback), settling `udevadm` when active, and ensuring `/dev/<part>` exists from `/sys/class/block/<part>/dev` in udev-less containers
- [X] T014 [US1] Implement initial filesystem inspection (`blkid -o value -s TYPE`, `changed_when: false`, `failed_when: rc not in [0, 2]`) and non-destructive `community.general.filesystem` formatting for unformatted devices in `roles/disk_mount/tasks/format.yml`
- [X] T015 [US1] Implement initial mount point directory creation (`ansible.builtin.file: state: directory`) and active mounting (`ansible.posix.mount: state: mounted`) in `roles/disk_mount/tasks/mount.yml`
- [X] T016 [US1] Implement per-disk orchestration dispatcher in `roles/disk_mount/tasks/process-disk.yml` verifying `_disk_mount_entry.device` exists and is a block device (`stat.isblk`) for active entries (`state in ['mounted', 'present']`) and invoking `partition.yml`, `format.yml`, and `mount.yml` in sequence
- [X] T017 [US1] Implement role entrypoint in `roles/disk_mount/tasks/main.yml` with platform guard (`ansible_facts['os_family'] in ['Debian', 'RedHat']`), OS variable loading (`{{ ansible_facts['os_family'] }}.yml`), `validate.yml`, zero-change short-circuit when `_disk_mount_entries | length == 0`, conditional `packages.yml` when active entries exist, and per-entry `include_tasks: process-disk.yml` loop with `loop_control.loop_var: _disk_mount_entry`

**Checkpoint**: User Story 1 (MVP) is complete and independently testable

---

## Phase 4: User Story 2 - Configure Partition Table and Filesystem Format Options (Priority: P2)

**Goal**: Support full partition format options (`gpt`/`msdos`, boundaries, alignment, GPT name, flags, and `partition: false` direct formatting), multi-filesystem formatting (`ext4`, `xfs`, `btrfs`, `ext3`, `vfat`) with format-time-only volume `label` and `mkfs_opts`, post-mount folder `owner`/`group`/`mode`, and fail-fast safety guards protecting existing data (`force: false` and `allow_non_empty: false`).

**Independent Test**: Converge multiple loopback disks—one with `msdos` + `xfs` + `label` + custom `owner`/`group`/`mode`, and another with `partition: false` + `ext4` + custom `mkfs_opts`—verify partition metadata, filesystem type/label, mounted root ownership/permissions, and confirm fail-fast rejection without data loss when attempting mismatched filesystems, conflicting partition tables, whole-disk filesystem overwrite, partition device passed with `partition: true`, or mounting over a non-empty unmounted folder.

### Implementation for User Story 2

- [X] T018 [P] [US2] Extend `roles/disk_mount/tasks/partition.yml` to inspect the parent block device via `lsblk -dn -o TYPE`, `blkid -o value -s PTTYPE` (normalizing `dos` -> `msdos`), and `blkid -o value -s TYPE`: fail fast when `TYPE == 'part'` (advising `partition: false` or parent disk), fail fast when `force: false` and a conflicting partition table or whole-disk filesystem signature exists, unmount active targets and run `wipefs -a` when `force: true` resolves a conflict, and pass optional GPT `name` (when `partition_table == 'gpt'` and `partition_name` is non-empty) and `flags` (when `partition_flags` is non-empty) to `community.general.parted`
- [X] T019 [P] [US2] Extend `roles/disk_mount/tasks/format.yml` to enforce filesystem mismatch protection (`force: false` fails fast when existing `TYPE != fstype`), support `force: true` conversion (unmount active mount on `target_device` via `findmnt`/`ansible.posix.mount: state: unmounted` before running `community.general.filesystem` with `force: true`), pass `_disk_mount_entry.effective_mkfs_opts` (combining `-L`/`-n` label flag and `mkfs_opts`) only when creating or forcefully reformatting a filesystem, and leave matching existing filesystems untouched (format-time-only semantics per Q3)
- [X] T020 [P] [US2] Extend `roles/disk_mount/tasks/mount.yml` to guard against mounting over an existing unmounted non-empty directory (`findmnt -rn -M <path>`, `stat`, and `find` with `file_type: any`, `hidden: true`, `recurse: false` failing fast when `matched > 0` and `allow_non_empty` is `false` per Q2) and to apply optional `owner`, `group`, and `mode` to `path` via `ansible.builtin.file` strictly after mounting completes (`state == 'mounted'`)

**Checkpoint**: User Stories 1 AND 2 work independently with complete format options and data-protection guards

---

## Phase 5: User Story 3 - Persist Auto-Mount Across Server Restarts and Manage Mount Lifecycle (Priority: P3)

**Goal**: Persist reboot-safe `/etc/fstab` entries using stable block identifiers (`UUID` by default, or `PARTUUID`/`LABEL`/`device`) with `defaults,nofail` and systemd reload synchronization, support idempotent non-persistent (`auto_mount: false`) ephemeral mounts, and handle `present`, `unmounted`, and `absent` lifecycle states cleanly without destroying on-disk data.

**Independent Test**: Verify `auto_mount: true` writes a `UUID=` (or `LABEL=`/`PARTUUID=`/`device`) entry to `/etc/fstab` and automatically remounts with data intact after `umount` + `mount -a`; verify `auto_mount: false` mounts ephemerally with zero `/etc/fstab` entry and `changed=0` on repeat runs; verify `state: "unmounted"` and `state: "absent"` unmount and manage `/etc/fstab` while keeping on-disk files intact.

### Implementation for User Story 3

- [X] T021 [US3] Extend `roles/disk_mount/tasks/mount.yml` to resolve persistent fstab `src` via `blkid` when persistent fstab management is active (`(state == 'mounted' and auto_mount) or state == 'present'`) for `fstab_src_type` (`uuid` -> `UUID=<val>`, `partuuid` -> `PARTUUID=<val>`, `label` -> `LABEL=<val>`, `device` -> `target_device`), asserting non-empty `blkid` output when `uuid`/`partuuid`/`label` is selected, and passing `fstab: "{{ disk_mount_fstab_path }}"`, `backup: "{{ disk_mount_backup_fstab }}"`, `opts`, `dump`, and `passno` to `ansible.posix.mount` (notifying `"reload systemd daemon"` on any fstab change)
- [X] T022 [US3] Implement full `(state, auto_mount)` lifecycle handling in `roles/disk_mount/tasks/mount.yml` and `roles/disk_mount/tasks/process-disk.yml`: `state: "mounted"` + `auto_mount: false` ensures no fstab entry (`state: absent_from_fstab`) and mounts via `state: ephemeral` with `src: "{{ _disk_mount_entry.target_device }}"` only when `findmnt -rn -o SOURCE -M <path>` does not already match the canonical target device (preserving `changed=0` idempotency); `state: "present"` writes `/etc/fstab` without mounting; `state: "unmounted"` unmounts while preserving `/etc/fstab` and disk data; and `state: "absent"` runs `state: unmounted` followed by `state: absent_from_fstab` (notifying `"reload systemd daemon"`) while preserving disk data

**Checkpoint**: All three user stories (US1, US2, US3) are complete and independently testable

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: End-to-end Molecule verification across all 5 CI distributions, role & collection documentation, CI matrix registration, and final lint/test validation

- [X] T023 Write `roles/disk_mount/molecule/default/converge.yml` loading loopback device paths from `/var/tmp/molecule-loop-devices.yml` and converging `hifra01.utils.disk_mount` across 3 loopback disks covering: (1) default GPT + `ext4` + `auto_mount: true` (`UUID`, `defaults,nofail`, `owner`/`group`/`mode: '0750'`), (2) `msdos` MBR + `xfs` + `label: "XFS_DATA"` + `fstab_src_type: "label"` + `auto_mount: true`, and (3) `partition: false` whole-disk + `ext4` + `mkfs_opts: "-m 1"` + `auto_mount: false` (ephemeral mount)
- [X] T024 Write `roles/disk_mount/molecule/default/verify.yml` asserting: partition tables (`gpt` / `msdos` / none), filesystems (`ext4`, `xfs`, volume label `XFS_DATA`), active mounts and post-mount ownership/mode, `/etc/fstab` entries (`UUID=` and `LABEL=` present, ephemeral path absent), reboot simulation (`umount` + `mount -a`) preserving marker files, empty `disk_mount_disks: []` zero-change no-op, fail-fast safety guards (`block`/`rescue` verifying mismatched `fstype` with `force: false`, conflicting partition table with `force: false`, whole-disk filesystem with `partition: true` and `force: false`, non-empty unmounted directory with `allow_non_empty: false`, and invalid inputs), and lifecycle transitions (`state: "unmounted"` and `state: "absent"` preserving on-disk data)
- [X] T025 [P] Update `roles/disk_mount/tests/test.yml` to reference `hifra01.utils.disk_mount` cleanly and write comprehensive role documentation (description, supported platforms, RHEL/Rocky `btrfs` note, requirements, role variables table with defaults and per-disk schema, safety behavior, example playbooks, license) in `roles/disk_mount/README.md`
- [X] T026 [P] Add `disk_mount` entry to the Roles table in `AGENTS.md`
- [X] T027 [P] Register `disk_mount` in all 4 required locations in `.github/workflows/ci.yml` (`detect-changes.outputs`, `paths-filter` `filters`, `molecule.strategy.matrix.role`, and the `case` statement in "Check if this role should be tested")
- [X] T028 Run `yamllint .` and `ansible-lint` from the repository root and fix any warnings or errors until both exit `0`
- [X] T029 Run multi-distro Molecule verification (`./test-matrix.sh -r disk_mount`) across all 5 supported CI images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) per `quickstart.md` and confirm every distribution passes including `idempotence` and `verify`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately (`T001` → `T002` → `T003`, then `T004` & `T005` in parallel).
- **Foundational (Phase 2)**: Depends on Setup (`T001`–`T002`) — BLOCKS all user stories (`T006`–`T010` parallel; `T011` & `T012` depend on `T007`–`T009`).
- **User Story 1 (Phase 3 — P1 MVP)**: Depends on Phase 2 completion (`T013`–`T015` → `T016` → `T017`).
- **User Story 2 (Phase 4 — P2)**: Depends on Phase 3 task files (`T018` extends `partition.yml`, `T019` extends `format.yml`, `T020` extends `mount.yml` — can run in parallel across the three distinct files).
- **User Story 3 (Phase 5 — P3)**: Depends on Phase 4 `mount.yml` & `process-disk.yml` (`T021` → `T022`).
- **Polish & Cross-Cutting (Phase 6)**: Depends on Phases 3–5 completion (`T023` → `T024`; `T025`, `T026`, `T027` parallel; then `T028` lint → `T029` 5-distro Molecule test matrix).

### Parallel Opportunities

- **Setup**: `T004` (`prepare.yml`) and `T005` (`cleanup.yml`) in parallel.
- **Foundational**: `T006` (`meta/main.yml`), `T007` (`vars/Debian.yml`), `T008` (`vars/RedHat.yml`), `T009` (`defaults/main.yml`), and `T010` (`handlers/main.yml`) in parallel.
- **User Story 2**: `T018` (`tasks/partition.yml`), `T019` (`tasks/format.yml`), and `T020` (`tasks/mount.yml`) edit separate files and can be implemented in parallel.
- **Polish**: `T025` (`README.md` + `tests/test.yml`), `T026` (`AGENTS.md`), and `T027` (`.github/workflows/ci.yml`) in parallel.

---

## Parallel Example: Foundational Phase (Phase 2)

```bash
# Run in parallel after T001-T002 scaffolding completes:
Task T006: Populate Galaxy metadata in roles/disk_mount/meta/main.yml
Task T007: Define Debian-family storage packages & label flags in roles/disk_mount/vars/Debian.yml
Task T008: Define RedHat-family storage packages & label flags in roles/disk_mount/vars/RedHat.yml
Task T009: Define disk_mount_* default variables in roles/disk_mount/defaults/main.yml
Task T010: Implement reload systemd daemon handler in roles/disk_mount/handlers/main.yml
```

## Parallel Example: User Story 2 (Phase 4)

```bash
# Run in parallel across distinct task files after Phase 3 MVP completes:
Task T018: Partition safety guards & custom partition options in roles/disk_mount/tasks/partition.yml
Task T019: Multi-filesystem label/mkfs_opts & mismatch safety in roles/disk_mount/tasks/format.yml
Task T020: Non-empty directory guard & post-mount permissions in roles/disk_mount/tasks/mount.yml
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`–`T005`)
2. Complete Phase 2: Foundational (`T006`–`T012`)
3. Complete Phase 3: User Story 1 (`T013`–`T017`)
4. **STOP and VALIDATE**: Confirm default GPT + `ext4` partitioning, formatting, mounting, and empty-list no-op work idempotently.

### Incremental Delivery

1. Setup + Foundational → Scaffolded, lint-clean role skeleton with full input validation & OS vars.
2. Add User Story 1 (MVP) → End-to-end raw disk → GPT → `ext4` → mounted folder.
3. Add User Story 2 → MBR/GPT options, `partition: false`, `xfs`/`btrfs`/`ext3`/`vfat`, volume labels, `mkfs_opts`, post-mount permissions, and all safety guards.
4. Add User Story 3 → Persistent `/etc/fstab` (`UUID`/`PARTUUID`/`LABEL`/`device`), `mount -a` reboot persistence, idempotent `auto_mount: false` ephemeral mounts, and `present`/`unmounted`/`absent` lifecycle states.
5. Complete Polish & Verification → Full Molecule scenario, docs, CI registration, `yamllint .`, `ansible-lint`, and 5-distro `./test-matrix.sh -r disk_mount`.

---

## Notes

- `[P]` tasks touch distinct files and have no unmet dependencies.
- `[US1]`/`[US2]`/`[US3]` map directly to User Stories 1–3 in [spec.md](spec.md).
- Never `git commit` or `git push` automatically; leave verified changes in the working tree for user review per `.specify/memory/constitution.md`.
