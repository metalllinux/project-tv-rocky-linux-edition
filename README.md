[English](README.md) | [日本語](docs/ja/README.md)

# Project TV - Rocky Linux Edition

Kubernetes-based media server for Rocky Linux 10, featuring EPGStation, Mirakurun, Jellyfin, Tube Archivist, and Navidrome.

This project is the successor to [Project TV v2 (Ubuntu)](https://metalinux.dev/linux-journey/courses/project-tv-v2/), rewritten from the ground up for Rocky Linux with Kubernetes (kubeadm) replacing Docker Compose.

## Attribution

This project includes manifests from the following open source software - please show them your support:

- **[Rocky Linux](https://rockylinux.org/)** — The foundation that makes this project possible. A community enterprise operating system designed to be 100% bug-for-bug compatible with Red Hat Enterprise Linux.
- **[px4_drv](https://github.com/tsukumijima/px4_drv)** by [tsukumijima](https://github.com/tsukumijima) (originally by [nns779](https://github.com/nns779/px4_drv)) — Linux driver for PLEX and e-Better TV tuner devices. Licensed under **GPL-2.0**. See the [px4_drv LICENSE](https://github.com/tsukumijima/px4_drv/blob/develop/LICENSE) for full text.
- **[EPGStation](https://github.com/l3tnun/EPGStation)** by [l3tnun](https://github.com/l3tnun) — Digital broadcast recording system
- **[Mirakurun](https://github.com/Chinachu/Mirakurun)** by [Chinachu](https://github.com/Chinachu) — Digital broadcast tuner server
- **[Jellyfin](https://jellyfin.org/)** — Free software media system
- **[Tube Archivist](https://github.com/tubearchivist/tubearchivist)** by [bbilly1](https://github.com/bbilly1) — YouTube archive manager
- **[Navidrome](https://github.com/navidrome/navidrome)** — Modern music server and streamer

All third-party software retains its original licence. This project's installer scripts and Kubernetes manifests are provided under the MIT licence unless otherwise noted. Refer to individual upstream repositories for their respective licence terms.

## AI Usage

This repository follows the [Fedora AI-Assisted Contribution Policy](https://docs.fedoraproject.org/en-US/council/policy/ai-contribution-policy/). Claude's Opus 4.6 model was used to create everything, with human testing for verification and feedback.

## Overview

Project TV - Rocky Linux Edition transforms a Rocky Linux 10 system into a fully featured media server running on Kubernetes. The interactive installer walks you through every step, from ZFS storage setup to application deployment.

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

This project targets the **x86_64** architecture only.

- **CPU**: Any x86_64 processor supported by Rocky Linux 10. Intel processors are recommended for their integrated **Intel Quick Sync Video (QSV)** hardware-accelerated encoding, which significantly improves Jellyfin transcoding performance and live TV streaming.
  - **Intel (recommended)**: 12th Gen Alder Lake or newer — Core i3, i5, i7, i9, Pentium Gold, or Celeron with Intel UHD Graphics
  - **AMD**: Ryzen 3000 series or newer — fully supported but uses software encoding only (no Intel QSV)
- **RAM**: 16 GB minimum (Elasticsearch alone requires 1 GB+)
- **Storage**: 256 GB NVMe minimum for the OS and application data. Additional disks (HDD or SSD) are recommended for a ZFS media pool.
- **Network**: Gigabit Ethernet

### TV tuner hardware (optional — Japanese broadcasting only)

The live TV recording and streaming functionality is designed for **Japanese digital broadcasting (ISDB-T / ISDB-S)**. If you are not in Japan or do not need TV functionality, you can skip modules 06 (px4_drv) and 07 (EPGStation + Mirakurun) during installation — the installer prompts before each module.

The following hardware is required for TV functionality:

| Component | Model | ID | Purpose |
|-----------|-------|----|---------|
| TV Tuner | PLEX PX-W3PE5 | USB `0511:073f` | 4-channel digital TV tuner — 2x terrestrial (ISDB-T) + 2x satellite (ISDB-S BS/CS) |
| PCIe USB Controller | MosChip MCS9990 | PCIe | 8-port PCIe to USB 2.0 controller — required to connect the PX-W3PE5 |
| SmartCard Reader | SCM SCR331-LC1 / SCR3310 | USB `04e6:5116` | Reads the B-CAS card for Japanese broadcast decryption |
| B-CAS Card | — | — | Required to decrypt Japanese terrestrial and satellite broadcasts (often included with the TV tuner or purchased separately) |

Other px4_drv-supported tuners (PX-Q3PE5, PX-Q3U4, PX-MLT5PE, etc.) should also work — adjust the tuner configuration in `manifests/epgstation/mirakurun-configmap.yaml` as needed.

### Software requirements

- Rocky Linux 10 minimal ISO
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

The installer presents an interactive main menu:

```
Project TV - Rocky Linux Edition Installer
=====================================

  [1]  Full Installation (run all modules in order)
  [2]  Run a specific module
  [3]  View installation status
  [4]  View log file
  [5]  K8s health summary
  [q]  Quit
```

### Main menu options

**[1] Full Installation** — Runs all modules in the execution order shown below. Before each module, you are asked whether to run it or skip it. If a module has already been completed, you are asked whether to re-run it. If a module fails, you can choose to continue with the next module or stop.

**[2] Run a specific module** — Displays a numbered list of all 21 modules (00–20) sorted numerically. Enter a module number to run it individually. Single digits are accepted (typing `5` is the same as `05`). Modules that have already been completed are marked `(done)`.

**[3] View installation status** — Shows a table of all modules with their current status: `[OK]` completed, `[!!]` failed, `[--]` skipped, or `[  ]` pending.

**[4] View log file** — Displays the last 30 timestamped log entries from the current session and reports the total number of errors.

**[5] K8s health summary** — Shows the current state of the Kubernetes cluster: node status, pod health, and service endpoints. Only available after Kubernetes is installed (module 03).

**[q] Quit** — Exits the installer. The log file path is displayed on exit.

## Installer logging

All installer output is logged to `logs/install-YYYYMMDD-HHMMSS.log`. If you encounter any issues:

1. Check the log file for `[ERROR]` lines: `grep ERROR logs/install-*.log`
2. The log includes timestamps, commands run, and exit codes
3. Share the relevant log section when reporting issues

## Module details

Modules are executed in the following order during a full installation. Module numbers are fixed (matching their filenames) but the execution order groups related tasks together:

**System setup:** 00 → 01 → 02 → 03 → 04 → 05 → 06

**Desktop and system configuration:** 17 → 16 → 15 → 18 → 14 → 12

**Kubernetes application deployments:** 07 → 08 → 09 → 10 → 11

**Extras and monitoring:** 13 → 19 → 20

---

### Module 00 — Preflight checks

Verifies the system meets all requirements before installation begins:
- Confirms Rocky Linux 10 (also supports 9 and 8 with warnings)
- Checks CPU architecture (x86_64 required), RAM (16 GB recommended), and CPU cores (4+ recommended)
- Tests internet connectivity to `dl.rockylinux.org`
- Detects PX TV tuner hardware and SmartCard reader via USB
- Lists available block devices for ZFS pool creation
- **Installs missing prerequisites** — if packages like `kernel-devel`, `kernel-modules-extra`, `git`, `gcc`, `podman`, or `epel-release` are missing, offers to install them automatically

This module allows the installer to work on **any Rocky Linux 10 machine**, not just one installed from the custom ISO.

### Module 01 — Timezone setup

- Displays the current timezone
- Prompts to confirm or change it (default: `Asia/Tokyo`)
- Validates the timezone exists in `/usr/share/zoneinfo/`
- Enables NTP synchronisation

### Module 02 — ZFS storage

Creates a ZFS pool and datasets for media storage. If ZFS is already installed and a pool exists, the module detects it and skips to completion.

**On a fresh system:**
1. Installs ZFS via DKMS from the OpenZFS repository
2. Shows available block devices and disk IDs in a numbered list
3. Prompts for pool name (default: `mediapool`), pool type (mirror/single/raidz1/raidz2), and disk selection by number
4. Detects existing filesystems on the selected disks and offers to force-create if needed
5. Prompts for the number of datasets and their names and mount points
6. Creates the pool with `ashift=12` for 4K sector alignment
7. Saves configuration to `config/datasets.conf`

### Module 03 — Kubernetes (kubeadm)

Installs a full upstream Kubernetes cluster. If the cluster is already running and the node is Ready, the module shows the current state and exits.

**On a fresh system:**
1. Configures SELinux (prompts for permissive or enforcing)
2. Loads all required kernel modules: `overlay`, `br_netfilter`, `nf_conntrack`, `xt_conntrack`, `xt_comment`, `xt_mark`, `ip_tables`, `ip6_tables`, `nf_nat`
3. Sets kernel sysctl parameters for Kubernetes networking
4. Installs containerd from the Docker CE repository
5. Installs kubeadm, kubelet, and kubectl from the Kubernetes repository
6. Disables swap (required by kubeadm)
7. Runs `kubeadm init` with Flannel pod network CIDR
8. Installs Flannel CNI and waits for all system pods (Flannel, kube-proxy, CoreDNS) to be running
9. Removes the control-plane taint for single-node operation

### Module 04 — K8s namespace

Creates the `project-tv` namespace used by all application deployments.

### Module 05 — K8s storage (PV/PVC)

Configures storage paths for all applications and generates Kubernetes PersistentVolume/PersistentVolumeClaim manifests.

**For each application, you choose where to store its data:**
- If ZFS datasets exist, they are shown as a numbered list — enter a number to select one
- You can also type any custom path on the NVMe or another filesystem
- If no ZFS pool exists, you are prompted to create directories on the NVMe

**Applications configured:**
| Application | What is stored | Default path |
|-------------|---------------|--------------|
| EPGStation | TV recordings | `/home/<user>/tv` |
| Jellyfin | Media libraries (supports multiple paths) | `/home/<user>/media` |
| Navidrome | Music collection | `/home/<user>/music` |
| Tube Archivist | YouTube downloads | `/home/<user>/youtube` |
| MakeMKV | DVD/Blu-ray rips | `/home/<user>/rips` |
| Prometheus | Metrics database | `/var/lib/project-tv/prometheus/data` |
| Grafana | Dashboard data | `/var/lib/project-tv/grafana/data` |

Storage paths are saved to `config/storage-paths.conf` and read by all subsequent modules.

### Module 06 — px4_drv TV tuner driver

Installs the px4_drv DKMS kernel module for PLEX TV tuner devices (PX-W3PE5, PX-Q3PE5, etc.):
1. Installs build prerequisites and SmartCard reader support (pcsc-lite)
2. Clones the px4_drv source from GitHub
3. Patches `driver_module.c` for Rocky Linux 10 kernel 6.12 compatibility
4. Builds and installs via DKMS (handles existing DKMS entries on re-run)
5. Installs firmware and udev rules
6. Loads the module and verifies device nodes (`/dev/px4video0-3`)

### Module 17 — Firewall rules

Configures firewalld with ports for all services. If firewalld is not running, offers to enable it first.

**Ports opened:** Jellyfin (30096), EPGStation (30888/30889), Mirakurun (30772), Tube Archivist (30800), Navidrome (30453), Kubernetes API (6443), kubelet (10250).

### Module 16 — SDDM autologin

Configures SDDM (KDE display manager) to automatically log in the installer user on boot.

### Module 15 — Browser installation

Installs web browsers via Flatpak. Presents a multi-select menu of:
- Google Chrome, Brave, Waterfox, Firefox, Vivaldi, Chromium, Microsoft Edge

After installation, if only one browser was installed it is automatically set as the default. If multiple were installed, you pick from a numbered list.

### Module 18 — Desktop applications

Optional applications installed individually (each prompted with Y/n):
- **SeaDrive** — Seafile virtual drive client (installed as AppImage to `~/Applications/`)
- **MakeMKV** — DVD/Blu-ray ripper (via Flatpak)
- **Jellyfin Media Player** — Desktop media client (via Flatpak)

### Module 14 — KDE customisation

Configures the KDE Plasma desktop:
- Disables screen edges (no hot corners)
- Disables sleep, suspend, and screen dimming
- Offers to install **ibus-anthy** for Japanese input

### Module 12 — Sanoid snapshots

Installs Sanoid (ZFS snapshot manager) from GitHub and configures automated snapshots:
- Prompts for retention: daily (default: 60), hourly (default: 24), weekly (default: 4), monthly (default: 12), yearly (default: 0)
- If hourly snapshots are enabled, prompts for run frequency: every hour (default), 30 minutes, 15 minutes, or custom
- Creates systemd timer and service units

### Module 07 — EPGStation + Mirakurun

Deploys the Japanese TV recording stack on Kubernetes:
1. **Builds custom container images** (if not already present):
   - Mirakurun with recpt1 (for px4_drv TV tuner support)
   - EPGStation with ffmpeg (for live TV streaming in the browser)
2. Prompts for MariaDB root and EPGStation database passwords
3. Deploys MariaDB, Mirakurun, and EPGStation with their ConfigMaps, Secrets, and Services
4. **Scans for TV channels** — offers terrestrial (GR), BS satellite, and CS satellite scans
5. Restarts Mirakurun to load scanned channels into services
6. Restarts EPGStation to pick up the channel data

**After deployment:**
- Mirakurun web UI: `http://<host-ip>:30772`
- EPGStation web UI: `http://<host-ip>:30888`
- Live TV: Select a channel in EPGStation and choose HLS 720p or 480p format

**Live streaming formats available:**
| Format | Description |
|--------|-------------|
| M2TS | Raw MPEG-TS passthrough (requires external player) |
| M2TS-LL | Low-latency raw MPEG-TS |
| HLS 720p / 480p | Browser-native streaming (recommended) |
| H.264 MP4 720p / 480p | Fragmented MP4 for browsers |
| WebM 720p / 480p | VP9 video for browsers |

**Re-scanning channels** at any time:
```bash
curl -X PUT "http://<host-ip>:30772/api/config/channels/scan?type=GR&setDisabledOnAdd=false"
curl -X PUT "http://<host-ip>:30772/api/config/channels/scan?type=BS&setDisabledOnAdd=false"
curl -X PUT "http://<host-ip>:30772/api/config/channels/scan?type=CS&setDisabledOnAdd=false"
```

### Module 08 — Jellyfin

Deploys Jellyfin media server on Kubernetes:
- Dynamically generates volume mounts from the media paths configured in module 05
- Each media directory is mounted read-only at `/data/<directory-name>` inside the container
- Detects existing deployments and skips on re-run

**After deployment:** `http://<host-ip>:30096`

### Module 09 — Tube Archivist

Deploys Tube Archivist (YouTube archive manager) with Redis and Elasticsearch:
- Prompts for Tube Archivist username/password and Elasticsearch password
- Uses the download path configured in module 05
- Detects existing deployments and skips on re-run

**After deployment:** `http://<host-ip>:30800`

### Module 10 — Navidrome

Deploys Navidrome music server on Kubernetes:
- Uses the music path configured in module 05
- Detects existing deployments and skips on re-run

**After deployment:** `http://<host-ip>:30453`

### Module 11 — Jellyfin library refresh

Creates a Kubernetes CronJob that periodically calls the Jellyfin REST API to refresh media libraries:
1. Displays the Jellyfin URL and guides you through initial setup (create user, add media libraries)
2. Walks you through generating an API key: Settings > Administration > Dashboard > API Keys > New API Key
3. Validates the cron schedule format (displays a visual diagram of the five fields)
4. Deploys the CronJob (default: runs every hour)

### Module 13 — Rsync media sync

Configures rsync-based backup of ZFS datasets to a remote server. Prompts for backup server, SSH user, and remote path.

### Module 19 — Prometheus monitoring

Deploys Prometheus on Kubernetes for metrics collection:
- Sets up RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
- Uses the data path configured in module 05
- Sets correct ownership (UID 65534 / nobody) on the data directory

**After deployment:** `http://<host-ip>:30090`

### Module 20 — Grafana dashboards

Deploys Grafana on Kubernetes with Prometheus pre-configured as a data source:
- Prompts for the Grafana admin password
- Uses the data path configured in module 05
- Sets correct ownership (UID 472 / grafana) on the data directory

**After deployment:** `http://<host-ip>:30300`

## Building the custom Rocky Linux 10 ISO (optional)

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
