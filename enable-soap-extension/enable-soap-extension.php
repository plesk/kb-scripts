#!/bin/bash

# Script from Plesk KB article https://support.plesk.com/hc/en-us/articles/213383629-How-to-enable-SOAP-PHP-extension-in-Plesk- 
# It checks whether or not the class provided by the SOAP module is loaded for OS PHP and enables if it isn't

resultFalse="bool(false)"
resultTrue="bool(true)"
command=`php -r 'var_dump(class_exists("SoapClient"));'`

if [ $command == $resultFalse ]
then
	echo "The SOAP module is not loaded yet!"
	sleep 2
	echo "Installing..."
	sleep 2
	yum install php-soap -y || apt install php-soap -y
	sleep 2 
	service php-fpm restart || service php7.0-fpm restart
fi

if [ $command == $resultTrue ]
then

echo "The SOAP Module is already loaded for OS PHP"
fi
