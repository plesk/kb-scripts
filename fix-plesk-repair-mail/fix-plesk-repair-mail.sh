#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script resolves an issue with 'plesk repair mail' when unicode characters are used in Auto-Reply and/or bounce messages text
# Requirements : bash 3.x, mysql-client, GNU coreutils
# Version      : 1.0
#########

timestamp=$(/bin/date +%Y%m%d-%H%M%S)
LOG=/var/log/plesk/repair-$timestamp.log
echo "-----------------------------------------------------------------------------" >> $LOG
echo "Script from the article https://support.plesk.com/hc/en-us/articles/213901665" >> $LOG
echo "-----------------------------------------------------------------------------" >> $LOG
echo >> $LOG
/bin/date >> $LOG
echo >> $LOG
echo "The following mailboxes have Auto-Reply enabled:" >> $LOG
/usr/sbin/plesk db "select m.mail_name,d.name,mr.endDate from domains d join mail m on m.dom_id = d.id join mail_resp mr on m.id = mr.mn_id where m.autoresponder='true';" >> $LOG
echo >> $LOG
echo "Switching off auto-reply..." >> $LOG
rm -f /tmp/autoresponder-enabled
plesk db -sNe "select CONCAT(m.mail_name, '@', d.name), mr.endDate as mailbox from domains d join mail m on m.dom_id = d.id join mail_resp mr on m.id = mr.mn_id where m.autoresponder='true'" > /tmp/autoresponder-enabled
sed -i "s/\tNULL/\toff/g" /tmp/autoresponder-enabled
for mailbox in $(plesk db -sNe "select CONCAT(m.mail_name, '@', d.name) from domains d join mail m on m.dom_id = d.id where m.autoresponder='true'"); do plesk bin autoresponder -u -mail $mailbox -status false; done >> $LOG
echo >> $LOG
echo "Starting plesk repair mail..." >> $LOG
/usr/sbin/plesk repair mail
echo >> $LOG
echo "Switching auto-reply back on..." >> $LOG
while read mailbox endDate; do plesk bin autoresponder -u -mail $mailbox -status true -end-date $endDate; done < /tmp/autoresponder-enabled >> $LOG
echo >> $LOG
rm -f /tmp/autoresponder-enabled
echo "Done!" >> $LOG
