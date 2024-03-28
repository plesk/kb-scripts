# Mail Filesize/Filename Fixer Script

## Overview

This script is designed to validate and correct discrepancies between the actual and stated file sizes in mail files. It's intended for use by technically experienced IT engineers.

The script checks mail files in a specified directory, and identifies any files where the size stated in the filename does not match the actual file size. It can optionally fix these discrepancies by renaming the files, and/or export the filenames of the mismatched files to a text file.

## Usage

The script can be run with the following command:

```
./scriptname [--fix] [--export]
```

Replace `scriptname` with the name of the script file.

The script accepts the following optional arguments:

- `--fix`: If this option is provided, the script will rename any files it finds where the size stated in the filename does not match the actual file size. The new filename will correct the stated size to match the actual size.

- `--export`: If this option is provided, the script will export the filenames of any mismatched files it finds to a text file. The text file will be named using the domain and username, in the format `{domain}_{username}_mismatches.txt`.

If no options are provided, the script will just check for mismatches and display the results. Once done, you'll be given the option to fix and/or export any mismatches found.

When you run the script, it will prompt you to enter the domain name and username. The script will then check the mail files in the directory `/var/qmail/mailnames/{domain}/{username}`.

## Requirements

The script requires Bash 3.x and GNU coreutils.

## Note

Please ensure that you have the necessary permissions to read and write to the directory and files before running the script.
