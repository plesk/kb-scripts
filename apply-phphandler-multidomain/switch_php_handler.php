<?php

### Copyright 1999-2023. Plesk International GmbH.

###############################################################################
# This script switch a specific PHP handler to another one
# Requirements : bash 3.x, mysql-client, >php7.4, GNU coreutils
# Version      : 1.7
#########

$shortOpts = "h";
$longOpts = [
    "old:",
    "new:",
    "ngx:",
    "include-disabled:",
    "help"
];
$inputOpts = getopt($shortOpts, $longOpts);
$invalidParams = [
    "old" => "false",
    "old-required" => "false",
    "new" => "false",
    "new-required" => "false",
    "ngx" => "false",
    "ngxcombination" => "false",
    "include-disabled" => "false"
];

function getHelp()
{
    echo "[i] Available command arguments:\n";
    echo "\t--old\t(Required) Current PHP Handler ID assigned to the domains\n";
    echo "\t--new\t(Required) New PHP Handler ID to be assigned to the domains\n";
    echo "\t--ngx\t(Default: false) Set this variable to true when the PHP FPM Handler has to be managed by Nginx\n";
    echo "\t--include-disabled\t(Default: false) Set this variable to true when the PHP Handler must be updated to the domains with PHP disabled\n\n";
    echo "[i] Check installed and enabled PHP handlers with the following command:\nplesk bin php_handler --list\n";
    exit(0);
}

function handleError($invalidParams)
{
    echo "[!] Error encountered:\n";
    if ($invalidParams['old'] === 'true') {
        echo "[!] Old PHP Handler is not installed or enabled: ".$GLOBALS['inputOpts']['old']."\n";
    }
    if ($invalidParams['old-required'] === 'true') {
        echo "[!] Old PHP Handler parameter '--old' must be defined\n";
    }
    if ($invalidParams['new'] === 'true') {
        echo "[!] New PHP Handler is not installed or enabled: ".$GLOBALS['inputOpts']['new']."\n";
    }
    if ($invalidParams['new-required'] === 'true') {
        echo "[!] New PHP Handler parameter '--new' must be defined\n";
    }
    if ($invalidParams['ngx'] === 'true') {
        echo "[!] Parameter '--ngx' must be boolean: true or false\n";
    }
    if ($invalidParams['ngxcombination'] === 'true') {
        echo "[!] Parameter '--ngx' can be enabled ONLY with FPM handler: ".$GLOBALS['inputOpts']['new']."\n";
    }
    if ($invalidParams['include-disabled'] === 'true') {
        echo "[!] Parameter '--include-disabled' must be boolean: true or false\n";
    }
    echo "[i] Run utility with '-h' or '--help' for instructions\n";
    exit("[!] Exiting...\n");
}

if (array_key_exists("h", $inputOpts) || array_key_exists("help", $inputOpts)) {
    getHelp();
}
if (!array_key_exists("ngx", $inputOpts)) {
    $inputOpts['ngx'] = 'false';
}
if (!array_key_exists("include-disabled", $inputOpts)) {
    $inputOpts['include-disabled'] = 'false';
}
if (!array_key_exists("old", $inputOpts)) {
    $invalidParams['old-required'] = 'true';
}
if (!array_key_exists("new", $inputOpts)) {
    $invalidParams['new-required'] = 'true';
}
if ($inputOpts['ngx'] !== 'true' && $inputOpts['ngx'] !== 'false') {
    $invalidParams['ngx'] = 'true';
}
if ($inputOpts['ngx'] === 'true' && substr($inputOpts['new'], -3) !== 'fpm') {
    $invalidParams['ngxcombination'] = 'true';
}
if ($inputOpts['include-disabled'] !== 'true' && $inputOpts['include-disabled'] !== 'false') {
    $invalidParams['include-disabled'] = 'true';
}
if (in_array("true", $invalidParams)) {
    handleError($invalidParams);
}

echo "[i] Information [!] Warning [+] Action [-] Skipped\n";
echo "----------\n[i] Retrieving installed PHP Handlers...\n";

$instHandlers = json_decode(shell_exec('plesk bin php_handler --list-json 2>/dev/null'), true);
$invalidParams['old'] = 'true';
$invalidParams['new'] = 'true';

foreach ($instHandlers as $handler) {
    if ($inputOpts['old'] === $handler['id'] && $handler['status'] === 'enabled') {
        $invalidParams['old'] = 'false';
    }
    if ($inputOpts['new'] === $handler['id'] && $handler['status'] === 'enabled') {
        $invalidParams['new'] = 'false';
    }
}

if (in_array("true", $invalidParams)) {
    handleError($invalidParams);
}
echo "[i] Checking domains assigned to PHP Handler ID ".$inputOpts['new']."...\n";
$dbdataCmd = shell_exec("plesk db -Ne \"SELECT d.name, h.php, h.php_handler_id FROM domains d, hosting h WHERE d.id=h.dom_id AND d.htype = 'vrt_hst'\"");
$dbdata = explode("\n", $dbdataCmd);
$dbdataLength = count($dbdata)-1;
$updatePerformed = 'false';

for ($i = 0; $i < $dbdataLength; $i++) {
    $tempArray = explode("\t", $dbdata[$i]);
    $domainName = $tempArray[0];
    $phpEnabled = $tempArray[1];
    $phpHandlerId = $tempArray[2];
    if ($phpHandlerId === $inputOpts['old']) {
        switch ($phpEnabled) {
            case 'true':
                echo "[+] Updating domain " . $domainName . " with PHP enabled: " . $inputOpts['old'] . " --> " . $inputOpts['new'] . "\n";
                $commandStx = "plesk bin domain -u " . $domainName . " -php_handler_id " . $inputOpts['new'] . " -nginx-serve-php " . $inputOpts['ngx'];
                $runUpdate = shell_exec($commandStx);
                $updatePerformed = 'true';
                break;
            case 'false':
                if ($inputOpts['include-disabled'] === 'true') {
                    echo "[+] Updating domain " . $domainName . " with PHP disabled: " . $inputOpts['old'] . " --> " . $inputOpts['new'] . "\n";
                    $commandStxEnable = "plesk bin domain -u " . $domainName . " -php true -php_handler_id " . $inputOpts['new'] . " -nginx-serve-php " . $inputOpts['ngx'];
                    $commandStxDisable = "plesk bin domain -u " . $domainName . " -php false";
                    $runEnable = shell_exec($commandStxEnable);
                    $runDisable = shell_exec($commandStxDisable);
                    $updatePerformed = 'true';
                } else {
                    echo "[-] Domain " . $domainName . " with PHP disabled not modified: " . $inputOpts['old'] . "\n";
                }
                break;
            default:
                echo "[!] Unexpected error:\n";
                echo "[!] Domain: " . $domainName . "\n";
                echo "[!] PHP enabled in domain: " . $phpEnabled . "\n";
                echo "[!] Current PHP Handler: " . $phpHandlerId . "\n";
                echo "[!] InputArray: " . json_encode($inputOpts) . "\n";
                exit("[!] Exiting...\n");
        }
    }
}

if ($updatePerformed === 'false') {
    echo "[i] The PHP handler ID " . $inputOpts['new'] . " has not been assigned to any domain\n";
}