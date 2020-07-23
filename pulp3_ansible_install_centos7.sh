#!/bin/bash
##########################################
# Script: pulp3_ansible_install_rpm-plugin.sh
#
# Description: Script to install pulp3 on CentOS 7 system minimal
#              using Ansible using rpm plugin.
# 
# Parameters: SELINUX: permissive
#             Firewalld: enabled
# Reference: https://docs.pulpproject.org/installation/instructions.html
##########################################

set -euo pipefail

TMPDIR=$(mktemp -d)
cd ${TMPDIR}

# Create password generator file
cat > passgen.py << EOF
import random

chars = 'abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*(-_=+)'
print(''.join(random.choice(chars) for i in range(50)))
EOF

chmod 0700 passgen.py

# Install epel-release (intentionally separate from other installs below)
yum -y install epel-release
# Install ansible/git with yum
yum -y install ansible git jq libsolv libmodulemd python2-httpie redis

# Enable redis
systemctl enable redis --now

# Install rpm pulp_rpm_prerequisites (https://galaxy.ansible.com/pulp/pulp_rpm_prerequisites)
ansible-galaxy install pulp.pulp_rpm_prerequisites

# Install postgresql role (https://pulp-installer.readthedocs.io/en/3.4.1/quickstart/)
ansible-galaxy install geerlingguy.postgresql
ansible-galaxy collection install pulp.pulp_installer

# Clone installer
git clone https://github.com/pulp/pulp_installer.git
cd pulp_installer

# Generate SECRET
PSECRET=$(python passgen.py)

# Generate Admin Password
APASS=$(python passgen.py)

# Create playbook
cat > pulp_install.yaml << EOF
---
- hosts: localhost
  vars:
    pulp_settings:
      secret_key: $PSECRET
      content_origin: "http://{{ ansible_fqdn }}"
    pulp_default_admin_password: $APASS
    pulp_install_plugins:
      # galaxy-ng: {}
      # pulp-ansible: {}
      # pulp-certguard: {}
      # pulp-container: {}
      # pulp-cookbook: {}
      # pulp-deb: {}
      # pulp-file: {}
      # pulp-gem: {}
      # pulp-maven: {}
      # pulp-npm: {}
      # pulp-python: {}
      pulp-rpm: {}
  roles:
    - pulp.pulp_installer.pulp_all_services
  environment:
    DJANGO_SETTINGS_MODULE: pulpcore.app.settings
EOF

# Disable httpd
systemctl disable httpd --now

# Run the playbook
ansible-playbook pulp_install.yaml -l localhost

cat > /usr/lib/systemd/system/pulpcore-api.service << EOF
[Unit]
Description=Pulp WSGI Server
After=network-online.target
Wants=network-online.target

[Service]
Environment="DJANGO_SETTINGS_MODULE=pulpcore.app.settings"
Environment="PULP_SETTINGS=/etc/pulp/settings.py"
Environment="PATH=/usr/local/lib/pulp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
User=pulp
PIDFile=/run/pulpcore-api.pid
RuntimeDirectory=pulpcore-api
ExecStart=/usr/local/lib/pulp/bin/gunicorn pulpcore.app.wsgi:application \
          --bind '127.0.0.1:24817' \
          --workers 1 \
          --access-logfile -
ProtectSystem=full
PrivateTmp=yes
PrivateDevices=yes


# This provides reconnect support for PostgreSQL and Redis. Without reconnect support, if either
# is not available at startup or becomes disconnected, this process will die and not respawn.
Restart=always
RestartSec=3

# This directive is set to an absolute path in other Pulp units. Using an
# absolute path is an abuse of the directive, as it should be a relative path,
# not an absolute path. PIDFile is now used to ensure that PID files are laid
# out in a standard way. If this directive had any other effects, it is better
# to use the correct directive than to uncomment this.
# WorkingDirectory=/var/run/pulpcore-api/

[Install]
WantedBy=multi-user.target
EOF

#systemctl daemon-reload
systemctl enable pulpcore-api.service --now

# Allow ports 80/443
echo "Adding ports 80/443 to firewalld"
firewall-cmd --zone=public --permanent --add-port=80/tcp
firewall-cmd --zone=public --permanent --add-port=443/tcp
firewall-cmd --reload

# Add new pulp commands to path
cp /etc/profile /etc/profile.bak
sed -i '52 a PATH=/usr/local/lib/pulp/bin:$PATH' /etc/profile

cat > /root/.netrc << EOF
machine localhost
login admin
password $APASS
EOF
chmod 0600 /root/.netrc

# HTTPie examples
#http example.org               # => GET
#http example.org hello=world   # => POST
#http :/pulp/api/v3/status/     # => http://pulp/api/v3/status/
#http example.org --auth USER[:PASS] -a USER[:PASS]
#http example.org --auth-type {basic,digest} -A {basic,digest}
#http http://xpa-pulp02.maverik.com/auth/login/?next=/pulp/api/v3/remotes/rpm/rpm/

# Clone pulp_rpm repo, very helpful scripts here
git clone https://github.com/pulp/pulp_rpm.git

echo "Admin password: $APASS"

exit