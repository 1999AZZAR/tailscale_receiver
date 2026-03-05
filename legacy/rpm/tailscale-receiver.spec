Name:           tailscale-receiver
Version:        2.3.0
Release:        1%{?dist}
Summary:        Automated Tailscale file receiver service

License:        MIT
URL:            https://github.com/1999AZZAR/tailscale_receiver
Source0:        %{name}-%{version}.tar.gz

Requires:       tailscale systemd coreutils findutils nc socat procps-ng util-linux
Requires(post): systemd
Requires(preun): systemd
Recommends:     libnotify kdialog zenity newt dolphin nautilus
Suggests:       clamav apparmor

BuildArch:      noarch

%description
Tailscale Receiver automatically accepts and processes files sent via
Tailscale's Taildrop feature. It runs as a systemd service and provides
desktop notifications when files are received.

Features include:
- Automatic file reception with ownership correction
- Directory support with recursive permissions
- Configurable polling intervals and health monitoring
- File integrity verification with checksums
- GNOME/KDE desktop integration
- Comprehensive logging and health monitoring
- Enterprise-grade configuration management

%prep
%setup -q

%build
# No build step required for shell scripts

%install
# Create directories
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_unitdir}
mkdir -p %{buildroot}%{_sysconfdir}/default
mkdir -p %{buildroot}%{_datadir}/kio/servicemenus
mkdir -p %{buildroot}%{_datadir}/kservices5/ServiceMenus
mkdir -p %{buildroot}%{_datadir}/doc/%{name}
mkdir -p %{buildroot}%{_skeldir}/.local/share/nautilus/scripts

# Install scripts
install -m 0755 tailscale-receive.sh %{buildroot}%{_bindir}/tailscale-receive.sh
install -m 0755 tailscale-send.sh %{buildroot}%{_bindir}/tailscale-send.sh
install -m 0755 install.sh %{buildroot}%{_bindir}/tailscale-receiver-install.sh
install -m 0755 uninstall.sh %{buildroot}%{_bindir}/tailscale-receiver-uninstall.sh

# Install systemd files
install -m 0644 rpm/tailscale-receive.service %{buildroot}%{_unitdir}/tailscale-receive.service
install -m 0644 rpm/tailscale-receive.timer %{buildroot}%{_unitdir}/tailscale-receive.timer

# Install desktop integration
install -m 0644 rpm/tailscale-send.desktop %{buildroot}%{_datadir}/kio/servicemenus/tailscale-send.desktop
install -m 0644 rpm/tailscale-send.desktop %{buildroot}%{_datadir}/kservices5/ServiceMenus/tailscale-send.desktop

# Install Nautilus script
install -m 0755 rpm/tailscale-nautilus-script %{buildroot}%{_skeldir}/.local/share/nautilus/scripts/Send\ to\ device\ using\ Tailscale

# Install configuration
install -m 0644 rpm/tailscale-receiver.default %{buildroot}%{_sysconfdir}/default/tailscale-receive

# Install documentation
install -m 0644 README.md %{buildroot}%{_datadir}/doc/%{name}/README.md
install -m 0644 LICENSE %{buildroot}%{_datadir}/doc/%{name}/LICENSE

%post
# Configure the service for the current user
TARGET_USER=""
if [ -n "$SUDO_USER" ] && id "$SUDO_USER" >/dev/null 2>&1; then
    TARGET_USER="$SUDO_USER"
elif [ -n "$USER" ] && [ "$USER" != "root" ] && id "$USER" >/dev/null 2>&1; then
    TARGET_USER="$USER"
else
    # Try to find a non-root user
    TARGET_USER=$(getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' | head -1)
fi

if [ -n "$TARGET_USER" ]; then
    TARGET_DIR="/home/$TARGET_USER/Downloads/tailscale"

    # Update configuration
    sed -i "s|^# TARGET_USER=.*|TARGET_USER=$TARGET_USER|" /etc/default/tailscale-receive
    sed -i "s|^# TARGET_DIR=.*|TARGET_DIR=$TARGET_DIR|" /etc/default/tailscale-receive

    # Create target directory
    mkdir -p "$TARGET_DIR"
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_DIR"
    chmod 755 "$TARGET_DIR"

    # Update systemd service
    sed -i "s|^ReadWritePaths=.*|ReadWritePaths=/home/$TARGET_USER/Downloads/tailscale|" %{_unitdir}/tailscale-receive.service

    echo "Configured Tailscale Receiver for user: $TARGET_USER"
fi

# Reload systemd
systemctl daemon-reload

# Enable service if Tailscale is available
if command -v tailscale >/dev/null 2>&1; then
    systemctl enable tailscale-receive.service
    echo "Service enabled. Start with: sudo systemctl start tailscale-receive.service"
fi

# Copy Nautilus script if Nautilus is available
if command -v nautilus >/dev/null 2>&1 && [ -n "$TARGET_USER" ]; then
    NAUTILUS_DIR="/home/$TARGET_USER/.local/share/nautilus/scripts"
    mkdir -p "$NAUTILUS_DIR"
    cp %{_skeldir}/.local/share/nautilus/scripts/Send\ to\ device\ using\ Tailscale "$NAUTILUS_DIR/"
    chown -R "$TARGET_USER:$TARGET_USER" "$NAUTILUS_DIR"
    chmod +x "$NAUTILUS_DIR/Send to device using Tailscale"
fi

%preun
if [ $1 -eq 0 ]; then
    # Stop and disable services on package removal
    systemctl stop tailscale-receive.timer >/dev/null 2>&1 || true
    systemctl stop tailscale-receive.service >/dev/null 2>&1 || true
    systemctl disable tailscale-receive.timer >/dev/null 2>&1 || true
    systemctl disable tailscale-receive.service >/dev/null 2>&1 || true
fi

%files
%license LICENSE
%doc README.md
%{_bindir}/tailscale-receive.sh
%{_bindir}/tailscale-send.sh
%{_bindir}/tailscale-receiver-install.sh
%{_bindir}/tailscale-receiver-uninstall.sh
%{_unitdir}/tailscale-receive.service
%{_unitdir}/tailscale-receive.timer
%config(noreplace) %{_sysconfdir}/default/tailscale-receive
%{_datadir}/kio/servicemenus/tailscale-send.desktop
%{_datadir}/kservices5/ServiceMenus/tailscale-send.desktop
%{_skeldir}/.local/share/nautilus/scripts/Send to device using Tailscale
%{_datadir}/doc/%{name}/README.md
%{_datadir}/doc/%{name}/LICENSE

%changelog
* $(date '+%a %b %d %Y') Tailscale Community <noreply@tailscale.com> - 2.3.0-1
- New upstream release 2.3.0
- Directory support: Full recursive directory reception
- Single-instance protection: PID/lock file mechanism
- Systemd timer mode: Power-efficient operation
- GNOME/Nautilus integration: Right-click context menus
- Configurable polling: Custom intervals and timeouts
- File integrity verification: SHA256/SHA512/MD5 checksums
- Health endpoint: HTTP monitoring with JSON metrics
- Configuration migration: Automatic version upgrades
- Enterprise packaging: Professional Debian/RPM packages