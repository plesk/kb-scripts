#!/bin/bash
### Copyright 1999-2024. Plesk International GmbH.

PATH=$PATH:/sbin:/bin:/usr/sbin:/usr/bin
cfTemp=/tmp/cloudflare-ips.txt
cfConfig="/etc/nginx/conf.d/cloudflare.conf"

# Sanity checks and exit if nginx gets broken
if [[ "$(/usr/local/psa/admin/bin/nginxmng --status)" != "Enabled" ]] ; then
	echo "Nginx is not in use on this Plesk server. Exiting..." && exit 0
fi

if [ -f /etc/nginx/conf.d/cf-stop ] ; then
	printf "Previous execution of the script failed!\nThere is /etc/nginx/conf.d/cf-stop\nReview the script functional and remove the /etc/nginx/conf.d/cf-stop\n"
	printf "The script execution was halted.\n" && exit 0 # also add some notifications here if you would like to receive them
fi	

prepareConf(){
    curl -sS https://www.cloudflare.com/ips-v4 >$cfTemp && printf "\n" >> $cfTemp
    curl -sS https://www.cloudflare.com/ips-v6 >>$cfTemp
    sed -i -e 's/^/set_real_ip_from /' $cfTemp
    sed -i '1ireal_ip_header CF-Connecting-IP' $cfTemp
    sed -i '/[^;] *$/s/$/;/' $cfTemp
}

placeConf(){
    prepareConf
    mv $cfTemp $cfConfig
    if [ `isSeEnforcing` == "1" ] ; then
        seContextApply "$cfConfig"
    fi
}

isSeEnforcing(){
    if [ ! -z `which getenforce` ] ; then # To avoid cosmetic errors when there is no Selinux binaries
        seMode=$(getenforce)
    fi
    if [ "$seMode" == "Enforcing" ] ; then
        echo "1"
    else
        echo "0"
    fi
}

seContextApply(){
  chcon -t httpd_config_t -u system_u "$1"
}


if [ ! -f $cfConfig ] ; then
	# CF IP List is missing in conf.d
	placeConf
else
	# CF IP List exists in conf.d 
	if [[ ! -z "$(cat $cfConfig)" ]] ; then
		# The list is not empty. Back up the previous one and install the new one.
		cp $cfConfig{,.bkp} && placeConf
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
 	mv $cfConfig.bkp $cfConfig
 	t2=$(nginx -t 2>/dev/null > /dev/null)
 	if [ "$t2" == 0 ] ; then
 		# Previous config is valid. Restarting.
 		echo "Rolled back to the older config. Restarting Nginx"
 		systemctl restart nginx
 	else
 		echo "Old config file also causes failure. Disabling the CF list completely"
 		mv $cfConfig{,.disabled}
 		# Add any failure notification of your liking(telegram/mail/etc...) here
 		systemctl restart nginx
 		# creating a stop flag. Script will exit automatically if it exists.
 		# It means you need to fix the issues and remove it manually
 		touch /etc/nginx/conf.d/cf-stop
 	fi
fi


exit 0
