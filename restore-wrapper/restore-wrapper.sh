#!/bin/bash
### Copyright 1999-2025. Plesk International GmbH.

###############################################################################
# The script reinstalls plesk-web-hosting package in order to restore cgi_wrapper
# Requirements : bash 3.x
# Version      : 2.0
#########
if [ -f /usr/bin/dpkg ]
        then
                dpkg -P --force-all `dpkg -l | egrep plesk-web-hosting | awk '{ print $2}'`
                plesk installer update
        else
                rpm -e --nodeps --justdb `rpm -qa | egrep plesk-web-hosting`
                plesk installer update
fi

