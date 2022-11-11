### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script enables Webdeploy for domains using a service plan providing it
# Requirements : Powershell 5.1
# Version      : 1.0
#########

$Dry = "yes"

function setWebdeploy($DryRun){
    $object_domains = (plesk db -e "
        SELECT
            DISTINCT d.name AS 'dom_name',
            d.id AS 'dom_id',
            h.webdeploy AS 'hosting_webdeploy_status',
            t.name AS 'hosting_plan_name',
            td.value AS 'templdata_val',
            td.element AS 'templdata_name'
        FROM
            domains d
            LEFT JOIN Subscriptions s ON d.id = s.object_id
            LEFT JOIN PlansSubscriptions ps ON s.id = ps.subscription_id
            LEFT JOIN Templates t ON ps.plan_id = t.id
            AND t.type = 'domain'
            LEFT JOIN tmpldata td ON td.tmpl_id = t.id
            LEFT JOIN SubscriptionProperties sp ON s.id = sp.subscription_id
            LEFT JOIN hosting h on d.id = h.dom_id
        WHERE
            td.element = 'webdeploy'
            AND td.value = 'true'
            AND h.webdeploy = 'false';
    ") |ConvertFrom-Csv -Delimiter "`t"

    if($object_domains -ne $nul){
        if($DryRun -eq "update"){
            plesk db dump psa > psa_dump_$(get-date -UFormat "%Y-%m-%d_%H-%M-%S").sql
            $object_domains.dom_id   | ForEach-Object  { plesk db "update hosting set webdeploy='true' where dom_id=$_"}
            $object_domains.dom_name | ForEach-Object  { plesk repair web $_ -y }
        }
        else{
            $object_domains.dom_id   | ForEach-Object  { write-host "plesk db `"update hosting set webdeploy='true' where dom_id=$_`""}
            $object_domains.dom_name | ForEach-Object  { write-host "plesk repair web $_ -y" }
        }
    }
    else{ write-host "No domains found"}
}
