#!/bin/bash
### Copyright 1999-2023. Plesk International GmbH.

###############################################################################
# The script uninstalls the 360 Monitoring agent and remove all the configuration
# Requirements : bash 3.x
# Version      : 1.0
#########

systemctl stop agent360 &&
echo -e "\\e[32mThe agent360 service has been stopped\\e[m"

systemctl disable agent360 &&
echo -e "\\e[32mThe agent360 service has been disabled\\e[m"

rm -f /etc/systemd/system/agent360 &&
echo -e "\\e[32mThe agent360 service configuration has been removed\\e[m"

rm -f /etc/agent360* &&
echo -e "\\e[32mThe 360 Monitoring configuration files have been deleted\\e[m"

pip3 uninstall -y agent360 &&
echo -e "\\e[32mThe Python modules for 360 Monitoring have been removed\\e[m"

userdel agent360 &&
echo -e "\\e[32mThe corresponding user has been deleted\\e[m"

echo
echo -e "\\e[34m[!] Please wait for 15 minutes and, then, remove the server from Plesk 360 > Monitoring > Servers\\e[m"
