#!/bin/sh
#install tools
sudo apt-get -y install parted kpartx dump

#   挂在U盘到 /mnt/usb 如果不将备份放到U盘，放到其他地方的话这里目录改为要备份到的目录
usbmount=/mnt/usb
#   备份的文件名 img=$usbmount/rpi.img
img=$usbmount/rpi-`date +%Y%m%d-%H%M`.img

cd $usbmount

echo ===================== part 1, create a new blank img ===============================
# New img file 新建IMG文件，先获取boot和root已用空间大小
bootsz=`df -P | grep /boot | awk '{print $2}'`
rootsz=`df -P | grep /dev/root | awk '{print $3}'`
totalsz=`echo $bootsz $rootsz | awk '{print int(($1+$2)*1.3)}'`
sudo dd if=/dev/zero of=$img bs=1K count=$totalsz

# format virtual disk
bootstart=`sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p1 | awk '{print $2}'`
bootend=`sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p1 | awk '{print $3}'`
rootstart=`sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p2 | awk '{print $2}'`
#rootend=`sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p2 | awk '{print $3}'`
echo "boot: $bootstart >>> $bootend, root: $rootstart >>> end"

sudo parted $img --script -- mklabel msdos
#sudo parted $img --script -- mkpart primary fat32 8192s 122879s
#sudo parted $img --script -- mkpart primary ext4 122880s -1
sudo parted $img --script -- mkpart primary fat32 ${bootstart}s ${bootend}s
sudo parted $img --script -- mkpart primary ext4 ${rootstart}s -1
sleep 5

loopdevice=`sudo losetup -f --show $img`
device=`sudo kpartx -va $loopdevice | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
device="/dev/mapper/${device}"
partBoot="${device}p1"
partRoot="${device}p2"
sleep 5

sudo mkfs.vfat $partBoot -n boot
sudo mkfs.ext4 $partRoot


echo ===================== part 2, fill the data to img =========================
# mount partitions
mountb=$usbmount/backup_boot/
mountr=$usbmount/backup_root/

mkdir -p $mountb $mountr
# backup /boot

sudo mount -t vfat $partBoot $mountb
sudo cp -rfp /boot/* $mountb
sync
echo "...Boot partition done"
sleep 5
#sudo umount $mountb
# backup /root
sudo mount -t ext4 $partRoot $mountr
cd $mountr
sudo dump -0uaf - / | sudo restore -rf -
echo "...Root partition done"
sleep 5
cd

# replace PARTUUID
echo "...Replace PARTUUID"
opartuuidb=`blkid -o export /dev/mmcblk0p1 | grep PARTUUID`
opartuuidr=`blkid -o export /dev/mmcblk0p2 | grep PARTUUID`
npartuuidb=`blkid -o export ${partBoot} | grep PARTUUID`
npartuuidr=`blkid -o export ${partRoot} | grep PARTUUID`
sudo sed -i "s/$opartuuidr/$npartuuidr/g" $mountb/cmdline.txt
sudo sed -i "s/$opartuuidb/$npartuuidb/g" $mountr/etc/fstab
sudo sed -i "s/$opartuuidr/$npartuuidr/g" $mountr/etc/fstab

sudo umount $mountb
sudo umount $mountr

# umount loop device
sudo kpartx -d $loopdevice
sudo losetup -d $loopdevice

rm -rf $mountb $mountr
echo "==== All done. You can un-plug the backup device"