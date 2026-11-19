# Quickstart & Validation Guide: `hifra01.utils.disk_mount`

**Feature**: `010-disk-mount-role`  
**Date**: 2026-11-19  
**Contracts**: [role-interface.md](contracts/role-interface.md) | **Data Model**: [data-model.md](data-model.md)

## Prerequisites

- Python virtual environment with repository dev/test dependencies installed (`requirements.txt`):
  ```bash
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt
  ```
- Docker daemon running locally (required for Molecule multi-distro container verification with privileged loopback block devices).

## 1. Linting Validation

Run the exact linters executed in CI from the repository root:

```bash
yamllint .
ansible-lint
```

**Expected outcome**: Both commands exit with status `0` and zero errors.

## 2. Multi-Distro Molecule Verification

Run the parallel matrix test runner across all 5 supported Linux distributions (`ubuntu2204`, `ubuntu2404`, `debian12`, `rockylinux9`, `rockylinux8`):

```bash
./test-matrix.sh -r disk_mount
```

Or run against a single distribution during iteration:

```bash
./test-matrix.sh -r disk_mount -o ubuntu2404
```

Or directly inside the role directory:

```bash
cd roles/disk_mount
MOLECULE_DISTRO=geerlingguy/docker-ubuntu2404-ansible:latest molecule test
```

## 3. End-to-End Validation Scenarios Covered

The `roles/disk_mount/molecule/default/` scenario provisions sparse loopback block devices (`truncate -s 320M` + `losetup -P`) in privileged containers and verifies all acceptance criteria from [spec.md](spec.md):

1. **Default GPT + `ext4` + Persistent UUID Auto-Mount (US1, US3, SC-001, SC-002)**:
   - Converges a raw loopback disk with default partitioning (`gpt`, `0%`–`100%`) and `ext4` mounted at `/mnt/data_ext4` with custom `owner`/`group`/`mode`.
   - Verifies GPT partition table, `ext4` filesystem, active mount, directory ownership/mode on the mounted root, and a `UUID=...` entry in `/etc/fstab` with `defaults,nofail`.
   - Writes a marker file, unmounts `/mnt/data_ext4`, runs `mount -a` (simulating a server restart), and asserts `/mnt/data_ext4` automatically remounts with the marker file intact.
2. **MBR (`msdos`) + `xfs` + Volume Label + `LABEL=` fstab Identifier (US2, SC-001, SC-002)**:
   - Converges a second loopback disk with `partition_table: "msdos"`, `fstype: "xfs"`, `label: "XFS_DATA"`, and `fstab_src_type: "label"` at `/mnt/data_xfs`.
   - Verifies MBR partition table, `xfs` filesystem with label `XFS_DATA`, and `LABEL=XFS_DATA` in `/etc/fstab`.
3. **Whole-Disk Direct Format (`partition: false`) + Custom `mkfs_opts` + Ephemeral Mount (`auto_mount: false`) (US2, US3, SC-003)**:
   - Converges a third loopback disk with `partition: false`, `fstype: "ext4"`, `mkfs_opts: "-m 1"`, and `auto_mount: false` at `/mnt/data_ephemeral`.
   - Verifies no partition table was created, filesystem is mounted and writable, and zero entries exist in `/etc/fstab` for `/mnt/data_ephemeral`.
4. **Strict Idempotency (SC-004)**:
   - Molecule's built-in `idempotence` step re-runs `converge.yml` unchanged and asserts `changed=0` across all disks (including the ephemeral mount and custom ownership/permissions) with all marker files preserved.
5. **Safety Guards & Lifecycle Transitions (US2, US3, SC-005)**:
   - Verifies fail-fast rejection with zero data loss when:
     - Requesting a mismatched filesystem (`xfs` on an `ext4` volume) with `force: false`.
     - Requesting a conflicting partition table (`gpt` on an `msdos` disk or partitioning a whole-disk filesystem) with `force: false`.
     - Targeting an existing, unmounted, non-empty directory with `allow_non_empty: false`.
     - Providing invalid inputs (e.g., targeting `/`, duplicate mount paths, `state: "present"` with `auto_mount: false`).
   - Verifies `state: "unmounted"` (unmounts while preserving `/etc/fstab` and data) and `state: "absent"` (unmounts and removes `/etc/fstab` while preserving on-disk data).
   - Verifies empty `disk_mount_disks: []` completes with `changed=0`.
6. **Clean Teardown**:
   - `cleanup.yml` detaches test loopback devices so no loop slots leak on the Docker host.

## 4. Production Playbook Smoke Usage

Refer to [role-interface.md](contracts/role-interface.md) for the complete `disk_mount_*` variable schema. Example minimal playbook:

```yaml
- name: Provision data disks
  hosts: storage_nodes
  become: true
  roles:
    - role: hifra01.utils.disk_mount
      vars:
        disk_mount_disks:
          - device: "/dev/sdb"
            path: "/mnt/data"
            fstype: "ext4"
            auto_mount: true
```
