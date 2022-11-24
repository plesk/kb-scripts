#!/usr/bin/env python3
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script helps to configure the PHP-FPM plugin for 360 Monitoring
# Requirements : Python 3.x
# Version      : 1.1
#########

from subprocess import Popen, call, PIPE
from sys import version_info
from os import get_terminal_size, remove
from re import sub


# ==================
# Defined variables
# ==================

#--------
# Common
#--------

defaultDir = '/usr/local/psa/admin/conf/templates/default/domain/'
customDir = '/usr/local/psa/admin/conf/templates/custom/domain/'
checkDir = '[ -d "/usr/local/psa/admin/conf/templates/custom/domain/" ] && echo 1 || echo 0'
checkFile = '[ -f "/usr/local/psa/admin/conf/templates/custom/domain/{}" ] && echo 1 || echo 0'
checkTemplate = 'grep "status_phpfpm" /usr/local/psa/admin/conf/templates/custom/domain/{} > /dev/null && echo 1 || echo 0'
createCustomDir = 'mkdir -p /usr/local/psa/admin/conf/templates/custom/domain/'
copyTemplate = 'cp -a /usr/local/psa/admin/conf/templates/default/domain/{0} /usr/local/psa/admin/conf/templates/custom/domain/{0}'
pleskLicenseCheck = 'plesk bin license -c'
getDomainList = 'plesk bin site -l'
checkAvailability = 'curl -s -o /dev/null -w "%{{http_code}}" {}'


#--------
# Arrays
#--------

urlsList = []
domainList = []
apacheDomains = []
nginxDomains = []
unavailableDomains = []


#--------
# Apache
#--------

searchApacheLine = 'Redirect permanent /awstats-icon https://<?php echo $VAR->domain->urlName ?>/awstats-icon'
apacheTemplateFile = 'domainVirtualHost.php'
targetApacheSection = """<?php if ($OPT['ssl'] || !$VAR->domain->physicalHosting->ssl): ?>
    Alias "/plesk-stat" "<?php echo $VAR->domain->physicalHosting->statisticsDir ?>"
        ...
    Redirect permanent /awstats-icon https://<?php echo $VAR->domain->urlName ?>/awstats-icon
<?php endif; ?>

<?php endif; ?>"""
pluginConfApache = """\n<?php if ($VAR->domain->active && $VAR->domain->physicalHosting->php && !$VAR->domain->physicalHosting->proxySettings['nginxServePhp']): ?>
        <LocationMatch "/status_phpfpm">
                Require local
                ProxyPass unix://<?php echo $VAR->server->webserver->vhostsDir ?>/system/<?php echo $VAR->domain->targetName; ?>/php-fpm.sock|fcgi://127.0.0.1:9000
        </LocationMatch>
<?php endif; ?>\n"""


#-------
# Nginx
#-------

searchNginxLine = '        <?php if ($VAR->domain->physicalHosting->directoryIndex && !$VAR->domain->physicalHosting->proxySettings[\'nginxProxyMode\']): ?>'
nginxTemplateFile = 'nginxDomainVirtualHost.php'
targetNginxSection = '<?php if ($VAR->domain->active && $VAR->domain->physicalHosting->php && $VAR->domain->physicalHosting->proxySettings[\'nginxServePhp\']): ?>'
pluginConfNginx = """\n    location ~ ^/status_phpfpm$ {
        allow <?php echo $OPT['ipAddress']->escapedAddress; ?>;
        deny all;
        fastcgi_split_path_info ^((?U).+\.php)(/?.+)$;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_pass "unix://<?php echo $VAR->server->webserver->vhostsDir ?>/system/<?php echo $VAR->domain->targetName; ?>/php-fpm.sock";
        include /etc/nginx/fastcgi.conf;
    }\n"""


#-----
# PHP
#-----

checkPHPServe = 'plesk db -Nse "SELECT value FROM WebServerSettingsParameters WHERE webServerSettingsId = (SELECT val FROM dom_param WHERE param = \'webServerSettingsId\' AND dom_id = (SELECT id FROM domains WHERE name = \'{}\')) AND name = \'nginxServePhp\'"'
checkPHPAdditionalSettings = 'grep -irl \'pm.status_path = /status_phpfpm\' /opt/plesk/php/*/etc/php-fpm.d/{}.conf && echo 1 || echo 0'
phpUpdate = 'plesk bin site --update-php-settings {} -additional-settings tmpfile'


#-----------
# Agent 360
#-----------

agentConfFile = '/etc/agent360.ini'
phpFPMConf = """\n[phpfpm]
enabled = yes\n"""
statusPageLine = 'status_page_url ='
statusPageUrlSearch = 'status_page_url'
agentRestart = 'systemctl restart agent360'
checkConf = 'grep \'\[phpfpm\]\' /etc/agent360.ini > /dev/null && echo 1 || echo 0'
parseConf = 'sed -n "/^\[phpfpm\]$/,/^\[/p" /etc/agent360.ini'


#---------------------
# Auxiliary functions
#---------------------

def printFunc(textToPrint = ""):
    if version_info[0] >= 3:
        print(textToPrint)
    else:
        print(textToPrint.strip('()'))

def prRed(textToPrint):
    printFunc("\033[91m {}\033[00m".format(textToPrint))

def prGreen(textToPrint):
    printFunc("\033[92m {}\033[00m".format(textToPrint))

def prBlue(textToPrint):
    printFunc("\033[96m {}\033[00m".format(textToPrint))

def getIndex(string, file):
    with open(file) as f:
        for i, line in enumerate(f):
            if string in line:
                return i

def adjustTemplate(tplFile, searchLine, pluginConf, index):
    with open(defaultDir + tplFile, 'r') as template:
        tplData = template.readlines()

    tplData.insert(getIndex(searchLine, defaultDir + tplFile) + index, pluginConf)

    with open(customDir + tplFile, 'w') as template:
        tplData = "".join(tplData)
        template.write(tplData)

def fillTheLine(symbol, multiplier = 0):
    columns, rows = get_terminal_size()
    if multiplier == 0:
        multiplier = columns - 5
    return symbol * multiplier



# ===================
# Preliminary checks
# ===================
licenseCheck = Popen(pleskLicenseCheck, stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
out, err = licenseCheck.communicate()
if '1' in err:
    printFunc()
    prRed("[!] Unable to proceed further due to the invalid Plesk license")
    printFunc(" Please install a valid license and restart the script once again")
    printFunc()
    quit()


# ============================================
# Generate lists of the domains on the server
# ============================================

prBlue(fillTheLine("*", 45))
prBlue(">>> Checking the domains on the servers...")
prBlue(fillTheLine("*", 45))
printFunc()

# Generate a list of all domains on the server
domains = Popen(getDomainList, stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
for domain in domains.stdout:
    domainList.append(domain.rstrip())

domainList.remove('example.com')

# Check the availability of the domains and group them
for d in domainList:
    statusCode = Popen(checkAvailability.format('https://' + d), stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
    sCode = statusCode.stdout.readline()
    if '30' in sCode:
        statusCodeWww = Popen(checkAvailability.format('https://www.' + d), stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
        sCodeWww = statusCodeWww.stdout.readline()
        if '200' not in sCodeWww:
            unavailableDomains.append(d)
    elif '200' in sCode:
        nginxApachePhp = Popen(checkPHPServe.format(d), stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
        serveBool = nginxApachePhp.stdout.readline()
        if 'true' in serveBool:
            nginxDomains.append(d)
        elif 'false' in serveBool:
            apacheDomains.append(d)
        else:
            unavailableDomains.append(d)
    else:
        unavailableDomains.append(d)

prGreen("[+] The list of the domains on the server has been processed successfully")
printFunc()
prBlue(fillTheLine("-"))
printFunc()


# ==================
# Analyze templates
# ==================

prBlue(fillTheLine("*", 51))
prBlue(">>> Checking the current state of the templates...")
prBlue(fillTheLine("*", 51))
printFunc()

# Check if the custom templates exist in general
isDirExists = Popen(checkDir, stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
if '1' in isDirExists.stdout.readline():
    isNginxFileExists = Popen(checkFile.format(nginxTemplateFile), stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
    isApacheFileExists = Popen(checkFile.format(apacheTemplateFile), stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)

# Look for the Nginx template
    if '1' in isNginxFileExists.stdout.readline():
        isTemplateExists = Popen(checkTemplate.format(nginxTemplateFile), stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
        if '1' in isTemplateExists.stdout.readline():
            printFunc(" [!] The Nginx template already contains the data about PHP-FPM status")
            printFunc(" [!] Please parse it manually to check the consistency")
            printFunc()
        else:
            prRed("[-] The Nginx custom template already exists. Please adjust it manually")
            printFunc()
    else:
        printFunc(" Creating the necessary Nginx template file...")
        call(copyTemplate.format(nginxTemplateFile), stdout=PIPE, stderr=PIPE, shell=True)
        adjustTemplate(nginxTemplateFile, searchNginxLine, pluginConfNginx, -1)
        prGreen("[+] The Nginx template has been created")
        printFunc()

# Look for the Apache template
    if '1' in isApacheFileExists.stdout.readline():
        isTemplateExists = Popen(checkTemplate.format(apacheTemplateFile), stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
        if '1' in isTemplateExists.stdout.readline():
            printFunc(" [!] The Apache template already contains the data about PHP-FPM status")
            printFunc(" [!] Please parse it manually to check the consistency")
            printFunc()
        else:
            prRed("[-] The Apache custom template already exists. Please adjust it manually")
            printFunc()
    else:
        printFunc(" Creating the necessary template file...")
        call(copyTemplate.format(apacheTemplateFile), stdout=PIPE, stderr=PIPE, shell=True)
        adjustTemplate(apacheTemplateFile, searchApacheLine, pluginConfApache, 4)
        prGreen("[+] The Apache template has been created")
        printFunc()
else:
    printFunc(" Creating the necessary template file")
    call(createCustomDir, stdout=PIPE, stderr=PIPE, shell=True)
    call(copyTemplate.format(nginxTemplateFile), stdout=PIPE, stderr=PIPE, shell=True)
    call(copyTemplate.format(apacheTemplateFile), stdout=PIPE, stderr=PIPE, shell=True)

    adjustTemplate(nginxTemplateFile, searchNginxLine, pluginConfNginx, -1)
    printFunc()
    prGreen("[+] The Nginx template has been created")
    adjustTemplate(apacheTemplateFile, searchApacheLine, pluginConfApache, 4)
    printFunc()
    prGreen("[+] The Apache template has been created")

prBlue(fillTheLine("-"))
printFunc()


# ====================
# Update PHP Settings
# ====================

prBlue(fillTheLine("*", 43))
prBlue(">>> Starting of the PHP Settings update...")
prBlue(fillTheLine("*", 43))
printFunc()

# Create a temporary file
with open("tmpfile", "w") as tmpFile:
    tmpFile.write("[php-fpm-pool-settings]\npm.status_path = /status_phpfpm")

# Adjust the configuration
for d in (nginxDomains + apacheDomains):
    isPHPAdditionalSettings = Popen(checkPHPAdditionalSettings.format(d), stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
    if '1' in isPHPAdditionalSettings.stdout.readline():
        printFunc(" Update PHP Settings for the domain " + d + "...")
        call = call(phpUpdate.format(d), stdout=PIPE, stderr=PIPE, shell=True)

printFunc()
prGreen("[+] The PHP Settings have been adjusted")
printFunc()

# Remove the temporary file
remove("tmpfile")

prBlue(fillTheLine("-"))
printFunc()


# ===========================
# Update the plugin settings
# ===========================

prBlue(fillTheLine("*", 79))
prBlue(">>> Adjusting the PHP-FPM plugin configuration for the 360 Monitoring agent...")
prBlue(fillTheLine("*", 79))
printFunc()

# Generate a list of links to the status pages of all configured domains
for d in (nginxDomains + apacheDomains):
    urlsList.append('https://' + d.rstrip() + '/status_phpfpm?json')

# Prepare the necessary line fot the agent360 configuration file
for url in urlsList:
    statusPageLine += ' ' + url + ','

# Remove the trailing comma
statusPageLine = statusPageLine[:-1] + "\n\n"

# Check the current configuration and adjust it to enable PHP-FPM for all prepared domains
isPluginEnabled = Popen(checkConf, stdout=PIPE, stderr=PIPE, universal_newlines=True, shell=True)
if '1' in isPluginEnabled.stdout.readline():
    phpSection = getIndex('[phpfpm]',agentConfFile)
    with open(agentConfFile, "r") as conf:
        confContent = conf.readlines()
    for i in confContent:
        itemIndex = confContent.index(i)
        if statusPageUrlSearch in i:
            if not (phpSection - itemIndex) >= 0:
                confContent[itemIndex] = statusPageLine
    with open(agentConfFile, "w") as conf:
        confContent = "".join(confContent)
        confContent = sub(r'\n\s*\n', '\n\n', confContent)
        conf.write(confContent)
else:
    with open(agentConfFile, "a+") as conf:
        conf.write(phpFPMConf + statusPageLine)

prGreen("[+] The plugin configuration has been adjusted")
printFunc()
prBlue(fillTheLine("-"))
printFunc()


# ====================================
# Restarting the 360 Monitoring agent
# ====================================

prBlue(fillTheLine("*", 57))
prBlue(">>> Restarting the service to apply the configuration...")
prBlue(fillTheLine("*", 57))
printFunc()
restart = call(agentRestart, stdout=PIPE, stderr=PIPE, shell=True)

prGreen("[+] The command to restart the service has been executed")
printFunc()
prBlue(fillTheLine("-"))
printFunc()


# =========================================
# Show the list of the unavailable domains
# =========================================

if unavailableDomains:
    printFunc()
    prRed(fillTheLine("="))
    prRed("<!!! ATTENTION !!!>")
    prRed("The following domains are unavailable (e.g. unresponsive, have an invalid SSL certificate, unresolvable, etc.):")
    printFunc()

    for d in unavailableDomains:
        prBlue(d)

    printFunc()
    prRed("[-] The configuration for the domains were not applied.")
    printFunc()
