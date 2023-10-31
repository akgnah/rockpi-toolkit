#!/bin/bash
set -e
SCRIPT_NAME=$(basename $0)
ROOT_MOUNT=$(mktemp -d)

DEVICE=/dev/$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p' | cut -b 1-7)

model=`uname -n`

MOUNT_POINT=/
GROW_SCRIPT=/usr/local/bin/growpart-by-backup.sh
GROW_SERVER_NAME=growpart-by-backup
GROW_SERVER=/etc/systemd/system/$GROW_SERVER_NAME.service

check_root() {
  if [ $(id -u) != 0 ]; then
    echo -e "${SCRIPT_NAME} needs to be run as root.\n"
    exit 1
  fi
}


get_option() {
  exclude=""
  label=rootfs
  OLD_OPTIND=$OPTIND
  while getopts "o:e:uhm:" flag; do
    case $flag in
      o)
        output="$OPTARG"
        ;;
      e)
        exclude="${exclude} --exclude ${OPTARG}"
        ;;
      u)
        $OPTARG
        unattended="1"
        ;;
      h)
        $OPTARG
        print_help="1"
        ;;
      m)
        MOUNT_POINT="$OPTARG"
        ;;
    esac
  done
  OPTIND=$OLD_OPTIND
}


confirm() {
  if [ "$unattended" == "1" ]; then
    return 0
  fi
  printf "\n%s [y/N] " "$1"
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


check_part() {
  echo Checking disk...

  device_part=$(df $MOUNT_POINT --output=source | tail -n +2)

  device=/dev/`lsblk -no pkname,MOUNTPOINT | grep "$MOUNT_POINT$" | awk '{print $1}'`
  device_part_num=`gdisk $device -l | awk '{last_line=$0} END{print $1}'`
  disk_type=`parted $device print | grep "Partition Table" | awk '{print $3}'`
  if [ "$disk_type" != "gpt" ]; then
    echo "Only supports GPT disk type."
    exit -1
  fi
  last_part_start=$(fdisk $device -l | grep $device | awk '{last_line=$0} END{print $2}')
  rootfs_start=$(fdisk $device -l | grep $device_part | awk 'NR == 1{print $2}')

  if [ "$last_part_start" != "$rootfs_start" ]; then
    echo "Unsupported partition format. The root partition is not at the end, or the root partition is not the largest partition."
    exit -2
  fi

  fstype=`lsblk $device_part -no FSTYPE,PATH | awk '{print $1}'`

  if [ "$fstype" != "ext4"  ];then
    echo "Only supports ext4 fstype."
    exit -1
  fi
}

create_service(){
  echo Create service...
    echo "[Unit]
Description=Auto grow the root part.
After=-.mount

[Service]
ExecStart=$GROW_SCRIPT
Type=oneshot

[Install]
WantedBy=multi-user.target
" > $MOUNT_POINT$GROW_SERVER

  ln -s $MOUNT_POINT$GROW_SERVER  $MOUNT_POINT/etc/systemd/system/multi-user.target.wants/ || true

  echo "#!/bin/bash
# Auto create by $SCRIPT_NAME

set -e
ROOT_PART=/dev/\`lsblk -no pkname,MOUNTPOINT | grep \"/$\" | awk '{print \$1}'\`
ROOT_PART_NO=$device_part_num
ROOT_DEV=\`lsblk -no PATH,MOUNTPOINT | grep \"/$\" | awk '{print \$1}'\`

# fix disk size
echo w | fdisk \$ROOT_PART

echo -e \"resizepart \$ROOT_PART_NO 100%\ny\" | parted ---pretend-input-tty \$ROOT_PART

# ext4 part only
resize2fs \$ROOT_DEV

# disabled server
systemctl disable $GROW_SERVER_NAME
" > $MOUNT_POINT$GROW_SCRIPT

  chmod +x $MOUNT_POINT$GROW_SCRIPT

}

install_tools() {
  commands="rsync parted gdisk fdisk kpartx tune2fs losetup "
  packages="rsync parted gdisk fdisk kpartx e2fsprogs util-linux"

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

gen_image_file() {
  if [ "$output" == "" ]; then
    output="${PWD}/${model}-backup-$(date +%y%m%d-%H%M).img"
  else
    if [ "${output:(-4)}" == ".img" ]; then
      output=$(realpath $output)
      mkdir -p $(dirname $output)
    else
      output=$(realpath $output)
      mkdir -p "$output"
      output="${output%/}/${model}-backup-$(date +%y%m%d-%H%M).img"
    fi
  fi

  rootfs_size=$(df -B512 $MOUNT_POINT | awk 'NR == 2{print $3}')
  backup_size=$(expr $rootfs_size +  $rootfs_start + 40 + 1000000 )

  dd if=/dev/zero of=${output} bs=512 count=0 seek=$backup_size status=none
}


check_avail_space() {
  output_=${output}
  while true; do
    store_size=$(df -B512 | grep "$output_\$" | awk '{print $4}' | sed 's/M//g')
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

rebuild_root_partition() {
  echo rebuild root partition...

  echo Delete inappropriate partition and fix
  echo -e "d\n$device_part_num\nw\ny" | gdisk $output > /dev/null

  # get partition infomations
  local type=`echo -e "x\ni\n$device_part_num\n" | gdisk $device |grep "Partition GUID code:"| awk '{print $12}'`
  local guid=`echo -e "x\ni\n$device_part_num\n" | gdisk $device |grep "Partition unique GUID:"| awk '{print $4}'`
  local attribute_flags=$((16#`echo -e "x\ni\n$device_part_num\n" | gdisk $device |grep "Attribute flags:"| awk '{print $3}'`))
  local _partition_name=`echo -e "x\ni\n$device_part_num\n" | gdisk $device |grep "Partition name:"| awk '{print $3}'`
  local partition_name=${_partition_name:1:-1}

  echo Create new root partition
  echo -e "n\n$device_part_num\n$rootfs_start\n\n\nw\ny\n" | gdisk $output > /dev/null

  echo Change part GUID
  echo -e "x\nc\n$device_part_num\n$guid\nw\ny\n" | gdisk $output > /dev/null

  echo Change part Label
  echo -e "c\n$device_part_num\n$partition_name\nw\ny\n" | gdisk $output > /dev/null

  echo Change part type
  echo -e "t\n$device_part_num\n$type\nw\ny\n" | gdisk $output > /dev/null

  echo Change attribute_flag
  flag_str=""
  local t=0
  echo flags $attribute_flags
  while [ $attribute_flags -ne 0 ]
  do
    echo $attribute_flags
    if (( (attribute_flags & 1) != 0 )); then
      flag_str="$flag_str$t\n"
    fi
    (( attribute_flags = attribute_flags >> 1 )) || true
    (( t = t + 1))
  done
  echo "x\na\n$device_part_num\n$flag_str\nw\ny\n"
  echo -e "x\na\n$device_part_num\n$flag_str\nw\ny\n" | gdisk $output
}

exclude_mounted_part() {
  # The other parts have been copied
  echo Exclude mounted part...
  _exclude=""
  for i in `lsblk -no PATH,MOUNTPOINT | awk {'print $2'}`;
  do
    if [ "$i" != "$MOUNT_POINT" ] ;then
      _exclude="$_exclude --exclude $i"
    fi
  done
  echo $_exclude

}

backup_image() {

  echo "Copy other partition"
  dd if=$device of=$output bs=512 seek=0 count=$(expr $rootfs_start - 1) status=progress conv=notrunc

  rebuild_root_partition

  echo Mount loop device...
  loopdevice=$(losetup -f --show $output)
  mapdevice="/dev/mapper/$(kpartx -va $loopdevice | sed -E 's/.*(loop[0-9]+)p.*/\1/g' | head -1)"
  sleep 2  # waiting for kpartx

  loop_root_dev=${mapdevice}p$device_part_num

  echo format root partition...
  mkfs.ext4 $loop_root_dev

  e2fsck -f $loop_root_dev

  tune2fs -U `lsblk $device_part -no UUID` $loop_root_dev

  mount $loop_root_dev $ROOT_MOUNT



  exclude_mounted_part

  echo Start rsync...


  rsync --force -rltWDEHSgop --delete --stats --progress $_exclude $exclude \
    --exclude "$output" \
    --exclude .gvfs \
    --exclude $MOUNT_POINT/dev \
    --exclude $MOUNT_POINT/media \
    --exclude $MOUNT_POINT/mnt \
    --exclude $MOUNT_POINT/proc \
    --exclude $MOUNT_POINT/run \
    --exclude $MOUNT_POINT/sys \
    --exclude $MOUNT_POINT/tmp \
    --exclude lost+found \
    --exclude $MOUNT_POINT/var/log \
    $MOUNT_POINT/ $ROOT_MOUNT

  # special dirs
  for i in dev media mnt proc run sys; do
    if [ ! -d $ROOT_MOUNT/$i ]; then
      mkdir $ROOT_MOUNT/$i
    fi
  done

  if [ ! -d $ROOT_MOUNT/tmp ]; then
    mkdir $ROOT_MOUNT/tmp
    chmod a+w $ROOT_MOUNT/tmp
  fi

  sync
  umount $ROOT_MOUNT && rm -rf $ROOT_MOUNT
  losetup -d $loopdevice
  kpartx -d $loopdevice

  rm $MOUNT_POINT/etc/systemd/system/multi-user.target.wants/$GROW_SERVER_NAME.service

  echo -e "\nBackup done, the file is ${output}"
}


usage() {
  echo -e "Usage:\n  sudo ./${SCRIPT_NAME} [-o path|-e pattern|-u|-m path]"
  echo '    -o Specify output position, default is $PWD.'
  echo '    -e Exclude files matching pattern for rsync.'
  echo '    -u Unattended, no need to confirm in the backup process.'
  echo '    -m Back up the root mount point, and support backups from other disks as well.'
}


main() {
  check_root

  echo -e "Welcome to rockpi-backup.sh, part of the ROCK Pi toolkit.\n"
  echo -e "  Enter ${SCRIPT_NAME} -h to view help."
  echo -e "  For a description and example usage, see the README.md at:
    https://rock.sh/rockpi-toolbox \n"
  echo '--------------------'
  install_tools
  check_part
  gen_image_file
  check_avail_space

  printf "The backup file will be saved at %s\n" "$output"
  printf "After this operation, %s MB of additional disk space will be used.\n" "$(expr $backup_size / 2048)"
  confirm "Do you want to continue?" "clean" "$output"
  create_service
  backup_image
}


get_option $@
if [ "$print_help" == "1" ]; then
  usage
else
  main
fi
# end
