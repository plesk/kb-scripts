#!/bin/bash
### Copyright 1999-2023. Plesk International GmbH.

if [ -f /usr/bin/dpkg ]
    then
        dpkg -P --force-all `dpkg -l | egrep plesk-web-hosting | awk '{ print $2}'`
        plesk installer update
    else
        rpm -e --nodeps --justdb `rpm -qa | egrep plesk-web-hosting`
        plesk installer update
fi

