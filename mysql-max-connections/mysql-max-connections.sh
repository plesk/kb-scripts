#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script increases the maximum number of simultaneous connections to the MySQL server hosted with Plesk
# Requirements : bash 3.x, mysql-server, GNU coreutils
# Version      : 1.0
#########

if [ -f /etc/mysql/my.cnf ] ; then
                                DistroBasedOn='Debian/Ubuntu'
								cp /etc/mysql/my.cnf /etc/mysql/my.cnf.bak
								echo "Backup of my.cnf was saved to /etc/mysql/my.cnf.bak"
                                sed -i -- 's/max_connections/# max_connections/g' /etc/mysql/my.cnf
								sed -i '/\[mysqld\]/a max_connections = 300' /etc/mysql/my.cnf
								echo 'Restarting MySQL process...'
								service mariadb restart >/dev/null 2>&1; service mysql restart >/dev/null 2>&1; service mysqld restart >/dev/null 2>&1
elif [ -f /etc/my.cnf ] ; then
                                DistroBasedOn='CentOS/RHEL/CloudLinux'
								cp /etc/my.cnf /etc/my.cnf.bak
								echo "Backup of my.cnf was saved to /etc/mysql/my.cnf.bak"
                                sed -i -- 's/max_connections/# max_connections/g' /etc/my.cnf
								sed -i '/\[mysqld\]/a max_connections = 300' /etc/my.cnf
								echo 'Restarting MySQL process...'
								service mariadb restart >/dev/null 2>&1; service mysql restart >/dev/null 2>&1; service mysqld restart >/dev/null 2>&1
else 
	echo 'File my.cnf was not found!'
fi
