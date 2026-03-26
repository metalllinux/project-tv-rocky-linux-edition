%global dkms_name px4_drv
%global dkms_version 0.5.5

Name:           %{dkms_name}-dkms
Version:        %{dkms_version}
Release:        1%{?dist}
Summary:        DKMS kernel module for PLEX/e-Better TV tuner devices (px4_drv)
License:        GPL-2.0-only
URL:            https://github.com/tsukumijima/px4_drv
Source0:        %{dkms_name}-%{dkms_version}.tar.gz

BuildArch:      noarch
Requires:       dkms >= 3.0
Requires:       gcc
Requires:       make
Requires:       kernel-devel

Provides:       %{dkms_name}-kmod = %{version}-%{release}

%description
Linux kernel driver for PLEX and e-Better TV tuner devices using the IT930x
chipset. Supported devices include: PX-W3U4, PX-Q3U4, PX-W3PE4, PX-Q3PE4,
PX-W3PE5, PX-Q3PE5, PX-MLT5PE, PX-MLT8PE, PX-M1UR, PX-S1UR, DTV02-1T1S-U,
DTV02A-1T1S-U, DTV02A-4TS-P, DTV03A-1TU.

Uses DKMS to automatically rebuild the kernel module when a new kernel is
installed. This ensures the driver remains functional across kernel updates.

Originally developed by nns779 (https://github.com/nns779/px4_drv).
Maintained by tsukumijima (https://github.com/tsukumijima/px4_drv).
Rocky Linux RPM packaging by the Metalllinux project.

%prep
%setup -q -n %{dkms_name}-%{dkms_version}

%install
# Install DKMS source tree
install -d %{buildroot}%{_usrsrc}/%{dkms_name}-%{dkms_version}
cp -a driver/ %{buildroot}%{_usrsrc}/%{dkms_name}-%{dkms_version}/
cp -a include/ %{buildroot}%{_usrsrc}/%{dkms_name}-%{dkms_version}/
cp -a dkms.conf %{buildroot}%{_usrsrc}/%{dkms_name}-%{dkms_version}/

# Install DKMS helper scripts if they exist
if [ -d dkms/ ]; then
    cp -a dkms/ %{buildroot}%{_usrsrc}/%{dkms_name}-%{dkms_version}/
fi

# Install firmware
install -D -m 644 etc/it930x-firmware.bin %{buildroot}/lib/firmware/it930x-firmware.bin

# Install udev rules
install -D -m 644 etc/99-px4video.rules %{buildroot}%{_udevrulesdir}/99-px4video.rules

%post
# Register with DKMS
dkms add -m %{dkms_name} -v %{dkms_version} -q --rpm_safe_upgrade 2>/dev/null || :

# Build the module
dkms build -m %{dkms_name} -v %{dkms_version} -q --force 2>/dev/null || :

# Install the module
dkms install -m %{dkms_name} -v %{dkms_version} -q --force 2>/dev/null || :

# Reload udev rules
udevadm control --reload-rules 2>/dev/null || :
udevadm trigger 2>/dev/null || :

%preun
# Remove from DKMS on package removal
dkms remove -m %{dkms_name} -v %{dkms_version} -q --all --rpm_safe_upgrade 2>/dev/null || :

%files
%license LICENSE
%{_usrsrc}/%{dkms_name}-%{dkms_version}/
/lib/firmware/it930x-firmware.bin
%{_udevrulesdir}/99-px4video.rules

%changelog
* Wed Mar 26 2026 Howard Van Der Wal <metalllinux@users.noreply.github.com> - 0.5.5-1
- Initial RPM package for Rocky Linux
- Based on upstream px4_drv v0.5.5 by tsukumijima
- DKMS-based build for kernel module compatibility across Rocky Linux 8/9/10
