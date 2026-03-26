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
- SeaDrive desktop client (Seafile virtual drive for KDE Dolphin)

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
