# Data Model: Disk Partitioning, Formatting, and Persistent Mount Role (`disk_mount`)

**Feature**: `010-disk-mount-role`  
**Date**: 2026-11-19  
**Spec**: [spec.md](spec.md)

## 1. Entities & Schema

### Entity 1: `DiskMountEntry` (Item in `disk_mount_disks`)

Each entry in `disk_mount_disks` is a dictionary describing the desired state of one block device / partition and its mount target.

| Field | Type | Required | Default | Constraints / Validation Rules |
|---|---|---|---|---|
| `device` | `string` | Yes | — | Non-empty absolute path starting with `/dev/` (e.g., `/dev/sdb`, `/dev/nvme1n1`, `/dev/loop0`, `/dev/sdb1`) |
| `path` | `string` | Yes | — | Non-empty absolute path starting with `/`; MUST NOT be in protected system paths (`/`, `/boot`, `/dev`, `/proc`, `/sys`, `/run`); unique across `disk_mount_disks` (normalized without trailing `/`) |
| `fstype` | `string` | No | `disk_mount_default_fstype` (`"ext4"`) | Must be one of `["ext4", "xfs", "btrfs", "ext3", "vfat"]` |
| `state` | `string` | No | `"mounted"` | Must be one of `["mounted", "present", "unmounted", "absent"]` |
| `auto_mount` | `boolean` | No | `disk_mount_default_auto_mount` (`true`) | Controls `/etc/fstab` persistence; MUST NOT be `false` when `state == "present"` |
| `partition` | `boolean` | No | `disk_mount_default_partition` (`true`) | When `true`, parent `device` MUST NOT itself be a partition (`lsblk TYPE != "part"`) |
| `partition_table` | `string` | No | `disk_mount_default_partition_table` (`"gpt"`) | Must be one of `["gpt", "msdos"]` |
| `partition_number` | `integer` | No | `1` | Positive integer `>= 1` (and `<= 4` for primary partitions on `msdos` unless extended) |
| `partition_start` | `string` | No | `"0%"` | Non-empty parted start offset string (e.g., `"0%"`, `"1MiB"`) |
| `partition_end` | `string` | No | `"100%"` | Non-empty parted end offset string (e.g., `"100%"`, `"50%"`, `"10GiB"`) |
| `partition_name` | `string` | No | `""` | Optional GPT partition name; only applied when `partition: true` and `partition_table == "gpt"` (rejected if non-empty with `msdos`) |
| `partition_flags` | `list[string]` | No | `[]` | Optional list of `parted` partition flags (e.g., `["lvm"]`, `["raid"]`) |
| `partition_align` | `string` | No | `"optimal"` | Must be one of `["optimal", "minimal", "cylinder", "none"]` |
| `label` | `string` | No | `""` | Optional filesystem volume label (format-time-only when `force: false`); required non-empty when `fstab_src_type == "label"` |
| `mkfs_opts` | `string` | No | `""` | Optional extra CLI flags appended to filesystem creation command (format-time-only when `force: false`) |
| `opts` | `string` | No | `disk_mount_default_opts` (`"defaults,nofail"`) | Non-empty comma-separated mount options string |
| `dump` | `integer` | No | `0` | Must be `0` or `1` |
| `passno` | `integer` | No | `0` | Must be `0`, `1`, or `2` |
| `fstab_src_type` | `string` | No | `disk_mount_default_fstab_src_type` (`"uuid"`) | Must be one of `["uuid", "partuuid", "label", "device"]` |
| `owner` | `string` | No | `""` | Optional username or UID applied to `path` after mounting (`state == "mounted"`) |
| `group` | `string` | No | `""` | Optional group name or GID applied to `path` after mounting (`state == "mounted"`) |
| `mode` | `string` | No | `""` | Optional quoted octal file mode string (e.g., `"0755"`, `"0750"`) applied to `path` after mounting (`state == "mounted"`) |
| `allow_non_empty` | `boolean` | No | `disk_mount_default_allow_non_empty` (`false`) | When `false`, fail fast if `path` exists, is not currently mounted, and contains files |
| `force` | `boolean` | No | `false` | Safety guard; when `true`, allows wiping conflicting partition tables/whole-disk signatures or reformatting mismatched filesystems |

### Entity 2: `NormalizedDiskEntry` (Internal Computed Fact `_disk_mount_entries`)

During pre-flight validation, each raw item in `disk_mount_disks` is normalized with role defaults and computed derived fields:

| Computed Field | Derivation Rule |
|---|---|
| `normalized_path` | `path` stripped of trailing `/` (preserving `"/"` only so the protected-path assertion catches it) |
| `target_device` | If `partition == false`: `device`. If `partition == true` and `device` ends with a digit (`.*[0-9]$`): `{{ device }}p{{ partition_number }}`. Otherwise: `{{ device }}{{ partition_number }}`. |
| `effective_mkfs_opts` | Combines filesystem label flag (`-L <label>` for `ext4`/`ext3`/`xfs`/`btrfs`, `-n <label>` for `vfat` when `label` is non-empty) with `mkfs_opts`, trimmed. |

### Entity 3: `ResolvedFstabSource` (Runtime Inspection Fact)

Computed per active entry (`state` in `["mounted", "present"]`) after partitioning and formatting complete:

| `fstab_src_type` | Inspection Command | Resulting `src` Value | Validation |
|---|---|---|---|
| `"uuid"` | `blkid -o value -s UUID <target_device>` | `UUID=<value>` | Assert `<value>` is non-empty |
| `"partuuid"` | `blkid -o value -s PARTUUID <target_device>` | `PARTUUID=<value>` | Assert `<value>` is non-empty (catches unpartitioned whole disks) |
| `"label"` | `blkid -o value -s LABEL <target_device>` | `LABEL=<value>` | Assert `<value>` is non-empty |
| `"device"` | None | `<target_device>` | Always valid block path |

## 2. Cross-Entry Uniqueness & Conflict Rules

Validated across the full `_disk_mount_entries` list in `tasks/validate.yml`:

1. **Unique mount paths**: No two entries may share the same `normalized_path`.
2. **Unique resolved target block devices**: No two entries may share the same `target_device` (e.g., two entries targeting `/dev/sdb1` are rejected; two entries on `/dev/sdb` with `partition_number: 1` and `partition_number: 2` produce `/dev/sdb1` and `/dev/sdb2` and are allowed).
3. **No whole-disk vs. partitioned collision on the same parent device**: If any entry targets `device: /dev/sdb` with `partition: false`, no other entry may target `device: /dev/sdb` with `partition: true` (and vice versa).
4. **Consistent partition table across multi-partition entries on the same parent device**: If multiple entries share the same `device` with `partition: true`, they MUST specify the same `partition_table` (`gpt` vs `msdos`).

## 3. State & Lifecycle Transition Matrix

| Desired `state` | `auto_mount` | Partition & Format? | Mount Point Check | Runtime Mount State | `/etc/fstab` Entry | Post-Mount `owner`/`group`/`mode` |
|---|---|---|---|---|---|---|
| `"mounted"` | `true` | Yes (verify device exists, partition if enabled, format if blank/forced) | Fail if unmounted & non-empty (unless `allow_non_empty: true`) | Mounted | Present (written/updated; triggers `systemctl daemon-reload`) | Applied after mount if set |
| `"mounted"` | `false` | Yes (same as above) | Fail if unmounted & non-empty (unless `allow_non_empty: true`) | Mounted ephemerally (only if not already mounted with `target_device`) | Absent (removed via `absent_from_fstab` if previously present; triggers `daemon-reload`) | Applied after mount if set |
| `"present"` | `true` | Yes (same as above) | Directory ensured present | Unchanged (not mounted immediately) | Present (written/updated; triggers `systemctl daemon-reload`) | Not applied (not mounted) |
| `"present"` | `false` | **Rejected at pre-flight validation** | — | — | — | — |
| `"unmounted"` | any | No (on-disk data untouched) | None | Unmounted | Preserved untouched | Not applied |
| `"absent"` | any | No (on-disk data untouched) | None | Unmounted | Removed (`absent_from_fstab`; triggers `daemon-reload`) | Not applied |

## 4. Safety Guard Decision Matrix

| Detected Disk / Folder Condition | `force` / `allow_non_empty` | Action |
|---|---|---|
| `partition: true` and `device` is already a partition (`lsblk TYPE == "part"`) | any | **Fail fast** (advise `partition: false` or pass parent disk) |
| `partition: true` and existing whole-disk filesystem detected | `force: false` | **Fail fast** without modifying disk |
| `partition: true` and existing whole-disk filesystem detected | `force: true` | Unmount active mount(s), `wipefs -a`, create partition table & partition |
| `partition: true` and existing `PTTYPE` differs from `partition_table` | `force: false` | **Fail fast** without modifying disk |
| `partition: true` and existing `PTTYPE` differs from `partition_table` | `force: true` | Unmount active partition mount(s), `wipefs -a`, create partition table & partition |
| Existing filesystem on `target_device` matches `fstype` | `force: false` or `true` | **No-op** (preserve data; `label`/`mkfs_opts` are format-time-only) |
| Existing filesystem on `target_device` differs from `fstype` | `force: false` | **Fail fast** without modifying disk |
| Existing filesystem on `target_device` differs from `fstype` | `force: true` | Unmount `target_device` if mounted, reformat with requested `fstype`, `label`, `mkfs_opts` |
| Unmounted existing directory at `path` contains files | `allow_non_empty: false` | **Fail fast** without mounting |
| Unmounted existing directory at `path` contains files | `allow_non_empty: true` | Proceed with mount |
