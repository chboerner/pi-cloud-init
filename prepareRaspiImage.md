# prepareRaspiImage.sh
This script uses the generic raspios image created before and adds some instance specifig configuration.

## Usage
Options:
* ``-I <disk image>``: the source image which shall be modified
* ``-T <disk image>``: the target image where the result shall be saved.
  * If this is not specified the customizations will be done directly to the source image.
* ``-C <instance configdir>``: the customizations which shall be added to the image


The script needs to be run with sudo or as root. This is required to mount the file systems and be able to create files
with root permissions in the target image.

## instance_config sample with central configuration options

This sample configuration holds

- basic configuration in bootfs to
    - create a simple network configuration
    - set a hostname
    - create some sample output files
- A network seed URL for the NoCloud configuration
    - this URL must have at least meta-data and user-data
    - Note: the URL must end with a "/". Check the NoCloud datasource documentation for further details.

The configuration of both sources (bootfs and net) are combined and applied to the machine. This way you can set machine
specific settings like the hostname per machine and configure a common set of configuration (eg. user accounts,
packages, ca-certificates) globally.

For multiple machines you can copy the directory and just change the ``-C`` parameter.

### Known issues
It is currently not possible (or completely undocumented) to define the NoCloud-Net URL dynamically (eg. with DMI or MAC
Address). Raspberry PI does not offer any DMI at the moment. Therefore it is also not possible to override these values 
via cmdline.txt. That's why the rootfs/etc/cloud/cloud.cfg.dir/00_NoCloud.cfg was introduced. In case you need machine 
specific cloud configurations you can adjust the URL there.

## Internals
The script looks out for specific files in the file system to detect which one is the boot filesystem and which is the
root filesystem.
In the next step all data from ``<instance configdir>/bootfs`` is copied recursively to the boot filesystem and
``<instance configdir>/rootfs`` to the root file system

## Troubleshooting
### Hostname from bootfs/user-data not set
Situation:
- NoCloud was configured with `fs_label: boot` and `seed: <myurl>`.
- In /boot/user-data only the `hostname: <myhostname>` was configured
- In /boot/meta-data only the `instance-id: <myinstance>` was configured
- The remaining data was read from the seed URL

Problem:
The hostname from /boot/user-data was not used

Solution:
Setting the hostname in /boot/meta-data as `local-hostname: <myhostname>` worked.
A test with a sample write_files revealed that user-data seems to be not used from the local drive when there a seed URL
is used as well.