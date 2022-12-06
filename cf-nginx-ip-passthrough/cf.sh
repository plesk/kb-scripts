#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script manages and updates chroot environment used in Plesk
# Requirements : bash 3.x, mysql-client, GNU coreutils
# Version      : 1.6
#########

PATH=$PATH:/sbin:/bin:/usr/sbin:/usr/bin
CFTEMP=/tmp/cloudflare-ips.txt

if [[ "$(/usr/local/psa/admin/bin/nginxmng --status)" != "Enabled" ]] ; then
	echo "Nginx is not in use on this Plesk server. Exiting..." && exit 0
fi

if [ -f /etc/nginx/conf.d/cf-stop ] ; then
	printf "Previous execution of the script failed!\nThere is /etc/nginx/conf.d/cf-stop\nReview the script functional and remove the /etc/nginx/conf.d/cf-stop\n"
	printf "The script execution was halted.\n" && exit 0 # also add some notifications here if you would like to receive them
fi	


curl -sS https://www.cloudflare.com/ips-v4 >$CFTEMP && printf "\n" >> $CFTEMP
curl -sS https://www.cloudflare.com/ips-v6 >>$CFTEMP
sed -i -e 's/^/set_real_ip_from /' $CFTEMP
sed -i '1ireal_ip_header CF-Connecting-IP' $CFTEMP
sed -i '/[^;] *$/s/$/;/' $CFTEMP

placeconf(){
	mv $CFTEMP /etc/nginx/conf.d/cloudflare.conf
}


if [ ! -f /etc/nginx/conf.d/cloudflare.conf ] ; then
	# CF IP List is missing in conf.d
	placeconf
else
	# CF IP List exists in conf.d 
	if [[ ! -z "$(cat /etc/nginx/conf.d/cloudflare.conf)" ]] ; then
		# The list is not empty. Back up the previous one and install the new one.
		cp /etc/nginx/conf.d/cloudflare.conf{,.bkp} && placeconf
	fi
fi

nginx -t 2>/dev/null > /dev/null
if [[ $? == 0 ]]; then
	# configuration is valid
 	echo "Configuration applied. Restarting Nginx."
 	systemctl restart nginx
else
 	# Configuration is not valid. Switching to the old CF IP list
 	echo "Nginx conf test failed. Rolling back"
 	mv /etc/nginx/conf.d/cloudflare.conf.bkp /etc/nginx/conf.d/cloudflare.conf
 	t2=$(nginx -t 2>/dev/null > /dev/null)
 	if [ "$t2" == 0 ] ; then
 		# Previous config is valid. Restarting.
 		echo "Rolled back to the older config. Restarting Nginx"
 		systemctl restart nginx
 	else
 		echo "Old config file also causes failure. Disabling the CF list completely"
 		mv /etc/nginx/conf.d/cloudflare.conf{,.disabled}
 		# Add any notification of your liking(telegram/mail/etc...)
 		systemctl restart nginx
 		# creating a stop flag
 		touch /etc/nginx/conf.d/cf-stop
 	fi
fi


exit 0