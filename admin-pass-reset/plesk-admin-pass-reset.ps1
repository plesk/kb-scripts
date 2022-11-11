### Copyright 1999-2022. Plesk International GmbH.

#==============================================================================
# This script reset password for the admin user of the PleskSQLServer
# 1. remove existing admin user from Plesk's MySQL
# 2. create new admin user with random password
# 3. update admin's password in Windows registry
#==============================================================================

# This script must be running at least in PowerShell version 4 
# and with Administrator privilege
#Requires -Version 4
#Requires -RunAsAdministrator

# Set path to a log file in the TS_DEBUG environment variable to enable debug 
if ($env:TS_DEBUG) {
	$output=$env:TS_DEBUG
#	Set-PSDebug -trace 1 # too much unnecessary output
}
else {
	$output=$null
}

function genpass {
# This function generates Strong or Very Strong password.
# Generate random 200 characters made of A-Z, a-z, 0-9, and symbols #$*+,-./:=?@[]_{}~
$pass=$(-join(0..200|%{[char][int]((65..90) + (97..122) + (48..57) + `
	(35,36,42,43,44,45,46,47,58,61,63,64,91,93,95,123,125,126) | Get-Random)}))
# Remove all subsequent letters and numbers
$pass=$($pass -replace "([a-z])[a-z]+", $1 -replace "([0-9])[0-9]+", $1) 
# Remove all subsequent symbols
$pass=$($pass -replace "([#$*+,-./:;=?@[]_{}~])[#$*+,-./:=?@[]_{}~]", $1)
# Took first 16 characters
$pass=$($pass.substring(3,16))

return $pass
}

# aborting if Plesk version older than 17.8
$PLESK_VER=$((Get-Content "$env:plesk_dir\version").Split(' ')[0])
if ( $($PLESK_VER.Split('.')[0]) -lt 17 -or (
	$($PLESK_VER.Split('.')[0]) -eq 17 -and $($PLESK_VER.Split('.')[1]) -lt 8) ) {
	Write-Host "This script intended for Plesk version 17.8 and newer. Current Plesk version: $PLESK_VER"
	exit 1
}

# generate random password
$ADMIN_PASS=$(genpass)

# remove existing admin user from Plesk's MySQL
plesk sbin mysqlmng_adm --del-user --user-login=admin >> $output

$rc=$(plesk sbin mysqlmng_adm --exist-user --user-login=admin)
if ( $rc -eq 1 ) {
	Write-Host "Cannot remove the 'admin' user. Use manual solution from article or contact Plesk support."
	exit 1
}

# create new admin user with random password generated above
plesk sbin mysqlmng_adm --add-super-user --login=admin --password=$ADMIN_PASS --allowed-host=localhost >> $output

# update admin's password in Windows registry
plesk sbin psadb -u --password=$ADMIN_PASS >> $output

# plesk sbin psadb -g

plesk db "DESC domains" >> $output
if ( $LastExitCode ) {
	Write-Host "Password reset unsuccessful. Use manual solution from article or contact Plesk support."
	exit 1
}
else {
	Write-Host "Password reset successful."
}
