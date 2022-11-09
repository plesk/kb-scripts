#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.
# This script deletes all emails for all mailboxes specified in the file mbox.txt placed to the same directory as the script file
# Requirements	: Dovecot 2.x
# Version		: 1.0 
for mailbox in $(cat mbox.txt); do 
    doveadm expunge -u $mailbox mailbox 'INBOX' all
    doveadm expunge -u $mailbox mailbox 'INBOX.*' all
    doveadm expunge -u $mailbox mailbox 'Sent' all
    doveadm expunge -u $mailbox mailbox 'Trash' all
    doveadm expunge -u $mailbox mailbox 'Drafts' all
    doveadm expunge -u $mailbox mailbox 'Spam' all
done
