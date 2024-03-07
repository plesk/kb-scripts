#!/bin/bash

### Copyright 1999-2024. Plesk International GmbH.

# Script from Plesk KB article https://support.plesk.com/hc/en-us/articles/12377651541527-How-to-provide-Plesk-Support-with-server-access
# It adds Plesk support SSH keys to authorized keys for the current user and adds Plesk IPs to the firewall

echo -e "1. Adding our IP address to the local firewall"
if [[ $(which iptables) ]] 2>/dev/null ; then
        echo "Adding our IP address to the local firewall:"
        sudo iptables -I INPUT -s 195.214.233.0/24,194.8.192.130,81.184.0.141,208.74.127.0/28,184.94.192.0/20 -j ACCEPT
        sudo ip6tables -I INPUT -s 2001:678:744::/64,2620:0:28a4:4000::/52 -j ACCEPT
else
        echo "Command iptables is not installed"
fi
sleep 1
echo -e "\e[1;31m Done. \e[0m"

echo -e "2. Making sure PubkeyAuthentication is enabled in SSH configuration"
sudo sed 's/\#PubkeyAuthentication\ yes/PubkeyAuthentication\ yes/g' -i /etc/ssh/sshd_config
sudo sed 's/\#PubkeyAuthentication\ no/PubkeyAuthentication\ yes/g' -i /etc/ssh/sshd_config
sudo sed 's/\PubkeyAuthentication\ no/PubkeyAuthentication\ yes/g' -i /etc/ssh/sshd_config
echo -e "\e[1;31m Done. \e[0m"
sudo grep PubkeyAuthentication /etc/ssh/sshd_config
sleep 1

echo -e "3. Reloading the sshd service to apply the above changes"
sudo systemctl reload sshd
sleep 1
echo -e "\e[1;31m Done. \e[0m"

echo -e "4. Making sure .ssh directory exists in the home directory of the user that will be provided to the Support Team"
mkdir ~/.ssh 2>/dev/null && chmod 700 ~/.ssh
sleep 1
echo -e "\e[1;31m Done. \e[0m"

echo -e "5. Placing the Plesk Support public SSH key to the authorized_keys to allow logging in using it"
curl -L https://raw.githubusercontent.com/plesk/kb-scripts/master/ssh_keys/id_rsa.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
sleep 1
echo -e "\e[1;31m Done. \e[0m"

echo -e "\e[1;42m6. The Plesk SSH Support Key has been installed under the user $(whoami). Please pass that information to the Support team. \e[0m"
