#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.
# Script from Plesk KB article https://support.plesk.com/hc/en-us/articles/213913305
# It restores necessary APS cache packages for installed applications
 name=
 i=0
 for line in `plesk bin aps -gp | awk  '/Name:|Version:/ {print $2}'`; do
  if [ $((i%2)) -eq 0 ];
  then
   name=$line
   ((++i))
  else
   plesk bin aps -d -package-name $name -package-version $line
   i=0
  fi
 done