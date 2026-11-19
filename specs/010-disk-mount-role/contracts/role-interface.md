# Role Interface Contract: `hifra01.utils.disk_mount`

**Feature**: `010-disk-mount-role`  
**Date**: 2026-11-19  
**Spec**: [spec.md](spec.md)

## 1. Public Role Variables (`roles/disk_mount/defaults/main.yml`)

```yaml
# SPDX-License-Identifier: MIT-0
---
# defaults file for disk_mount

# List of disks/partitions to partition, format, and mount.
# Empty by default so invoking the role without explicit disk definitions is a safe no-op.
disk_mount_disks: []

# Default filesystem type when not specified on an individual disk entry.
# Supported values: ext4, xfs, btrfs, ext3, vfat
disk_mount_default_fstype: "ext4"

# Whether to create/manage a partition table and partition on the target block device by default.
# Set to false on an entry (or globally) to format a whole disk or an already-partitioned block device directly.
disk_mount_default_partition: true

# Default partition table format when partition is true.
# Supported values: gpt, msdos
disk_mount_default_partition_table: "gpt"

# Default auto-mount behavior across server restarts (persists entry in /etc/fstab).
# When false with state: "mounted", mounts ephemerally for the current session only.
disk_mount_default_auto_mount: true

# Default mount options string written to /etc/fstab and used when mounting.
# Includes nofail so missing secondary disks do not block server boot.
disk_mount_default_opts: "defaults,nofail"

# Default device identifier written to /etc/fstab for persistent auto-mount.
# Supported values: uuid, partuuid, label, device
disk_mount_default_fstab_src_type: "uuid"

# Whether mounting over an existing, unmounted, non-empty directory is permitted by default.
# Keep false to fail fast and avoid silently shadowing pre-existing files.
disk_mount_default_allow_non_empty: false

# Path to the fstab file managed for persistent mounts.
disk_mount_fstab_path: "/etc/fstab"

# Whether to create a timestamped backup of fstab before modifying it.
disk_mount_backup_fstab: true
```

### Example `disk_mount_disks` Entry Contract

```yaml
disk_mount_disks:
  # Minimal GPT + ext4 + persistent UUID auto-mount
  - device: "/dev/sdb"
    path: "/mnt/data"

  # Custom partition layout, XFS with volume label, directory ownership/mode
  - device: "/dev/nvme1n1"
    path: "/var/lib/app-data"
    partition: true
    partition_table: "gpt"
    partition_number: 1
    partition_start: "0%"
    partition_end: "100%"
    partition_name: "app-data"
    partition_flags: []
    partition_align: "optimal"
    fstype: "xfs"
    label: "APP_DATA"
    mkfs_opts: ""
    opts: "defaults,noatime,nofail"
    dump: 0
    passno: 0
    auto_mount: true
    fstab_src_type: "uuid"
    owner: "root"
    group: "root"
    mode: "0750"
    allow_non_empty: false
    state: "mounted"
    force: false

  # Whole-disk direct format (no partition table) with ephemeral (non-reboot) mount
  - device: "/dev/vdc"
    path: "/mnt/scratch"
    partition: false
    fstype: "ext4"
    mkfs_opts: "-m 1"
    auto_mount: false
    state: "mounted"
```

## 2. OS-Specific Variables (`roles/disk_mount/vars/<os_family>.yml`)

### `roles/disk_mount/vars/Debian.yml`

```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for disk_mount (Debian family)

disk_mount_base_packages:
  - parted
  - util-linux
  - e2fsprogs

disk_mount_fs_packages:
  ext4:
    - e2fsprogs
  ext3:
    - e2fsprogs
  xfs:
    - xfsprogs
  btrfs:
    - btrfs-progs
  vfat:
    - dosfstools

disk_mount_label_flags:
  ext4: "-L"
  ext3: "-L"
  xfs: "-L"
  btrfs: "-L"
  vfat: "-n"
```

### `roles/disk_mount/vars/RedHat.yml`

```yaml
# SPDX-License-Identifier: MIT-0
---
# vars file for disk_mount (RedHat family)

disk_mount_base_packages:
  - parted
  - util-linux
  - e2fsprogs

disk_mount_fs_packages:
  ext4:
    - e2fsprogs
  ext3:
    - e2fsprogs
  xfs:
    - xfsprogs
  btrfs:
    - btrfs-progs
  vfat:
    - dosfstools

disk_mount_label_flags:
  ext4: "-L"
  ext3: "-L"
  xfs: "-L"
  btrfs: "-L"
  vfat: "-n"
```

## 3. Handlers (`roles/disk_mount/handlers/main.yml`)

| Listener / Handler | Triggered When | Behavior |
|---|---|---|
| `reload systemd daemon` | Any `/etc/fstab` add, update, or removal occurs | Runs `ansible.builtin.systemd: daemon_reload: true` when `ansible_facts['service_mgr'] == 'systemd'` so `systemd-fstab-generator` stays synchronized with `/etc/fstab`. |

## 4. Pre-Flight & Safety Failure Contracts

The role MUST fail with an explicit, actionable `fail_msg` in all of the following cases before performing destructive operations:

1. Host OS family not in `['Debian', 'RedHat']`.
2. Invalid role-level defaults (`disk_mount_disks` not a list, invalid default `fstype`, `partition_table`, `fstab_src_type`, non-absolute `disk_mount_fstab_path`).
3. Invalid entry schema (missing `device`/`path`, `device` not starting with `/dev/`, `path` not absolute or in protected list `['/', '/boot', '/dev', '/proc', '/sys', '/run']`, unsupported `fstype`/`partition_table`/`partition_align`/`state`/`fstab_src_type`, `partition_name` set with `msdos`, `fstab_src_type == 'label'` with empty `label`, or `state == 'present'` with `auto_mount == false`).
4. Cross-entry conflict (duplicate normalized `path`, duplicate resolved `target_device`, mixed `partition: true` and `partition: false` on the same parent `device`, or conflicting `partition_table` values on the same parent `device`).
5. Active entry (`state` in `['mounted', 'present']`) whose `device` does not exist or is not a block device.
6. Active entry with `partition: true` where `device` is already a partition device (`lsblk TYPE == 'part'`).
7. Active entry with `partition: true` and `force: false` where `device` already has a conflicting partition table type or a whole-disk filesystem signature.
8. Active entry with `force: false` where the resolved `target_device` already contains a filesystem different from `fstype`.
9. Active entry with `state == 'mounted'` and `allow_non_empty: false` where `path` already exists, is not currently mounted, and contains files or subdirectories.
10. Active entry whose configured `fstab_src_type` (`uuid`, `partuuid`, or `label`) resolves to an empty value from `blkid` (e.g., `partuuid` on an unpartitioned whole disk).
