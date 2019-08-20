# Rockpi-toolkit

Welcome to rockpi-toolkit, the repository will collect tools that can be used on officially supported ubuntu and debian.

## 1. rockpi-backup.sh

This script allows you to back up your system using Rockpi4 or RockpiS. It is currently possible to back up each other between uSD and eMMC. I haven't tested it on NVMe, because I don't have it yet.

### Install

``` bash
linaro@rockpi:~ $ curl -sL https://rock.sh/rockpi-backup -o rockpi-backup.sh
linaro@rockpi:~ $ chmod +x rockpi-backup.sh
```

### Usage

Run ./rockpi-backup.sh -h to print usage.

```bash
linaro@rockpi:~ $ sudo ./rockpi-backup.sh -h
Usage:
  sudo ./rockpi-backup.sh [-o output|-m model|-l label|-t target|-u]
    -o specify output position, default is $PWD
    -m specify model, rockpi4 or rockpis, default is rockpi4
    -l specify a volume label for rootfs, default is rootfs
    -t specify target, backup or expand, default is backup
    -u unattended backup image, no confirmations asked
linaro@rockpi:~ $
```

If you run it without any arguments, the script will work with the default values and will confirm you.

```bash
linaro@rockpi:~ $ sudo ./rockpi-backup.sh
Welcome to rockpi-backup.sh, part of the Rockpi toolbox.

  Enter rockpi-backup.sh -h to view help.
  For a description and example usage, see the README.md at:
    https://rock.sh/rockpi-toolbox

--------------------
Warning: The resulting partition is not properly aligned for best performance.
--------------------
The backup file will be saved at /home/linaro/rockpi-backup-190725-1004.img
After this operation, 4656 MB of additional disk space will be used.

Do you want to continue? [Y/n]
```

You can specify output path with provide -o argument, if it is a directory, the output file will be directory+date.img, if it is a .img ending file, the output file will be the file.

```bash
linaro@rockpi:~ $ sudo ./rockpi-backup.sh -o /home/linaro/debian.img
Welcome to rockpi-backup.sh, part of the Rockpi toolbox.

  Enter rockpi-backup.sh -h to view help.
  For a description and example usage, see the README.md at:
    https://rock.sh/rockpi-toolbox

--------------------
Warning: The resulting partition is not properly aligned for best performance.
--------------------
The backup file will be saved at /home/linaro/debian.img
After this operation, 4656 MB of additional disk space will be used.

Do you want to continue? [Y/n]
```

### Tips

1. If you want to use dd to restore your image, and your uSD or eMMC has GPT partitions and is mounted, please umount before dd.

2. If you are using ubuntu, want to backup and restore from uSD to eMMC, or from eMMC to uSD, you need to edit the boot line in /etc/fstab, mmcblk0 for uSD and mmcblk1 for eMMC.
