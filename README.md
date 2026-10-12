# Ansible Collection - hifra01.utils

Documentation for the collection.

## Pengujian Lokal dengan Molecule

Pengujian lokal Ansible roles menggunakan Molecule dan Docker dapat dijalankan dengan langkah-langkah berikut:

### Prasyarat
1. Pastikan Docker Daemon sudah berjalan di mesin Anda.
2. Pastikan Python 3.10 atau versi terbaru telah terinstal.

### Instalasi Dependensi
Jalankan perintah berikut untuk menginstal semua dependensi Python:
```bash
pip install -r requirements.txt
```

### Menjalankan Pengujian
Masuk ke direktori role yang ingin diuji, lalu jalankan perintah `molecule test`.

Contoh untuk menguji role `datetime`:
```bash
cd roles/datetime
molecule test
```

### Parameterisasi Distro (Opsional)
Secara default, pengujian menggunakan image `geerlingguy/docker-ubuntu2204-ansible:latest`. Anda dapat menentukan distro lain melalui environment variable `MOLECULE_DISTRO`:
```bash
MOLECULE_DISTRO=geerlingguy/docker-rockylinux9-ansible:latest molecule test
```

