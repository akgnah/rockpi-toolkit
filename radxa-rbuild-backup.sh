#!/bin/bash
set -e
VERSION="1.0"
MODEL=`cat /proc/device-tree/model`
BOARD_NAME=${MODEL// /-}
SCRIPT_NAME=$(basename $0)
CONFIG_MOUNT=$(mktemp -d)
ROOT_MOUNT=$(mktemp -d)
DEVICE=/dev/$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p' | cut -b 1-7)

check_root() {
  if [ $(id -u) != 0 ]; then
    echo -e "${SCRIPT_NAME} needs to be run as root.\n"
    exit 1
  fi
}

get_option() {
  exclude=""
  label=rootfs
  model=$BOARD_NAME
  OLD_OPTIND=$OPTIND
  while getopts "o:e:l:u:h" flag; do
    case $flag in
      o)
        output="$OPTARG"
        ;;
      e)
        exclude="${exclude} --exclude ${OPTARG}"
        ;;
      l)
        label="$OPTARG"
        ;;
      u)
        $OPTARG
        unattended="1"
        ;;
      h)
        $OPTARG
        print_help="1"
        ;;
    esac
  done
  OPTIND=$OLD_OPTIND
}

confirm() {
  if [ "$unattended" == "1" ]; then
    return 0
  fi
  printf "\n%s [Y/n] " "$1"
  read resp
  if [ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ]; then
    return 0
  fi
  if [ "$2" == "abort" ]; then
    echo -e "Abort.\n"
    exit 0
  fi
  if [ "$2" == "clean" ]; then
    rm "$3"
    echo -e "Abort.\n"
    exit 0
  fi
  return 1
}

install_tools() {
  commands="rsync parted gdisk fdisk kpartx mkfs.vfat losetup"
  packages="rsync parted gdisk fdisk kpartx dosfstools util-linux"

  idx=1
  need_packages=""
  for cmd in $commands; do
    if ! command -v $cmd > /dev/null; then
      pkg=$(echo "$packages" | cut -d " " -f $idx)
      printf "%-30s %s\n" "Command not found: $cmd", "package required: $pkg"
      need_packages="$need_packages $pkg"
    fi
    ((++idx))
  done

  if [ "$need_packages" != "" ]; then
    confirm "Do you want to apt-get install the packages?" "abort"
    apt-get update
    apt-get install -y --no-install-recommends $need_packages
    echo '--------------------'
  fi
}

gen_partitions() {
  if [ "$model" ]; then
    loader1_size=8000
    reserved1_size=128
    reserved2_size=8192
    loader2_size=8192
    atf_size=8192
    boot_size=1048576

    system_start=0
    loader1_start=64
    config_start=32768
    reserved1_start=$(expr ${loader1_start} + ${loader1_size})
    reserved2_start=$(expr ${reserved1_start} + ${reserved1_size})
    loader2_start=$(expr ${reserved2_start} + ${reserved2_size})
    atf_start=$(expr ${loader2_start} + ${loader2_size})
    boot_start=$(expr ${atf_start} + ${atf_size})
    rootfs_start=65536
  else
    echo cannot find board name !!!
    exit -1
  fi
}

gen_image_file() {
  if [ "$output" == "" ]; then
    output="${PWD}/${model}-backup-$(date +%y%m%d-%H%M).img"
  else
    if [ "${output:(-4)}" == ".img" ]; then
      mkdir -p $(dirname $output)
    else
      mkdir -p "$output"
      output="${output%/}/${model}-backup-$(date +%y%m%d-%H%M).img"
    fi
  fi

  rootfs_size=$(expr $(df -P | grep /$ | awk '{print $3}') \* 5 / 4 \* 1024)
  backup_size=$(expr \( $rootfs_size + \( ${rootfs_start} + 40 \) \* 512 \) / 1024 / 1024)

  dd if=/dev/zero of=${output} bs=1M count=0 seek=$backup_size status=none

  if [ "$model" ]; then
    parted -s ${output} mklabel gpt
    parted -s ${output} unit s mkpart config ${config_start} $(expr ${rootfs_start} - 1)

    parted -s ${output} -- unit s mkpart rootfs ${rootfs_start} -34s
    parted -s ${output} set 2 boot on
    ROOT_UUID=$(blkid -o export ${DEVICE}p2 | grep ^UUID)

    fdisk ${output} > /dev/null << EOF
x
u
2
${ROOT_UUID}
r
w
EOF
  fi
}

check_avail_space() {
  output_=${output}
  while true; do
    store_size=$(df -BM | grep "$output_\$" | awk '{print $4}' | sed 's/M//g')
    if [ "$store_size" != "" ] || [ "$output_" == "\\" ]; then
      break
    fi
    output_=$(dirname $output_)
  done

  if [ $(expr ${store_size} - ${backup_size}) -lt 64 ]; then
    rm ${output}
    echo -e "No space left on ${output_}\nAborted.\n"
    exit 1
  fi

  return 0
}

backup_image() {
  loopdevice=$(losetup -f --show $output)
  mapdevice="/dev/mapper/$(kpartx -va $loopdevice | sed -E 's/.*(loop[0-9]+)p.*/\1/g' | head -1)"
  sleep 2  # waiting for kpartx

  if [ "$model" ]; then
    mkfs.vfat -n config ${mapdevice}p1
    mkfs.ext4 -L ${label} ${mapdevice}p2
    mount -t vfat ${mapdevice}p1 ${CONFIG_MOUNT}
    mount -t ext4 ${mapdevice}p2 ${ROOT_MOUNT}

    dd if=${DEVICE} of=${output} skip=${loader1_start} seek=${loader1_start} count=32703 conv=notrunc
  fi

  rsync --force -rltWDEgop --delete --stats --progress //config/ ${CONFIG_MOUNT}

  rsync --force -rltWDEgop --delete --stats --progress $exclude \
    --exclude "$output" \
    --exclude '.gvfs' \
    --exclude '/config' \
    --exclude '/dev' \
    --exclude '/media' \
    --exclude '/mnt' \
    --exclude '/proc' \
    --exclude '/run' \
    --exclude '/sys' \
    --exclude '/tmp' \
    --exclude 'lost\+found' \
    // $ROOT_MOUNT

  # special dirs
  for i in config dev media mnt proc run sys; do
    if [ ! -d $ROOT_MOUNT/$i ]; then
      mkdir $ROOT_MOUNT/$i
    fi
  done

  if [ ! -d $ROOT_MOUNT/tmp ]; then
    mkdir $ROOT_MOUNT/tmp
    chmod a+w $ROOT_MOUNT/tmp
  fi

  expand_fs && update_uuid && sync
  umount $CONFIG_MOUNT && rm -rf $CONFIG_MOUNT
  umount $ROOT_MOUNT && rm -rf $ROOT_MOUNT
  losetup -d $loopdevice
  kpartx -d $loopdevice

  echo -e "\nBackup done, the file is ${output}"
}

expand_fs() {
  basic_target=$ROOT_MOUNT/etc/systemd/system/basic.target.wants
  if [ ! -d $basic_target ]; then
    mkdir $basic_target
  fi

  if [ "$model" ]; then
    ln -s $ROOT_MOUNT/lib/systemd/system/resize-assistant.service $basic_target/resize-assistant.service
  fi
}

update_uuid() {
  if [ "$model" ]; then
    old_config_uuid=$(blkid -o export ${DEVICE}p1 | grep ^UUID)
    old_root_uuid=$(blkid -o export ${DEVICE}p2 | grep ^UUID)
    new_config_uuid=$(blkid -o export ${mapdevice}p1 | grep ^UUID)
    new_root_uuid=$(blkid -o export ${mapdevice}p2 | grep ^UUID)

    sed -i "s/$old_config_uuid/$new_config_uuid/g" $ROOT_MOUNT/etc/fstab
    sed -i "s/$old_root_uuid/$new_root_uuid/g" $ROOT_MOUNT/etc/fstab
    sed -i "s/${old_root_uuid}/${new_root_uuid}/g" $ROOT_MOUNT/boot/extlinux/extlinux.conf
  fi
}

usage() {
  echo -e "Usage:\n  sudo ./${SCRIPT_NAME} [-o path|-e pattern|-m model|-l label|-t target|-u]"
  echo '    -o specify output position, default is $PWD'
  echo '    -e exclude files matching pattern for rsync'
  echo '    -l specify a volume label for rootfs, default is rootfs'
  echo '    -u unattended, no need to confirm in the backup process'
}

main() {
  check_root

  echo -e "Welcome to rockpi-backup.sh, part of the ROCK Pi toolkit.\n"
  echo -e "  Enter ${SCRIPT_NAME} -h to view help."
  echo -e "  For a description and example usage, see the README.md at:
    https://rock.sh/rockpi-toolbox \n"
  echo '--------------------'

  if [ "$target" == "expand" ]; then
    target_expand
  else
    install_tools
    gen_partitions
    gen_image_file
    check_avail_space

    printf "The backup file will be saved at %s\n" "$output"
    printf "After this operation, %s MB of additional disk space will be used.\n" "$backup_size"
    confirm "Do you want to continue?" "clean" "$output"

    backup_image
  fi
}

get_option $@
if [ "$print_help" == "1" ]; then
  usage
else
  main
fi
# end
