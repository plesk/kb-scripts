#Script deletes all emails for all mailboxes specified in the file mbox.txt
#!/bin/bash
for mailbox in $(cat mbox.txt); do 
    doveadm expunge -u $mailbox mailbox 'INBOX' all
    doveadm expunge -u $mailbox mailbox 'INBOX.*' all
    doveadm expunge -u $mailbox mailbox 'Sent' all
    doveadm expunge -u $mailbox mailbox 'Trash' all
    doveadm expunge -u $mailbox mailbox 'Drafts' all
    doveadm expunge -u $mailbox mailbox 'Spam' all
done