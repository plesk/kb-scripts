#!/bin/bash
### Copyright 1999-2023. Plesk International GmbH.

###############################################################################
# The script uninstalls the 360 Monitoring agent and remove all the configuration
# Requirements : bash 3.x
# Version      : 2.0
#########

handle_cmd () {
  noservicestop="Unit agent360.service not loaded"
  noservicedisable="Unit file agent360.service does not exist"
  nomodule="Cannot uninstall requirement agent360, not installed"
  nouser="user 'agent360' does not exist"
  if result=$($1 2>&1) ; then
    echo -e "\\e[32m[SUCCESS] $2\\e[m"
  else
    if [[ $result = *$noservicestop* ]] ; then
      echo -e "\\e[33m[WARNING] Unable to stop the service agent360 because it was not found\n\t  Probably, it was removed earlier\\e[m"
    elif [[ $result = *$noservicedisable* ]] ; then
      echo -e "\\e[33m[WARNING] The service agent360 can not be disabled because it was not found\n\t  Probably, it was removed earlier\\e[m"
    elif [[ $result = *$nomodule* ]] ; then
      echo -e "\\e[33m[WARNING] The Python modules for 360 Monitoring are not found\n\t  Probably, it was removed earlier\\e[m"
    elif [[ $result = *$nouser* ]] ; then
      echo -e "\\e[33m[WARNING] The user agent360 does not exist\n\t  Probably, it was removed earlier\\e[m"
    else
      echo -e "\\e[31m[ERROR] $result\\e[m"
    fi
  fi
}

handle_cmd 'systemctl stop agent360' 'The service agent360 has been stopped'
handle_cmd 'systemctl disable agent360' 'The service agent360 has been disabled'
handle_cmd 'pip3 uninstall -y agent360' 'The Python modules for 360 Monitoring have been removed'
handle_cmd 'userdel agent360' 'The user agent360 has been deleted'

if [[ -f /etc/systemd/system/agent360.service ]] || [[ -f /etc/systemd/system/agent360 ]] ; then
  handle_cmd 'rm -f /etc/systemd/system/agent360*' 'The configuration of the service agent360 has been removed'
  handle_cmd 'systemctl reset-failed' 'The systemd data has been updated'
else
  echo -e "\\e[33m[WARNING] The configuration file of the service agent360 is not found\n\t  Probably, it was removed earlier\\e[m"
fi
if [[ -f /etc/agent360.ini ]] || [[ -f /etc/agent360-token.ini ]] ; then
  handle_cmd 'rm -f /etc/agent360*' 'The 360 Monitoring configuration files have been deleted'
else
  echo -e "\\e[33m[WARNING] The 360 Monitoring configuration files are not found\n\t  Probably, they were removed earlier\\e[m"
fi

if [[ -f /var/log/agent360.log ]] || [[ -f /var/log/agent360-install.log ]]; then
  echo
  read -r -p "Do you want to remove agent360 logs (y/n)? " choice
  case "$choice" in
    y|Y ) handle_cmd 'rm -f /var/log/agent360*' 'The logs have been removed';;
    n|N ) echo -e "\\e[32m[SUCCESS] The logs remain on the server\n\t  You might remove them manually later\\e[m";;
    * ) echo -e "\\e[31m[ERROR] The input is invalid! The logs have not been removed\\e[m";;
  esac
fi

echo
echo -e "\\e[34m[INFO] Please wait for 15 minutes and, then, remove the server from 360 Monitoring > Servers\\e[m"
