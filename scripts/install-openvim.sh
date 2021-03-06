#!/bin/bash

##
# Copyright 2015 Telefónica Investigación y Desarrollo, S.A.U.
# This file is part of openvim
# All Rights Reserved.
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
# For those usages not covered by the Apache License, Version 2.0 please
# contact with: nfvlabs@tid.es
##

#ONLY TESTED for Ubuntu 14.10 14.04 16.04, CentOS7 and RHEL7
#Get needed packages, source code and configure to run openvim
#Ask for database user and password if not provided

function usage(){
    echo -e "usage: sudo $0 [OPTIONS]"
    echo -e "Install last stable source code in ./openvim and the needed packages"
    echo -e "On a Ubuntu 16.04 it configures openvim as a service"
    echo -e "  OPTIONS"
    echo -e "     -u USER:    database admin user. 'root' by default. Prompts if needed"
    echo -e "     -p PASS:    database admin password to be used or installed. Prompts if needed"
    echo -e "     -q --quiet: install in an unattended mode"
    echo -e "     -h --help:  show this help"
    echo -e "     --develop:  install last version for developers, and do not configure as a service"
    echo -e "     --skip-install-packages: use this option to skip and update and install the requires packages. This avoid wasting time if you are sure requires packages are present for e.g. a previous installation"
}

function install_packages(){
    [ -x /usr/bin/apt-get ] && apt-get install -y $*
    [ -x /usr/bin/yum ]     && yum install -y $*   
    
    #check properly installed
    for PACKAGE in $*
    do
        PACKAGE_INSTALLED="no"
        [ -x /usr/bin/apt-get ] && dpkg -l $PACKAGE            &>> /dev/null && PACKAGE_INSTALLED="yes"
        [ -x /usr/bin/yum ]     && yum list installed $PACKAGE &>> /dev/null && PACKAGE_INSTALLED="yes" 
        if [ "$PACKAGE_INSTALLED" = "no" ]
        then
            echo "failed to install package '$PACKAGE'. Revise network connectivity and try again"
            exit -1
       fi
    done
}


GIT_URL=https://osm.etsi.org/gerrit/osm/openvim.git
DBUSER="root"
DBPASSWD=""
DBPASSWD_PARAM=""
QUIET_MODE=""
DEVELOP=""
NO_PACKAGES=""
while getopts ":u:p:hiq-:" o; do
    case "${o}" in
        u)
            export DBUSER="$OPTARG"
            ;;
        p)
            export DBPASSWD="$OPTARG"
            export DBPASSWD_PARAM="-p$OPTARG"
            ;;
        q)
            export QUIET_MODE=yes
            export DEBIAN_FRONTEND=noninteractive
            ;;
        h)
            usage && exit 0
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            [ "${OPTARG}" == "develop" ] && DEVELOP="y" && continue
            [ "${OPTARG}" == "quiet" ] && export QUIET_MODE=yes && export DEBIAN_FRONTEND=noninteractive && continue
            [ "${OPTARG}" == "skip-install-packages" ] && export NO_PACKAGES=yes && continue
            echo -e "Invalid option: '--$OPTARG'\nTry $0 --help for more information" >&2
            exit 1
            ;;
        \?)
            echo -e "Invalid option: '-$OPTARG'\nTry $0 --help for more information" >&2
            exit 1
            ;;
        :)
            echo -e "Option '-$OPTARG' requires an argument\nTry $0 --help for more information" >&2
            exit 1
            ;;
        *)
            usage >&2
            exit -1
            ;;
    esac
done

#check root privileges and non a root user behind
[ "$USER" != "root" ] && echo "Needed root privileges" >&2 && exit -1
if [[ -z "$SUDO_USER" ]] || [[ "$SUDO_USER" = "root" ]]
then
    [[ -z $QUIET_MODE ]] && read -e -p "Install in the root user (y/N)?" KK
    [[ -z $QUIET_MODE ]] && [[ "$KK" != "y" ]] && [[ "$KK" != "yes" ]] && echo "Cancelled" && exit 1
    export SUDO_USER=root
fi

#Discover Linux distribution
#try redhat type
[ -f /etc/redhat-release ] && _DISTRO=$(cat /etc/redhat-release 2>/dev/null | cut  -d" " -f1) 
#if not assuming ubuntu type
[ -f /etc/redhat-release ] || _DISTRO=$(lsb_release -is  2>/dev/null)            
if [ "$_DISTRO" == "Ubuntu" ]
then
    _RELEASE=$(lsb_release -rs)
    if [[ ${_RELEASE%%.*} != 14 ]] && [[ ${_RELEASE%%.*} != 16 ]]
    then
        [[ -z $QUIET_MODE ]] && read -e -p "WARNING! Not tested Ubuntu version. Continue assuming a trusty (14.XX)'? (y/N)" KK
        [[ -z $QUIET_MODE ]] && [[ "$KK" != "y" ]] && [[ "$KK" != "yes" ]] && echo "Cancelled" && exit 1
        _RELEASE = 14
    fi
elif [ "$_DISTRO" == "CentOS" ]
then
    _RELEASE="7" 
    if ! cat /etc/redhat-release | grep -q "7."
    then
        read -e -p "WARNING! Not tested CentOS version. Continue assuming a '_RELEASE' type? (y/N)" KK
        [ "$KK" != "y" -a  "$KK" != "yes" ] && echo "Cancelled" && exit 0
    fi
elif [ "$_DISTRO" == "Red" ]
then
    _RELEASE="7" 
    if ! cat /etc/redhat-release | grep -q "7."
    then
        read -e -p "WARNING! Not tested Red Hat OS version. Continue assuming a '_RELEASE' type? (y/N)" KK
        [ "$KK" != "y" -a  "$KK" != "yes" ] && echo "Cancelled" && exit 0
    fi
else  #[ "$_DISTRO" != "Ubuntu" -a "$_DISTRO" != "CentOS" -a "$_DISTRO" != "Red" ] 
    _DISTRO_DISCOVER=$_DISTRO
    [ -x /usr/bin/apt-get ] && _DISTRO="Ubuntu" && _RELEASE="14"
    [ -x /usr/bin/yum ]     && _DISTRO="CentOS" && _RELEASE="7"
    read -e -p "WARNING! Not tested Linux distribution '$_DISTRO_DISCOVER '. Continue assuming a '$_DISTRO $_RELEASE' type? (y/N)" KK
    [ "$KK" != "y" -a  "$KK" != "yes" ] && echo "Cancelled" && exit 0
fi


if [[ -z "$NO_PACKAGES" ]]
then
echo '
#################################################################
#####               UPDATE REPOSITORIES                     #####
#################################################################'
[ "$_DISTRO" == "Ubuntu" ] && apt-get update -y

[ "$_DISTRO" == "CentOS" -o "$_DISTRO" == "Red" ] && yum check-update -y
[ "$_DISTRO" == "CentOS" ] && sudo yum install -y epel-release
[ "$_DISTRO" == "Red" ] && wget http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm \
  && sudo rpm -ivh epel-release-7-5.noarch.rpm && sudo yum install -y epel-release && rm -f epel-release-7-5.noarch.rpm
[ "$_DISTRO" == "CentOS" -o "$_DISTRO" == "Red" ] && sudo yum repolist
fi

if [[ -z "$NO_PACKAGES" ]]
then
echo '
#################################################################
#####               INSTALL REQUIRED PACKAGES               #####
#################################################################'
[ "$_DISTRO" == "Ubuntu" ] && install_packages "git screen wget mysql-server"
[ "$_DISTRO" == "CentOS" -o "$_DISTRO" == "Red" ] && install_packages "git screen wget mariadb mariadb-server"

if [[ "$_DISTRO" == "Ubuntu" ]]
then
    #start services. By default CentOS does not start services
    service mysql start >> /dev/null
    # try to set admin password, ignore if fails
    [[ -n $DBPASSWD ]] && mysqladmin -u $DBUSER -s password $DBPASSWD
fi

if [ "$_DISTRO" == "CentOS" -o "$_DISTRO" == "Red" ]
then
    #start services. By default CentOS does not start services
    service mariadb start
    service httpd   start
    systemctl enable mariadb
    systemctl enable httpd
    read -e -p "Do you want to configure mariadb (recomended if not done before) (Y/n)" KK
    [ "$KK" != "n" -a  "$KK" != "no" ] && mysql_secure_installation

    read -e -p "Do you want to set firewall to grant web access port 80,443  (Y/n)" KK
    [ "$KK" != "n" -a  "$KK" != "no" ] && 
        firewall-cmd --permanent --zone=public --add-service=http &&
        firewall-cmd --permanent --zone=public --add-service=https &&
        firewall-cmd --reload
fi
fi  #[[ -z "$NO_PACKAGES" ]]

#check and ask for database user password. Must be done after database installation
if [[ -n $QUIET_MODE ]]
then
    echo -e "\nCheking database connection and ask for credentials"
    while ! mysqladmin -s -u$DBUSER $DBPASSWD_PARAM ping
    do
        [ -n "$logintry" ] &&  echo -e "\nInvalid database credentials!!!. Try again (Ctrl+c to abort)"
        [ -z "$logintry" ] &&  echo -e "\nProvide database credentials"
        read -e -p "database user? ($DBUSER) " DBUSER_
        [ -n "$DBUSER_" ] && DBUSER=$DBUSER_
        read -e -s -p "database password? (Enter for not using password) " DBPASSWD_
        [ -n "$DBPASSWD_" ] && DBPASSWD="$DBPASSWD_" && DBPASSWD_PARAM="-p$DBPASSWD_"
        [ -z "$DBPASSWD_" ] && DBPASSWD=""           && DBPASSWD_PARAM=""
        logintry="yes"
    done
fi

if [[ -z "$NO_PACKAGES" ]]
then
echo '
#################################################################
#####               INSTALL PYTHON PACKAGES                 #####
#################################################################'
[ "$_DISTRO" == "Ubuntu" ] && install_packages "python-yaml python-libvirt python-bottle python-mysqldb python-jsonschema python-paramiko python-argcomplete python-requests"
[ "$_DISTRO" == "CentOS" -o "$_DISTRO" == "Red" ] && install_packages "PyYAML libvirt-python MySQL-python python-jsonschema python-paramiko python-argcomplete python-requests"

#The only way to install python-bottle on Centos7 is with easy_install or pip
[ "$_DISTRO" == "CentOS" -o "$_DISTRO" == "Red" ] && easy_install -U bottle

fi  #[[ -z "$NO_PACKAGES" ]]

echo '
#################################################################
#####                 DOWNLOAD SOURCE                       #####
#################################################################'
su $SUDO_USER -c 'git clone '"${GIT_URL}"' openvim'
#[[ -z $DEVELOP ]] && su $SUDO_USER -c 'git checkout <tag version>'

#Unncoment to use a concrete branch, if not main branch 
#pushd openvim
#su $SUDO_USER -c 'git checkout v0.4'
#popd

echo '
#################################################################
#####               CREATE DATABASE                         #####
#################################################################'
mysqladmin -u$DBUSER $DBPASSWD_PARAM -s create vim_db || ! echo "Cannot create database vim_db" || exit 1

echo "CREATE USER 'vim'@'localhost' identified by 'vimpw';"     | mysql -u$DBUSER $DBPASSWD_PARAM || ! echo "Failed while creating user vim at dabase" || exit 1
echo "GRANT ALL PRIVILEGES ON vim_db.* TO 'vim'@'localhost';"   | mysql -u$DBUSER $DBPASSWD_PARAM || ! echo "Failed while creating user vim at dabase" || exit 1
echo " Database 'vim_db' created, user 'vim' password 'vimpw'"


su $SUDO_USER -c './openvim/database_utils/init_vim_db.sh -u vim -p vimpw'  || ! echo "Failed while creating user vim at dabase" || exit 1


if [ "$_DISTRO" == "CentOS" -o "$_DISTRO" == "Red" ]
then
    echo '
#################################################################
#####        CONFIGURE firewalld                            #####
#################################################################'
    read -e -p "Configure firewalld for openvimd port 9080? (Y/n)" KK
    if [ "$KK" != "n" -a  "$KK" != "no" ]
    then
        #Creates a service file for openvim
        echo '<?xml version="1.0" encoding="utf-8"?>
<service>
 <short>openvimd</short>
 <description>openvimd service</description>
 <port protocol="tcp" port="9080"/>
</service>' > /etc/firewalld/services/openvimd.xml
        #put proper permissions
        pushd /etc/firewalld/services > /dev/null
        restorecon openvim
        chmod 640 openvim
        popd > /dev/null
        #Add the openvim service to the default zone permanently and reload the firewall configuration
        firewall-cmd --permanent --add-service=openvim > /dev/null
        firewall-cmd --reload > /dev/null
        echo "done." 
    else
        echo "skipping."
    fi
fi

echo '
#################################################################
#####        CONFIGURE openvim CLIENT                       #####
#################################################################'
#creates a link at ~/bin
su $SUDO_USER -c 'mkdir -p ~/bin'
su $SUDO_USER -c 'rm -f ${HOME}/bin/openvim'
su $SUDO_USER -c 'rm -f ${HOME}/bin/openflow'
su $SUDO_USER -c 'rm -f ${HOME}/bin/service-openvim'
su $SUDO_USER -c 'rm -f ${HOME}/bin/initopenvim'
su $SUDO_USER -c 'rm -f ${HOME}/bin/service-floodlight'
su $SUDO_USER -c 'rm -f ${HOME}/bin/service-opendaylight'
su $SUDO_USER -c 'rm -f ${HOME}/bin/get_dhcp_lease.sh'
su $SUDO_USER -c 'ln -s ${PWD}/openvim/openvim   ${HOME}/bin/openvim'
su $SUDO_USER -c 'ln -s ${PWD}/openvim/openflow  ${HOME}/bin/openflow'
su $SUDO_USER -c 'ln -s ${PWD}/openvim/scripts/service-openvim.sh  ${HOME}/bin/service-openvim'
su $SUDO_USER -c 'ln -s ${PWD}/openvim/scripts/initopenvim.sh  ${HOME}/bin/initopenvim'
su $SUDO_USER -c 'ln -s ${PWD}/openvim/scripts/service-floodlight.sh  ${HOME}/bin/service-floodlight'
su $SUDO_USER -c 'ln -s ${PWD}/openvim/scripts/service-opendaylight.sh  ${HOME}/bin/service-opendaylight'
su $SUDO_USER -c 'ln -s ${PWD}/openvim/scripts/get_dhcp_lease.sh  ${HOME}/bin/get_dhcp_lease.sh'

#insert /home/<user>/bin in the PATH
#skiped because normally this is done authomatically when ~/bin exist
#if ! su $SUDO_USER -c 'echo $PATH' | grep -q "/home/${SUDO_USER}/bin"
#then
#    echo "    inserting /home/$SUDO_USER/bin in the PATH at .bashrc"
#    su $SUDO_USER -c 'echo "PATH=\$PATH:/home/\${USER}/bin" >> ~/.bashrc'
#fi

if [[ $SUDO_USER == root ]]
then
    if ! echo $PATH | grep -q "${HOME}/bin"
    then
        echo "PATH=\$PATH:\${HOME}/bin" >> ${HOME}/.bashrc
    fi
fi


#configure arg-autocomplete for this user
#in case of minmal instalation this package is not installed by default
[[ "$_DISTRO" == "CentOS" || "$_DISTRO" == "Red" ]] && yum install -y bash-completion
#su $SUDO_USER -c 'mkdir -p ~/.bash_completion.d'
su $SUDO_USER -c 'activate-global-python-argcomplete --user'
if ! grep -q bash_completion.d/python-argcomplete.sh /home/${SUDO_USER}/.bashrc
then
    echo "    inserting .bash_completion.d/python-argcomplete.sh execution at .bashrc"
    su $SUDO_USER -c 'echo ". /home/${USER}/.bash_completion.d/python-argcomplete.sh" >> ~/.bashrc'
fi



if [[ "$_DISTRO" == "Ubuntu" ]] &&  [[ ${_RELEASE%%.*} == 16 ]] && [[ -z $DEVELOP ]]
then
echo '
#################################################################
#####             CONFIGURE OPENMANO SERVICE                #####
#################################################################'

    ./openvim/scripts/install-openvim-service.sh -f openvim #-u $SUDO_USER
#    alias service-openvim="service openvim"
#    echo 'alias service-openvim="service openvim"' >> ${HOME}/.bashrc

    echo
    echo "Done!  you may need to logout and login again for loading client configuration"
    echo " Manage server with 'service openvim start|stop|status|...' "


else

    echo
    echo "Done!  you may need to logout and login again for loading client configuration"
    echo " Run './openvim/scripts/service-openvim.sh start' for starting openvim in a screen"

fi
