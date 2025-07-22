#!/bin/bash
### Copyright 1999-2025. Plesk International GmbH.

###############################################################################
# This script hashes email accounts passwords in Plesk that are sym encrypted.
# Requirements : bash 4.x, Plesk 18.0.72+ (Linux only)
# Version      : 1.0
###############################################################################

timestamp=$(/bin/date +%Y%m%d-%H%M%S)
LOG=/var/log/plesk/hash-sym-email-accounts-passwords-$timestamp.log
echo >> $LOG
echo "-----------------------------------------------------------------------------" >> $LOG
echo >> $LOG
/bin/date >> $LOG
echo >> $LOG

required_version="18.0.72.0"
plesk_version=$(plesk version | grep 'Product version' | cut -d' ' -f5 | xargs)

if [ -z "$plesk_version" ]; then
    echo "Failed to detect Plesk version." >> $LOG
    echo "Failed to detect Plesk version."
    exit 1
fi

version_ge() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

if ! version_ge "$plesk_version" "$required_version"; then
    echo "Plesk version should be > $required_version. Current version $plesk_version" >> $LOG
    echo "Plesk version should be > $required_version. Current version $plesk_version"
    exit 1
fi

echo "Collecting email addresses and passwords to process..." >> $LOG
output=$(plesk sbin mail_auth_view)
declare -A email_passwords_to_hash
while IFS= read -r line; do
    if [[ $line == *"|"* ]] && [[ $line != *"address"* ]] && [[ $line != *"+"* ]]; then
        line=$(echo "$line" | sed 's/^|//; s/|$//')
        IFS='|' read -r address flags password <<< "$line"
        address=$(echo "$address" | xargs)
        flags=$(echo "$flags" | xargs)
        password=$(echo "$password" | xargs)

        if [[ -z "$flags" ]]; then
            email_passwords_to_hash["$address"]="$password"
        fi
    fi
done <<< "$output"

if [[ ${#email_passwords_to_hash[@]} -eq 0 ]]; then
    echo "No candidates for hashing found." >> $LOG
    echo "No candidates for hashing found."
    exit 0
fi

echo "email addresses and passwords to process count: ${#email_passwords_to_hash[@]}" >> $LOG
echo "email addresses and passwords to process count: ${#email_passwords_to_hash[@]}"

echo "WARNING: This operation is irreversible. It is strongly recommended to create a backup before proceeding."

read -p "Do you want to continue? (y/n): " user_input
if [[ "$user_input" != "y" ]]; then
    echo "Operation canceled by the user." >> $LOG
    echo "Operation canceled by the user."
    exit 0
fi

echo "Checking the status of email-password-hashing..." >> $LOG
hashing_status=$(plesk bin server_pref -s | grep email-password-hashing | cut -d':' -f2 | xargs)

if [[ $hashing_status == "false" ]]; then
    echo "email-password-hashing is disabled. Enabling it now..." >> $LOG
    plesk bin server_pref -u -email-password-hashing true >> $LOG 2>&1
else
    echo "email-password-hashing is already enabled." >> $LOG
fi

for email in "${!email_passwords_to_hash[@]}"; do
    password="${email_passwords_to_hash[$email]}"

    echo "Hashing password for $email..." >> $LOG
    env PSA_PASSWORD="$password" plesk bin mail --update "$email" -passwd '' >> $LOG 2>&1
done

if [[ $hashing_status == "false" ]]; then
    echo "Restoring email-password-hashing to disabled state..." >> $LOG
    plesk bin server_pref -u -email-password-hashing false >> $LOG 2>&1
fi

echo >> $LOG
echo "Done!"
echo "Done!" >> $LOG
