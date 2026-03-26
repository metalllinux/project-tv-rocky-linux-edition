# Platform Notes: Rocky Linux 8, 9, and 10

## Version Comparison

| Area | Rocky 8 (4.18.x) | Rocky 9 (5.14.x) | Rocky 10 (6.12.x) |
|------|-------------------|-------------------|---------------------|
| Kernel | 4.18.0-553+ | 5.14.0-611+ | 6.12.0-124+ |
| GCC | 8.x | 11.x | 14.x |
| Python | 3.6 | 3.9 | 3.12 |
| Container runtime | containerd (manual) | containerd | containerd |
| Default containers | Podman 3.x | Podman 4.x | Podman 5.x |
| DKMS source | EPEL 8 | EPEL 9 | EPEL 10 |
| ZFS repo | zfsonlinux EL8 | zfsonlinux EL9 | zfsonlinux EL10 |
| kubeadm | 1.28+ (last for EL8) | 1.32+ | 1.32+ |
| firewalld backend | iptables | nftables | nftables |
| systemd | 239 | 252 | 257 |
| SELinux | Enforcing | Enforcing | Enforcing |
| KDE Plasma | 5.x (limited) | 5.x | 6.x |

## Known Differences

### Rocky Linux 8
- **End of Active Support**: May 2024 (Maintenance until May 2029)
- Python 3.6 may cause issues with newer pip packages
- Docker CE repo works directly (no releasever workaround needed)
- kubeadm 1.28 is the last version supporting EL8
- EPEL 8 packages may stop receiving updates
- ZFS on Linux EL8 packages are stable but may not receive new features

### Rocky Linux 9
- Stable target, most widely tested
- Docker CE repo works directly
- Full kubeadm support for latest versions
- ZFS on Linux EL9 packages well maintained
- nftables backend for firewalld (different rule syntax than EL8)

### Rocky Linux 10
- Newest release, kernel 6.12 may have API changes
- Docker CE repo requires releasever workaround: `sed -i 's|$releasever|9|g'`
- ZFS on Linux EL10 packages may lag behind initial release
- KDE Plasma 6 (significant UI changes from Plasma 5)
- px4_drv v0.5.5 predates Rocky 10 GA — compilation against 6.12 needs testing

## Installer Adjustments by Version

The installer `modules/02-zfs.sh` and `modules/03-kubeadm.sh` handle version
differences automatically by checking `/etc/os-release` VERSION_ID and adjusting
repository URLs and package names accordingly.
