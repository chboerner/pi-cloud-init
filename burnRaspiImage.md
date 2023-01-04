## burnRaspiImage

## Usage
Options:
* `-D <target device>`      Target device for RaspberryPiOS.
  * Only device, not file systems! Ex. /dev/sdd instead of /dev/sdd1
* `-I <image>`            RaspberryPiOS image which should be written to the disk.
* `-S <size>`             Size of secondary partition in Gigabytes (created at end of disk)

The target device and image parameters are mandatory (for obvious reasons).<br>
The parameter `-S <size>` is optional. If it is provided an additional partition is added to the end of the device with
the given size. The units `K` (Kilobyte), `M` (Megabyte), `G` (Gigabyte) and `T` (Terabyte) are supported.

The script must be run with sudo or as root.

### Example
```bash
sudo ./burnRaspiImage -D /dev/sdh -I /home/user/2023-01-04-raspios-bullseye-aarch64-lite-cloud-init.img -S 200G
```
This will transfer the image to the storage device /dev/sdh and create an additional partition with 200G size.

## Requirements
If the secondary partition parameter is given, **parted** must be installed.
