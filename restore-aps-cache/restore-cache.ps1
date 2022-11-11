### Copyright 1999-2022. Plesk International GmbH.
# Script from Plesk KB article https://support.plesk.com/hc/en-us/articles/213913305
# This script must be run with Administrator privilege
# It restores necessary APS cache packages for installed applications
$arr=@((plesk bin aps -gp | Select-String -Pattern "Name|Version" | Out-String | Foreach {$_ -replace ".*:\s*", '' }).Split("`r|`n",[System.StringSplitOptions]::RemoveEmptyEntries))
for ($i = 0; $i -le $arr.Count; $i = $i + 2){plesk bin aps -d -package-name $arr[$i] -package-version $arr[$i+1]}