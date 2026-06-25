#!/bin/bash
### Copyright 1999-2026. WebPros International GmbH.
###############################################################################
# This script changes webstat component in Templates in Service Plans and in Subscriptions from awstats to goaccess in Plesk
# Requirements : bash 3.x, mysql-client, GNU coreutils
# Version      : 1.0
# usage: #./webstat-goaccess-change.sh
#########


plesk db -N -e "select Templates.name from Templates,clients,TmplData where Templates.owner_id=clients.id and Templates.type='domain' and Templates.id=TmplData.tmpl_id and TmplData.element='webstat' and TmplData.value='awstats';" > /root/templates.txt

plesk db -N -e "select clients.login from Templates,clients,TmplData where Templates.owner_id=clients.id and Templates.type='domain' and Templates.id=TmplData.tmpl_id and TmplData.element='webstat' and TmplData.value='awstats';" > /root/owner.txt

file1="/root/templates.txt"
file2="/root/owner.txt"

N=`cat /root/templates.txt | wc -l`

for i in `seq 1 $N`; do
    plesk bin service_plan -u "`cat $file1 | awk NR==$i`" -owner "`cat $file2 | awk NR==$i`" -webstat goaccess
done

plesk db -N -e "select domains.name from hosting,domains where hosting.webstat='awstats' and hosting.dom_id=domains.id;" > /root/subscriptions.txt

file3="/root/subscriptions.txt"

while read line
do
    plesk bin domain -u "$line" -webstat goaccess

done < $file3
