#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script updates default MySQL/MariaDB on CentOS to MariaDB 10.5
# Requirements : bash 3.x, GNU coreutils
# Version      : 1.0
#########

LOG_FILE=plesk_mariadbupdate.log
ERROR_LOG_FILE=plesk_updatemariadb_error.log

exec 1>$LOG_FILE
exec 2>$ERROR_LOG_FILE

echo "Dumping all databases"
MYSQL_PWD=`cat /etc/psa/.psa.shadow` mysqldump -u admin --verbose --all-databases --routines --triggers > /root/all-databases.sql 2> /dev/null

#avoid inconsistency with repo if one exists
if [ -f "/etc/yum.repos.d/MariaDB.repo" ] ; then
  mv /etc/yum.repos.d/MariaDB.repo /etc/yum.repos.d/mariadb.repo
fi

#Stopping MariaDB
echo "stopping MariaDB service"
systemctl stop mariadb


echo "creating backup of mysql directory"
cp -v -a /var/lib/mysql/ /var/lib/mysql_backup 2> /dev/null

echo "removing mysql-server package in case it exists"
rpm -e --nodeps "`rpm -q --whatprovides mariadb-server`"

echo "Upgrading MariaDB"

echo "#http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.5/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" > /etc/yum.repos.d/mariadb.repo

yum clean all

yum install MariaDB-client MariaDB-server MariaDB-compat MariaDB-shared -y

systemctl restart mariadb

MYSQL_PWD=`cat /etc/psa/.psa.shadow` mysql_upgrade -uadmin

systemctl restart mariadb

echo "Informing Plesk of the changes (plesk sbin packagemng -sdf)"
plesk sbin packagemng -sdf

systemctl start mariadb # to start MariaDB if not started
systemctl enable mariadb # to make sure that MariaDB will start after the server reboot automatically
