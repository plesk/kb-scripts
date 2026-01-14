#!/bin/bash
### Copyright 1999-2026. WebPros International GmbH.

########################
##################
##################
# This script analyzes mail logs to verify POP3/IMAP traffic statistics per mailbox.
# It excludes localhost connections (Webmail) and calculates usage in human-readable formats.
# Requirements: bash, grep, awk, coreutils
# Version: 1.0
#########

# 1. Ask for Subscription
echo -e "Please specify the name of the subscription: "
read SUBSCRIPTION

# 2. Detect OS Log Path (Auto-detects RHEL vs Debian/Ubuntu)
if [ -f /var/log/mail.log ]; then
    # Debian/Ubuntu often use mail.log and mail.log.1
    LOG_PATTERN="/var/log/mail.log*"
elif [ -f /var/log/maillog ]; then
    # RHEL/CentOS use maillog and maillog-DATE
    LOG_PATTERN="/var/log/maillog*"
else
    echo "Error: Could not find mail logs at /var/log/maillog or /var/log/mail.log"
    exit 1
fi

echo "Scanning logs: $LOG_PATTERN"

# 3. Get Domain ID
SUBSCRIPTIONID=$(plesk db -Ne "select domains.id from domains where domains.name='$SUBSCRIPTION'")

if [ -z "$SUBSCRIPTIONID" ]; then
    echo "Subscription not found."
    exit 1
fi

# 4. Get list of emails
EMAILS=$(plesk db -Ne "SELECT CONCAT(mail_name,'@',name) FROM mail,domains WHERE domains.id=mail.dom_id and domains.id IN (select domains.id from domains where domains.id = '$SUBSCRIPTIONID' or domains.parentDomainId='$SUBSCRIPTIONID' or domains.webspace_id='$SUBSCRIPTIONID')")

# 5. Process
# Create a temp file with ONLY the relevant IMAP/POP3 lines.
# We explicitly exclude 127.0.0. (Webmail) to match the legacy logic.
echo "Gathering relevant log data..."
TMP_LOG=$(mktemp)

# Explanation of grep chain:
# 1. Look for service=pop3 or imap
# 2. Exclude localhost (127.0.0.)
# 3. Ensure line has 'rcvd=' or 'sent='
zgrep -h -E "service=(pop3|imap)" $LOG_PATTERN | grep -v "127.0.0." | grep -E "rcvd=|sent=" > "$TMP_LOG"

echo -e "\n--- Traffic Statistics (Excluding Webmail/Localhost) ---\n"

for EMAIL in $EMAILS; do
    # Filter the pre-fetched log data for this specific email
    # awk parses "rcvd=123" by splitting on "=" and taking the 2nd part.
    # It handles comma suffixes automatically (awk math ignores trailing non-digits).
    STATS=$(grep "$EMAIL" "$TMP_LOG" | awk '{
        for(i=1;i<=NF;i++) {
            if ($i ~ /^rcvd=/) {
                split($i,a,"="); r += a[2];
            }
            if ($i ~ /^sent=/) {
                split($i,a,"="); s += a[2];
            }
        }
    } END { print r+0 " " s+0 }')

    RCVD=$(echo $STATS | cut -d' ' -f1)
    SENT=$(echo $STATS | cut -d' ' -f2)

    if [ "$RCVD" -eq "0" ] && [ "$SENT" -eq "0" ]; then
        # No output for empty accounts (Cleaner)
        :
    else
        echo -e "Account: $EMAIL"
        
        # Math: Bytes -> GB with 2 decimal places
        awk -v r="$RCVD" -v s="$SENT" 'BEGIN {
            printf "Bytes:     Sent=%d, Rcvd=%d\n", s, r;
            printf "Kilobytes: Sent=%.2f, Rcvd=%.2f\n", s/1024, r/1024;
            printf "Megabytes: Sent=%.2f, Rcvd=%.2f\n", s/1024/1024, r/1024/1024;
            printf "Gigabytes: Sent=%.2f, Rcvd=%.2f\n", s/1024/1024/1024, r/1024/1024/1024;
        }'
        echo "-----------------------------------"
    fi
done

# Cleanup
rm -f "$TMP_LOG"