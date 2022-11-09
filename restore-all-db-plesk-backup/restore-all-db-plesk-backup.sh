#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script restores only all databases from a specified Plesk backup
# Requirements : bash 3.x, mysql-client, GNU coreutils
# Version      : 1.0
#########

#########
# Change only the following two values
DRYRUN=1
TIMESTAMP=backup_sqldump_datetime.tgz
#########

# Set TEMPDIR name
TEMPDIR_DB=/root/plesksupport/restore_all_databases_tmp
# Create TEMPDIR
mkdir -p $TEMPDIR_DB
# Retrieve database backup files
find /var/lib/psa/dumps -name "*$TIMESTAMP" -type f > /root/plesksupport/list_of_all_dbs.txt
# create restore command
while 
    read d; 
    do 
        #get name of database
        DBNAME=$(echo $d |sed -r 's/.*databases\/(.*)\/.*/\1/g' | sed -r 's/(.*)_1/\1/g') ; 
        # extract database backup from archive and keep its filename
        DBFILENAME=$(tar -zxvf $d --directory $TEMPDIR_DB)

        if [[ $(grep "Database: $DBNAME" $TEMPDIR_DB/$DBFILENAME) ]]
            then
            echo "# TASK: Restoring database dump of DB $DBNAME..."
            if [[ $DRYRUN -ne 0 ]]
                then
                    REALNAME=$( grep "Database: $DBNAME" $TEMPDIR_DB/$DBFILENAME | sed -r 's/.*Database\: (.*)/\1/g' )
                    echo "plesk db < $REALNAME"
                else
                    plesk db < $TEMPDIR_DB/$DBFILENAME
                fi
            echo "# TASK: Done"
            rm $TEMPDIR_DB/$DBFILENAME
        fi
                
    done < /root/plesksupport/list_of_all_dbs.txt

rm -rf $TEMPDIR_DB

echo "######"
echo "All databases from $TIMESTAMP restored"