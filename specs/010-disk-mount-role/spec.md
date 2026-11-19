# Feature Specification: Disk Partitioning, Formatting, and Persistent Mount Role (`disk_mount`)

**Feature Branch**: `010-disk-mount-role`

**Created**: 2026-11-19

**Status**: Draft

**Input**: User description: "create role to format disk with partition format options and mount to folder, with ability to auto mount when server restarted. name branch based on convention"

## Clarifications

### Session 2026-11-19

- Q: When partitioning is enabled (`partition: true`) and `force` is `false`, how should the role handle a disk that already has a different partition table type (e.g., `msdos` instead of `gpt`) or an unpartitioned whole-disk filesystem? (FR-005) → A: Fail fast with a safety error without modifying the disk; require explicit `force: true` to wipe and recreate the partition table.
- Q: If a target mount folder already exists, is not currently mounted, and contains files, how should the role behave? (FR-007) → A: Fail fast by default when the unmounted target folder is non-empty, unless the entry sets `allow_non_empty: true`.
- Q: When a disk already has a matching filesystem and `force` is `false`, how should the role handle a new or changed `label` or `mkfs_opts` value? (FR-006) → A: Treat `label` and `mkfs_opts` as format-time-only (applied when creating a new filesystem or when `force: true`); leave existing matching filesystems untouched.
- Q: When an operator specifies only `device` and `path` (without setting `partition`), should the role create a GPT partition table with a full-disk partition by default, or format `device` directly without creating a partition table? (FR-005, FR-010) → A: Default `partition: true` with `partition_table: "gpt"` (0%–100% single partition); set `partition: false` to format a raw disk or existing partition directly.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Partition, Format, and Mount a Disk to a Target Directory (Priority: P1)

Infrastructure operators need to provision raw or newly attached block storage devices on Linux servers by optionally creating a partition table and partition, formatting the device with a chosen filesystem and format options, creating the target mount folder, and mounting the filesystem so applications and services can immediately store data on it.

**Why this priority**: Turning a raw attached block device into a formatted, mounted directory with safe defaults and strict idempotency is the foundational capability of the role.

**Independent Test**: Can be fully tested by attaching an unformatted block device (or loopback block device backed by an image file) to a clean Linux host, applying the `disk_mount` role with a disk entry targeting `/mnt/data`, verifying that the partition table, partition, filesystem, mount directory, and active mount are present and writable, and confirming that a second run makes zero changes and preserves written data.

**Acceptance Scenarios**:

1. **Given** a clean supported Linux host (Debian/Ubuntu or RHEL/Rocky/AlmaLinux) with an unformatted block device and a configured entry in `disk_mount_disks`, **When** the operator applies the `disk_mount` role with default partition and filesystem options, **Then** the role creates a GPT partition table with a single full-disk partition, formats it as `ext4`, creates the target mount directory, and mounts the partition at the configured path.
2. **Given** an already partitioned, formatted, and mounted disk containing existing files, **When** the operator re-runs the role with unchanged variables, **Then** the existing partition and filesystem are untouched, existing data remains intact, the filesystem is not remounted unnecessarily, and the run completes with zero changes (idempotent).
3. **Given** a host where `disk_mount_disks` is empty (the default), **When** the operator applies the `disk_mount` role, **Then** no disks, partitions, filesystems, directories, or mount tables are modified and the run succeeds with zero changes.

---

### User Story 2 - Configure Partition Table and Filesystem Format Options (Priority: P2)

Platform and storage engineers need granular control over how each disk is partitioned and formatted—including choosing between partitioned disks (`gpt` or `msdos` with customizable partition number, start/end boundaries, alignment, name, and flags) or direct whole-disk / pre-existing partition formatting (`partition: false`), selecting the filesystem type (`ext4`, `xfs`, `btrfs`, `ext3`, `vfat`), assigning a filesystem volume label, passing custom format options, and setting mount folder ownership and permissions—so each volume matches its workload requirements (e.g., databases, container storage, or shared media).

**Why this priority**: Different workloads and cloud storage architectures require specific partition layouts (such as GPT vs. MBR vs. unpartitioned cloud volumes) and filesystem types (such as XFS for databases vs. ext4 for general data).

**Independent Test**: Can be independently tested by configuring multiple block devices with distinct options—one partitioned with `gpt` and formatted as `xfs` with a volume label and custom directory ownership/mode, and another configured with `partition: false` formatted directly as `ext4` with custom format options—and verifying each device's partition table, filesystem metadata, label, mount options, and mounted directory permissions.

**Acceptance Scenarios**:

1. **Given** a block device configured with `partition: true`, `partition_table: "gpt"` (or `"msdos"`), custom boundaries (`partition_start`, `partition_end`), and `fstype: "xfs"` with a `label`, **When** the role is applied, **Then** the specified partition layout is created, the partition is formatted with `xfs` carrying the configured label, and the volume is mounted at the target folder.
2. **Given** a raw block device or pre-existing partition configured with `partition: false`, `fstype: "ext4"`, and custom `mkfs_opts`, **When** the role is applied, **Then** no partition table is created on the device, the device is formatted directly with the requested filesystem and options, and it is mounted at the target folder.
3. **Given** a disk entry specifying `owner`, `group`, and `mode` (e.g., `'0750'`), **When** the disk is mounted, **Then** the configured ownership and permissions are applied to the mounted filesystem root directory and remain idempotent on subsequent runs.
4. **Given** a block device that already has an existing filesystem of a different type (e.g., `ext4` when `xfs` is requested) and `force: false` (default), **When** the role is applied, **Then** execution fails fast with a clear safety error without modifying or erasing the existing data.

---

### User Story 3 - Persist Auto-Mount Across Server Restarts and Manage Mount Lifecycle (Priority: P3)

System administrators need mounted volumes to automatically remount after a server reboot via persistent `/etc/fstab` configuration using stable block identifiers (UUID by default), while also being able to configure non-persistent (ephemeral) mounts (`auto_mount: false`) or cleanly unmount and remove managed mount entries (`state: "unmounted"` or `state: "absent"`) without losing data on the underlying disk.

**Why this priority**: Persistent reboot-safe mounting is a core requirement of the user request, and safe lifecycle transitions (toggling auto-mount or unmounting) prevent operational lock-in and boot failures.

**Independent Test**: Can be independently tested by mounting a disk with `auto_mount: true`, verifying the `/etc/fstab` entry uses the filesystem `UUID` and configured mount options, unmounting the directory manually and invoking system-wide fstab mounting (`mount -a`) to simulate a server restart and confirm automatic remounting; then toggling `auto_mount: false` and `state: "absent"` to verify `/etc/fstab` cleanup and unmount behavior while disk data stays intact.

**Acceptance Scenarios**:

1. **Given** a disk entry with `auto_mount: true` (the default) and `state: "mounted"`, **When** the role is applied, **Then** a persistent entry is written to `/etc/fstab` referencing the formatted volume by its stable `UUID` (or configured `fstab_src_type`) with the configured mount options (`defaults,nofail` by default), dump, and passno values, and simulating a reboot (`umount` followed by `mount -a`) automatically remounts the volume at the target folder.
2. **Given** a disk entry with `auto_mount: false` and `state: "mounted"`, **When** the role is applied, **Then** the disk is mounted immediately for the current session without adding an entry to `/etc/fstab` (and any previously managed `/etc/fstab` entry for that path is removed).
3. **Given** an already mounted disk entry whose `state` is changed to `"unmounted"`, **When** the role is applied, **Then** the directory is unmounted while keeping its `/etc/fstab` entry and on-disk data intact.
4. **Given** a managed disk entry whose `state` is changed to `"absent"`, **When** the role is applied, **Then** the directory is unmounted and its `/etc/fstab` entry is removed while preserving all data on the underlying block device.

---

### Edge Cases

- **Unsupported operating system family**: When executed on an OS family outside `Debian` and `RedHat`, the role fails immediately at the beginning of execution with a descriptive assertion message before installing packages or touching storage devices.
- **Block device paths ending in a digit (NVMe, loopback, MMC)**: When partitioning devices such as `/dev/nvme0n1`, `/dev/loop0`, or `/dev/mmcblk0`, the resulting partition device path MUST use the `p<number>` suffix (e.g., `/dev/nvme0n1p1`, `/dev/loop0p1`), whereas devices ending in a letter (e.g., `/dev/sdb`, `/dev/vdb`) use `<number>` directly (e.g., `/dev/sdb1`, `/dev/vdb1`).
- **Missing or invalid block device**: When `state` is `"mounted"` or `"present"` and the specified `device` does not exist as a block device on the target host, execution fails fast with a clear error message before modifying `/etc/fstab` or creating mounts.
- **Protected system paths and conflicting definitions**: Pre-flight validation MUST reject dangerous target mount paths (`/`, `/boot`, `/dev`, `/proc`, `/sys`, `/run`), non-absolute mount paths, duplicate `path` entries, duplicate resolved target block devices (for example, two entries targeting `/dev/sdb1`, or mixing whole-disk `partition: false` with `partition: true` on the same parent device), and contradictory combinations such as `state: "present"` with `auto_mount: false`.
- **Partition table and whole-disk filesystem mismatch protection**: When `partition: true` and `force: false`, if the target disk already has a different partition table type (e.g., `msdos` when `gpt` is requested) or an unpartitioned whole-disk filesystem signature, the role MUST fail fast with a safety error without modifying the disk; recreating or wiping the existing partition table requires explicit `force: true`.
- **Filesystem mismatch protection**: If the target device/partition already contains a filesystem different from `fstype` and `force` is `false`, the role MUST fail fast with an actionable message rather than silently skipping or destroying existing data. When `force` is explicitly `true`, the role unmounts the device if currently mounted before reformatting.
- **Incompatible `/etc/fstab` identifier configuration**: Selecting `fstab_src_type: "label"` without providing a non-empty `label`, or selecting `fstab_src_type: "partuuid"` on an unpartitioned whole disk (`partition: false` with no partition UUID), MUST fail validation with a clear diagnostic error.
- **Secondary disk absent on server restart**: Default mount options (`defaults,nofail`) ensure that if an optional secondary data disk is detached or unavailable during reboot, the operating system still completes booting cleanly rather than halting in emergency mode.
- **Non-empty target mount point directory**: When `state` is `"mounted"` and the target mount folder already exists, is not currently a mount point, and contains existing files or subdirectories, the role MUST fail fast with a safety error by default (`allow_non_empty: false`) to prevent silently shadowing existing data; operators can explicitly opt in to mounting over a non-empty folder by setting `allow_non_empty: true` on the entry.
- **Mount point directory permissions masked by mounting**: Setting `owner`, `group`, or `mode` before mounting only modifies the hidden underlying directory; the role MUST apply configured directory ownership and permissions *after* the volume is mounted (when `state: "mounted"`).
- **Empty `disk_mount_disks` list**: Running the role with no entries performs validation cleanly and exits with zero changes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `disk_mount` role MUST validate at the beginning of execution that the target host belongs to a supported OS family (`Debian` or `RedHat`) and validate all entries in `disk_mount_disks` (required `device` and `path` fields, absolute non-protected mount paths, unique mount paths, non-conflicting resolved target block devices, supported `fstype`, `partition_table`, `state`, `fstab_src_type`, non-empty `label` when `fstab_src_type == "label"`, and rejecting `state: "present"` when `auto_mount: false`), failing fast with a descriptive error message on invalid input.
- **FR-002**: The `disk_mount` role MUST isolate OS-specific prerequisite package names for partitioning, block-device inspection, and supported filesystems (`ext4`/`ext3`, `xfs`, `btrfs`, `vfat`) in OS-family variable files (`Debian` and `RedHat`), installing only the required base storage utilities and any filesystem utilities needed by the configured `disk_mount_disks` entries.
- **FR-003**: When `disk_mount_disks` is empty (`[]`), the role MUST complete cleanly as a no-op with zero system changes.
- **FR-004**: For each active disk entry (`state` in `["mounted", "present"]`), the role MUST verify that the configured `device` exists as a block device on the target host before performing partitioning, formatting, or mounting operations.
- **FR-005**: When `partition` is `true` (the default, using `partition_table: "gpt"` with a single `0%`–`100%` partition unless overridden) for an active entry, the role MUST inspect the parent block device before modifying it:
  - If `device` is itself already a partition block device rather than a whole disk, fail fast with a clear error advising the operator to set `partition: false` or pass the parent disk device.
  - If the disk already holds a different partition table type than `partition_table` or contains an unpartitioned whole-disk filesystem signature and `force` is `false`, fail fast with a safety error without modifying the disk.
  - If `force` is `true` and a conflicting partition table or whole-disk filesystem exists, unmount any mounted target and wipe/recreate the partition table cleanly.
  - Ensure the configured partition table (`gpt` or `msdos`) and partition (`partition_number`, `partition_start`, `partition_end`, `partition_align`, optional `partition_name` for GPT, optional `partition_flags`) exist on the block device, wait for the kernel/udev to recognize the partition device node, and resolve the partition path correctly for both letter-ending devices (`/dev/sdb1`) and digit-ending devices (`/dev/nvme0n1p1`, `/dev/loop0p1`).
  When `partition` is `false`, the role MUST operate directly on `device` without creating a partition table.
- **FR-006**: For each active entry, the role MUST inspect the target block device/partition for an existing filesystem:
  - If no filesystem is present, format it with the configured `fstype`, optional `label`, and optional `mkfs_opts`.
  - If an existing filesystem matches `fstype` and `force` is `false`, leave the filesystem untouched (preserving all existing data; `label` and `mkfs_opts` are format-time-only and MUST NOT trigger relabeling, unmounting, or reformatting on an existing matching filesystem).
  - If an existing filesystem differs from `fstype` and `force` is `false`, fail fast with a clear safety error rather than overwriting data.
  - If an existing filesystem differs from `fstype` and `force` is `true`, unmount the target device if currently mounted and reformat it with the requested `fstype`, `label`, and `mkfs_opts` (matching filesystems remain untouched to preserve idempotency across repeated runs).
- **FR-007**: For each active entry, the role MUST ensure the mount point directory (`path`) exists before mounting. When `state` is `"mounted"`, if `path` already exists, is not currently mounted, and is non-empty, the role MUST fail fast with a clear safety error unless `allow_non_empty` is `true` (default `false`). When `state` is `"mounted"` and `owner`, `group`, or `mode` are specified, the role MUST apply them to `path` after the filesystem is mounted.
- **FR-008**: For each entry, the role MUST manage mounting and persistent auto-mount behavior according to `state` and `auto_mount`:
  - `state: "mounted"` with `auto_mount: true`: mount the volume at `path` and persist an entry in `disk_mount_fstab_path` (default `/etc/fstab`) using the resolved identifier specified by `fstab_src_type` (`uuid`, `partuuid`, `label`, or `device`), along with `fstype`, `opts`, `dump`, and `passno`.
  - `state: "mounted"` with `auto_mount: false`: mount the volume at `path` for the current session without persisting an entry in `/etc/fstab` (removing any existing `/etc/fstab` entry for `path` if previously configured).
  - `state: "present"`: ensure the partition, filesystem, mount directory, and `/etc/fstab` entry exist without mounting the volume immediately.
  - `state: "unmounted"`: unmount `path` if mounted while preserving its `/etc/fstab` entry and on-disk data.
  - `state: "absent"`: unmount `path` if mounted and remove its `/etc/fstab` entry while preserving all data on disk.
- **FR-009**: Whenever `/etc/fstab` is modified, the role MUST optionally create a backup (controlled by `disk_mount_backup_fstab`, default `true`) and trigger a systemd daemon reload when systemd is running so boot/mount units stay synchronized with `/etc/fstab`.
- **FR-010**: The `disk_mount` role MUST provide user-tunable, `disk_mount_`-prefixed variables with clear defaults and comments, including at minimum:
  - `disk_mount_disks` (list of disk configuration dictionaries, default `[]`)
  - `disk_mount_default_fstype` (default filesystem type: `"ext4"`, `"xfs"`, `"btrfs"`, `"ext3"`, `"vfat"`; default `"ext4"`)
  - `disk_mount_default_partition` (default boolean controlling whether to partition the disk before formatting, default `true`)
  - `disk_mount_default_partition_table` (default partition table format: `"gpt"` or `"msdos"`, default `"gpt"`)
  - `disk_mount_default_auto_mount` (default boolean controlling `/etc/fstab` persistence for auto-mount on reboot, default `true`)
  - `disk_mount_default_opts` (default mount options string, default `"defaults,nofail"`)
  - `disk_mount_default_fstab_src_type` (default persistent identifier type in `/etc/fstab`: `"uuid"`, `"partuuid"`, `"label"`, or `"device"`; default `"uuid"`)
  - `disk_mount_default_allow_non_empty` (default boolean controlling whether mounting over an unmounted non-empty directory is allowed, default `false`)
  - `disk_mount_fstab_path` (path to the fstab file, default `"/etc/fstab"`)
  - `disk_mount_backup_fstab` (boolean to back up fstab before modification, default `true`)
  And each item in `disk_mount_disks` MUST support: `device`, `path`, `fstype`, `state`, `auto_mount`, `partition`, `partition_table`, `partition_number`, `partition_start`, `partition_end`, `partition_name`, `partition_flags`, `partition_align`, `label`, `mkfs_opts`, `opts`, `dump`, `passno`, `fstab_src_type`, `owner`, `group`, `mode`, `allow_non_empty`, and `force`.
- **FR-011**: All role operations MUST be strictly idempotent across repeated runs, conform to the collection's lint and documentation standards, be registered in the repository's CI test matrix and documentation, and be verified across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8).

### Key Entities

- **Disk Mount Entry (`disk_mount_disks` item)**: Declarative specification linking a host block device (`device`), optional partitioning rules (`partition`, `partition_table`, boundaries, alignment, flags), filesystem format configuration (`fstype`, `label`, `mkfs_opts`, `force`), mount target (`path`, `owner`, `group`, `mode`, `allow_non_empty`), and runtime/boot persistence behavior (`state`, `auto_mount`, `opts`, `dump`, `passno`, `fstab_src_type`).
- **Partition Layout**: The on-disk partition table (`gpt` or `msdos`) and partition entry created on a raw block device prior to filesystem creation, or omitted when formatting a whole disk or pre-existing partition directly.
- **Formatted Filesystem**: The initialized filesystem (`ext4`, `xfs`, `btrfs`, `ext3`, or `vfat`) on the target block device/partition carrying a stable `UUID` (and optional `LABEL` / `PARTUUID`).
- **Persistent Mount Entry (`/etc/fstab` record)**: The boot-time mount definition mapping a stable volume identifier (`UUID=...`, `PARTUUID=...`, `LABEL=...`, or device path) to a mount folder, filesystem type, and mount options so the operating system automatically mounts the volume after server restarts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can provision, format, mount, and configure persistent auto-mount for one or more disks across all 5 supported Linux distributions (Ubuntu 22.04, Ubuntu 24.04, Debian 12, Rocky Linux 9, Rocky Linux 8) in a single automated run, with every target directory mounted and writable immediately after completion.
- **SC-002**: 100% of volumes configured with `auto_mount: true` are automatically remounted at their configured folders after unmounting and running system fstab mount recovery (`mount -a`), with zero boot-blocking errors and 100% of previously written test files preserved.
- **SC-003**: 100% of volumes configured with `auto_mount: false` are mounted during the active session and have zero entries written to `/etc/fstab`.
- **SC-004**: Running the role a second consecutive time with unchanged variables produces 0 changed tasks and preserves 100% of data on all mounted volumes across all supported distributions.
- **SC-005**: Attempting to overwrite a device that already holds a mismatched filesystem, conflicting partition table, or whole-disk filesystem (when partitioning is requested) with `force: false`, or mounting over a non-empty unmounted folder with `allow_non_empty: false`, is blocked 100% of the time with zero data loss or shadowing; invalid/dangerous configurations (e.g., targeting `/`, duplicate mount paths, missing block devices) fail during pre-flight validation before any disk is altered.
- **SC-006**: Repository linting checks pass with zero errors and automated multi-distribution verification passes across all 5 target Linux distributions.

## Assumptions

- Target hosts run a supported Linux distribution from the `Debian` family (Ubuntu 22.04, Ubuntu 24.04, Debian 12) or `RedHat` family (Rocky Linux 8, Rocky Linux 9) with superuser privileges required for block device partitioning, formatting, and mounting.
- The role name is `disk_mount` (following the collection's descriptive snake_case naming convention such as `apt_mirror` and `linux_users`), invoked as `hifra01.utils.disk_mount`.
- Advanced storage layers such as LVM (Logical Volume Manager), software RAID (`mdadm`), LUKS disk encryption, ZFS pools, swap space management, and online partition/filesystem resizing are out of scope for the initial version of this role.
- Automated multi-distribution verification in containerized test environments can use loopback block devices backed by sparse image files to exercise real partitioning, formatting, mounting, `/etc/fstab` persistence, and `mount -a` reboot-simulation behavior without requiring physical secondary disks.
- `defaults,nofail` is a safe default mount options string for secondary data disks so server reboots succeed even if an attached data volume is temporarily absent; operators requiring strict boot failure on missing disks can override `opts` (e.g., `"defaults"`).
