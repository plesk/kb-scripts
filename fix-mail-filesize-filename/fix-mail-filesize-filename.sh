#!/bin/bash
### Copyright 1999-2024. Plesk International GmbH.

###############################################################################
# This script validates and corrects discrepancies between actual and stated file sizes in mail files.
# Detailed instructions and usage guidelines can be found in the README.md.
# Requirements : bash 3.x, GNU coreutils
# Version      : 2.1
#########

# Initialize flags for fix and export options
fix_flag=0
export_flag=0

# Initialize counter for fixed mismatches
fixed_count=0

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

# Initialize an array to store the mismatches
declare -a mismatches

# Function to check filenames
check_filenames() {
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

            # Store the mismatch information
            mismatches+=("${file} ${expected_size} ${actual_size}")
        fi

        # Show the progress
        count=$((count+1))
        echo -ne "Progress: ${count}/${total_files} files checked\r"
    done
    echo ""  # Move to a new line after the loop
}

# Function to export mismatches
export_mismatches() {
    for mismatch in "${mismatches[@]}"; do
        IFS read -r -a array <<< "$mismatch"
        file="${array[0]}"
        echo "${file}" >> "${domain}_${username}_mismatches.txt"
    done
}

# Function to fix mismatches
fix_mismatches() {
    for mismatch in "${mismatches[@]}"; do
        IFS read -r -a array <<< "$mismatch"
        file="${array[0]}"
        expected_size="${array[1]}"
        actual_size="${array[2]}"
        new_file=$(echo ${file} | sed "s/S=${expected_size}/S=${actual_size}/")
        if mv "${file}" "${new_file}"; then
            echo "File has been renamed to: ${new_file}"
            fixed_count=$((fixed_count+1))
        else
            echo "Error: Failed to rename file: ${file}"
        fi
    done
}

# Run the appropriate functions based on the provided arguments
check_filenames
if [ $export_flag -eq 1 ]; then
    export_mismatches
fi
if [ $fix_flag -eq 1 ]; then
    fix_mismatches
fi

# If no options were provided, ask the user if they want to fix or export the mismatches
if [ $fix_flag -eq 0 ] && [ $export_flag -eq 0 ] && [ $mismatch_count -gt 0 ]; then
    echo -n "Inconsistencies found. Would you like to fix them or export them to a file? Enter 'fix', 'export', or 'both': "
    read action
    case $action in
        fix)
            fix_mismatches
            ;;
        export)
            export_mismatches
            ;;
        both)
            fix_mismatches
            export_mismatches
            ;;
        *)
            echo "Invalid option. No action taken."
            ;;
    esac
fi

# Calculate the elapsed time
end_time=$(date +%s)
elapsed_time=$((end_time-start_time))

# Print the statistics
echo "Total files checked: ${total_files}"
echo "Total mismatches found: ${mismatch_count}"
if [ $fix_flag -eq 1 ] || [ "${action:-}" == "fix" ] || [ "${action:-}" == "both" ]; then
    echo "Total mismatches fixed: ${fixed_count}"
fi
echo "Elapsed time: ${elapsed_time} seconds"
