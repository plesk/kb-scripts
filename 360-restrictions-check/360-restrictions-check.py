#!/usr/bin/env python

### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script helps to check whether there are any restriction to add a server to Plesk 360
# Requirements : Python 2.7 or 3.x
# Version      : 1.0
#########

import subprocess
import sys

ipAddresses = ['52.51.23.204', '52.213.169.7', '34.254.37.129']

# Define functions to calculate IP addresses and subnets
def ipConvert(ip):
	octets = ip.split('.')
	binOctets = '{0:08b}'.format(int(octets[0])) + '{0:08b}'.format(int(octets[1])) + '{0:08b}'.format(int(octets[2])) + '{0:08b}'.format(int(octets[3]))
	return binOctets

def calculateCIDR(mask):
	convertedMask = ipConvert(mask)
	cidr = convertedMask.count('1')
	return cidr

def startIP(range):
	if '/' in range:
		ip = range.split('/')[0]
		mask = range.split('/')[1]
	else:
		ip = range
		mask = '32'
	sIP = ipConvert(ip)[:int(mask)] + '0' * (32 - int(mask))
	return sIP

def endIP(range):
	if '/' in range:
		ip = range.split('/')[0]
		mask = range.split('/')[1]
	else:
		ip = range
		mask = '32'
	eIP = ipConvert(ip)[:int(mask)] + '1' * (32 - int(mask))
	return eIP
	
def checkIpInSubnet(ip, start, end):
	if int(start, 2) <= int(ip, 2) <= int(end, 2):
		return True
	else:
		return False


# Define functions to find and compare elements
def checkIfInList(list, itemone, itemtwo):
	result = False
	for sublist in list:
		if itemone in sublist:
			if itemtwo in sublist:
				result = True
				break
	return result

def getPosition(list, itemone, itemtwo):
	for sublist in list:
		if itemone in sublist:
			if itemtwo in sublist:
				return str(list.index(sublist)) + " " + str(sublist.index(itemtwo))
				break
			
def comparePositions(first, second):
	if int(first.split()[0]) < int(second.split()[0]):
		return True
	else:
		return False


# Define colored output for print and re-define print based on the Python version
def printFunc(textToPrint = ""):
	if sys.version_info[0] >= 3:
		print(textToPrint)
	else:
		print(textToPrint.strip('()'))

def prRed(textToPrint):
	printFunc("\033[91m {}\033[00m" .format(textToPrint))
	
def prGreen(textToPrint):
	printFunc("\033[92m {}\033[00m" .format(textToPrint))
	
def prBlue(textToPrint):
	printFunc("\033[96m {}\033[00m" .format(textToPrint))


# Check Cloudflare
errCCode = False
getPleskHostname = 'plesk db -Nse "select val from misc where param = \'FullHostName\'"'
resolveIPList = []
commandC = 'curl --silent -I {} | grep Server | cut -f 2 -d ":"'
cArticle = "https://support.plesk.com/hc/en-us/articles/4408702163218"

prBlue("=========================================================")
prBlue("Checking whether the server is behind Cloudflare:")
prBlue("=========================================================")
printFunc()

getServerHostname = subprocess.Popen(getPleskHostname, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=True)
serverHostname = getServerHostname.stdout.readline()
getIP = 'dig +short @8.8.8.8 ' + serverHostname

resolveIP = subprocess.Popen(getIP, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=True)

for ip in resolveIP.stdout:
	resolveIPList.append(ip.rstrip())

for item in resolveIPList:
	checkCIP = commandC.format(item)
	checkCloudflare = subprocess.Popen(checkCIP, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=True)
	if 'cloudflare' in checkCloudflare.stdout.readline():
		errCCode = True
		prRed("The server is behind Cloudflare")
		prRed("Please disable proxying in Cloudflare or use the workaround")
		break
	else:
		prGreen("The server is not behind Cloudflare")
		break

if errCCode:
		printFunc()
		prRed(">>> Here is the article for help: " + cArticle)

printFunc()


# Check firewall rules
listRules = []
checkDropRule = False
checkAllowRule = False
positionAllowDrop = True
errFCode = False
fArticle = "https://support.plesk.com/hc/en-us/articles/115001078014"

prBlue("================================")
prBlue("Checking firewall rules:")
prBlue("================================")
printFunc()

commandF = 'iptables -nvL | grep :8443 | awk \'{print $3, $8}\''
firewallOutput = subprocess.Popen(commandF, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=True)
outData, errData = firewallOutput.communicate()

if errData and not "iptables-legacy" in errData:
	printFunc("ERROR: " + errData)
	prRed("Please fix the issue and re-run this script")
	prRed("Otherwise, please check the firewall rules on your own")
	printFunc()
elif not outData:
	prGreen("There are no firewall restrictions for accessing Plesk UI via port 8443")
	printFunc()
else:
	for line in outData.splitlines():
		lineToList = line.split()
		listRules.append(lineToList)

	for sublist in listRules:
		if checkIfInList(listRules, 'DROP', '0.0.0.0/0') or checkIfInList(listRules, 'REJECT', '0.0.0.0/0'):
			errFCode = True
			checkDropRule = True
			dropRulePosition = getPosition(listRules, 'DROP', '0.0.0.0/0')
			break

	for sublist in listRules:
		if checkIfInList(listRules, 'ACCEPT', '0.0.0.0/0'):
			checkAllowRule = True
			allowRulePosition = getPosition(listRules, 'ACCEPT', '0.0.0.0/0')
			break

	if checkAllowRule and checkDropRule:
		for ip in ipAddresses:
			for sublist in listRules:
				if checkIpInSubnet(ipConvert(ip), startIP(sublist[1]), endIP(sublist[1])):
					if comparePositions(dropRulePosition, getPosition(listRules, sublist[0], sublist[1])) and comparePositions(dropRulePosition, allowRulePosition):
						prRed("Access is not allowed for the IP address" + "\033[93m {}\033[00m".format(ip))
						break
					elif "DROP" in sublist or "REJECT" in sublist:
						prRed("Access is forbidden for the IP address" + "\033[93m {}\033[00m".format(ip))
						break
					elif (("DROP" in sublist or "REJECT" in sublist) and comparePositions(allowRulePosition, getPosition(listRules, sublist[0], sublist[1]))) or ("ACCEPT" in sublist and comparePositions(getPosition(listRules, sublist[0], sublist[1]), dropRulePosition)):
						prGreen("Access is allowed for the IP address" + "\033[93m {}\033[00m".format(ip))
						break
	elif checkAllowRule and allowRulePosition[0] == '0':
		prGreen("There are no firewall restrictions for accessing Plesk UI via port 8443")
	elif checkAllowRule:
		for ip in ipAddresses:
			for sublist in listRules:
				if checkIpInSubnet(ipConvert(ip), startIP(sublist[1]), endIP(sublist[1])):
					if ("DROP" in sublist or "REJECT" in sublist) and comparePositions(getPosition(listRules, sublist[0], sublist[1]), allowRulePosition):
						errFCode = True
						prRed("Access is forbidden for the IP address" + "\033[93m {}\033[00m".format(ip))
						break
					else:
						prGreen("Access is not filtered for the IP address" + "\033[93m {}\033[00m".format(ip))
						break
	elif checkDropRule:
		for ip in ipAddresses:
			for sublist in listRules:
				if checkIpInSubnet(ipConvert(ip), startIP(sublist[1]), endIP(sublist[1])):
					if "ACCEPT" in sublist and comparePositions(getPosition(listRules, sublist[0], sublist[1]), dropRulePosition):
						prGreen("Access is allowed for the IP address" + "\033[93m {}\033[00m".format(ip))
						break
					else:
						prRed("Access is not allowed for the IP address" + "\033[93m {}\033[00m".format(ip))
						break
	elif not checkAllowRule and not checkDropRule:
		for ip in ipAddresses:
			for sublist in listRules:
				if checkIpInSubnet(ipConvert(ip), startIP(sublist[1]), endIP(sublist[1])):
					if "DROP" in sublist or "REJECT" in sublist:
						errFCode = True
						prRed("Access is forbidden for the IP address" + "\033[93m {}\033[00m".format(ip))
						break
					else:
						prGreen("There are no firewall restrictions for accessing Plesk UI via port 8443")
		
	if errFCode:
		printFunc()
		prRed(">>> Here is the article for help: " + fArticle)

	printFunc()
	
		
# Check administrative restrictions
noAdmRes = False
denyList = []
excludeDenyList = ['52.51.23.204', '52.213.169.7', '34.254.37.129']
allowList = []
excludeAllowList = []
ipCount = 0
errACode = False
aArticle = "https://support.plesk.com/hc/en-us/articles/115001881814"

prBlue("===============================================================")
prBlue("Checking restrictions for administrative access rules:")
prBlue("===============================================================")
printFunc()

commandAR = 'MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysql -uadmin -Nse "SELECT type,netaddr,netmask FROM psa.cp_access"'
optionAR = 'MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysql -uadmin -Nse "SELECT val FROM psa.misc WHERE param = \'access_policy\'"'
restrictions = subprocess.Popen(commandAR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=True)
outData, errData = restrictions.communicate()
optionCheck = subprocess.Popen(optionAR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=True)
policy = optionCheck.stdout.readline()

if errData:
	printFunc("ERROR:" + errData)
	prRed("Please fix the issue and re-run this script")
	prRed("Otherwise, please check the administrative restirction on your own")
	prRed("Here is the article for help: " + aArticle)
	printFunc()
else:
	if policy.strip() == "allow":
		for line in outData.splitlines():
			if "allow" in line:
				allowList.append(line.split())

	if policy.strip() == "deny":
		for line in outData.splitlines():
			if "deny" in line:
				denyList.append(line.split())
				
	if not allowList and not denyList:
		noAdmRes = True
		prGreen("There are no administrative restrictions")
        
	if allowList and not noAdmRes:
		for ip in ipAddresses:
			for item in allowList:
				if checkIpInSubnet(ipConvert(ip), startIP(str(item[1]) + '/' + str(calculateCIDR(item[2]))), endIP(str(item[1]) + '/' + str(calculateCIDR(item[2])))):
					errACode = True
					prRed("Access to the Plesk UI is denied for the IP address" + "\033[93m {}\033[00m".format(ip))
					excludeAllowList.append(ip)
					break

	if excludeAllowList and not noAdmRes:
		for ip in ipAddresses:
			if ip not in excludeAllowList:
				prGreen("Access to the Plesk UI is not denied for the IP address" + "\033[93m {}\033[00m".format(ip))

	if denyList and not noAdmRes:
		for ip in ipAddresses:
			for item in denyList:
				if checkIpInSubnet(ipConvert(ip), startIP(str(item[1]) + '/' + str(calculateCIDR(item[2]))), endIP(str(item[1]) + '/' + str(calculateCIDR(item[2])))):
					prGreen("Access to the Plesk UI is allowed for the IP address" + "\033[93m {}\033[00m".format(ip))
					excludeDenyList.remove(ip)
					break
	
	if excludeDenyList and not noAdmRes:
		for ip in ipAddresses:
			if ip in excludeDenyList:
				errACode = True
				prRed("Access to the Plesk UI is not allowed for the IP address" + "\033[93m {}\033[00m".format(ip))

	if errACode:
		printFunc()
		prRed(">>> Here is the article for help: " + aArticle)

	printFunc()


# Check API
errApiCode = False
apiArticle = "https://support.plesk.com/hc/en-us/articles/360001125374"

prBlue("=========================================")
prBlue("Checking [api] section in panel.ini:")
prBlue("=========================================")
printFunc()

commandCheckAPI = 'grep "^\[api\]" /usr/local/psa/admin/conf/panel.ini'
commandAPI = 'sed -n "/^\[api\]/,/^\[/p" /usr/local/psa/admin/conf/panel.ini'
checkAPI = subprocess.Popen(commandCheckAPI, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=True)
apiSection = subprocess.Popen(commandAPI, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, shell=True)

if checkAPI.stdout.readline():
	for line in apiSection.stdout:
		if "enabled" in line and "off" in line and ";" not in line:
			errApiCode = True
			prRed("Access to the API is restricted for all connections")
		elif "allowedIPs" in line and not ";" in line:
			for ip in ipAddresses:
				if ip not in line:
					errApiCode = True
					prRed("Access to the API is not allowed for the IP address" + "\033[93m {}\033[00m".format(ip))
				else:
					prGreen("Access to the API is allowed for the IP address" + "\033[93m {}\033[00m".format(ip))
		elif "allowedIPs" in line and ";" in line:
			prGreen("There are no restrictions for accessing the API")
else:
	prGreen("There are no restrictions for accessing the API")

if errApiCode:
	printFunc()
	prRed(">>> Here is the article for help: " + apiArticle)

printFunc()


# Additional section with IP addresses
if errFCode or errACode or errApiCode:
	printFunc()
	prBlue("++++++++++++++++++++++++++++++++++++++++++++++++")
	prBlue("++++++++++++++++++++++++++++++++++++++++++++++++")
	prBlue("The following IP addresses should be added:")
	prBlue("\t" + ipAddresses[0])
	prBlue("\t" + ipAddresses[1])
	prBlue("\t" + ipAddresses[2])
	prBlue("++++++++++++++++++++++++++++++++++++++++++++++++")
	prBlue("++++++++++++++++++++++++++++++++++++++++++++++++")