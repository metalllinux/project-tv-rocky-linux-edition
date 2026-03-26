# Project TV - Rocky Edition: Test Plan

## Overview

This document defines the complete test plan for Project TV - Rocky Edition.
Testing is split into two tracks: automated VM testing (Track 1) and manual
hardware testing (Track 2).

## Test Environments

| Environment | OS | Purpose |
|-------------|-------------|---------|
| rocky10-test VM | Rocky Linux 10.1 | Primary automated testing |
| rocky9-test VM | Rocky Linux 9.7 | Cross-version validation |
| rocky8-test VM | Rocky Linux 8.10 | Cross-version validation |
| vector (physical) | Rocky Linux 10.1 | Manual hardware testing (PX-W3PE5 tuner) |

## Track 1: Automated VM Testing

### Execution plan

Each platform is tested 3 times from a clean snapshot:

```
For each platform in [Rocky 10, Rocky 9, Rocky 8]:
    For run_number in [1, 2, 3]:
        1. Revert VM to base-install snapshot
        2. Copy RPM and test scripts via SCP
        3. Run test suites A, B, C-ZF
        4. Collect results
        5. Shutdown VM
```

Run with: `./test/run_tests.sh <vm-name> <run-number>`

### Category A: RPM Installation (12 tests)

| ID | Test | Method | Pass |
|----|------|--------|------|
| A-01 | RPM installs | `dnf install ./px4_drv-dkms*.rpm` | Exit 0 |
| A-02 | DKMS registered | `dkms status px4_drv` | Shows "installed" |
| A-03 | Module built | `ls /lib/modules/*/updates/dkms/px4_drv.ko*` | File exists |
| A-04 | Module loads | `modprobe px4_drv` | Exit 0 |
| A-05 | Module info | `modinfo px4_drv` | Shows GPL |
| A-06 | Firmware | `ls /lib/firmware/it930x-firmware.bin` | File exists |
| A-07 | Udev rules | `ls /etc/udev/rules.d/99-px4video.rules` | File exists |
| A-08 | RPM verify | `rpm -V px4_drv-dkms` | No output |
| A-09 | Clean removal | `dnf remove px4_drv-dkms` | Exit 0 |
| A-10 | DKMS gone | `dkms status px4_drv` | Empty |
| A-11 | Reinstall | Install again | Exit 0 |
| A-12 | Load after reinstall | `modprobe px4_drv` | Exit 0 |

### Category B: Installer Validation (12 tests)

| ID | Test | Pass |
|----|------|------|
| B-01 | install.sh exists and is executable | -x check |
| B-02 | All 19 module files present | File check |
| B-03 | All library files present | File check |
| B-04 | Config defaults present | File check |
| B-05 | Manifest directory structure correct | Dir check |
| B-06 | README.md exists | File check |
| B-07 | LICENSE exists | File check |
| B-08 | RPM spec file exists | File check |
| B-09 | No hardcoded passwords in manifests | Grep check |
| B-10 | All shell scripts valid syntax | `bash -n` |
| B-11 | All YAML manifests valid | Python yaml.safe_load |
| B-12 | AI Usage policy in README | Grep check |

### Category C: Application API Health

| ID | App | Endpoint | Pass |
|----|-----|----------|------|
| C-JF-01 | Jellyfin | GET :30096/health | "Healthy" |
| C-JF-02 | Jellyfin | GET :30096/System/Info/Public | JSON with ServerName |
| C-EP-01 | EPGStation | GET :30888/api/version | JSON with version |
| C-MK-01 | Mirakurun | GET :30772/api/status | JSON response |
| C-TA-01 | Tube Archivist | GET :30800/health | Response |
| C-NV-01 | Navidrome | GET :30453/api/ping | Response |

### Category C-ZF: ZFS (6 tests)

| ID | Test | Method | Pass |
|----|------|--------|------|
| C-ZF-01 | Module loaded | `lsmod \| grep zfs` | Present |
| C-ZF-02 | Pool creation | `zpool create` with file-backed device | Exit 0 |
| C-ZF-03 | Dataset creation | `zfs create` | Exit 0 |
| C-ZF-04 | Snapshot creation | `zfs snapshot` | Exit 0 |
| C-ZF-05 | Snapshot rollback | `zfs rollback` + data verify | Data restored |
| C-ZF-06 | Pool destroy | `zpool destroy` | Exit 0 |

### Category D: Kubernetes Health (6 tests)

| ID | Test | Pass |
|----|------|------|
| D-01 | Node Ready | `kubectl get nodes` shows Ready |
| D-02 | Namespace exists | `kubectl get ns project-tv` |
| D-03 | All pods Running | No pods in non-Running state |
| D-04 | No excessive restarts | All pods < 5 restarts |
| D-05 | CronJob exists | jellyfin-library-refresh present |
| D-06 | Services have endpoints | No services with `<none>` endpoints |

### Category E: Pod Log Health (8 tests)

| ID | Pod | Pass |
|----|-----|------|
| E-01 | mirakurun | No FATAL/panic/OOM in last 100 lines |
| E-02 | mariadb | No FATAL/panic/OOM |
| E-03 | epgstation | No FATAL/panic/OOM |
| E-04 | jellyfin | No FATAL/panic/OOM |
| E-05 | tubearchivist | No FATAL/panic/OOM |
| E-06 | elasticsearch | No FATAL/panic/OOM |
| E-07 | redis | No FATAL/panic/OOM |
| E-08 | navidrome | No FATAL/panic/OOM |

## Track 2: Manual Hardware Testing (Howard's Rocky 10 box)

| ID | Test | Method | Pass |
|----|------|--------|------|
| HW-01 | px4_drv module + devices | `ls /dev/px4video*` | 4 devices |
| HW-02 | Mirakurun detects tuner | API /api/tuners shows PX-W3PE5 |
| HW-03 | Channel scan | `PUT :40772/api/config/channels/scan` | Channels found |
| HW-04 | EPG populated | EPGStation shows programme guide |
| HW-05 | Test recording | Record via EPGStation, file on ZFS | File exists |
| HW-06 | Jellyfin indexes media | All libraries visible in Jellyfin |
| HW-07 | Library refresh CronJob | CronJob runs, Jellyfin scans | HTTP 204 |
| HW-08 | Tube Archivist download | Download test video | File on ZFS |
| HW-09 | Navidrome scans music | Music library populated | Tracks listed |
| HW-10 | Full installer E2E | Run install.sh start to finish | All modules pass |
| HW-11 | ZFS datasets correct | `zfs list` matches user input | Names match |
| HW-12 | Sanoid snapshots | `zfs list -t snapshot` | Snapshots present |

## Results Recording

Test results are saved to `~/test-results/<vm-name>/run<N>/`:
- `rpm-tests.tap` — RPM test results
- `installer-tests.tap` — Installer validation results
- `zfs-tests.tap` — ZFS test results
- `os-release.txt` — OS version info
- `kernel.txt` — Kernel version
- `packages.txt` — Installed packages list
