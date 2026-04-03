# Project TV - Rocky Edition

Kubernetes-based media server for Rocky Linux 10, featuring EPGStation, Mirakurun, Jellyfin, Tube Archivist, and Navidrome.

This project is the successor to [Project TV v2 (Ubuntu)](https://metalinux.dev/linux-journey/courses/project-tv-v2/), rewritten from the ground up for Rocky Linux with Kubernetes (kubeadm) replacing Docker Compose.

## Attribution

This project includes and depends on the following open source software:

- **[px4_drv](https://github.com/tsukumijima/px4_drv)** by [tsukumijima](https://github.com/tsukumijima) (originally by [nns779](https://github.com/nns779/px4_drv)) — Linux driver for PLEX and e-Better TV tuner devices. Licensed under **GPL-2.0**. See the [px4_drv LICENSE](https://github.com/tsukumijima/px4_drv/blob/develop/LICENSE) for full text.
- **[EPGStation](https://github.com/l3tnun/EPGStation)** by [l3tnun](https://github.com/l3tnun) — Digital broadcast recording system
- **[Mirakurun](https://github.com/Chinachu/Mirakurun)** by [Chinachu](https://github.com/Chinachu) — Digital broadcast tuner server
- **[Jellyfin](https://jellyfin.org/)** — Free software media system
- **[Tube Archivist](https://github.com/tubearchivist/tubearchivist)** by [bbilly1](https://github.com/bbilly1) — YouTube archive manager
- **[Navidrome](https://github.com/navidrome/navidrome)** — Modern music server and streamer

All third-party software retains its original licence. This project's installer scripts and Kubernetes manifests are provided under the MIT licence unless otherwise noted. Refer to individual upstream repositories for their respective licence terms.

## AI Usage

This repository adheres to an AI contribution policy inspired by the [Fedora AI-Assisted Contribution Policy](https://docs.fedoraproject.org/en-US/council/policy/ai-contribution-policy/). AI tools (such as Claude) are used to assist with content creation, formatting, and site development. All AI-generated content is reviewed and verified by a human before publication. If you find any errors, please open an issue.

## Overview

Project TV - Rocky Edition transforms a Rocky Linux 10 system into a fully featured media server running on Kubernetes. The interactive installer walks you through every step, from ZFS storage setup to application deployment.

### Architecture

```
Rocky Linux 10 (Host)
├── ZFS Pool (user-configured datasets)
├── Kubernetes (kubeadm + containerd + Flannel)
│   ├── Mirakurun (TV tuner management, port 40772)
│   ├── EPGStation + MariaDB (TV recording/scheduling, port 8888)
│   ├── Jellyfin (media server, port 8096)
│   ├── Tube Archivist + Redis + Elasticsearch (YouTube archiving, port 8000)
│   ├── Navidrome (music server, port 4533)
│   └── CronJob: Jellyfin library refresh (hourly)
├── Sanoid (ZFS snapshot management)
├── KDE Plasma (desktop environment)
└── px4_drv (TV tuner kernel driver via DKMS RPM)
```

### Key improvements over Project TV v2

- **Kubernetes** replaces Docker Compose for container orchestration
- **Navidrome** provides a lightweight, K8s-native music server
- **Jellyfin API CronJob** replaces the virt-manager VM hack for library refreshes
- **Dynamic ZFS datasets** — the installer prompts for dataset names and mount points
- **px4_drv RPM** — proper DKMS RPM package instead of manual driver compilation
- **Rocky Linux 10** as the base OS, with testing on Rocky 9 and 8

## Prerequisites

### Hardware requirements

- **CPU**: x86_64 processor (Intel or AMD), 4+ cores recommended
- **RAM**: 16 GB minimum (Elasticsearch alone requires 1 GB+)
- **Storage**: At least two disks — one for the OS (NVMe/SSD recommended), one or more for ZFS media pool
- **Network**: Gigabit Ethernet
- **TV tuner** (optional): PLEX PX-W3PE5, PX-Q3PE5, or other px4_drv-supported device
- **Smart card reader** (optional): SCM SCR331 or compatible (for B-CAS card)

### Software requirements

- Rocky Linux 10 minimal or KDE install
- Internet connection (for downloading packages and container images)
- A user account with sudo privileges

## Quick start

```bash
# Clone the repository
git clone https://github.com/Metalllinux/project-tv-rocky-edition.git
cd project-tv-rocky-edition

# Run the installer
sudo ./install.sh
```

The installer presents an interactive menu. You can run a full installation or select individual modules:

```
Project TV - Rocky Edition Installer
=====================================

[1]  Full Installation (run all modules in order)
[2]  Run a specific module
[3]  View installation status
[4]  View log file
[q]  Quit

Available modules:
  00  Preflight checks          09  Tube Archivist
  01  Timezone setup            10  Navidrome
  02  ZFS storage               11  Jellyfin library refresh
  03  Kubernetes (kubeadm)      12  Sanoid snapshots
  04  K8s namespace             13  Rsync media sync
  05  K8s storage (PV/PVC)      14  KDE customisation
  06  px4_drv TV tuner driver   15  Browser installation
  07  EPGStation + Mirakurun    16  SDDM autologin
  08  Jellyfin                  17  Firewall rules
                                18  Desktop applications
```

## Installer logging

All installer output is logged to `logs/install-YYYYMMDD-HHMMSS.log`. If you encounter any issues:

1. Check the log file for `[ERROR]` lines: `grep ERROR logs/install-*.log`
2. The log includes timestamps, commands run, and exit codes
3. Share the relevant log section when reporting issues

## Module details

### ZFS storage (module 02)

The installer interactively creates your ZFS pool and datasets:
- Shows available disks via `lsblk` and `/dev/disk/by-id/`
- Prompts for pool name, type (mirror/single/raidz), and disk selection
- Asks how many datasets you want and prompts for each name and mount point
- Creates the pool with `ashift=12` for 4K sector alignment
- Saves configuration to `config/datasets.conf` for use by later modules

### Kubernetes (module 03)

Installs full upstream Kubernetes via kubeadm:
- containerd as the container runtime
- Flannel CNI for pod networking
- Single-node configuration (control-plane taint removed)

### Application deployments (modules 07-10)

Each application is deployed as Kubernetes Deployments with Services, ConfigMaps, and Secrets. Media is accessed via PersistentVolumes backed by ZFS dataset host paths.

### TV channel scanning (module 07)

After Mirakurun is deployed, the installer offers to scan for TV channels. Three scan types are available:

1. **Terrestrial (GR)** — local broadcast channels (NHK, commercial stations, regional channels)
2. **BS satellite** — free-to-air satellite channels
3. **CS satellite** — premium satellite channels

Each scan takes a few minutes and reports how many channels were found. Scanned channels are saved to `/var/lib/project-tv/mirakurun/config/channels.yml` and persist across pod restarts.

You can re-scan at any time from the Mirakurun web UI or via the API:

```bash
# Terrestrial
curl -X PUT "http://<host-ip>:30772/api/config/channels/scan?type=GR&setDisabledOnAdd=false"

# BS satellite
curl -X PUT "http://<host-ip>:30772/api/config/channels/scan?type=BS&setDisabledOnAdd=false"

# CS satellite
curl -X PUT "http://<host-ip>:30772/api/config/channels/scan?type=CS&setDisabledOnAdd=false"
```

### Jellyfin library refresh (module 11)

Replaces the VM-based xdotool hack from v2 with a Kubernetes CronJob that calls the Jellyfin REST API:
```
POST /Library/Refresh
```
Runs hourly. Requires a Jellyfin API key (generated after first boot).

### Browser installation (module 15)

Offers a choice of browsers to install via Flatpak:
- Google Chrome, Brave, Waterfox, Firefox, Vivaldi, Chromium, Microsoft Edge

### Desktop applications (module 18)

Optional applications including:
- MakeMKV — DVD/Blu-ray ripper (via Flatpak)
- Jellyfin Media Player — desktop media client (via Flatpak)
- SeaDrive — Seafile virtual drive for KDE Dolphin

## Building the custom Rocky Linux 10 ISO

A pre-built custom ISO can be created that auto-installs Rocky Linux 10 with all prerequisites, then installs KDE Plasma on first boot. The result is a USB-bootable ISO — insert it, select install, and boot into KDE with the Project TV installer ready.

### Prerequisites

```bash
# Tools needed on the build host
sudo dnf install -y xorriso pykickstart
```

### Step 1: Extract the Rocky Linux 10 DVD ISO

```bash
mkdir -p ~/isos/custom-rocky10
xorriso -osirrox on \
  -indev ~/isos/Rocky-10.1-x86_64-dvd1.iso \
  -extract / ~/isos/custom-rocky10/iso-root
```

### Step 2: Copy the Project TV files into the ISO tree

```bash
rsync -a --exclude='.git' --exclude='logs/' \
  /path/to/project_tv_rocky_linux/ \
  ~/isos/custom-rocky10/iso-root/project_tv_rocky_linux/
```

### Step 3: Add the kickstart file

Copy `test/kickstart/ks-custom-iso.cfg` to the ISO root:

```bash
cp test/kickstart/ks-custom-iso.cfg ~/isos/custom-rocky10/iso-root/ks.cfg
```

**Important:** Edit `ks.cfg` before building the ISO:

1. **Target disk** — the default kickstart targets `nvme0n1`. Change `ignoredisk --only-use=`, `clearpart --drives=`, and `autopart --drives=` to match your target disk. **This will erase the target disk entirely.** All other disks are left untouched.
2. **Password** — set your own password on the `rootpw` and `user` lines. You can generate a SHA-512 hash with:

```bash
openssl passwd -6 'your-password-here'
```

Then replace the `--plaintext` lines with `--iscrypted $6$hash...`.

### Step 4: Modify the boot menu

Add a kickstart boot entry to the GRUB configuration. The new entry must be the **first** menuentry and `set default="0"` must be set.

**BIOS boot** — edit `iso-root/boot/grub2/grub.cfg`:

```
set default="0"
```

Add before the existing "Install Rocky Linux 10.1" entry:

```
menuentry 'Install Rocky Linux 10.1 (Project TV - Kickstart)' --class fedora --class gnu-linux --class gnu --class os {
	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Rocky-10-1-x86_64-dvd inst.ks=file:/ks.cfg quiet
	initrd /images/pxeboot/initrd.img
}
```

**EFI boot** — edit `iso-root/EFI/BOOT/grub.cfg` with the same entry but using `linuxefi`/`initrdefi`.

**EFI boot image** — the `grub.cfg` inside `iso-root/images/efiboot.img` must also be updated:

```bash
cp iso-root/images/efiboot.img /tmp/efiboot_rw.img
sudo mount -o loop /tmp/efiboot_rw.img /tmp/efiboot_mnt
sudo cp iso-root/EFI/BOOT/grub.cfg /tmp/efiboot_mnt/EFI/BOOT/grub.cfg
sudo umount /tmp/efiboot_mnt
sudo cp /tmp/efiboot_rw.img iso-root/images/efiboot.img
```

### Step 5: Inject the kickstart into the initrd

Anaconda reads kickstart files from the initrd most reliably:

```bash
mkdir -p /tmp/ks-inject
cp iso-root/ks.cfg /tmp/ks-inject/ks.cfg
cd /tmp/ks-inject
echo "ks.cfg" | cpio -o -H newc > /tmp/ks-initrd.img
cat ~/isos/custom-rocky10/iso-root/images/pxeboot/initrd.img /tmp/ks-initrd.img \
  > /tmp/initrd-with-ks.img
cp /tmp/initrd-with-ks.img ~/isos/custom-rocky10/iso-root/images/pxeboot/initrd.img
```

### Step 6: Rebuild the ISO

The volume label **must** be `Rocky-10-1-x86_64-dvd` (the GRUB `search` command depends on it):

```bash
cd ~/isos/custom-rocky10

xorriso -as mkisofs \
  -V 'Rocky-10-1-x86_64-dvd' \
  -o ~/isos/Rocky-10.1-x86_64-custom.iso \
  -b images/eltorito.img \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  --grub2-boot-info \
  -eltorito-alt-boot \
  -e images/efiboot.img \
  -no-emul-boot \
  --grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:~/isos/Rocky-10.1-x86_64-dvd1.iso \
  --protective-msdos-label \
  -partition_cyl_align off \
  -partition_offset 16 \
  -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B iso-root/images/efiboot.img \
  -appended_part_as_gpt \
  -iso_mbr_part_type A2A0D0EB-E5B9-3344-87C0-68B6B72699C7 \
  --boot-catalog-hide \
  -R -J \
  iso-root/
```

This creates a hybrid MBR/GPT ISO that boots from both USB and optical media without needing `isohybrid`.

### Step 7: Write to USB

```bash
sudo dd if=~/isos/Rocky-10.1-x86_64-custom.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your actual USB device (check with `lsblk`).

### Step 8: Boot and install

1. Boot from the USB — "Install Rocky Linux 10.1 (Project TV - Kickstart)" is the default menu entry
2. **SSH is enabled during installation** (`inst.sshd` is on the kernel cmdline). Once the installer boots and obtains an IP via DHCP, you can SSH in as root (no password) to inspect Anaconda logs:

   ```bash
   ssh root@<installer-ip>
   cat /tmp/packaging.log    # Repository and package errors
   cat /tmp/anaconda.log     # General installer log
   cat /tmp/storage.log      # Disk/partitioning issues
   ```

3. Anaconda opens in graphical mode. Most settings are pre-configured by the kickstart, but you may need to confirm the following spokes before clicking **"Begin Installation"**:

   **Installation Source** (if marked with a warning):
   - Click **"Installation Source"**
   - Select **"Auto-detected installation media"** (the USB drive)
   - Click **"Done"** — Anaconda will verify the media and resolve the warning

   **Software Selection** (if marked with a warning):
   - Click **"Software Selection"**
   - Select **"Minimal Install"** (the kickstart `%packages` section handles the rest)
   - Click **"Done"**

   **Installation Destination** (if marked with a warning):
   - Click **"Installation Destination"**
   - Select your target disk (e.g. `nvme0n1`) — ensure no other disks are ticked
   - Select **"Automatic"** partitioning
   - If existing partitions are found, click **"Reclaim space"** and then **"Delete all"** to wipe them
   - Click **"Done"**

   Once all warnings are cleared, click **"Begin Installation"**.
4. The kickstart installs the base system from the DVD (~5 minutes)
5. The system reboots, then the first-boot service installs KDE Plasma + dkms + flatpak from EPEL (~5-10 minutes depending on internet speed)
6. The system reboots again into SDDM — log in and run `sudo ./project_tv_rocky_linux/install.sh`

### Testing the ISO in a VM

```bash
virt-install \
  --connect qemu:///system \
  --name rocky10-ks-test \
  --ram 8192 --vcpus 4 \
  --os-variant rocky10 \
  --location ~/isos/Rocky-10.1-x86_64-custom.iso \
  --disk size=80 \
  --network network=default \
  --initrd-inject=test/kickstart/ks-custom-iso.cfg \
  --extra-args="inst.ks=file:/ks-custom-iso.cfg console=ttyS0,115200n8" \
  --noautoconsole --wait=-1
```

**Note:** When testing with `virt-install --location`, use `--initrd-inject` to inject the kickstart into the initrd. This is the most reliable method for VM testing.

## Supported Rocky Linux versions

| Version | Status | Notes |
|---------|--------|-------|
| Rocky Linux 10 | Primary target | Fully tested and supported |
| Rocky Linux 9 | Tested | See PLATFORM_NOTES.md for differences |
| Rocky Linux 8 | Tested | See PLATFORM_NOTES.md for differences |

## Troubleshooting

### Common issues

**ZFS module fails to load**
- Ensure `kernel-devel` matches your running kernel: `dnf install kernel-devel-$(uname -r)`
- Rebuild DKMS modules: `dkms autoinstall`

**Kubernetes pods stuck in Pending**
- Check PV/PVC binding: `kubectl get pv,pvc -n project-tv`
- Verify ZFS datasets are mounted: `zfs list`

**Mirakurun cannot find TV tuner**
- Verify px4_drv is loaded: `lsmod | grep px4_drv`
- Check device nodes: `ls -la /dev/px4video*`
- Verify USB device: `lsusb | grep -i plex`
- Check pcscd for SmartCard reader: `systemctl status pcscd`

**Elasticsearch OOM**
- Check resource limits: `kubectl describe pod -n project-tv -l app=elasticsearch`
- Reduce ES heap if needed in the deployment manifest

### Getting help

If you encounter issues not covered here:
1. Check the installer log: `grep ERROR logs/install-*.log`
2. Open an issue on this repository with the relevant log output

## Licence

Installer scripts and Kubernetes manifests in this repository are provided under the [MIT Licence](LICENSE) unless otherwise noted. Third-party software (px4_drv, EPGStation, Mirakurun, Jellyfin, Tube Archivist, Navidrome) retains its original licence — see each upstream repository for details.

The px4_drv driver is licensed under [GPL-2.0](https://github.com/tsukumijima/px4_drv/blob/develop/LICENSE). The RPM packaging in this repository respects and preserves this licence.
