##
# Copyright 2016
# This file is part of openvim
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
##

import os
from charms.reactive import (
    hook,
    set_state,
    when,
    when_not,
)
from charmhelpers.core.hookenv import (
    network_get_primary_address,
    status_set,
    unit_private_ip,
)
from charmhelpers.core.unitdata import kv
from charmhelpers.core.host import (
    mkdir,
    symlink,
    chownr,
    add_user_to_group,
)

from charmhelpers.fetch.archiveurl import ArchiveUrlFetchHandler
from charmhelpers.contrib.unison import ensure_user
import subprocess
import socket

# WIP: need to get the virtual bridges/vlan setup accordingly
# @hook('config-changed')
# def validate_config():
#     if len(cfg['bridge_interface']):
#         if cfg.changed('bridge_interface') or cfg.changed('bridge_mtu'):
#             configure_bridges()
#     else:
#         status_set('waiting', 'Please set bridge interface.')
# def configure_bridges():
#
#     mtu = cfg['bridge_mtu']
#     interface = cfg['bridge_interface']
#
#     # Verify the bridge exists
#     status_set("maintenance", "Verifying interface {} exists".format(interface))
#     try:
#         _run("ifconfig {}".format(interface))
#     except subprocess.CalledProcessError:
#         status_set('waiting', 'Invalid bridge interface. Please set bridge interface.')
#         return
#
#     # For management and data interfaces
#     if os.path.isfile("/etc/udev/rules.d/pci_config.rules"):
#         status_set("maintenance", "Removing udev pci rules")
#         os.remove("/etc/udev/rules.d/pci_config.rules")
#
#     # Render interfaces
#     status_set("maintenance", "Rendering interfaces.")
#     render(
#         source="interfaces",
#         target="/etc/network/interfaces.d/openvim.cfg",
#         owner="root",
#         perms=0o664,
#         context={"interface": interface, "mtu": mtu}
#     )
#
#     # Set MTU and raise interface
#     status_set("maintenance", "Reconfiguring interface {} MTU".format(interface))
#     try:
#         _run("ifconfig {} mtu {}".format(interface, mtu))
#     except subprocess.CalledProcessError as e:
#         status_set("waiting", "Invalid MTU. Please try again.")
#         return
#
#     status_set("maintenance", "Raising interface {}".format(interface))
#     _run("ifconfig {} up".format(interface))
#
#
#     status_set("maintenance", "Raising virtual interfaces.")
#     for i in range(1, 21):
#         # echo "ifconfig ${interface}.20$i2digits mtu $MTU
#         # ifconfig virbrMan$j mtu $MTU
#         # ifconfig virbrMan$j up
#
#         _run("ifconfig {}.20{} mtu {}".format(interface, '%02d' % i, mtu))
#         _run("ifconfig virbrMan{} mtu {}".format(interface, mtu))
#         _run("ifconfig virbrMan{} up".format('%02d' % i))
#
#     #  echo "ifconfig em2.1001 mtu $MTU
#     # ifconfig virbrInf mtu $MTU
#     # ifconfig virbrInf up
#     status_set("maintenance", "Raising virtual bridge interface")
#     _run("ifconfig {}.1001 mtu {}".format(interface, mtu))
#     _run("ifconfig virbrInf mtu {}".format(mtu))
#     _run("ifconfig virbrInf up")
#
#     status_set('active', "Ready")


def create_openvim_user():
    status_set("maintenance", "Creating OpenVIM user")
    ensure_user('openvim')


def group_openvim_user():
    status_set("maintenance", "Adding OpenVIM user to groups")
    add_user_to_group('openvim', 'libvirtd')
    add_user_to_group('openvim', 'sudo')
    add_user_to_group('openvim', 'kvm')


def nopasswd_openvim_sudo():
    status_set("maintenance", "Allowing nopasswd sudo for OpenVIM user")
    with open('/etc/sudoers', 'r+') as f:
        data = f.read()
        if 'openvim ALL=(ALL) NOPASSWD:ALL' not in data:
            f.seek(0)
            f.truncate()
            data += '\nopenvim ALL=(ALL) NOPASSWD:ALL\n'
            f.write(data)


def setup_qemu_binary():
    status_set("maintenance", "Setting up qemu-kvm binary")
    mkdir('/usr/libexec', owner='root', group='root', perms=0o775, force=False)
    symlink('/usr/bin/kvm', '/usr/libexec/qemu-kvm')


def setup_images_folder():
    status_set("maintenance", "Setting up VM images folder")
    mkdir('/opt/VNF', owner='openvim', group='openvim', perms=0o775, force=False)
    symlink('/var/lib/libvirt/images', '/opt/VNF/images')
    chownr('/opt/VNF', owner='openvim', group='openvim', follow_links=False, chowntopdir=True)
    chownr('/var/lib/libvirt/images', owner='root', group='openvim', follow_links=False, chowntopdir=True)
    os.chmod('/var/lib/libvirt/images', 0o775)


def download_default_image():
    # TODO: This should actually sync from the NFS mount
    status_set("maintenance", "Downloading default image")
    fetcher = ArchiveUrlFetchHandler()
    fetcher.download(
        source="https://cloud-images.ubuntu.com/releases/16.04/release/ubuntu-16.04-server-cloudimg-amd64-disk1.img",
        dest="/opt/VNF/images/ubuntu-16.04-server-cloudimg-amd64-disk1.img"
        # TODO: add checksum
    )


def configure_kernel():
    """Configure the Kernel for hugepages/iommu/isolcpus
    and reboot if necessary"""

    try:
        _run("scripts/configure-kernel.sh")
        return True
    except subprocess.CalledProcessError:
        # if the kernel can't be configured, this machine won't work as a
        # compute node and we should float that information back to the oper.
        return False


@when_not('openvim-compute.installed', 'openvim-compute.wrong-hardware')
def prepare_openvim_compute():
    if configure_kernel():
        create_openvim_user()
        group_openvim_user()
        nopasswd_openvim_sudo()
        setup_qemu_binary()
        setup_images_folder()
        download_default_image()

        status_set("active", "Ready")
        set_state('openvim-compute.installed')
    else:
        # This should be smarter. Differentiate between "unsupported hardware"
        # and "we need to reboot for changes to take effect"
        status_set("blocked", "Insufficient/unsupported hardware detected.")
        set_state('openvim-compute.wrong-hardware')


@when('compute.available', 'openvim-compute.installed')
def host_add(compute):
    """Add this compute node to OpenVIM"""

    # Get the IP address of the private network interface
    compute_ip = network_get_primary_address('internal')
    try:
        socket.inet_aton(compute_ip)
        # legal
    except socket.error:
        # Fallback to the "private" unit ip
        compute_ip = unit_private_ip()

    (config, _) = _run("scripts/host-add.sh openvim {}".format(compute_ip))

    compute.send_compute_private_address(compute_ip)
    compute.send_host_config(config)


@when('compute.available', 'openvim-compute.installed')
def install_ssh_key(compute):
    cache = kv()
    if cache.get("ssh_key:" + compute.ssh_key()):
        compute.ssh_key_installed()
        cache.set("ssh_key:" + compute.ssh_key(), True)
        return

    mkdir('/home/openvim/.ssh', owner='openvim', group='openvim', perms=0o700)
    with open("/home/openvim/.ssh/authorized_keys", 'a') as f:
        f.write(compute.ssh_key() + '\n')

    os.chmod('/home/openvim/.ssh/authorized_keys', 0o600)
    chownr('/home/openvim/.ssh/authorized_keys', owner='openvim', group='openvim', follow_links=False, chowntopdir=True)

    compute.ssh_key_installed()
    cache.set("ssh_key:" + compute.ssh_key(), True)


@when('compute.connected')
def send_user(compute):
    compute.send_user('openvim')


def _run(cmd, env=None):
    if isinstance(cmd, str):
        cmd = cmd.split() if ' ' in cmd else [cmd]

    p = subprocess.Popen(cmd,
                         env=env,
                         stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE)
    stdout, stderr = p.communicate()
    retcode = p.poll()
    if retcode > 0:
        raise subprocess.CalledProcessError(returncode=retcode,
                                            cmd=cmd,
                                            output=stderr.decode("utf-8").strip())
    return (stdout.decode('utf-8'), stderr.decode('utf-8'))
