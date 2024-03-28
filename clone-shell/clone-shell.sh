#!/usr/bin/env bash

### Copyright 1999-2022. Plesk International GmbH.

# Script from Plesk KB article https://support.plesk.com/hc/en-us/articles/213912005
# It script clones the shell of the main user to the additional user
# Requirements : bash 3.x, GNU coreutils, mysql client
# Version      : 1.0

export LANG=C
export LC_ALL=C
###########################################################
# Function `err()`
# Echoes to the `stderr` and finishes script execution
# Input   : $* any number of strings (will be concatenated)
# Output  : None
# Globals : None
err() {
  echo -ne "\\e[31mERROR\\e[m"
  echo ": $*" >&2
  exit 1
}

###########################################################
# Function `warn()`
# Echoes to the `stderr` and continues script execution
# Input   : $* any number of strings (will be concatenated)
# Output  : None
# Globals : None
warn() {
  echo -ne "\\e[33mWARNING\\e[m"
  echo ": $*" >&2
}

###########################################################
# Function `init()`
# Checks existence of necessary files and preconditions
# Input   : None
# Output  : None
# Globals : None
init() {
  if [[ ! -f /etc/psa/.psa.shadow ]]; then
    err "Could not find file \"/etc/psa/.psa.shadow\", cannot proceed"
  fi
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run with root privileges"
  fi
}

###########################################################
# Function `mysql_query()`
# Runs MySQL query to the Plesk database
# Input   : $1 string (MySQL query)
# Output  : >1 string (results of the MySQL query)
# Globals : None
mysql_query() {
  local query="${1}"
  MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysql -Ns -uadmin -Dpsa -e"${query}"
}

###########################################################
# Function `user_exists()`
# Checks if the user can be found within passwd database
# Input   : $1 string (User name)
# Output  : $? zero is user exists, non-zero otherwise
# Globals : None
user_exists() {
  local user="${1}"
  getent passwd "${user:?}" >/dev/null 2>&1
  return $?
}

###########################################################
# Function `user_shell()`
# Extracts user's shell from the passwd database
# Input   : $1 string (User name)
# Output  : >1 string (Shell name)
# Globals : None
user_shell() {
  local user="${1}"
  getent passwd "${user:?}" | cut -d':' -f7
  return $?
}

###########################################################
# Function `convert_passwd()`
# Extracts user's info from the passwd and converts it
# Input   : $1 string (User name)
# Output  : >1 string (New passwd contents)
# Globals : None
convert_passwd() {
  local user="${1}"
  getent passwd "${user:?}" \
    | awk -F: '{OFS=FS; $6="/";$7="/bin/bash"; print $0 }'
}

###########################################################
# Function `process_username()`
# Clones the shell of main user to the additional user
# Input   : $1 string (User name)
# Output  : None
# Globals : None
process_username() {
  local user="${1}" main_user main_shell old_shell vhost_d
  if ! user_exists "${user}"; then
    warn "User ${user} does not exist, skipping"
    return
  fi
  main_user="$(mysql_query "SELECT s.login FROM sys_users s \
    LEFT JOIN sys_users s1 ON s.id = s1.mapped_to \
    WHERE s1.login = \"${user}\"")"
  if [[ -z $main_user ]]; then
    warn "Could not find main user for the user ${user}, skipping"
    return
  fi
  main_shell="$(user_shell "${main_user}")"
  old_shell="$(user_shell "${user}")"
  echo "Changing ${user} shell from ${old_shell} to ${main_shell}"
  usermod -s "${main_shell}" "${user}"
  if [[ "${main_shell}" == *chrootsh* ]]; then
    vhost_d="$(mysql_query "SELECT s.home FROM sys_users s \
      WHERE s.login = \"${main_user}\"")"
    if ! grep -q "${user}" "${vhost_d}/etc/passwd"; then
      echo "Adding ${user} to the chrooted passwd file"
      convert_passwd "${user}" >> "${vhost_d}/etc/passwd"
    fi
  fi
}

main() {
  local username=''
  while :; do
    username="${1}"
    shift
    if [[ "${username}" == '' ]]; then
      break
    fi
    process_username "${username}"
  done
}

init
main "$@"
