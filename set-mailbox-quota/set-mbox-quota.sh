#!/bin/bash
### Copyright 1999-2023. Plesk International GmbH.
​
curl_flags="-sLk"
​hostname="${1:?"Provide hostname as the first argument"}"
admin_pass="${2:?"Provide admin password as the second argument"}"
title="${3:?"Provide file with new title as the third argument"}"
text="${4:?"Provide file with new text as the fourth argument"}"
​[[ ! -f "$title" ]] && echo "File '${title}' does not exist, bailing out" >&2 && exit 1
[[ ! -f "$text" ]] && echo "File '${text}' does not exist, bailing out" >&2 && exit 1
​session="$(curl $curl_flags -vo /dev/null \
    "https://$hostname:8443/login_up.php3" \
    --data-urlencode "login_name=admin" \
    --data-urlencode "passwd=${admin_pass}" \
    --data-urlencode "locale_id=en-US" 2>&1 | \
    grep -Eo 'PLESKSESSID=[^;]*')"
​echo "Extracted session cookie $session"
[[ -z "$session" ]] && echo 'Session cookie appears to be empty, bailing out' >&2 && exit 1
​token="$(curl $curl_flags --cookie "$session" \
    "https://$hostname:8443/" | \
    xmllint --html --xpath 'string(//html/head/meta[@name="forgery_protection_token"]/@content)' -)"
​echo "Extracted forgery protection token $token"
[[ -z "$token" ]] && echo 'Forgery protection token appears to be empty, bailing out' >&2 && exit 1
​echo "Changing the template"
curl $curl_flags -o /dev/null -w "%{http_code}" "https://$hostname:8443/admin/mail-settings/customize-mailbox-quota-warning" \
    -H 'content-type: application/x-www-form-urlencoded; charset=UTF-8' \
    -H "x-forgery-protection-token: $token" \
    --cookie "$session" \
    --data-urlencode "subject@${title}" \
    --data-urlencode "message@${text}" \
    --data-urlencode "hidden=" \
    --data-urlencode "forgery_protection_token=${token}"
