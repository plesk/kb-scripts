<?php
### Copyright 1999-2024. WebPros International GmbH.

###############################################################################
# This script removes addresses from spamfilter and spamfilter_preference that are not present in Plesk.
# Requirements : >php7.4, GNU coreutils
# Version      : 1.0
#########
$mysql_pass = trim(file_get_contents('/etc/psa/.psa.shadow', false));

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

$mysql = new mysqli('localhost', 'admin', $mysql_pass, 'psa');

$get_list_username_spamfilter = mysqli_query($mysql, "SELECT id, username FROM spamfilter");

print "Start the checking and fixing of the spamfilter table \n";

while ($mailboxes = mysqli_fetch_array($get_list_username_spamfilter)) 
{
    if ($mailboxes['username'] == "*@*") continue;
    [$login, $domain] = explode("@", $mailboxes['username']);

    $checking_domain = mysqli_query($mysql, "select id, name from domains where name = '$domain'");
    if (mysqli_num_rows($checking_domain) == 0)
    {
        print ("========================================================================================================== \n");
        print ("Domain '$domain' does not exist in Plesk. The rows about the mailbox {$login}@{$domain} will be removed from the SpamAssassin tables \n");
        $removing_pref = mysqli_query($mysql, "delete from spamfilter_preferences where spamfilter_id = $mailboxes[id]");
        $removing_filter = mysqli_query($mysql, "delete from spamfilter where id = $mailboxes[id]");
        print ("The rows related to mailbox {$login}@{$domain} have been removed\n");
        print ("========================================================================================================== \n");
    }
    else {
        $sql = "select 
                    mail.mail_name, 
                    mail.dom_id 
                from mail 
                left join domains 
                on mail.dom_id = domains.id 
                where 
                mail.mail_name = '$login' 
                and domains.name = '$domain'";
        $checking_user = mysqli_query($mysql, $sql);
        if (mysqli_num_rows($checking_user) == 0)
        {
            print ("========================================================================================================== \n");
            print ("Mailbox {$login}@{$domain} does not exist in Plesk. The rows about this mailbox will be removed from the SpamAssassin tables \n");
            $removing_pref = mysqli_query($mysql, "delete from spamfilter_preferences where spamfilter_id = $mailboxes[id]");
            $removing_filter = mysqli_query($mysql, "delete from spamfilter where id = $mailboxes[id]");
            print ("The rows related to mailbox {$login}@{$domain} have been removed\n");
            print ("========================================================================================================== \n");
        }
    }
}

print ("All rows related to not existing domains or mailboxes have been removed \n");
