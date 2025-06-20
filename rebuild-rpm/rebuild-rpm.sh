#!/bin/bash
### Copyright 1999-2024. WebPros International GmbH.
###############################################################################
# Safely repairs the RPM database on Plesk and other RPM-based Linux systems.
# Performs preflight checks, creates a backup, attempts repair, and verifies
# integrity. Automatic rollback is available if repair fails.
# Requirements: bash 3.x, GNU coreutils, rpm, (yum|dnf|zypper) if available
# Version: 1.0
###############################################################################

# Usage: ./rebuild-rpm.sh [--dry-run] [--verbose] [--help]

set -euo pipefail

# Global configuration
readonly SCRIPT_NAME="${0##*/}"
readonly RPM_DB_DIR="/var/lib/rpm"
readonly BACKUP_DIR="/var/lib/rpm-backups"
readonly LOG_FILE="/var/log/plesk/rpm-repair.log"
readonly TEMP_DIR="/tmp/rpm-repair-$$"

# Global state
CLEANUP_NEEDED=false
BACKUP_CREATED=""

# Centralized logging function
log() {
    local level="$1"
    shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Use "$@" to handle arguments with spaces correctly
    echo "[${timestamp}] [${level}]" "$@" | tee -a "$LOG_FILE"
}

# Unified cleanup function
cleanup() {
    local exit_code=$?
    if [[ $CLEANUP_NEEDED == true ]]; then
        log "INFO" "Performing cleanup operations..."
        [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
        
        # If we failed and have a backup, offer recovery
        if [[ $exit_code -ne 0 && -n "$BACKUP_CREATED" ]]; then
            log "ERROR" "Script failed. To restore from backup, run:"
            log "ERROR" "tar xzf '$BACKUP_CREATED' -C '$RPM_DB_DIR'"
        fi
    fi
    
    log "INFO" "Script exiting with code: $exit_code"
    exit $exit_code
}

# Set trap for all exit scenarios
trap cleanup EXIT INT TERM ERR

# Show compatibility warning
show_compatibility_warning() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                          COMPATIBILITY WARNING                   ║
╠══════════════════════════════════════════════════════════════════╣
║ This script is designed for RPM-based systems only:             ║
║   ✓ Red Hat Enterprise Linux (RHEL)                             ║
║   ✓ CentOS / Rocky Linux / AlmaLinux                            ║
║   ✓ Fedora                                                       ║
║   ✓ openSUSE (with RPM)                                         ║
║                                                                  ║
║ NOT compatible with:                                             ║
║   ✗ Ubuntu / Debian (use APT tools instead)                     ║
║   ✗ Arch Linux (use Pacman tools instead)                       ║
║   ✗ Other non-RPM distributions                                 ║
╚══════════════════════════════════════════════════════════════════╝

EOF
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Safely repair Plesk server's RPM database with automatic backup and recovery.

OPTIONS:
    --dry-run    Show what would be done without making changes
    --verbose    Enable verbose output and command tracing
    --help       Show this help message

EXAMPLES:
    $SCRIPT_NAME --dry-run     # Preview actions
    $SCRIPT_NAME --verbose     # Run with detailed logging
    $SCRIPT_NAME               # Normal operation

LOGS:
    All operations are logged to: $LOG_FILE

BACKUPS:
    Automatic backups are stored in: $BACKUP_DIR

COMPATIBILITY:
    This script is designed for RPM-based systems (RHEL, CentOS, Fedora).
    For Ubuntu/Debian systems, use APT tools instead.
EOF
}

# Detect package management system and check for conflicts
validate_system_compatibility() {
    log "INFO" "Validating system compatibility..."

    # Ensure this is not a Debian/Ubuntu system
    if command -v dpkg >/dev/null 2>&1; then
        log "ERROR" "Debian/Ubuntu system detected (dpkg found)."
        log "ERROR" "This script is for RPM-based systems only."
        log "ERROR" "For Debian/Ubuntu, consider using: apt --fix-broken install, dpkg --configure -a"
        exit 14
    fi

    # Ensure this is not an Arch Linux system
    if command -v pacman >/dev/null 2>&1; then
        log "ERROR" "Arch Linux system detected (pacman found)."
        log "ERROR" "Use Arch Linux package management tools instead."
        exit 15
    fi

    # Ensure this is not a Gentoo system
    if command -v emerge >/dev/null 2>&1; then
        log "ERROR" "Gentoo system detected (emerge found)."
        log "ERROR" "Use Gentoo package management tools instead."
        exit 16
    fi

    # Confirm that RPM command exists
    if ! command -v rpm >/dev/null 2>&1; then
        log "ERROR" "RPM command not found. This does not appear to be an RPM-based system."
        exit 10
    fi

    # Verify RPM database directory exists
    if [[ ! -d "$RPM_DB_DIR" ]]; then
        log "ERROR" "RPM database directory not found: $RPM_DB_DIR"
        log "ERROR" "This system may not use RPM package management as expected."
        exit 11
    fi

    log "INFO" "System compatibility checks passed: RPM-based system confirmed."
}

# Validate RPM environment
validate_rpm_environment() {
    log "INFO" "Validating RPM environment..."
    
    local found_rpm_distro=false
    
    # Prefer /etc/os-release for modern systems
    if [[ -f /etc/os-release ]]; then
        # Source in a subshell to avoid polluting the script's environment
        local os_vars
        # leaving this line as is to avoid using cut or other subprocesses
        # shellcheck disable=SC1091
        os_vars=$(. /etc/os-release && echo "$ID $ID_LIKE;${PRETTY_NAME:-$NAME}")
        
        local os_id_info="${os_vars%;*}"
        local os_pretty_name="${os_vars#*;}"
        
        case " $os_id_info " in
            *" rhel "*|*" fedora "*|*" centos "*|*" suse "*|*" opensuse "*|*" rocky "*|*" alma "*|*" oracle "*)
                found_rpm_distro=true
                log "INFO" "RPM-based distribution detected: $os_pretty_name"
                ;;
        esac
    fi
    
    # Fallback for older systems without /etc/os-release
    if [[ $found_rpm_distro == false ]]; then
        for release_file in /etc/{redhat,centos,fedora,oracle,rocky,almalinux,SuSE}-release; do
            if [[ -f "$release_file" ]]; then
                found_rpm_distro=true
                # Use read instead of head to avoid a subprocess
                read -r first_line < "$release_file"
                log "INFO" "RPM-based distribution detected: ${first_line:-unknown}"
                break
            fi
        done
    fi
    
    # Warn if running on non-standard RPM system
    if [[ $found_rpm_distro == false ]]; then
        log "WARN" "Standard RPM distribution files not found"
        log "WARN" "This may not be a standard RPM-based distribution"
        
        # In non-interactive mode, abort for safety
        if [[ ! -t 0 ]]; then
            log "ERROR" "Non-interactive mode: aborting on unrecognized system"
            exit 12
        fi
        
        # Give user a chance to abort in interactive mode. Prompt on stderr.
        echo -n "This script may not be suitable for your system. Continue anyway? (y/N): " >&2
        read -r response
        if [[ ! $response =~ ^[Yy]$ ]]; then
            log "INFO" "Operation aborted by user"
            exit 12
        fi
    fi
    
    # Check for at least one package manager
    local package_managers=("yum" "dnf" "zypper")
    local found_pm=false
    for pm in "${package_managers[@]}"; do
        if command -v "$pm" >/dev/null 2>&1; then
            log "INFO" "Found package manager: $pm"
            found_pm=true
        fi
    done
    
    if [[ $found_pm == false ]]; then
        log "WARN" "No standard package managers found (yum/dnf/zypper)"
    fi
}

# Consolidated preflight checks
preflight_checks() {
    log "INFO" "Running comprehensive preflight safety checks..."
    
    # Root privilege check
    [[ $EUID -eq 0 ]] || { log "ERROR" "Must run as root"; exit 1; }
    
    # Operating system and package manager validation
    validate_system_compatibility
    validate_rpm_environment
    
    # Improved process lock check - use a while-read loop for safety
    local running_pids=()
    while IFS= read -r pid; do
        if [[ "$pid" != "$$" && "$pid" != "$BASHPID" ]]; then
            running_pids+=("$pid")
        fi
    done < <(pgrep -x rpm yum dnf zypper plesk 2>/dev/null)

    if [[ ${#running_pids[@]} -gt 0 ]]; then
        log "ERROR" "Package manager processes active. Aborting for safety."
        log "ERROR" "Active PIDs: ${running_pids[*]}"
        # Correctly format PIDs for ps (comma-separated)
        local pids_csv
        pids_csv=$(IFS=,; echo "${running_pids[*]}")
        # Use ps with no headers and loop to log each process
        ps -o pid=,cmd= -p "$pids_csv" | while IFS= read -r line; do
            log "ERROR" "  $line"
        done
        exit 3
    fi
    
    # Disk space check (require 1GB free)
    local free_space
    free_space=$(df "$RPM_DB_DIR" | awk 'NR==2 {print $4}')
    [[ $free_space -gt 1048576 ]] || { 
        log "ERROR" "Insufficient disk space (need 1GB, have $((free_space/1024))MB)"; exit 2;
    }
    
    # Create required directories
    mkdir -p "$BACKUP_DIR" "$TEMP_DIR" "$(dirname "$LOG_FILE")"
    CLEANUP_NEEDED=true
    
    log "INFO" "All preflight checks passed - RPM environment validated"
}

# Single-function backup with built-in verification
create_backup() {
    log "INFO" "Creating RPM database backup..."
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    BACKUP_CREATED="$BACKUP_DIR/rpmdb_${timestamp}.tar.gz"
    
    # Create backup with verification
    if tar czf "$BACKUP_CREATED" -C "$RPM_DB_DIR" . && 
       tar tzf "$BACKUP_CREATED" >/dev/null; then
        log "INFO" "Backup created and verified: $BACKUP_CREATED"
        # Read size into an array to avoid using cut or other subprocesses
        local backup_size_info
        read -r -a backup_size_info < <(du -h "$BACKUP_CREATED")
        log "INFO" "Backup size: ${backup_size_info[0]}"
    else
        log "ERROR" "Backup creation/verification failed"
        exit 2
    fi
}

# Restore from backup function
restore_from_backup() {
    if [[ -n "$BACKUP_CREATED" && -f "$BACKUP_CREATED" ]]; then
        log "INFO" "Restoring from backup: $BACKUP_CREATED"
        rm -rf "${RPM_DB_DIR:?}"/*
        tar xzf "$BACKUP_CREATED" -C "$RPM_DB_DIR"
        log "INFO" "Database restored from backup"
    fi
}

# Enhanced repair function with automatic rollback capability
repair_rpm_database() {
    log "INFO" "Starting RPM database repair..."
    
    # Step 1: Handle lock files safely
    local lock_files=("$RPM_DB_DIR"/__db*)
    if [[ -e "${lock_files[0]}" ]]; then
        log "INFO" "Moving ${#lock_files[@]} lock file(s) to temp directory"
        mv -f "${lock_files[@]}" "$TEMP_DIR/"
    fi
    
    # Step 2: Rebuild with transaction support
    log "INFO" "Rebuilding RPM database..."
    if ! rpm --rebuilddb; then
        log "ERROR" "Database rebuild failed - initiating rollback"
        restore_from_backup
        exit 4
    fi
    
    # Step 3: Clean package manager caches using appropriate commands
    log "INFO" "Cleaning package manager caches..."
    if command -v dnf >/dev/null 2>&1; then
        log "INFO" "Running: dnf clean all"
        dnf -q clean all 2>/dev/null || log "WARN" "dnf clean all failed but continuing"
    elif command -v yum >/dev/null 2>&1; then
        log "INFO" "Running: yum clean all"
        yum -q clean all 2>/dev/null || log "WARN" "yum clean all failed but continuing"
    fi

    if command -v zypper >/dev/null 2>&1; then
        log "INFO" "Running: zypper clean"
        zypper --non-interactive clean 2>/dev/null || log "WARN" "zypper clean failed but continuing"
    fi
    
    log "INFO" "RPM database repair completed successfully"
}

# Streamlined verification with essential checks only
verify_system_integrity() {
    log "INFO" "Verifying system integrity..."
    
    # Basic RPM functionality test
    if ! rpm -qa >/dev/null 2>&1; then
        log "ERROR" "RPM database verification failed"
        return 1
    fi
    
    local package_count
    package_count=$(rpm -qa | wc -l)
    log "INFO" "RPM database contains $package_count packages"
    
    # Plesk-specific checks
    local plesk_installed=false
    for pkg in psa plesk; do
        if rpm -q "$pkg" >/dev/null 2>&1; then
            plesk_installed=true
            log "INFO" "Plesk package detected: $pkg"
            break
        fi
    done
    
    if [[ $plesk_installed == true ]]; then
        log "INFO" "Running Plesk consistency check..."
        if command -v plesk >/dev/null; then
            plesk repair db 2>&1 | tee -a "$LOG_FILE" || {
                log "WARN" "Plesk repair reported issues - manual review needed"
            }
        fi
    else
        log "INFO" "No Plesk installation detected - skipping Plesk checks"
    fi
    
    log "INFO" "System integrity verification completed"
}

# Dry run function
perform_dry_run() {
    log "INFO" "DRY RUN MODE - No changes will be made"
    echo
    echo "The following operations would be performed:"
    echo "1. Validate RPM-based system compatibility"
    echo "2. Create backup: $BACKUP_DIR/rpmdb_$(date +%Y%m%d_%H%M%S).tar.gz"
    echo "3. Remove RPM lock files from: $RPM_DB_DIR"
    echo "4. Rebuild RPM database using: rpm --rebuilddb"
    echo "5. Clean package manager caches"
    echo "6. Verify RPM database functionality"
    echo "7. Check Plesk package integrity (if installed)"
    echo
    echo "Current system information:"
    # leaving this line as is to avoid using cut or other subprocesses
    # shellcheck disable=SC1091
    if [[ -f /etc/os-release ]]; then
        # Source in a subshell to avoid polluting environment
        echo "  OS: $(. /etc/os-release && echo "${PRETTY_NAME:-N/A}")"
    fi
    echo "  RPM packages: $(rpm -qa 2>/dev/null | wc -l || echo "N/A")"
    # Read size into an array to avoid using cut
    local db_size_info
    read -r -a db_size_info < <(du -sh "$RPM_DB_DIR" 2>/dev/null)
    echo "  Estimated disk space needed: ~${db_size_info[0]:-Unknown}"
    echo "  Backup location: $BACKUP_DIR"
    echo "  Log file: $LOG_FILE"
    echo
    log "INFO" "Dry run completed - use without --dry-run to execute"
}

# Main execution function
main() {
    show_compatibility_warning
    log "INFO" "Starting $SCRIPT_NAME"
    
    if [[ ${DRY_RUN:-false} == true ]]; then
        # Still run basic compatibility checks in dry-run mode
        validate_system_compatibility
        perform_dry_run
        return 0
    fi
    
    preflight_checks
    create_backup
    repair_rpm_database
    verify_system_integrity
    
    log "INFO" "$SCRIPT_NAME completed successfully"
    echo
    echo "✓ RPM database repair completed successfully"
    echo "✓ Backup available at: $BACKUP_CREATED"
    echo "✓ Full log available at: $LOG_FILE"
}

# Argument parsing
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) 
            DRY_RUN=true 
            ;;
        --verbose) 
            set -x 
            ;;
        --help) 
            show_usage
            exit 0 
            ;;
        *) 
            log "ERROR" "Unknown option: $1"
            echo "Use --help for usage information"
            exit 99 
            ;;
    esac
    shift
done

# Execute main function
main "$@"