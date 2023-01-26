#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

mkdir -p ~/spam_investigation
rm -f ~/spam_investigation/*.txt
plesk db -N -e "select displayName from domains" > ~/spam_investigation/domains.txt
while read domain; do
cat /var/log/maillog | grep "from=<" | grep "postfix/qmgr" | cut -d "<" -f2 | cut -d ">" -f1 | grep $domain | sort -n | uniq -c | sort -n >> ~/spam_investigation/list.txt
done < ~/spam_investigation/domains.txt
cat ~/spam_investigation/list.txt | sort -nr -k1 > ~/spam_investigation/sorted_list.txt

