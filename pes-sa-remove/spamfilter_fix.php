<?php

### Copyright 1999-2025. WebPros International GmbH.

###############################################################################
# This script shows addresses in spamfilter and spamfilter_preference that are not present in Plesk.
# Requirements : >php7.4, GNU coreutils
# Version      : 1.2
#########
$shortOptions = "fh";
$longOptions = ["fix", "help"];
$options = getopt($shortOptions, $longOptions);

$usage = "Here is the list of the available options: \n
-f, --fix      If this option is defined the affected mailboxes will be removed from the SpamAssassin table;
-h, --help     Show the script usage;\n";

if (isset($options["h"]) || isset($options["help"])) {
    print($usage);
    exit;
}

/**
 * Executes a PDO query and returns the result.
 *
 * @param string $query The SQL query to execute.
 * @param array $args The arguments for the SQL query.
 * @return array The result of the query.
 */
function pdoQuery($query, $args)
{
    $host = '127.0.0.1';
    $db = 'psa';
    $dbUser = 'admin';
    $dbPass = trim(file_get_contents('/etc/psa/.psa.shadow', false));
    
    $dsn = "mysql:host=$host;dbname=$db";

    try {
        $sqlConn = new PDO($dsn, $dbUser, $dbPass);
        $stmt = $sqlConn->prepare($query);
        $stmt->execute($args);
    
        $data = $stmt->fetchAll();
    } catch (PDOException $error) {
        echo $error->getMessage();
    }

    return $data;
}

/**
 * Retrieves the list of mailboxes from the spamfilter table.
 *
 * @return array The list of mailboxes.
 */
function getMboxList()
{
    $query = "SELECT id, username FROM spamfilter";
    $args = [];

    $data = pdoQuery($query, $args);
    return $data;
}

/**
 * Checks if a mailbox exists in the mail table.
 *
 * @param string $mbox The mailbox to check.
 * @return array The result of the check.
 */
function checkMbox($mbox)
{
    [$login, $domain] = explode("@", $mbox);

    $query = "SELECT 
               mail.mail_name, 
               mail.dom_id 
             FROM mail 
             LEFT JOIN domains 
             ON mail.dom_id = domains.id 
             WHERE 
             mail.mail_name = :login 
             AND domains.name = :domain";
    $args = [
        ':login' => $login,
        ':domain' => $domain
    ];
    $data = pdoQuery($query, $args);
    return $data;
}

/**
 * Checks if a domain exists in the domains table.
 *
 * @param string $mbox The mailbox to check.
 * @return array The result of the check.
 */
function checkDomain($mbox)
{
    [$login, $domain] = explode("@", $mbox);

    $query = "SELECT id, name FROM domains WHERE name = :domain";
    $args = [':domain' => $domain];

    $data = pdoQuery($query, $args);
    return $data;
}

/**
 * Removes records related to a mailbox from the spamfilter tables.
 *
 * @param int $mboxId The ID of the mailbox to remove.
 * @return bool True if the records were removed, false otherwise.
 */
function removeRecords($mboxId)
{
    $query1 = "DELETE FROM spamfilter_preferences WHERE spamfilter_id = :mbox_id";
    $query2 = "DELETE FROM spamfilter WHERE id = :mbox_id";
    $args = [':mbox_id' => $mboxId];

    $del1 = pdoQuery($query1, $args);
    $del2 = pdoQuery($query2, $args);

    $rm = false;

    if (count($del1) === 0 && count($del2) === 0) {
        $rm = true;
    }

    return $rm;
}

/**
 * Checks and optionally repairs the spamfilter table.
 *
 * @param bool $fix Whether to fix the incorrect records.
 */
function checkRepair($fix)
{
    $mboxes = getMboxList();

    foreach ($mboxes as $box) {
        if ($box['username'] == "*@*") {
            continue;
        }

        $check = false;
        $checkMb = checkMbox($box['username']);
        $checkDom = checkDomain($box['username']);

        if (count($checkMb) === 0 || count($checkDom) === 0) {
            $check = true;
        }
        
        if ($check) {
            print("The SpamAssassin contains the records about non-existent mailbox " . $box['username'] . ".\n");
            
            if ($fix) {
                print("Start removal... \n");
                $fmb = removeRecords($box['id']);

                if ($fmb) {
                    print("The records were removed. \n");
                } else {
                    print("The records were not removed. \n");
                }
            }
        }
    }
    exit;
}

if (isset($options["f"]) || isset($options["fix"])) {
    $fix = true;
    print("Start the checks with the automatic removal of the incorrect records ...\n");
} else {
    $fix = false;
    print("Start the checks. The incorrect records will not be automatically removed ...\n");
}

$fixMbox = checkRepair($fix);