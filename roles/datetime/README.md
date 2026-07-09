Datetime Role
=============

This role ensures that `tzdata` is installed on target servers and configures the system timezone.

Supported Platforms
------------------

This role is compatible with:
*   **Debian/Ubuntu** (APT)
*   **RHEL/CentOS/Rocky/Alma** (RPM)
*   **Alpine Linux** (APK)
*   **Arch Linux** (pacman)

Requirements
------------

Ensure that the target host supports fact gathering (`gather_facts: true`) as the role relies on `ansible_os_family` to validate the OS and refresh package caches before installing `tzdata`.

Role Variables
--------------

*   `datetime_tz`: The timezone to set on the server. Default is `"UTC"`.

Example Playbook
----------------

```yaml
- hosts: all
  become: true
  roles:
    - role: datetime
      vars:
        datetime_tz: "Asia/Jakarta"
```

License
-------

MIT-0

