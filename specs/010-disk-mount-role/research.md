# Technical Research: Disk Partitioning, Formatting, and Persistent Mount Role (`disk_mount`)

**Feature**: `010-disk-mount-role`  
**Date**: 2026-11-19  
**Spec**: [spec.md](spec.md)

## Research Decisions

### 1. Core Ansible Modules & Collection Dependencies

- **Decision**: Use existing collection dependencies already declared in `galaxy.yml`:
  - `community.general.parted` (`community.general >= 9.0.0`) for partition table and partition creation/inspection.
  - `community.general.filesystem` (`community.general >= 9.0.0`) for filesystem creation.
  - `ansible.posix.mount` (`ansible.posix >= 1.5.0`) for `/etc/fstab` management, mounting, ephemeral mounting, and unmounting.
  - `ansible.builtin` (`assert`, `include_vars`, `include_tasks`, `apt`, `package`, `stat`, `file`, `find`, `command`, `set_fact`, `systemd`, `fail`) for validation, package installation, inspection (`blkid`, `lsblk`, `findmnt`), directory management, and systemd daemon reload.
- **Rationale**: Zero additional collection dependencies are needed; all modules are maintained in the already-required `ansible.posix` and `community.general` collections and support standard Ansible check/idempotency semantics.
- **Alternatives considered**:
  - Raw shell scripts (`sgdisk`, `fdisk`, `mkfs.*`, `mount`, `sed` on `/etc/fstab`): Harder to keep idempotent, error-prone when parsing `/etc/fstab` edits, and violates Constitution Principle IV (prefer idempotent modules).
  - `linux-system-roles.storage`: Introduces heavy external dependency (`blivet`) and LVM/RAID complexity explicitly out of scope for v1.

### 2. Safe Partition Inspection & Conflicting Table / Whole-Disk Detection (Q1 & Q4)

- **Decision**: Before running `community.general.parted` when `partition: true`, inspect the parent block device using read-only `util-linux` commands (`lsblk -dn -o TYPE <device>`, `blkid -o value -s PTTYPE <device>`, `blkid -o value -s TYPE <device>`):
  1. Reject `device` if `lsblk` reports type `part` (fail fast advising `partition: false` or passing the parent disk device).
  2. Normalize `blkid`'s `PTTYPE` (`dos` → `msdos`) to match `parted`'s `label` terminology (`gpt` / `msdos`).
  3. If `force` is `false` and either (a) `blkid` reports a non-empty whole-disk `TYPE` (unpartitioned filesystem signature) OR (b) `blkid` reports a normalized `PTTYPE` that differs from `partition_table`, fail fast with a descriptive safety error before calling `parted`.
  4. If `force` is `true` and a conflicting `PTTYPE` or whole-disk `TYPE` exists, unmount any active mount(s) on the device or its child partitions (`findmnt -rn -o TARGET <device>*` → unmount) and wipe signatures with `wipefs -a <device>` before creating the requested partition table and partition with `community.general.parted`.
- **Rationale**: Calling `parted mklabel` directly on a disk that already has an MBR table or whole-disk filesystem silently destroys the existing metadata. Pre-checking via `lsblk`/`blkid` guarantees zero accidental data loss when `force: false` while still supporting clean destructive reinitialization when `force: true`.
- **Alternatives considered**:
  - Relying solely on `community.general.parted`: Does not protect against overwriting an existing whole-disk filesystem or mismatching partition table type with a clear safety failure.

### 3. Partition Device Path Resolution & Kernel/Container Device Node Readiness

- **Decision**:
  - Resolve the target block device path from `(device, partition, partition_number)`:
    - When `partition: false`: target is `device` unchanged.
    - When `partition: true`: if `device` matches `.*[0-9]$` (e.g., `/dev/nvme0n1`, `/dev/loop0`, `/dev/mmcblk0`), target is `{{ device }}p{{ partition_number }}`; otherwise (e.g., `/dev/sdb`, `/dev/vdb`, `/dev/xvdf`), target is `{{ device }}{{ partition_number }}`.
  - After creating a partition with `community.general.parted`, refresh the kernel partition table (`partprobe <device>` with fallback `partx -u <device>`), invoke `udevadm settle` when `udevadm` is available and `/run/udev/control` exists, and if the kernel has registered the partition under `/sys/class/block/<part_name>/dev` while `/dev/<part_name>` is missing (common in privileged Docker containers lacking a running `udevd`), create the matching block node via `mknod` using the kernel's `major:minor` numbers.
- **Rationale**: Handles standard SCSI/virtio disks, NVMe drives, MMC devices, and loopback test devices consistently across bare metal, VMs, and privileged Docker containers used in Molecule CI.
- **Alternatives considered**:
  - Hardcoding `{{ device }}{{ partition_number }}`: Breaks on NVMe (`/dev/nvme0n1p1`) and loopback (`/dev/loop0p1`) devices.
  - Relying solely on `udevadm settle`: Fails or leaves `/dev/loop0p1` missing inside containerized Molecule environments where `udevd` does not manage `/dev`.

### 4. Filesystem Formatting, Label Flags, and Format-Time-Only Semantics (Q3)

- **Decision**:
  - Inspect the resolved target block device using `blkid -o value -s TYPE <target_device>` (`failed_when: rc not in [0, 2]`, `changed_when: false`).
  - Pass filesystem volume labels via `community.general.filesystem`'s `opts` parameter using a per-filesystem label flag mapping:
    - `ext4`, `ext3`, `xfs`, `btrfs`: `-L <label>`
    - `vfat`: `-n <label>`
    (Verified via `ansible-doc community.general.filesystem`: the native `label` option was only added in 13.1.0 for `gfs2` and does not support `ext4`/`xfs`/`btrfs`/`vfat`.)
  - Formatting behavior:
    - If existing `TYPE` is empty: run `community.general.filesystem` with `fstype`, `dev`, and combined `opts` (label flag + `mkfs_opts`).
    - If existing `TYPE == fstype`: skip formatting regardless of `label`/`mkfs_opts` (format-time-only per Q3; guarantees idempotency and prevents unexpected unmounts/data loss even when `force: true` is left enabled on subsequent runs after a conversion).
    - If existing `TYPE != fstype` and `force == false`: fail fast with a clear safety error.
    - If existing `TYPE != fstype` and `force == true`: unmount any active mount on `<target_device>`, then run `community.general.filesystem` with `force: true` and the requested `fstype` and `opts`.
- **Rationale**: Guarantees strict idempotency on repeated runs, prevents accidental live unmounts (especially on XFS where `xfs_admin -L` requires unmounting), and handles `vfat`'s `-n` flag correctly.
- **Alternatives considered**:
  - Passing `force: true` unconditionally to `community.general.filesystem`: Re-formats the disk on every run, breaking idempotency and wiping data.
  - Using `community.general.filesystem`'s `label:` parameter: Unsupported for `ext4`/`ext3`/`xfs`/`btrfs`/`vfat`.

### 5. Non-Empty Mount Point Guard & Post-Mount Directory Ownership/Permissions (Q2)

- **Decision**:
  - When `state == "mounted"`:
    1. Check whether `path` is already mounted using `findmnt -rn -M <path>` (`changed_when: false`, `failed_when: false`).
    2. Check whether `path` exists using `ansible.builtin.stat`.
    3. If `path` exists, is NOT currently mounted, and `allow_non_empty` is `false`, inspect entries with `ansible.builtin.find` (`paths: <path>`, `file_type: any`, `hidden: true`, `recurse: false`) and assert `matched == 0`, failing fast with a safety message advising to empty the directory or set `allow_non_empty: true`.
    4. Ensure `path` exists as a directory before mounting.
    5. Apply `owner`, `group`, and `mode` to `path` **after** mounting completes (only when at least one of those attributes is non-empty).
- **Rationale**: Prevents silently shadowing pre-existing files on an unmounted folder and ensures ownership/permissions apply to the mounted filesystem root rather than the masked underlying mount point directory.
- **Alternatives considered**:
  - Setting `owner`/`group`/`mode` before mounting: Masked once the filesystem mounts over `path`, causing incorrect permissions on the mounted root and failing idempotency checks.

### 6. Idempotent Ephemeral Mounts, Persistent `/etc/fstab`, and Clean `absent` Handling

- **Decision**: Verified via `ansible-doc -j ansible.posix.mount`:
  - `state: ephemeral` ALWAYS returns `changed=true` and triggers a remount if the path is already mounted.
  - `state: absent` has no effect if the path is not in `/etc/fstab` AND removes the mount point directory.
  - Therefore, implement mount lifecycle transitions cleanly as:
    - `state: "mounted"` + `auto_mount: true`: Resolve `src` (`UUID=...`, `PARTUUID=...`, `LABEL=...`, or device path via `blkid`, asserting non-empty), run `ansible.posix.mount` with `state: mounted`, `fstab`, `backup`, `opts`, `dump`, `passno`, notifying `"reload systemd daemon"`.
    - `state: "mounted"` + `auto_mount: false`:
      1. Ensure no `/etc/fstab` entry exists via `ansible.posix.mount` with `state: absent_from_fstab`, `fstab`, `backup` (notifying `"reload systemd daemon"` on change).
      2. Check active mount source on `path` via `findmnt -rn -o SOURCE -M <path>` (`changed_when: false`, `failed_when: false`).
      3. Run `ansible.posix.mount` with `state: ephemeral` ONLY when `path` is not already mounted with the resolved target device (ensuring `changed=0` on repeat runs!).
    - `state: "present"`: Resolve `src` via `blkid`, run `ansible.posix.mount` with `state: present`, `fstab`, `backup`, `opts`, `dump`, `passno`, notifying `"reload systemd daemon"`.
    - `state: "unmounted"`: Run `ansible.posix.mount` with `state: unmounted` (unmounts if mounted, preserves `/etc/fstab` and disk data).
    - `state: "absent"`:
      1. Run `ansible.posix.mount` with `state: unmounted` (ensures both fstab-backed and ephemeral mounts are unmounted).
      2. Run `ansible.posix.mount` with `state: absent_from_fstab`, `fstab`, `backup` (removes `/etc/fstab` entry cleanly without deleting the directory or failing if the mount was ephemeral), notifying `"reload systemd daemon"`.
- **Rationale**: Resolves both `ansible.posix.mount` quirks (`ephemeral` always reporting changed, `absent` ignoring non-fstab mounts), ensuring 100% strict idempotency (`changed=0`) across all 5 states and `auto_mount` toggles.
- **Alternatives considered**:
  - Calling `ansible.posix.mount: state: ephemeral` unconditionally: Fails `molecule idempotence`.
  - Calling `ansible.posix.mount: state: absent` alone: Leaves ephemeral mounts mounted and unexpectedly deletes mount directories.

### 7. OS-Specific Packages & On-Demand Filesystem Utilities

- **Decision**: Isolate package definitions in `vars/Debian.yml` and `vars/RedHat.yml` as:
  - `disk_mount_base_packages`: `["parted", "util-linux", "e2fsprogs"]` (on both Debian and RedHat families).
  - `disk_mount_fs_packages`: mapping from `fstype` to required packages:
    - `ext4`: `["e2fsprogs"]`
    - `ext3`: `["e2fsprogs"]`
    - `xfs`: `["xfsprogs"]`
    - `btrfs`: `["btrfs-progs"]` (Note: on RHEL/Rocky 8 & 9, `btrfs-progs` is not shipped in BaseOS/AppStream by default; operators using `btrfs` on RHEL/Rocky must enable a repo providing `btrfs-progs` such as ELRepo/EPEL, documented in `README.md`.)
    - `vfat`: `["dosfstools"]`
  - Only install base packages + filesystem packages corresponding to `fstype` values actually requested by active entries in `disk_mount_disks` (and skip package installation altogether when `disk_mount_disks` is empty so empty runs remain a strict zero-change no-op!).
- **Rationale**: Avoids installing unnecessary packages (and prevents `btrfs-progs` unavailability errors on Rocky Linux 8/9 when only `ext4`/`xfs`/`vfat` are used) while honoring FR-002 and FR-003.
- **Alternatives considered**:
  - Installing all filesystem packages unconditionally on every host: Fails on Rocky Linux 8/9 due to missing `btrfs-progs` in default repos and causes unwanted changes when `disk_mount_disks: []`.

### 8. Containerized Multi-Distro Molecule Verification Strategy

- **Decision**:
  - Use the standard collection Docker systemd `molecule.yml` baseline (`privileged: true`, `/sys/fs/cgroup:/sys/fs/cgroup:rw`, `cgroupns_mode: host`, `become_method: su`) across all 5 CI matrix images (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`).
  - In `prepare.yml`:
    1. Keep the mandatory RHEL/Rocky 8 `python39` bootstrap at the top.
    2. Ensure `util-linux` (`losetup`) and 4 sparse image files exist (`/var/tmp/disk1.img` through `/var/tmp/disk4.img`, each created with `truncate -s 320M` to satisfy XFS's >=300 MB minimum in `xfsprogs >= 5.19` on Ubuntu 24.04/Debian 12/Rocky 9 while consuming near-zero real disk blocks).
    3. Attach deterministic loopback devices with `losetup -P --find --show` (`--partscan`) and store their paths in a small state file (e.g., `/var/tmp/molecule-loop-devices.yml`) or dynamic lookup in `converge.yml` / `verify.yml` so repeated `converge` + `idempotence` + `verify` runs target the exact same loop devices cleanly, and detach loop devices in `cleanup.yml` so host loop slots are never leaked!
  - Test scenarios covered in `converge.yml` + `verify.yml`:
    - Disk 1: Default GPT partition + `ext4` + `auto_mount: true` (`UUID` in `/etc/fstab`, `defaults,nofail`), custom `owner`/`group`/`mode` (`'0750'`), reboot simulation (`umount` + `mount -a`) verifying auto-remount and file persistence.
    - Disk 2: `partition: true` + `msdos` MBR + `xfs` + volume `label: "XFS_DATA"` + `fstab_src_type: "label"` + `auto_mount: true`.
    - Disk 3: `partition: false` (whole-disk direct format) + `ext4` + custom `mkfs_opts: "-m 1"` + `auto_mount: false` (ephemeral mount, verified absent from `/etc/fstab` and idempotent on second run).
    - Disk 4 (in `verify.yml`): Safety checks — verify mismatched filesystem with `force: false`, conflicting partition table with `force: false`, non-empty unmounted folder with `allow_non_empty: false`, and lifecycle transitions (`state: "unmounted"` and `state: "absent"` preserving data on disk).
- **Rationale**: Using `truncate -s 320M` sparse files + `losetup -P` exercises 100% real Linux block devices, partitioning, `ext4`/`xfs`, `/etc/fstab`, and `mount -a` reboot recovery inside standard Docker containers with near-zero disk usage and full cleanup.
- **Alternatives considered**:
  - 64 MB image files for XFS: Fails on `xfsprogs >= 5.19` (Ubuntu 24.04, Debian 12) which enforces a 300 MB minimum XFS volume size! Using 320 MB sparse files avoids this pitfall across all 5 distros.
