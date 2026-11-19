# Implementation Plan: Disk Partitioning, Formatting, and Persistent Mount Role (`disk_mount`)

**Branch**: `010-disk-mount-role` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/010-disk-mount-role/spec.md`

## Summary

Create a new `hifra01.utils.disk_mount` Ansible role under `roles/disk_mount/` that declaratively partitions, formats, and mounts Linux block devices to target folders with reboot-persistent auto-mount via `/etc/fstab` (using stable `UUID` identifiers and `defaults,nofail` mount options by default) on Debian-family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat-family (`Rocky Linux 8`, `Rocky Linux 9`, `AlmaLinux`, `RHEL`) systems.

The role supports optional partitioning (`gpt` or `msdos` with configurable partition number, boundaries, alignment, GPT name, and flags) as well as direct whole-disk or pre-existing partition formatting (`partition: false`), multiple filesystems (`ext4`, `xfs`, `btrfs`, `ext3`, `vfat`) with format-time-only volume `label` and `mkfs_opts`, post-mount folder ownership/permissions (`owner`/`group`/`mode`), ephemeral non-reboot mounts (`auto_mount: false`), and safe unmount/removal (`state: "unmounted"` / `"absent"`). Built-in safety guards block accidental data loss by failing fast on conflicting partition tables, whole-disk filesystem signatures, mismatched filesystems (`force: false`), partition devices passed with `partition: true`, and non-empty unmounted target folders (`allow_non_empty: false`).

## Technical Context

**Language/Version**: YAML / Ansible (`ansible-core >= 2.21.0`, tested with Python 3.9–3.14)

**Primary Dependencies**:
- `ansible.builtin` (`assert`, `include_vars`, `include_tasks`, `apt`, `package`, `stat`, `file`, `find`, `command`, `set_fact`, `systemd`, `fail`)
- `community.general >= 9.0.0` (`community.general.parted`, `community.general.filesystem`) — already declared in `galaxy.yml`
- `ansible.posix >= 1.5.0` (`ansible.posix.mount`) — already declared in `galaxy.yml`
- Target host utilities: `parted`, `util-linux` (`blkid`, `lsblk`, `findmnt`, `wipefs`, `partx`), `e2fsprogs`, and on-demand filesystem packages (`xfsprogs`, `btrfs-progs`, `dosfstools`) isolated in `vars/<os_family>.yml`

**Storage**:
- Managed block devices and partitions (`/dev/sd*`, `/dev/vd*`, `/dev/xvd*`, `/dev/nvme*`, `/dev/mmcblk*`, `/dev/loop*`)
- Target mount directories (`path`)
- Persistent mount table (`disk_mount_fstab_path`, default `/etc/fstab`) with optional backup (`disk_mount_backup_fstab: true`)

**Testing**: `yamllint .`, `ansible-lint`, and `molecule test` (`molecule-plugins[docker]`) across all 5 CI matrix distributions (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`) using 320 MB sparse loopback block devices (`losetup -P`) in privileged systemd Docker containers

**Target Platform**: Debian family (`Ubuntu 22.04`, `Ubuntu 24.04`, `Debian 12`) and RedHat family (`Rocky Linux 9`, `Rocky Linux 8`, `AlmaLinux`, `RHEL`)

**Project Type**: Ansible Collection role (`hifra01.utils.disk_mount`)

**Performance Goals**: Single-host convergence in `< 30s` (excluding initial package cache update); strict `changed=0` on repeated runs with unchanged variables across all states (`mounted` with `auto_mount: true` and `false`, `present`, `unmounted`, `absent`) and empty `disk_mount_disks: []`

**Constraints**:
- Must pass `yamllint .` (2-space indent, max 160 chars, quoted octal modes, `true`/`false` booleans) and `ansible-lint` with zero errors
- Must use `ansible_facts['os_family']` / `ansible_facts['service_mgr']` for `ansible-core >= 2.21` compatibility
- Must work cleanly on Rocky Linux 8 (Python 3.9 bootstrap in Molecule `prepare.yml`, no unavailable `btrfs-progs` installed unless `btrfs` is explicitly configured)
- Must handle containerized `/dev` nodes (where `udevd` may not auto-populate `/dev/loopNp1`) and XFS's 300 MB minimum filesystem size in Molecule tests

**Scale/Scope**: New Ansible role (`roles/disk_mount/`), Molecule default scenario (`molecule.yml`, `prepare.yml`, `converge.yml`, `verify.yml`, `cleanup.yml`), CI workflow registration in `.github/workflows/ci.yml` (4 required locations), and documentation update in `AGENTS.md`

## Constitution Check

*GATE: Evaluated before Phase 0 research and re-verified after Phase 1 design.*

| Principle | Pre-Design | Post-Design | Verification Notes |
|---|---|---|---|
| **I. Spec-Driven Role Development** | PASS | PASS | Following `speckit-specify` → `speckit-clarify` (4 clarifications recorded) → `speckit-plan` → `speckit-tasks` → `speckit-analyze` → `speckit-implement` in `specs/010-disk-mount-role/`. |
| **II. Official CLI Scaffolding & Role Isolation** | PASS | PASS | Role and Molecule scenario will be scaffolded via `ansible-galaxy role init --init-path roles disk_mount` and `molecule init scenario default` before customization. No hand-crafted skeletons or edits under `.specify/scripts/` or `.specify/templates/`. |
| **III. Multi-OS Portability & Variable Discipline** | PASS | PASS | Supports `Debian` and `RedHat` families; starts `tasks/main.yml` with an `ansible.builtin.assert` platform guard; all public variables prefixed with `disk_mount_`; OS-specific package/flag maps isolated in `vars/Debian.yml` and `vars/RedHat.yml`; internal facts/registers prefixed with `_disk_mount_`; all included task loops define `loop_control.loop_var`. |
| **IV. Idempotency & Strict Ansible/YAML Hygiene** | PASS | PASS | Uses FQCNs exclusively, descriptive imperative task names, quoted octal modes (`'0755'`, `'0750'`), `true`/`false` booleans, explicit `changed_when`/`failed_when` on all `command` tasks (`blkid`, `lsblk`, `findmnt`, `wipefs`, `partprobe`), idempotent guards around `ansible.posix.mount: state: ephemeral`, and `listen: "reload systemd daemon"` handler for `/etc/fstab` changes. |
| **V. Linter & Multi-Distro Molecule Verification** | PASS | PASS | Full Molecule scenario (`molecule.yml`, `prepare.yml` with RHEL 8 `python39` bootstrap + loopback disk setup, `converge.yml` using `hifra01.utils.disk_mount`, `verify.yml` testing mounts/fstab/`mount -a`/safety/lifecycle, `cleanup.yml` detaching loop devices) across all 5 CI distros + `yamllint .` and `ansible-lint`. |
| **CI Matrix & Documentation Constraints** | PASS | PASS | Plan includes registering `disk_mount` in all 4 locations of `.github/workflows/ci.yml`, writing `roles/disk_mount/README.md`, updating `roles/disk_mount/meta/main.yml`, and adding `disk_mount` to the roles table in `AGENTS.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/010-disk-mount-role/
├── plan.md                  # This file (/speckit-plan output)
├── research.md              # Phase 0 technical research & module findings
├── data-model.md            # Phase 1 entity schemas, validation & state matrices
├── quickstart.md            # Phase 1 validation & runnable test guide
├── contracts/
│   └── role-interface.md    # Phase 1 public defaults, OS vars, handlers, failure contracts
├── checklists/
│   └── requirements.md      # Spec quality checklist (/speckit-specify output)
└── tasks.md                 # Phase 2 task breakdown (/speckit-tasks output - not created here)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    └── ci.yml                             # Register disk_mount in all 4 matrix/filter locations
AGENTS.md                                  # Add disk_mount to the Roles table
roles/
└── disk_mount/
    ├── README.md                          # Role documentation, variables table, safety notes, examples
    ├── defaults/
    │   └── main.yml                       # User-tunable disk_mount_* default variables
    ├── handlers/
    │   └── main.yml                       # "reload systemd daemon" listener for /etc/fstab edits
    ├── meta/
    │   └── main.yml                       # Galaxy metadata (platforms: Debian, Ubuntu, EL 8/9; tags)
    ├── tasks/
    │   ├── main.yml                       # Platform guard, OS vars load, validate, packages, per-disk orchestration
    │   ├── validate.yml                   # Normalize disk_mount_disks, validate schema & cross-entry uniqueness
    │   ├── packages.yml                   # Install base + on-demand filesystem packages for active entries
    │   ├── process-disk.yml               # Per-entry dispatcher (loop_var: _disk_mount_entry) for active vs unmount/absent
    │   ├── partition.yml                  # Block device check, partition-device/table/whole-disk safety, parted, node refresh
    │   ├── format.yml                     # blkid check, fstype mismatch guard, format-time label/mkfs_opts via filesystem
    │   └── mount.yml                      # Non-empty dir guard, fstab src resolution, mount/ephemeral/present/unmount/absent, post-mount perms
    ├── tests/
    │   ├── inventory
    │   └── test.yml
    ├── vars/
    │   ├── Debian.yml                     # Debian/Ubuntu base + per-fstype packages & label flags
    │   └── RedHat.yml                     # RedHat/Rocky base + per-fstype packages & label flags
    └── molecule/
        └── default/
            ├── molecule.yml               # Docker privileged systemd baseline for 5-distro matrix
            ├── prepare.yml                # RHEL 8 python39 bootstrap + 320M sparse loopback block devices
            ├── converge.yml               # Converge hifra01.utils.disk_mount (GPT/ext4, MBR/xfs, raw/ephemeral)
            ├── verify.yml                 # Verify partitions, filesystems, fstab, mount -a reboot sim, safety & lifecycle
            └── cleanup.yml                # Unmount test paths and detach loopback devices cleanly
```

**Structure Decision**: Follows the standard `hifra01.utils` multi-file task decomposition pattern (`validate.yml`, `packages.yml`, `process-disk.yml`, `partition.yml`, `format.yml`, `mount.yml`) initialized with `ansible-galaxy role init --init-path roles disk_mount` and `molecule init scenario default`. Splitting disk processing into focused included task files keeps each concern testable, readable, and strictly scoped with explicit `loop_control.loop_var: _disk_mount_entry`.

## Task Execution Flow Design

1. **`tasks/main.yml`**:
   - Assert `ansible_facts['os_family'] in ['Debian', 'RedHat']`.
   - Load `vars/{{ ansible_facts['os_family'] }}.yml`.
   - Include `tasks/validate.yml` (always runs, even when `disk_mount_disks` is empty, validating defaults and normalizing entries into `_disk_mount_entries`).
   - Short-circuit gracefully when `_disk_mount_entries | length == 0` (FR-003 zero-change no-op).
   - Include `tasks/packages.yml` when any entry has `state in ['mounted', 'present']` (installs `disk_mount_base_packages` + on-demand `disk_mount_fs_packages[fstype]` for requested active filesystems).
   - Loop over `_disk_mount_entries` with `loop_control.loop_var: _disk_mount_entry`, including `tasks/process-disk.yml`.
2. **`tasks/process-disk.yml`**:
   - When `_disk_mount_entry.state in ['mounted', 'present']`:
     - Verify `_disk_mount_entry.device` exists and is a block device (`stat.isblk`).
     - Include `tasks/partition.yml` (when `_disk_mount_entry.partition | bool`).
     - Include `tasks/format.yml`.
     - Include `tasks/mount.yml`.
   - When `_disk_mount_entry.state in ['unmounted', 'absent']`:
     - Include `tasks/mount.yml` directly (skips partitioning and formatting so disk data is never touched).
3. **`tasks/partition.yml`**:
   - Inspect parent device with `lsblk -dn -o TYPE` and `blkid -o value -s PTTYPE` / `-s TYPE`.
   - Fail fast if `TYPE == 'part'` (Q4 guard).
   - Normalize `PTTYPE` (`dos` → `msdos`) and check against `_disk_mount_entry.partition_table` and whole-disk `TYPE`; fail fast if conflicting and `force == false` (Q1 guard).
   - If conflicting and `force == true`, unmount any active mounts on the device/partitions and run `wipefs -a`.
   - Run `community.general.parted` (`state: present`, `label`, `number`, `part_start`, `part_end`, `align`, optional `name` for `gpt`, optional `flags`).
   - Refresh kernel partition table (`partprobe` / `partx -u`), settle `udevadm` when active, and ensure `/dev/<part>` node exists from `/sys/class/block/<part>/dev` if running inside a udev-less container.
4. **`tasks/format.yml`**:
   - Inspect `_disk_mount_entry.target_device` with `blkid -o value -s TYPE`.
   - If existing `TYPE` is non-empty and differs from `fstype` and `force == false`: fail fast.
   - If existing `TYPE` is non-empty and differs from `fstype` and `force == true`: unmount any active mount on `target_device`, then run `community.general.filesystem` with `force: true` and `effective_mkfs_opts`.
   - If existing `TYPE` is empty: run `community.general.filesystem` with `force: false` and `effective_mkfs_opts`.
   - If existing `TYPE == fstype`: no-op (format-time-only semantics per Q3; preserves data and guarantees idempotency).
5. **`tasks/mount.yml`**:
   - For `state in ['mounted', 'present']`:
     - When persistent fstab management is active (`(state == 'mounted' and auto_mount) or state == 'present'`): resolve fstab `src` (`UUID=...`, `PARTUUID=...`, `LABEL=...`, or `target_device`) via `blkid` and assert non-empty when using `uuid`/`partuuid`/`label`.
     - Check whether `path` is already mounted (`findmnt -rn -o SOURCE -M <path>`).
     - When `state == 'mounted'` and not currently mounted and `allow_non_empty == false`: check `stat` + `find` on `path` and fail fast if non-empty (Q2 guard).
     - Ensure `path` directory exists (`file: state: directory`).
     - Apply mount / fstab state:
       - `mounted` + `auto_mount: true`: `ansible.posix.mount: state: mounted` with resolved fstab `src` (notifies `"reload systemd daemon"`).
       - `mounted` + `auto_mount: false`: `ansible.posix.mount: state: absent_from_fstab` (notifies `"reload systemd daemon"`), then `ansible.posix.mount: state: ephemeral` with `src: _disk_mount_entry.target_device` ONLY when `path` is not already mounted with `target_device`.
       - `present`: `ansible.posix.mount: state: present` with resolved fstab `src` (notifies `"reload systemd daemon"`).
     - When `state == 'mounted'` and any of `owner`/`group`/`mode` are non-empty: apply via `ansible.builtin.file: state: directory` post-mount.
   - For `state == 'unmounted'`: `ansible.posix.mount: state: unmounted`.
   - For `state == 'absent'`: `ansible.posix.mount: state: unmounted`, then `ansible.posix.mount: state: absent_from_fstab` (notifies `"reload systemd daemon"`).

## Complexity Tracking

No Constitution violations exist.
