#!/bin/bash
### Copyright 1999-2024. WebPros International GmbH.
###############################################################################
# Safely repairs the RPM database on Plesk and other RPM-based Linux systems.
# Performs preflight checks, creates a backup, attempts repair, and verifies
# integrity. Automatic rollback is available if repair fails.
# Requirements: bash 3.x, GNU coreutils, rpm, (yum|dnf|zypper) if available
# Version: 0.1
###############################################################################

# Usage: ./rebuild-rpm.sh [--dry-run] [--verbose] [--help]

set -euo pipefail

# Global configuration
readonly SCRIPT_NAME="$(basename "$0")"
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
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] $*" | tee -a "$LOG_FILE"
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

# Detect package management system
detect_package_system() {
    log "INFO" "Detecting package management system..."
    
    # Check if this is an RPM-based system
    if ! command -v rpm >/dev/null 2>&1; then
        log "ERROR" "RPM command not found - this appears to be a non-RPM system"
        
        # Detect specific distributions
        if [[ -f /etc/debian_version ]]; then
            log "ERROR" "Debian/Ubuntu system detected - this script is for RPM-based systems only"
            log "ERROR" "For Debian/Ubuntu systems, use instead:"
            log "ERROR" "  - apt --fix-broken install"
            log "ERROR" "  - dpkg --configure -a"
            log "ERROR" "  - apt-get clean && apt-get autoremove"
        elif [[ -f /etc/arch-release ]]; then
            log "ERROR" "Arch Linux detected - use 'pacman' package manager tools"
            log "ERROR" "  - pacman -Syu"
            log "ERROR" "  - pacman -Sc"
        else
            log "ERROR" "Unknown non-RPM system detected"
        fi
        exit 10
    fi
    
    # Verify RPM database directory exists
    if [[ ! -d "$RPM_DB_DIR" ]]; then
        log "ERROR" "RPM database directory not found: $RPM_DB_DIR"
        log "ERROR" "This system may not use RPM package management"
        exit 11
    fi
    
    log "INFO" "RPM-based system confirmed"
}

# Validate RPM environment
validate_rpm_environment() {
    log "INFO" "Validating RPM environment..."
    
    # Check for RPM-based distribution indicators
    local rpm_distros=("/etc/redhat-release" "/etc/centos-release" "/etc/fedora-release" "/etc/oracle-release" "/etc/rocky-release" "/etc/almalinux-release")
    local found_rpm_distro=false
    
    for distro_file in "${rpm_distros[@]}"; do
        if [[ -f "$distro_file" ]]; then
            found_rpm_distro=true
            log "INFO" "RPM-based distribution detected: $(cat "$distro_file" 2>/dev/null | head -1)"
            break
        fi
    done
    
    # Check for openSUSE
    if [[ -f /etc/os-release ]] && grep -q "openSUSE" /etc/os-release; then
        found_rpm_distro=true
        log "INFO" "openSUSE distribution detected"
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
        
        # Give user a chance to abort in interactive mode
        echo "Continue anyway? (y/N): "
        read -r response
        if [[ ! $response =~ ^[Yy]$ ]]; then
            log "INFO" "Operation aborted by user"
            exit 12
        fi
    fi
    
    # Verify essential RPM tools exist
    local rpm_tools=("rpm")
    local package_managers=("yum" "dnf" "zypper")
    
    for tool in "${rpm_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log "INFO" "Found essential RPM tool: $tool"
        else
            log "ERROR" "Required RPM tool not found: $tool"
            exit 13
        fi
    done
    
    # Check for at least one package manager
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

# Check for package manager conflicts
check_package_manager_conflicts() {
    log "INFO" "Checking for package manager conflicts..."
    
    # Detect APT-based systems
    if command -v apt >/dev/null 2>&1 || command -v dpkg >/dev/null 2>&1; then
        log "ERROR" "APT/DPKG package manager detected"
        log "ERROR" "This script is designed for RPM-based systems only"
        log "ERROR" ""
        log "ERROR" "For Debian/Ubuntu systems, use these alternatives:"
        log "ERROR" "  Fix broken packages: apt --fix-broken install"
        log "ERROR" "  Configure packages:  dpkg --configure -a"
        log "ERROR" "  Clean package cache: apt-get clean"
        log "ERROR" "  Update package list: apt-get update"
        log "ERROR" "  Autoremove unused:   apt-get autoremove"
        exit 14
    fi
    
    # Check for other package managers
    if command -v pacman >/dev/null 2>&1; then
        log "ERROR" "Pacman package manager detected (Arch Linux)"
        log "ERROR" "Use Arch Linux package management tools instead"
        exit 15
    fi
    
    if command -v emerge >/dev/null 2>&1; then
        log "ERROR" "Portage package manager detected (Gentoo)"
        log "ERROR" "Use Gentoo package management tools instead"
        exit 16
    fi
    
    log "INFO" "No conflicting package managers detected"
}

# Consolidated preflight checks
preflight_checks() {
    log "INFO" "Running comprehensive preflight safety checks..."
    
    # Root privilege check
    [[ $EUID -eq 0 ]] || { log "ERROR" "Must run as root"; exit 1; }
    
    # NEW: Operating system and package manager validation
    detect_package_system
    validate_rpm_environment
    check_package_manager_conflicts
    
    # Improved process lock check
    local pm_pids=""
    for pm in rpm yum dnf zypper; do
        for pid in $(pgrep -x "$pm" 2>/dev/null); do
            # Exclude our own PID and shell subshells
            if [[ "$pid" != "$$" && "$pid" != "$BASHPID" ]]; then
                pm_pids="$pm_pids $pid"
            fi
        done
    done
    if [[ -n "$pm_pids" ]]; then
        log "ERROR" "Package manager processes active. Aborting for safety."
        log "ERROR" "Active PIDs:$pm_pids"
        for pid in $pm_pids; do
            log "ERROR" "PID $pid: $(ps -p $pid -o cmd=)"
        done
        exit 3
    fi
    
    # Disk space check (require 1GB free)
    local free_space=$(df "$RPM_DB_DIR" | awk 'NR==2 {print $4}')
    [[ $free_space -gt 1048576 ]] || { 
        log "ERROR" "Insufficient disk space (need 1GB, have $(($free_space/1024))MB)"; exit 2; 
    }
    
    # Create required directories
    mkdir -p "$BACKUP_DIR" "$TEMP_DIR" "$(dirname "$LOG_FILE")"
    CLEANUP_NEEDED=true
    
    log "INFO" "All preflight checks passed - RPM environment validated"
}

# Single-function backup with built-in verification
create_backup() {
    log "INFO" "Creating RPM database backup..."
    local timestamp=$(date +%Y%m%d_%H%M%S)
    BACKUP_CREATED="$BACKUP_DIR/rpmdb_${timestamp}.tar.gz"
    
    # Create backup with verification
    if tar czf "$BACKUP_CREATED" -C "$RPM_DB_DIR" . && 
       tar tzf "$BACKUP_CREATED" >/dev/null; then
        log "INFO" "Backup created and verified: $BACKUP_CREATED"
        log "INFO" "Backup size: $(du -h "$BACKUP_CREATED" | cut -f1)"
    else
        log "ERROR" "Backup creation/verification failed"
        exit 2
    fi
}

# Restore from backup function
restore_from_backup() {
    if [[ -n "$BACKUP_CREATED" && -f "$BACKUP_CREATED" ]]; then
        log "INFO" "Restoring from backup: $BACKUP_CREATED"
        rm -rf "$RPM_DB_DIR"/*
        tar xzf "$BACKUP_CREATED" -C "$RPM_DB_DIR"
        log "INFO" "Database restored from backup"
    fi
}

# Enhanced repair function with automatic rollback capability
repair_rpm_database() {
    log "INFO" "Starting RPM database repair..."
    
    # Step 1: Handle lock files safely
    local lock_files=("$RPM_DB_DIR"/__db*)
    if [[ -f "${lock_files[0]}" ]]; then
        log "INFO" "Moving $(ls "$RPM_DB_DIR"/__db* 2>/dev/null | wc -l) lock files to temp directory"
        mv "$RPM_DB_DIR"/__db* "$TEMP_DIR/" 2>/dev/null || true
    fi
    
    # Step 2: Rebuild with transaction support
    log "INFO" "Rebuilding RPM database..."
    if ! rpm --rebuilddb; then
        log "ERROR" "Database rebuild failed - initiating rollback"
        restore_from_backup
        exit 4
    fi
    
    # Step 3: Clean package manager caches
    log "INFO" "Cleaning package manager caches..."
    for cmd in "yum clean all" "dnf clean all" "zypper clean"; do
        local pm_cmd="${cmd%% *}"
        if command -v "$pm_cmd" >/dev/null 2>&1; then
            log "INFO" "Running: $cmd"
            $cmd --quiet 2>/dev/null || true
        fi
    done
    
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
    
    local package_count=$(rpm -qa | wc -l)
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
    if [[ -f /etc/os-release ]]; then
        echo "  OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    fi
    echo "  RPM packages: $(rpm -qa 2>/dev/null | wc -l || echo "N/A")"
    echo "  Estimated disk space needed: ~$(du -sh "$RPM_DB_DIR" 2>/dev/null | cut -f1 || echo "Unknown")"
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
        detect_package_system
        check_package_manager_conflicts
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
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) 
            DRY_RUN=true 
            ;;
        --verbose) 
            VERBOSE=true
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