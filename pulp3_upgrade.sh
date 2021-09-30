#!/bin/bash
##########################################
# script: pulp3_upgrade.sh
#
##########################################

pip3 install --upgrade setuptools
cd /software/pulp_installer
git pull
ansible-playbook pulp_install.yaml -l localhost
pip3 install pulp_rpm --upgrade
exit
