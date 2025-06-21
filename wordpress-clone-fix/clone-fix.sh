#!/bin/bash
### Copyright 1999-2025. WebPros International GmbH.
###############################################################################
# Fixes WordPress multisite cloning issues in Plesk by updating the WP Toolkit
# database table prefix for a cloned site.
#
# Requirements : bash 4.x, sqlite3, plesk CLI, GNU coreutils
# Version      : 1.0
###############################################################################

set -euo pipefail
IFS=$'\n\t'

# Initialize variables
SOURCE_DOMAIN=""
TARGET_DOMAIN=""
VERBOSE=false
LOG_FILE="/var/log/clone-fix.log"
WP_TOOLKIT_DB="/usr/local/psa/var/modules/wp-toolkit/wp-toolkit.sqlite3"
LOCK_FILE="/tmp/wp-toolkit-db.lock"
TIMEOUT=10

# Display usage information
usage() {
	cat <<EOF
Usage: $0 --source <source_domain> --target <target_domain> [--verbose]

Options:
  --source    Source domain name
  --target    Target domain name
  --verbose   Enable verbose logging

Example: $0 --source example.com --target example2.com
EOF
	exit 1
}

# Log messages to file and optionally to stderr
log() {
	local level="$1"
	local message="$2"
	local timestamp
	timestamp=$(date +"%Y-%m-%d %H:%M:%S")

	# Format: [timestamp] [LEVEL] message
	printf "[%s] [%s] %s\n" "$timestamp" "$level" "$message" >>"$LOG_FILE"

	# Display non-DEBUG messages always, DEBUG only in verbose
	if [[ $level != "DEBUG" || $VERBOSE == true ]]; then
		echo "[$timestamp] [$level] $message" >&2
	fi
}

# Handle errors and cleanup
handle_error() {
	local exit_code="${1:-1}"
	local error_message="${2:-"Unexpected error"}"
	local line="${3-}"

	if [[ -n $line ]]; then
		log "ERROR" "Line $line: $error_message (Exit code: $exit_code)"
	else
		log "ERROR" "$error_message (Exit code: $exit_code)"
	fi

	# Release lock if held by current process
	if [[ -f $LOCK_FILE && "$(cat "$LOCK_FILE" 2>/dev/null)" == "$$" ]]; then
		rm -f "$LOCK_FILE"
	fi

	exit "$exit_code"
}

# Setup error trap with line numbers
trap 'handle_error $? "$BASH_COMMAND" "$LINENO"' ERR

# Acquire exclusive lock using flock
acquire_lock() {
	local start_time
	start_time=$(date +%s)
	log "DEBUG" "Attempting to acquire lock: $LOCK_FILE"

	exec 200>"$LOCK_FILE"
	while true; do
		if flock -n 200; then
			echo "$$" >"$LOCK_FILE"
			log "DEBUG" "Lock acquired: $LOCK_FILE"
			return 0
		fi

		# Check for stale lock
		local pid
		pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
		if [[ -n $pid ]] && ! kill -0 "$pid" 2>/dev/null; then
			log "WARN" "Removing stale lock from terminated process $pid"
			rm -f "$LOCK_FILE"
		fi

		# Timeout check
		if (($(date +%s) - start_time >= TIMEOUT)); then
			log "ERROR" "Lock acquisition timed out after $TIMEOUT seconds"
			return 1
		fi

		sleep 1
	done
}

# Release lock if held by current process
release_lock() {
	if [[ -f $LOCK_FILE && "$(cat "$LOCK_FILE")" == "$$" ]]; then
		flock -u 200
		rm -f "$LOCK_FILE"
		log "DEBUG" "Released lock: $LOCK_FILE"
	fi
	exec 200>&- # Close FD
}

# Validate file existence
validate_file() {
	local file="$1"
	local description="$2"

	if [[ ! -f $file ]]; then
		handle_error 1 "$description not found: $file"
	fi
	log "DEBUG" "Validated $description: $file"
}

# Extract table_prefix from wp-config.php
extract_table_prefix() {
	local config_file="$1"
	validate_file "$config_file" "WordPress configuration"

	local regex='^\s*\$\s*table_prefix\s*=\s*['\''"]\s*([a-zA-Z0-9_]+)\s*['\''"]\s*;'
	local prefix
	prefix=$(grep -E "$regex" "$config_file" | sed -E "s/$regex/\1/" | head -1)

	if [[ -z $prefix ]]; then
		handle_error 1 "Failed to extract table prefix from $config_file"
	fi

	echo "$prefix"
}

# Run Plesk DB query with clean output
run_plesk_query() {
	local query="$1"
	local raw_output
	raw_output=$(plesk db -N -e "$query" 2>/dev/null | tr -d '[:space:]')

	if [[ -z $raw_output ]]; then
		log "ERROR" "Empty result for query: $query"
		return 1
	fi
	echo "$raw_output"
}

# Get domain ID from Plesk
get_domain_id() {
	local domain="$1"
	run_plesk_query "SELECT id FROM domains WHERE name='$domain' LIMIT 1"
}

# Get vhost path for domain
get_vhost_path() {
	local domain="$1"
	local domain_id
	domain_id=$(get_domain_id "$domain")
	run_plesk_query "SELECT www_root FROM hosting WHERE dom_id='$domain_id'"
}

# Get WP Toolkit instance ID
get_wp_instance_id() {
	local domain_id="$1"
	sqlite3 "$WP_TOOLKIT_DB" "SELECT id FROM Instances WHERE domainId='$domain_id' LIMIT 1;"
}

# Get current table prefix for instance
get_current_prefix() {
	local instance_id="$1"
	sqlite3 "$WP_TOOLKIT_DB" "SELECT value FROM InstanceProperties WHERE instanceId='$instance_id' AND name='tablePrefix';"
}

# Update table prefix in database
update_table_prefix() {
	local instance_id="$1"
	local new_prefix="$2"
	sqlite3 "$WP_TOOLKIT_DB" "UPDATE InstanceProperties SET value='$new_prefix' WHERE instanceId='$instance_id' AND name='tablePrefix';"
}

# Backup WP Toolkit database
backup_wp_toolkit_db() {
	local backup_file="/usr/local/psa/var/modules/wp-toolkit/wp-toolkit.sqlite3.backup.$(date +%Y%m%d%H%M%S)"

	if ! cp -p "$WP_TOOLKIT_DB" "$backup_file"; then
		handle_error 1 "Database backup failed"
	fi
	log "INFO" "Backup created: $backup_file"
	echo "$backup_file"
}

# Validate domain format
is_valid_domain() {
	[[ $1 =~ ^[a-zA-Z0-9.-]+$ ]]
}

# Validate table prefix format
is_valid_prefix() {
	[[ $1 =~ ^[a-zA-Z0-9_]+$ ]]
}

# Main script execution
main() {
	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-s | --source)
			SOURCE_DOMAIN="${2?Missing source domain}"
			shift 2
			;;
		-t | --target)
			TARGET_DOMAIN="${2?Missing target domain}"
			shift 2
			;;
		-v | --verbose)
			VERBOSE=true
			shift
			;;
		-h | --help)
			usage
			;;
		*)
			handle_error 1 "Invalid argument: $1"
			;;
		esac
	done

	# Validate domains
	if [[ -z $SOURCE_DOMAIN || -z $TARGET_DOMAIN ]]; then
		handle_error 1 "Source and target domains required"
	fi
	if ! is_valid_domain "$SOURCE_DOMAIN"; then
		handle_error 1 "Invalid source domain format: $SOURCE_DOMAIN"
	fi
	if ! is_valid_domain "$TARGET_DOMAIN"; then
		handle_error 1 "Invalid target domain format: $TARGET_DOMAIN"
	fi
	if [[ $SOURCE_DOMAIN == "$TARGET_DOMAIN" ]]; then
		handle_error 1 "Source and target domains must differ"
	fi

	log "INFO" "Starting WordPress multisite cloning fix (source=$SOURCE_DOMAIN, target=$TARGET_DOMAIN)"

	# Require root
	if [[ $EUID -ne 0 ]]; then
		handle_error 1 "Script requires root privileges"
	fi

	# Validate database file
	validate_file "$WP_TOOLKIT_DB" "WP Toolkit database"

	# Get domain IDs
	local source_domain_id target_domain_id
	source_domain_id=$(get_domain_id "$SOURCE_DOMAIN") || handle_error 1 "Source domain not found"
	target_domain_id=$(get_domain_id "$TARGET_DOMAIN") || handle_error 1 "Target domain not found"

	# Get instance IDs
	local source_instance_id target_instance_id
	source_instance_id=$(get_wp_instance_id "$source_domain_id") || handle_error 1 "Source WordPress instance not found"
	target_instance_id=$(get_wp_instance_id "$target_domain_id") || handle_error 1 "Target WordPress instance not found"

	# Acquire lock
	acquire_lock

	# Create backup
	local backup_file
	backup_file=$(backup_wp_toolkit_db)

	# Get source table prefix
	local source_vhost_path source_table_prefix
	source_vhost_path=$(get_vhost_path "$SOURCE_DOMAIN") || handle_error 1 "Source vhost path not found"
	source_table_prefix=$(extract_table_prefix "${source_vhost_path}/wp-config.php") || handle_error 1 "Source table prefix extraction failed"

	if ! is_valid_prefix "$source_table_prefix"; then
		handle_error 1 "Invalid source table prefix: $source_table_prefix"
	fi

	# Get current target prefix
	local current_target_prefix
	current_target_prefix=$(get_current_prefix "$target_instance_id") || handle_error 1 "Target prefix lookup failed"

	# Update prefix
	log "INFO" "Updating target prefix: $current_target_prefix => $source_table_prefix"
	update_table_prefix "$target_instance_id" "$source_table_prefix" || handle_error 1 "Prefix update failed"

	release_lock

	log "SUCCESS" "Operation completed successfully"
	log "INFO" "Backup location: $backup_file"
	log "INFO" "You can now try cloning the WordPress multisite again"
}

# Execute main function
main "$@"
exit 0
