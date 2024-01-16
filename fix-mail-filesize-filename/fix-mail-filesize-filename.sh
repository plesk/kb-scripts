#!/bin/bash
### Copyright 1999-2024. Plesk International GmbH.

###############################################################################
# This script validates and corrects discrepancies between actual and stated file sizes in mail files.
# Detailed instructions and usage guidelines can be found in the README.md.
# Requirements : bash 3.x, GNU coreutils
# Version      : 1.0
#########

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

# Get the total number of files that match the expected filename format
total_files=$(find ${dir} -type f | grep -E 'S=[0-9]+:' | wc -l)
count=0
mismatch_count=0

# Function to check and fix filenames
check_and_fix() {
    for file in $(find ${dir} -type f | grep -E 'S=[0-9]+:'); do
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
            if [ "${2}" == "--export" ]; then
                echo "${file}" >> "${1}_mismatches.txt"
            fi

            # If the --fix option is set, rename the file
            if [ "${1}" == "--fix" ]; then
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

# Run the function with the provided arguments
check_and_fix $1 $2

# Calculate the elapsed time
end_time=$(date +%s)
elapsed_time=$((end_time-start_time))

# Print the statistics
echo "Total files checked: ${total_files}"
echo "Total mismatches found: ${mismatch_count}"
echo "Elapsed time: ${elapsed_time} seconds"
