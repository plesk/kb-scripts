### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script retrieves FastCGI settings of sites from IIS
# Requirements : Powershell 5.1
# Version      : 1.0
#########

[xml]$apphost = get-content -path "C:\Windows\System32\inetsrv\config\applicationHost.config"
function getDomainFCGISettings($domain){
    #retrieve info about site for id
    $site = $apphost.configuration."system.applicationHost".sites.site
    $site_id = $site | Select-Object name, id |Where-Object name -eq "$($domain)"

    #retrieve fastcgi config
    $site_config = $apphost.configuration."system.webServer".fastCgi.application

    $site_fcgisettings = $site_config | Select-Object arguments, activityTimeout, instanceMaxRequests, MaxInstances | Where-Object arguments -eq "-d siteId=$($site_id.id)"
    
    # print FCGI Settings
    "Site               :`t" + $site_id.name
    "MaxInstances       :`t" + $site_fcgisettings.MaxInstances
    "activityTimeout    :`t" +$site_fcgisettings.activityTimeout
    "instanceMaxRequests:`t" + $site_fcgisettings.instanceMaxRequests
    "----------------------------------------------------------------"

}

# To retrieve data of a single domain, replace example.com with the domain name and comment all following lines:
#getDomainFCGISettings("example.com")

# Or retrieve data of all domains hosted in Plesk:
foreach ($domain in $(plesk bin domain -l)){
getDomainFCGISettings("$domain")
}