#!/bin/bash
# Utility functions for configuring chrooted rootfs images
#
# These functions are designed to be sourced and used within chroot environments
# or when working with mounted rootfs images.

set -euo pipefail

# setup_hostname <hostname>
# Sets the system hostname by writing to /etc/hostname
setup_hostname() {
    local hostname="$1"
    echo "$hostname" > /etc/hostname
}

# setup_etc_hosts <hostname>
# Configures /etc/hosts with standard entries including the given hostname
setup_etc_hosts() {
    local hostname="$1"
    cat > /etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 $hostname

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
}

# set_password <user> <password>
# Sets the password for the specified user using chpasswd
set_password() {
    local user="$1"
    local password="$2"
    echo "$user:$password" | chpasswd
}

# setup_ssh_keys <username> <public_ssh_key_path>
# Creates .ssh for the user and appends the contents of public_ssh_key_path to .ssh/authorized_keys
setup_ssh_keys() {
    local username="$1"
    local public_ssh_key_path="$2"
    local home
    home=$(getent passwd "$username" | cut -d: -f6)
    [[ -z "$home" ]] && { echo "User not found: $username" >&2; return 1; }
    mkdir -p "$home/.ssh"
    cat "$public_ssh_key_path" >> "$home/.ssh/authorized_keys"
    chmod 700 "$home/.ssh"
    chmod 600 "$home/.ssh/authorized_keys"
    chown -R "$username:$username" "$home/.ssh"
}


# setup_fstab / [mount_point ...]
# Writes /etc/fstab for Firecracker-style block devices. First argument must be /.
# Subsequent arguments are extra mount points (e.g. /home, /data). Devices are
# assigned in order: / -> /dev/vda, next -> /dev/vdb, etc. Creates mount point dirs.
setup_fstab() {
    [[ $# -ge 1 && "$1" == "/" ]] || { echo "First argument must be /" >&2; return 1; }

    echo '# <device>  <mount>  <type>  <options>  <dump>  <pass>' > /etc/fstab

    echo "/dev/vda  /   ext4    defaults    0 1" >> /etc/fstab

    local letters="bcdefghijklmnopqrstuvwxyz"
    while [[ $# -gt 1 ]]
    do
        shift
        letter=${letters:0:1}
        letters=${letters:1}
        device="/dev/vd$letter"
        mount=$1

        echo "$device  $mount   ext4    defaults,nofail    0 2" >> /etc/fstab
    done
}

# setup_sshd [permit_root_login] [password_auth] [pubkey_auth]
# Configures SSH daemon settings by appending to /etc/ssh/sshd_config
# Defaults: PermitRootLogin yes, PasswordAuthentication yes, PubkeyAuthentication yes
setup_sshd() {
    local permit_root="${1:-yes}"
    local password_auth="${2:-yes}"
    local pubkey_auth="${3:-yes}"

    cat >> /etc/ssh/sshd_config << EOF

# Custom configuration
PermitRootLogin $permit_root
PasswordAuthentication $password_auth
PubkeyAuthentication $pubkey_auth
EOF
}
