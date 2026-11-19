# Disk Mount Role (`hifra01.utils.disk_mount`)

Ansible role to declaratively partition, format, and persistently mount Linux block storage devices via `/etc/fstab` (or ephemerally for the active session), with built-in pre-flight validation and data-protection safety guards.

## Supported Platforms

* **Debian Family**: Debian 12 (Bookworm), Ubuntu 22.04 (Jammy), Ubuntu 24.04 (Noble)
* **RedHat Family**: Rocky Linux 8 & 9, AlmaLinux 8 & 9, RHEL 8 & 9

> **Note on `btrfs` on RHEL / Rocky Linux**: `btrfs-progs` is not included in default RHEL/Rocky 8 & 9 BaseOS/AppStream repositories. The role installs filesystem packages on demand only for `fstype` values actually used in `disk_mount_disks`; if you configure `fstype: "btrfs"` on RHEL/Rocky hosts, ensure a repository providing `btrfs-progs` is enabled first.

## Requirements

* `ansible-core >= 2.21.0`
* Collection dependencies (declared in `galaxy.yml`):
  * `ansible.posix >= 1.5.0`
  * `community.general >= 9.0.0`
* Fact gathering (`gather_facts: true`) must be enabled.
* Root / `become: true` privileges on target hosts.

## Role Variables

### Global Defaults (`defaults/main.yml`)

| Variable | Default | Description |
|---|---|---|
| `disk_mount_disks` | `[]` | List of disk mount entries. Empty by default so running the role without entries is a safe zero-change no-op. |
| `disk_mount_default_fstype` | `"ext4"` | Default filesystem type (`ext4`, `xfs`, `btrfs`, `ext3`, `vfat`) |
| `disk_mount_default_partition` | `true` | Create/manage a partition table and partition before formatting (`false` formats `device` directly) |
| `disk_mount_default_partition_table` | `"gpt"` | Default partition table label (`gpt` or `msdos`) |
| `disk_mount_default_auto_mount` | `true` | Persist mount entry in `/etc/fstab` for auto-mount on reboot (`false` mounts ephemerally) |
| `disk_mount_default_opts` | `"defaults,nofail"` | Default mount options string (`nofail` prevents boot hangs if a secondary disk is absent) |
| `disk_mount_default_fstab_src_type` | `"uuid"` | Default block identifier written to `/etc/fstab` (`uuid`, `partuuid`, `label`, `device`) |
| `disk_mount_default_allow_non_empty` | `false` | Permit mounting over an existing unmounted non-empty directory |
| `disk_mount_fstab_path` | `"/etc/fstab"` | Path to the fstab file managed for persistent mounts |
| `disk_mount_backup_fstab` | `true` | Create a backup of `disk_mount_fstab_path` before making changes |

### Per-Disk Entry Schema (`disk_mount_disks` items)

| Key | Required | Default | Description |
|---|---|---|---|
| `device` | Yes | — | Block device path starting with `/dev/` (e.g., `/dev/sdb`, `/dev/nvme1n1`, `/dev/sdb1`) |
| `path` | Yes | — | Target absolute mount point path (must not be `/`, `/boot`, `/dev`, `/proc`, `/sys`, `/run`) |
| `fstype` | No | `disk_mount_default_fstype` | Filesystem type (`ext4`, `xfs`, `btrfs`, `ext3`, `vfat`) |
| `state` | No | `"mounted"` | Lifecycle state: `mounted`, `present`, `unmounted`, `absent` |
| `auto_mount` | No | `disk_mount_default_auto_mount` | Persist `/etc/fstab` entry (`true`) or mount ephemerally (`false`; invalid with `state: "present"`) |
| `partition` | No | `disk_mount_default_partition` | Manage partition table & partition (`true`) or format/mount `device` directly (`false`) |
| `partition_table` | No | `disk_mount_default_partition_table` | Partition table format (`gpt` or `msdos`) |
| `partition_number` | No | `1` | Partition index (`>= 1`; `<= 4` on `msdos`) |
| `partition_start` | No | `"0%"` | Start offset passed to `parted` |
| `partition_end` | No | `"100%"` | End offset passed to `parted` |
| `partition_name` | No | `""` | Optional GPT partition name (rejected when `partition_table: "msdos"`) |
| `partition_flags` | No | `[]` | Optional list of `parted` flags (e.g., `["lvm"]`) |
| `partition_align` | No | `"optimal"` | Partition alignment (`optimal`, `minimal`, `cylinder`, `none`) |
| `label` | No | `""` | Optional volume label applied at format time (required non-empty when `fstab_src_type: "label"`) |
| `mkfs_opts` | No | `""` | Optional extra CLI flags appended at format time (format-time-only unless `force: true` reformats) |
| `opts` | No | `disk_mount_default_opts` | Comma-separated mount options |
| `dump` | No | `0` | fstab dump field (`0` or `1`) |
| `passno` | No | `0` | fstab fsck pass number (`0`, `1`, or `2`) |
| `fstab_src_type` | No | `disk_mount_default_fstab_src_type` | fstab device identifier (`uuid`, `partuuid`, `label`, `device`) |
| `owner` | No | `""` | Optional directory owner applied after mounting (`state: "mounted"`) |
| `group` | No | `""` | Optional directory group applied after mounting (`state: "mounted"`) |
| `mode` | No | `""` | Optional quoted octal permissions applied after mounting (`state: "mounted"`, e.g., `'0750'`) |
| `allow_non_empty` | No | `disk_mount_default_allow_non_empty` | Allow mounting over an unmounted non-empty directory |
| `force` | No | `false` | Allow wiping conflicting partition tables/whole-disk signatures or reformatting mismatched filesystems |

## Safety Behavior

By default (`force: false`, `allow_non_empty: false`), the role fails fast before modifying storage or hiding existing files when:

* `device` is already a partition (`lsblk TYPE == "part"`) while `partition: true`.
* `device` already holds a conflicting partition table type or an unpartitioned whole-disk filesystem while `partition: true`.
* The target block device/partition already contains a different filesystem than `fstype`.
* An unmounted target mount directory already exists and contains files or subdirectories.
* Validation detects protected mount paths (`/`, `/boot`, `/dev`, `/proc`, `/sys`, `/run`), duplicate mount paths or target block devices, mixed `partition: true`/`false` on the same parent disk, or `state: "present"` with `auto_mount: false`.

> **Format-time-only options**: `label` and `mkfs_opts` are applied only when creating a new filesystem or forcefully reformatting a mismatched filesystem (`force: true`). Existing matching filesystems are left untouched to preserve data and ensure idempotency.

## Example Playbooks

### Basic GPT + `ext4` + Persistent UUID Auto-Mount

```yaml
---
- name: Provision data disk
  hosts: storage_nodes
  become: true
  roles:
    - role: hifra01.utils.disk_mount
      vars:
        disk_mount_disks:
          - device: "/dev/sdb"
            path: "/mnt/data"
            owner: "www-data"
            group: "www-data"
            mode: "0750"
```

### Multi-Disk: XFS Database Volume, Whole-Disk Ephemeral Scratch, and Lifecycle Removal

```yaml
---
- name: Configure specialized storage mounts
  hosts: app_nodes
  become: true
  roles:
    - role: hifra01.utils.disk_mount
      vars:
        disk_mount_disks:
          - device: "/dev/nvme1n1"
            path: "/var/lib/pgdata"
            partition_table: "gpt"
            partition_name: "pgdata"
            fstype: "xfs"
            label: "PGDATA"
            opts: "defaults,noatime,nofail"
            fstab_src_type: "label"
            auto_mount: true

          - device: "/dev/vdc"
            path: "/mnt/scratch"
            partition: false
            fstype: "ext4"
            mkfs_opts: "-m 1"
            auto_mount: false

          - device: "/dev/vdd"
            path: "/mnt/retired"
            state: "absent"
```

## License

MIT-0

## Author Information

Hilman F. Rakhmad (`hifra.dev`)
