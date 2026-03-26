# Project TV - Rocky Edition

## Project overview

Kubernetes-based media server installer for Rocky Linux 10. Successor to Project TV v2 (Ubuntu/Docker).

- **Repo**: github.com/metalllinux/project-tv-rocky-edition (PRIVATE)
- **Local path**: ~/Documents/projects/project_tv_rocky_linux
- **Documentation site**: metalinux.dev/linux-journey/courses/project-tv-v3/
- **Site repo**: ~/Documents/projects/github_pages (Jekyll, minimal-mistakes theme)

## Architecture

- **OS**: Rocky Linux 10 (primary), also tested on Rocky 9 and 8
- **Kubernetes**: kubeadm (full upstream) with containerd and Flannel CNI — NOT k3s
- **Storage**: ZFS with dynamically created datasets (installer prompts user for names/mounts)
- **Namespace**: `project-tv`

### Applications (all on Kubernetes)

| App | Port | NodePort | Image |
|-----|------|----------|-------|
| Mirakurun | 40772 | 30772 | chinachu/mirakurun |
| EPGStation | 8888 | 30888 | l3tnun/epgstation |
| MariaDB | 3306 | ClusterIP | mariadb:10.5 |
| Jellyfin | 8096 | 30096 | lscr.io/linuxserver/jellyfin |
| Tube Archivist | 8000 | 30800 | bbilly1/tubearchivist |
| Elasticsearch | 9200 | ClusterIP | bbilly1/tubearchivist-es |
| Redis | 6379 | ClusterIP | redis/redis-stack-server |
| Navidrome | 4533 | 30453 | deluan/navidrome |

### Hardware (deployment target: `vector`)

- Intel 12th Gen Alder Lake-S, UHD 730
- PX-W3PE5 TV tuner: USB `0511:073f` (via MosChip MCS9990 PCIe USB card)
- SCM SCR331-LC1 SmartCard reader: USB `04e6:5116` (B-CAS card)
- px4_drv kernel module (DKMS RPM, v0.5.5) — forked at metalllinux/px4_drv

## Project structure

```
install.sh              # Main entry point (interactive menu, run as root)
config/defaults.conf    # Default values (images, ports, timezone)
config/datasets.conf    # Generated at install time (ZFS dataset names:mount paths)
lib/                    # Shared bash functions (logging, prompts, k8s-helpers, validators)
modules/00-18*.sh       # Installer modules (each has a run() function)
manifests/              # Kubernetes YAML (epgstation/, jellyfin/, tube-archivist/, navidrome/, cronjobs/, storage/)
drivers/px4_drv/        # RPM spec and build script
test/                   # Kickstart files, TAP test scripts, test orchestrator
logs/                   # Created at runtime (gitignored)
```

## Key conventions

- British English spelling in all documentation and user-facing text
- Every installer module is in `modules/` and exports a `run()` function
- Modules are sourced by `install.sh` — they have access to all lib/ functions and config variables
- Kubernetes manifests use `hostPath` volumes pointing to ZFS mount points
- Secrets use `CHANGE_ME_*` placeholders — the installer module replaces these with user input via `sed`
- Jellyfin deployment is generated dynamically by `modules/08-jellyfin.sh` from `config/datasets.conf`
- The `config/datasets.conf` format is: `dataset_name:mount_point` (one per line)
- Module 05 (storage) reads `datasets.conf` and generates PV/PVC YAML at install time

## Testing

- `test/scripts/test_installer.sh` — validates project structure (TAP format)
- `test/scripts/test_rpm_install.sh` — RPM install/remove/reinstall cycle
- `test/scripts/test_k8s_apps.sh` — K8s pod health + API endpoint checks + log analysis
- `test/scripts/test_zfs.sh` — ZFS pool/dataset/snapshot operations
- `test/run_tests.sh <vm-name> <run-number>` — full automated test run on a VM
- All instructions in README must be tested at least 3x on Rocky 10 VMs

## Common tasks

- **Add a new installer module**: Create `modules/NN-name.sh` with a `run()` function, add entry to `MODULE_DESC` in `install.sh`
- **Add a new K8s app**: Create manifests in `manifests/<app>/`, create deployer module in `modules/`
- **Update px4_drv version**: Edit version in `drivers/px4_drv/px4_drv-dkms.spec`, update changelog
- **Add documentation page**: Create `.md` file in `~/Documents/projects/github_pages/_linux_journey/courses/project-tv-v3/` with frontmatter (title, category: project-tv-v3, tags)

## Important notes

- The AI Usage policy in README.md must exactly match metalllinux.github.io
- px4_drv is GPL-2.0 — licence and attribution must be preserved
- GitHub username is `metalllinux` (triple L), personal brand is `metalinux` (single L)
- Never commit real passwords — secrets use `CHANGE_ME_*` or `PLACEHOLDER_*` markers
- SELinux: installer prompts user for permissive vs enforcing (permissive recommended for device passthrough)
