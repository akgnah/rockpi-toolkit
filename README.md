> **note**
> Please visit https://github.com/radxa/backup-sh

# Rockpi-toolkit

Welcome to rockpi-toolkit, the repository will collect tools that can be used on officially supported ubuntu and debian.

## 1. rockpi-backup.sh

This script allows you to back up your system using Rock. It is currently possible to back up each other between uSD and eMMC. I haven't tested it on NVMe, because I don't have it yet.

_It may work for unofficial systems, but we do not provide any technical support._

### Install

```bash
linaro@rockpi:~ $ curl -sL https://rock.sh/rockpi-backup -o rockpi-backup.sh
linaro@rockpi:~ $ chmod +x rockpi-backup.sh
```

### Usage

#### Run `./rockpi-backup.sh -h` to print usage. Example for rock-5a.

```bash
root@rock-5a:/home/radxa# ./rockpi-backup.sh -h
Usage:
  sudo ./rockpi-backup.sh [-o path|-e pattern|-u|-m path]
    -o Specify output position, default is $PWD.
    -e Exclude files matching pattern for rsync.
    -u Unattended, no need to confirm in the backup process.
    -m Back up the root mount point, and support backups from other disks as well.
root@rock-5a:/home/radxa#
```
#### If you run it without any arguments, the script will work with the default values and will confirm you.

```bash
root@rock-5a:/home/radxa# ./rockpi-backup.sh
Welcome to rockpi-backup.sh, part of the ROCK Pi toolkit.

  Enter rockpi-backup.sh -h to view help.
  For a description and example usage, see the README.md at:
    https://rock.sh/rockpi-toolbox 

--------------------
Checking disk...
The backup file will be saved at /home/radxa/rock-5a-backup-231031-1015.img
After this operation, 5392 MB of additional disk space will be used.

Do you want to continue? [y/N]
```
#### You can specify output path with provide `-o argument`, if it is a directory, the output file will be directory+date.img, if it is a .img ending file, the output file will be the file.

```bash
root@rock-5a:/home/radxa# ./rockpi-backup.sh -o /mnt/backup
Welcome to rockpi-backup.sh, part of the ROCK Pi toolkit.

  Enter rockpi-backup.sh -h to view help.
  For a description and example usage, see the README.md at:
    https://rock.sh/rockpi-toolbox 

--------------------
Checking disk...
The backup file will be saved at /mnt/backup/rock-5a-backup-231031-1030.img
After this operation, 5392 MB of additional disk space will be used.

Do you want to continue? [y/N] 
```
#### You can specify the root mount path with -m mount-point, and it will back up the specified mount point system.

### Tips

1. If you want to use dd to restore your image, and your uSD or eMMC has GPT partitions and is mounted, please umount before dd.

2. The script only supports GPT disk type and the ext4 file system for the root, and it assumes that the root partition is the largest partition on the disk.
