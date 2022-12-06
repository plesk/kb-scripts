#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script moves spam messages to the Spam folder
# Requirements : bash 3.x
# Version      : 1.0
#########

for i in `plesk db -Ne "select name from domains;"`
do
MYSQL_PWD=`cat /etc/psa/.psa.shadow` mysql -u admin psa -Ne"select id from domains where name = '$i';" > /root/${i}_id.txt
MYSQL_PWD=`cat /etc/psa/.psa.shadow` mysql -u admin psa -Ne"select mail_name from mail where dom_id=`cat /root/${i}_id.txt`;" > /root/${i}_mailnames.txt
for n in `cat /root/${i}_mailnames.txt`
do
plesk bin spamassassin -u $n@$i -status true
plesk bin spamassassin -u $n@$i -action move
done
done
