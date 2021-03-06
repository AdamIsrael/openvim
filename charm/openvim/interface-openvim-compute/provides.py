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

from charms.reactive import hook
from charms.reactive import RelationBase
from charms.reactive import scopes


class ProvidesOpenVIMCompute(RelationBase):
    scope = scopes.GLOBAL

    auto_accessors = ['ssh_key']

    @hook('{provides:openvim-compute}-relation-{joined,changed}')
    def changed(self):
        self.set_state('{relation_name}.connected')
        if self.ssh_key():
            self.set_state('{relation_name}.available')

    @hook('{provides:openvim-compute}-relation-{broken,departed}')
    def departed(self):
        self.remove_state('{relation_name}.connected')
        self.remove_state('{relation_name}.available')

    def ssh_key_installed(self):
        convo = self.conversation()
        convo.set_remote('ssh_key_installed', True)

    def send_user(self, user):
        convo = self.conversation()
        convo.set_remote('user', user)
