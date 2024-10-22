<?php
### Copyright 1999-2024. WebPros International GmbH.

###############################################################################
# This script shows addresses in spamfilter and spamfilter_preference that are not present in Plesk.
# Requirements : >php7.4, GNU coreutils
# Version      : 1.1
#########
$short_options = "fh";
$long_options = ["fix","help"];
$options = getopt($short_options, $long_options);

$usage = "Here is the list of the available options: \n
-f, --fix      If this option is defined the affected mailboxes will be removed from the SpamAssassin table;
-h, --help     Show the script usage;\n";

if (isset($options["h"]) || isset($options["help"])) {
    print($usage);
    exit;
}

function SqlQuery($query){
    //Function for calling MySQL

    $mysql_pass = trim(file_get_contents('/etc/psa/.psa.shadow', false));
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    $mysql = new mysqli('localhost', 'admin', $mysql_pass, 'psa');

    $q_result = mysqli_query($mysql,$query);

    return $q_result;
}

function RemoveRecords($box_id){
    //Removing the incorrect records from the SpamFilter table

    $r_pref_query = "delete from spamfilter_preferences where spamfilter_id = $box_id";
    $r_pref = SqlQuery($r_pref_query);
    
    $r_filt_query = "delete from spamfilter where id = $box_id";
    $r_filr = SqlQuery($r_filt_query);
}

function GetListMaiboxes(){
    //Getting the list of the mailboxes that exist in the SpamFilter table

    $l_mailbox_query = "SELECT id, username FROM spamfilter";
    $l_mailbox = SqlQuery($l_mailbox_query);

    $mboxes = [];

    $row = mysqli_fetch_array($l_mailbox);
    while ($row = mysqli_fetch_array($l_mailbox)) {
        $mboxes[] = $row;
    }

    return $mboxes;
}

function CheckMailbox($mbox){
    //Comparing the mailboxes in Plesk and in the SpamFilter tables

    [$login, $domain] = explode("@", $mbox);

    $d_check_query = "select id, name from domains where name = '$domain'";
    $d_check = SqlQuery($d_check_query);

    $mb_check_query = "select 
                        mail.mail_name, 
                        mail.dom_id 
                    from mail 
                    left join domains 
                    on mail.dom_id = domains.id 
                    where 
                    mail.mail_name = '$login' 
                    and domains.name = '$domain'";
    $mb_check = SqlQuery($mb_check_query);

    $affected = false;

    if (mysqli_num_rows($d_check) == 0|| mysqli_num_rows($mb_check) == 0) {
        $affected = true;
    }

    return $affected;
}

function Check(){
    print("Starting checking ...\n");
    $mboxes = GetListMaiboxes();

    $affected_mailboxes = [];

    foreach($mboxes as $box) {
        if ($box['username'] == "*@*") continue;

        $check = CheckMailbox($box['username']);

        if($check == true){
            $affected_mailboxes[] = $box;
        }
    }

    print("Checks finished. List of the affected mailboxes: \n");
    foreach($affected_mailboxes as $mb) {
        print($mb['username']."\n");
    }

    return $affected_mailboxes;
}

function Fix($fix_list){
    //Call remove action based on checks result

    $fixed_mailboxes = [];

    foreach($fix_list as $box) {
        
        $fix = RemoveRecords($box['id']);

        $fixed_mailboxes[] = $box;
    }

    return $fixed_mailboxes;
}

$affected_mboxes = Check();

if (isset($options["f"]) || isset($options["fix"])) {
    print("Start the fixing ...\n");

    $fix_mbox = Fix($affected_mboxes);

    print("Fix finished. List of the mailboxes that were removed from the SpamFilter tables: \n");
    foreach($fix_mbox as $mb) {
        print($mb['username']."\n");
    }
    exit;
} else {
    exit;
}