#!/bin/bash -ex
PICLOUDINITDIR=$(readlink -m $(dirname $0))

ARCH="${ARCH:-aarch64}"

# go to home and fetch pi-gen
cd /home/vagrant

if [ -d pi-gen ] ; then
  echo "found pi-gen, skipping clone"
else
  echo "cloning pi-gen"

  git clone https://github.com/RPi-Distro/pi-gen.git
fi

pushd pi-gen

chmod +x build.sh

case "$ARCH" in
  armhf)
    git checkout master
    ;;
  aarch64)
    echo "WARNING: 64-bit build is experimental"
    git checkout arm64
    ;;
  *)
    >&2 echo "unsupported architecture '$ARCH'"
    exit 1
    ;;
esac

### write out config
eval "cat >config <<EOF
$(<$PICLOUDINITDIR/pigen_config/config)
EOF
" 2> /dev/null

### modify stage2
pushd stage2

# don't need NOOBS
rm -f EXPORT_NOOBS || true

cat > EXPORT_IMAGE <<EOF
IMG_SUFFIX="-lite-cloud-init"
if [ "${USE_QEMU}" = "1" ]; then
	export IMG_SUFFIX="${IMG_SUFFIX}-qemu"
fi
EOF

### add cloud-init step to stage2
step="10-cloud-init"
if [ -d "$step" ]; then
  rm -Rf $step
fi
mkdir $step && pushd $step

cat > 00-packages <<EOF
cloud-init
EOF


cp $PICLOUDINITDIR/pigen_config/cloud.cfg .
cat > 01-run.sh <<EOF
install -m 644 cloud.cfg "\${ROOTFS_DIR}/etc/cloud/cloud.cfg"
EOF
chmod +x 01-run.sh

cat > 01-run-chroot.sh <<EOF
#!/bin/bash

# Disable dhcpcd - it has a conflict with cloud-init network config
systemctl mask dhcpcd
EOF
chmod +x 01-run-chroot.sh

popd

### add cgroups step to stage2
step="11-cgroups"
if [ -d "$step" ]; then
  rm -Rf $step
fi
mkdir $step && pushd $step

cat > 00-run-chroot.sh <<"EOF"
#!/bin/bash

# Raspberry Pi OS doesn't enable cgroups by default
cmdline_string="cgroup_memory=1 cgroup_enable=memory"

if ! grep -q "$cmdline_string" /boot/cmdline.txt ; then
  sed -i "1 s/\$/ $cmdline_string/" /boot/cmdline.txt
fi
EOF
chmod +x 00-run-chroot.sh

popd

### add rfkill step to stage2
step="12-rfkill"
if [ -d "$step" ]; then
  rm -Rf $step
fi
mkdir $step && pushd $step

# must run after stage2/02-net-tweaks (which installs the wifi-check.sh script)
cat > 00-run-chroot.sh <<"EOF"
#!/bin/bash

# disable warning message on login about WiFi being blocked by rfkill
# WiFi is disabled by default, see https://github.com/RPi-Distro/pi-gen/blob/66cd2d17a0d2d04985b83a2ba830915c9a7d81dc/export-noobs/00-release/files/release_notes.txt#L223-L229
if [ -e /etc/profile.d/wifi-check.sh ] ; then
  mv /etc/profile.d/wifi-check.sh /etc/profile.d/wifi-check.sh.bak
fi
EOF
chmod +x 00-run-chroot.sh

popd

# end modifying stage2
popd

### start pi-gen build
sudo ./build.sh

### copy image back to project dir
zip_file=$(find deploy -name 'image_*.zip' -printf '%T@ %p\n' | sort -n | cut -d' ' -f 2- | tail -n 1)
copied_zip_file="${zip_file##*/image_}"
cp "$zip_file" "/home/vagrant/pi-cloud-init/$copied_zip_file"
