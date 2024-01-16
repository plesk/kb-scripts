#!/bin/bash
### Copyright 1999-2024. Plesk International GmbH.

###############################################################################
# This script validates and corrects discrepancies between actual and stated file sizes in mail files.
# Detailed instructions and usage guidelines can be found in the README.md.
# Requirements : bash 3.x, GNU coreutils
# Version      : 1.3
#########

# Initialize flags for fix and export options
fix_flag=0
export_flag=0

# Check the arguments
for arg in "$@"; do
    case $arg in
        --fix)
            fix_flag=1
            shift
            ;;
        --export)
            export_flag=1
            shift
            ;;
        --help)
            echo "Usage: $0 [--fix] [--export]"
            echo "--fix: Renames files to correct the discrepancy between actual and stated file sizes."
            echo "--export: Saves the names of files with discrepancies to a text file."
            echo "--help: Displays this help message."
            exit 0
            ;;
        *)
            echo "Error: Invalid argument: $arg"
            echo "Usage: $0 [--fix] [--export]"
            exit 1
            ;;
    esac
done

# Start the timer
start_time=$(date +%s)

# Get the domain name and username
echo -n "Enter the domain name: "
read domain
echo -n "Enter the username: "
read username

# Set the directory path
dir="/var/qmail/mailnames/${domain}/${username}"
echo "The directory to be checked is: ${dir}"

# Check if the directory exists and is readable
if [ ! -d "${dir}" ] || [ ! -r "${dir}" ]; then
    echo "Error: Directory does not exist or is not readable: ${dir}"
    exit 1
fi

# Get the total number of files that match the expected filename format
total_files=$(find ${dir} -type f | grep -E 'S=[0-9]+:' | wc -l)
count=0
mismatch_count=0

# Function to sanitize filenames
sanitize_filename() {
    local filename="${1}"
    # Remove any potentially harmful characters
    filename=$(echo "${filename}" | tr -d '$`|><&\n')
    echo "${filename}"
}

# Function to check and fix filenames
check_and_fix() {
    for file in $(find ${dir} -type f | grep -E 'S=[0-9]+:'); do
        # Sanitize the filename
        file=$(sanitize_filename "${file}")

        # Extract the expected size from the filename
        expected_size=$(echo ${file} | grep -oP 'S=\K[0-9]+')

        # Get the actual size
        actual_size=$(stat -c%s "${file}")

        # Check if the sizes match
        if [ "${expected_size}" != "${actual_size}" ]; then
            echo "Mismatch found in file: ${file}"
            echo "Expected size: ${expected_size}, Actual size: ${actual_size}"
            mismatch_count=$((mismatch_count+1))

            # If the --export option is set, save the filename to a file
            if [ $export_flag -eq 1 ]; then
                echo "${file}" >> "${domain}_${username}_mismatches.txt"
            fi

            # If the --fix option is set, rename the file
            if [ $fix_flag -eq 1 ]; then
                new_file=$(echo ${file} | sed "s/S=${expected_size}/S=${actual_size}/")
                mv "${file}" "${new_file}"
                echo "File has been renamed to: ${new_file}"
            fi
        fi

        # Show the progress
        count=$((count+1))
        echo -ne "Progress: ${count}/${total_files} files checked\r"
    done
    echo ""  # Move to a new line after the loop
}

# Run the function
check_and_fix

# Calculate the elapsed time
end_time=$(date +%s)
elapsed_time=$((end_time-start_time))

# Print the statistics
echo "Total files checked: ${total_files}"
echo "Total mismatches found: ${mismatch_count}"
echo "Elapsed time: ${elapsed_time} seconds"
