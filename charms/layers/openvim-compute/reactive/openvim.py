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

from os import chmod
from charms.reactive import when, when_not, set_state
from charmhelpers.core.hookenv import (
    unit_private_ip,
    status_set,
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
    chmod('/var/lib/libvirt/images', 0o775)

def download_default_image():
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
        status_set("blocked", "Insufficient/unsupported hardware detected.")
        set_state('openvim-compute.wrong-hardware')


@when('compute.available', 'openvim-compute.installed')
def host_add(compute):
    (config, _) = _run("scripts/host-add.sh openvim {}".format(unit_private_ip()))
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

    chmod('/home/openvim/.ssh/authorized_keys', 0o600)
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
