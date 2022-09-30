#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script manages and updates chroot environment used in Plesk
# Requirements : bash 3.x, mysql-client, GNU coreutils
# Version      : 1.6
#########

export LANG=C
export LC_ALL=C

###########################################################
# Function `err()`
# Echoes to the `stderr` and finishes script execution
# Input   : $* any number of strings (will be concatenated)
# Output  : None
# Globals : None
err() {
  echo -e "\\e[31mERROR\\e[m: $*" >&2
  exit 1
}

###########################################################
# Function `warn()`
# Echoes to the `stderr` and continues script execution
# Input   : $* any number of strings (will be concatenated)
# Output  : None
# Globals : None
warn() {
  echo -e "\\e[33mWARNING\\e[m: $*" >&2
}

###########################################################
# Function `completed()`
# Echoes predefined string to the `stdout`
# Input   : None
# Output  : None
# Globals : None
completed() {
  echo -e "\\e[32mDone!\\e[m Do not forget to run '$0 --apply domains...'" \
          "to apply changes in chroot template to domains."
}

###########################################################
# Function `sanity_check_before()`
# Performs crucial sanity checks required for `init()`
# Input   : None
# Output  : None
# Globals : None
sanity_check_before() {
  if [[ ! -e /etc/psa/psa.conf ]]; then
    err "Could not find Plesk configuration file \"/etc/psa/psa.conf\"."
  fi
  if [[ ! -e /etc/psa/.psa.shadow ]]; then
    err "Could not find Plesk MySQL password file."
  fi
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root"
  fi
  if [[ -f /etc/cloudlinux-release ]]; then
    warn "It is required to add programs to CageFS on CloudLinux: "   \
         "See https://support.plesk.com/hc/en-us/articles/213909545 " \
         "for more information"
  fi
}

###########################################################
# Function `init()`
# Initializes main globals and runs sanity checks
# Input   : None
# Output  : None
# Globals : +COPY, +PRODUCT_ROOT_D, +CHROOT_ROOT_D
init() {
  sanity_check_before

  COPY="cp -v -p -L -u"
  PRODUCT_ROOT_D=$(grep ^PRODUCT_ROOT_D /etc/psa/psa.conf | awk '{print $2}')
  HTTPD_VHOSTS_D=$(grep ^HTTPD_VHOSTS_D /etc/psa/psa.conf | awk '{print $2}')
  CHROOT_ROOT_D="$HTTPD_VHOSTS_D/chroot"

  sanity_check_after
}

###########################################################
# Function `sanity_check_after()`
# Performs sanity checks for further script work
# Input   : None
# Output  : None
# Globals : PRODUCT_ROOT_D, CHROOT_ROOT_D
sanity_check_after() {
  if [[ -z "$PRODUCT_ROOT_D" ]]; then
    err "Could not extract PRODUCT_ROOT_D from Plesk configuration."
  fi
  if [[ -z "$HTTPD_VHOSTS_D" ]]; then
    err "Could not extract HTTPD_VHOSTS_D from Plesk configuration."
  fi
  if [[ ! -d "$CHROOT_ROOT_D" ]]; then
    warn "Folder $CHROOT_ROOT_D does not exist. Some operations might fail."
  fi
  # CentOS-specific W/A: There is a dangling link /sbin -> usr/sbin
  if [[ -L "$CHROOT_ROOT_D/sbin" && ! -e "$CHROOT_ROOT_D/sbin" ]]; then
    mkdir "$CHROOT_ROOT_D/usr/sbin"
    warn "Created a $CHROOT_ROOT_D/usr/sbin directory to fix ldconfig"
  fi
}

###########################################################
# Function `usage()`
# Shows help message
# Input   : None
# Output  : None
# Globals : None
usage() {
    cat <<HELP
Manage global chroot template and apply it to domains.

Usage:
  $0 --install
  $0 --update
    Create default chroot template or update existing one using libraries
    from the system.

  $0 --rebuild
    Remove old template from all domains, rebuild it from scratch and
    reapply it. Only applications from /bin will be reinstalled.

  $0 --add [path | name]
    Add program with dependent shared libraries to the chroot template. Program
    will be put relatively in the same directory is was on the host OS.

  $0 --devices [[device] ... | all]
    Add filesystem node (special device) to the chroot template. Available
    devices are "tty", "urandom", "random", "null", "ptmx" and "zero". Some
    applications might need these devices. If no device is specified, all
    devices are created.

  $0 --locales
    Add locale definitions to the chroot template, might be required if
    non-ASCII symbols will be used in the shell.

  $0 --termcap
    Add termcap (terminal capabilities) to the chroot template to ensure
    that applications can define current terminal and supported functions.
    Also adds GNU Readline configuration file if it exists.

  $0 --remove [[domain] ... | all]
    Remove chrooted environment from specific domains or all domains with
    enabled chrooted shell.

  $0 --apply [[domain] ... | all]
    Apply new chrooted template to specific domains or all domains with
    enabled chrooted shell. This operation is necessary to apply changes done
    by '--install', '--add' and '--devices' commands.
HELP
}

###########################################################
# Function `mysql_query()`
# Runs MySQL query to the Plesk database
# Input   : $1 string (MySQL query)
# Output  : >1 string (results of the MySQL query)
# Globals : None
mysql_query() {
  local query="$1"
  MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysql -Ns -uadmin -Dpsa -e"$query"
}

###########################################################
# Function `all_domains()`
# Gets all domains, version specific
# Input   : None
# Output  : >1 string (results of the MySQL query)
# Globals : None
all_domains() {
  if [[ $(plesk_version) -lt 100 ]]; then
    mysql_query "SELECT d.name FROM domains d, hosting h, sys_users s  \
      WHERE d.id = h.dom_id AND h.sys_user_id = s.id AND               \
      s.shell = '$PRODUCT_ROOT_D/bin/chrootsh'"
  else
    mysql_query "SELECT d.name FROM domains d, hosting h, sys_users s  \
      WHERE d.id = h.dom_id AND h.sys_user_id = s.id AND               \
      s.shell = '$PRODUCT_ROOT_D/bin/chrootsh' AND d.webspace_id = 0"
  fi
}

###########################################################
# Function `plesk_version()`
# Gets Plesk version from the version file
# Input   : None
# Output  : $1 string/int (extracted Plesk version)
# Globals : PRODUCT_ROOT_D
plesk_version() {
  awk -F. '{print $1$2}' "$PRODUCT_ROOT_D/version"
}

###########################################################
# Function `add_device()`
# Parses input and creates specific device in the template
# Input   : $1 string (Device name/all)
# Output  : None
# Globals : None
add_device() {
  [ ! -d "$CHROOT_ROOT_D/dev" ] && mkdir -p "$CHROOT_ROOT_D/dev"
  case "$1" in
    "random")   create_node "random"  444 1 8
      ;;
    "urandom")  create_node "urandom" 444 1 9
      ;;
    "tty")      create_node "tty"     666 5 0
      ;;
    "ptmx")     create_node "ptmx"    666 5 2
      ;;
    "zero")     create_node "zero"    666 1 5
      ;;
    "null")     create_node "null"    666 1 3
      ;;
    "all")      add_all
      ;;
    *)          warn "$1 is not a known device, skipping."
      ;;
  esac
}

###########################################################
# Function `add_all()`
# Creates all special files (devices) in the template
# Input   : None
# Output  : None
# Globals : None
add_all() {
  local devices="random urandom tty ptmx zero null"
  for i in $devices; do
    add_device "$i"
  done
}

###########################################################
# Function `create_node()`
# Creates a special file (device) in the template
# Input   : $1 string (device name)
#           $2 int    (device mode)
#           $3 int    (mknod major)
#           $4 int    (mknod minor)
# Output  : None
# Globals : None
create_node() {
  local device="$1" mode="$2" dev_major="$3" dev_minor="$4"
  if [[ -e "$CHROOT_ROOT_D/dev/$device" ]]; then
    warn "Device $device already exists in template, skipping."
  else
    echo "Creating device $1."
    mknod -m "$mode" "$CHROOT_ROOT_D/dev/$device" c "$dev_major" "$dev_minor"
  fi
}

###########################################################
# Function `install_libs()`
# Deploys shared libraries to the chroot template
# Input   : $1 string (path to the application)
# Output  : None
# Globals : COPY, CHROOT_ROOT_D
install_libs() {
  local lib libs path="$1"
  # Extracts paths from the `ldd` output
  libs=$(ldd "$path" | grep -o '\(\/.*\s\)')
  # Trims empty entries and proceeds if the array still exists
  if [[ -n "${libs// }" ]]; then
    for lib in $libs; do
      path="$(dirname "$lib")"
      [ ! -d "$CHROOT_ROOT_D$path/" ] && mkdir -p "$CHROOT_ROOT_D$path/"
      [ ! -f "$CHROOT_ROOT_D$lib"   ] && $COPY "$lib" "$CHROOT_ROOT_D$lib"
    done
  fi
}

###########################################################
# Function `get_path()`
# Returns full path to the application
# Input   : $1 string (path to the application, or name)
# Output  : >1 string (path to the application OR
# Returns : "1" if the application is not present in $PATH)
# Globals : None
get_path() {
  local program="$1"
  if [[ ! -e "$program" ]]; then
    if ! command -v "$program" >/dev/null 2>&1; then
      warn "Could not find $program."
      return 1
    else
      program="$(type -P "$program")"
    fi
  fi
  echo "$program"
  return 0
}

###########################################################
# Function `install_chroot_program()`
# Deploys an application to the chroot template
# Input   : $1 string (path to the application)
# Output  : None
# Globals : COPY, CHROOT_ROOT_D
install_chroot_program() {
  local program="$1" filetype path
  path="$(get_path "$program")"
  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    return 1;
  fi
  binary_dir="$(dirname "$path")"
  filetype="$(file -Lib "$path")"
  case "$filetype" in
    application/octet-stream*|\
    application/x-executable*|\
    application/x-shellscript*|\
    text/x-shellscript*|\
    application/x-sharedlib*|\
	application/x-pie-executable*|\
    text/x-perl*)
      install_libs "$path"
    ;;
    *)
      warn "$path is not a program (filetype $filetype), skipping."
      return 2
    ;;
  esac

  # If the specific directory does not exist, it must be created
  if [[ ! -d "$CHROOT_ROOT_D/$binary_dir" ]]; then
    mkdir -p "$CHROOT_ROOT_D/$binary_dir"
  fi
  $COPY "$path" "$CHROOT_ROOT_D$binary_dir"

  ldpath="$(get_path "ldconfig")"
  # shellcheck disable=SC2181
  if [[ $? -eq 0 ]]; then
    if [[ ! -f "$CHROOT_ROOT_D/$ldpath" ]]; then
      ldconfig_init
    fi
    # Some applications might have lib-depends in unusual directories
    if [[ -f "$CHROOT_ROOT_D/bin/sh" ]]; then
      chroot "$CHROOT_ROOT_D" "/bin/sh" -c "ldconfig"
    fi
  fi
  return 0
}

###########################################################
# Function `ldconfig_init()`
# Deploys ldconfig, required for some programs/PHP modules
# Input   : None
# Output  : None
# Globals : COPY, CHROOT_ROOT_D
ldconfig_init() {
  $COPY "-r" /etc/ld.so.conf* "$CHROOT_ROOT_D/etc/"
  install_chroot_program ldconfig
  # Ubuntu-specific workaround
  if [[ -f /sbin/ldconfig.real ]]; then
    install_chroot_program "/sbin/ldconfig.real"
  fi
}

###########################################################
# Function `locale_init()`
# Deploys locales, so non-ASCII symbols are displayed right
# Input   : None
# Output  : None
# Globals : COPY, CHROOT_ROOT_D
locale_init() {
  termcap_init
  $COPY "-r" /usr/share/i18n "$CHROOT_ROOT_D/usr/share/"
  $COPY "-r" /usr/share/locale "$CHROOT_ROOT_D/usr/share/"
  $COPY "-r" /usr/lib/locale "$CHROOT_ROOT_D/usr/lib/"

  if command -v consoletype >/dev/null 2>&1; then
    install_chroot_program consoletype
    install_chroot_program localedef
    install_chroot_program id
    mkdir "$CHROOT_ROOT_D/etc/profile.d"
    $COPY /etc/profile "$CHROOT_ROOT_D/etc/"
    $COPY /etc/profile.d/lang.sh "$CHROOT_ROOT_D/etc/profile.d/"
    mkdir "$CHROOT_ROOT_D/etc/sysconfig"
    echo 'LANG="en_US.UTF-8"' > "$CHROOT_ROOT_D/etc/sysconfig/i18n"
    echo 'LANG="en_US.UTF-8"' > "$CHROOT_ROOT_D/etc/locale.conf"
    chroot "$CHROOT_ROOT_D" localedef -ci en_US -f UTF-8 en_US.UTF-8
  elif command -v locale-gen >/dev/null 2>&1; then
    $COPY /etc/locale.alias "$CHROOT_ROOT_D/etc/"
    install_chroot_program "locale-gen"
    install_chroot_program "echo"
    install_chroot_program "sort"
    install_chroot_program "sed"
    install_chroot_program "localedef"
    if [[ -f /etc/locale.gen ]]; then
      $COPY /etc/locale.gen "$CHROOT_ROOT_D/etc/"
      sed -i '/en_US.UTF-8 UTF-8/s/^#//' "$CHROOT_ROOT_D/etc/locale.gen"
      chroot "$CHROOT_ROOT_D" locale-gen
    else
      chroot "$CHROOT_ROOT_D" locale-gen en_US.UTF-8
    fi
    if command -v update-locale >/dev/null 2>&1; then
      mkdir "$CHROOT_ROOT_D/etc/default"
      if [[ ! -f /etc/default/locale                      \
            || $(grep -cve '^#' /etc/default/locale) == 0 \
      ]]; then
        warn "Multibyte encodings will work correctly only if host system" \
             "uses a multibyte encoding."
        warn "Consider running 'update-locale LANG=en_US.UTF8' command."
      fi
      echo 'LANG="en_US.UTF-8"' > "$CHROOT_ROOT_D/etc/default/locale"
    fi
    if [[ -d /var/lib/locales/supported.d ]]; then
      mkdir -p "$CHROOT_ROOT_D/var/lib/locales/"
      $COPY "-r" /var/lib/locales/supported.d "$CHROOT_ROOT_D/var/lib/locales/"
    fi
  else
    err "Could not determine how to generate locales in chroot."
  fi
}

###########################################################
# Function `termcap_init()`
# Deploys termcap, so terminal functions will work right
# Input   : None
# Output  : None
# Globals : COPY, CHROOT_ROOT_D
termcap_init() {
  [[ -d /etc/termcap  ]] && $COPY -r /etc/termcap "$CHROOT_ROOT_D/etc/"
  [[ -d /etc/terminfo ]] && $COPY -r /etc/terminfo "$CHROOT_ROOT_D/etc/"
  [[ -d /lib/terminfo ]] && $COPY -r /lib/terminfo "$CHROOT_ROOT_D/lib/"
  if [[ -d /usr/share/terminfo/ ]]; then
    mkdir -p "$CHROOT_ROOT_D/usr/share"
    $COPY -r /usr/share/terminfo "$CHROOT_ROOT_D/usr/share/"
  fi
  if [[ -f /etc/inputrc ]]; then
    $COPY /etc/inputrc "$CHROOT_ROOT_D/etc/"
  fi
}

###########################################################
# Function `install_ld()`
# Installs Linux dynamic loader libraries
# Input   : None
# Output  : None
# Globals : COPY, CHROOT_ROOT_D
install_ld() {
  if [[ -d /lib/x86_64-linux-gnu ]]; then
    mkdir "$CHROOT_ROOT_D/lib/x86_64-linux-gnu/"
    mkdir "$CHROOT_ROOT_D/lib64/"
    $COPY /lib/x86_64-linux-gnu/libnss_*.so.2 \
            "$CHROOT_ROOT_D/lib/x86_64-linux-gnu"
    $COPY /lib64/ld-linux* "$CHROOT_ROOT_D/lib64/"
  else
    libcheck="$(ls /lib/ld-linux* 2> /dev/null | wc -l)"
    if [[ $libcheck -ne 0 ]]; then
      $COPY /lib/ld-linux* /lib/libnss_*.so.2  "$CHROOT_ROOT_D/lib"
    fi
    if [[ -d /lib64 ]]; then
      $COPY /lib64/ld-linux* /lib64/libnss_*.so.2  "$CHROOT_ROOT_D/lib64"
    fi
  fi
}

###########################################################
# Function `install_chroot_skeleton()`
# Installs basic environment's directories
# Input   : None
# Output  : None
# Globals : CHROOT_ROOT_D
install_chroot_skeleton() {
  mkdir -m 755 "$CHROOT_ROOT_D"       "$CHROOT_ROOT_D/dev"     \
               "$CHROOT_ROOT_D/etc"   "$CHROOT_ROOT_D/lib"     \
               "$CHROOT_ROOT_D/usr"   "$CHROOT_ROOT_D/usr/bin" \
               "$CHROOT_ROOT_D/var"   "$CHROOT_ROOT_D/usr/lib" \
               "$CHROOT_ROOT_D/sbin"
   # Some OS's have /bin present as a symlink to /usr/bin
  if [[ -L "/bin" && -d "/bin" ]]; then
    ln -rs "$CHROOT_ROOT_D/usr/bin" "$CHROOT_ROOT_D/bin"
  else
    mkdir -m 755 "$CHROOT_ROOT_D/bin"
  fi
  [[ -d /lib64       ]] && mkdir -m 755 "$CHROOT_ROOT_D/lib64"
  [[ -d /usr/libexec ]] && mkdir -m 755 "$CHROOT_ROOT_D/usr/libexec"
  [[ -d /libexec     ]] && mkdir -m 755 "$CHROOT_ROOT_D/libexec"
  mkdir -m 1777 "$CHROOT_ROOT_D/tmp" "$CHROOT_ROOT_D/var/tmp"
}

###########################################################
# Function `install_chroot_base()`
# Installs almost default chroot template
# Input   : None
# Output  : None
# Globals : COPY, CHROOT_ROOT_D
install_chroot_base() {
  local CHROOT_PROGRAMS="bash cat chmod cp curl du false grep groups gunzip \
                         gzip head id less ln ls mkdir more mv pwd rm rmdir \
                         scp tail tar touch true unzip vi wget zip sh"
  local program  libcheck
  install_chroot_skeleton
  chown root.root "$CHROOT_ROOT_D"
  install_ld
  # Create necessary devices
  add_device "urandom"
  add_device "random"
  add_device "null"
  # Install default programs
  for program in $CHROOT_PROGRAMS; do
    install_chroot_program "$program"
  done
  # Get correct SFTP path and install it
  sftp_server="$(awk '/^Subsystem[[:space:]]sftp.*$/ {print $3}' \
              < /etc/ssh/sshd_config)"
  install_chroot_program "$sftp_server"
  $COPY /etc/resolv.conf "$CHROOT_ROOT_D/etc/resolv.conf"
  termcap_init
  touch "$CHROOT_ROOT_D/etc/passwd"
  touch "$CHROOT_ROOT_D/etc/group"
}

###########################################################
# Function `apply_template()`
# Applies/removes chroot template for a subscripton
# Input   : $1 string ("--apply" to apply or any to remove)
#           $2 string (domain's name)
# Output  : None
# Globals : COPY, CHROOT_ROOT_D, PRODUCT_ROOT_D
apply_template() {
  local action extra_action shell action_name domain="$2" user
  shell=$(mysql_query "SELECT s.shell FROM domains d, hosting h, sys_users s \
                       WHERE s.id = h.sys_user_id AND h.dom_id = d.id        \
                       AND d.name = '$domain'")
  if [[ -z "$shell" || "$shell" != "$PRODUCT_ROOT_D/bin/chrootsh" ]]; then
    warn "Domain $domain does not exist or has no chrooted shell" \
         "enabled, skipping."
    return
  fi
  
  user=$(mysql_query "SELECT s.login FROM domains d, hosting h, sys_users s \
                       WHERE s.id = h.sys_user_id AND h.dom_id = d.id       \
                       AND d.name = '$domain'")
  if [[ -z "$user" ]]; then
    warn "Cannot find user for the domain '$domain', skipping"
  fi
  
  if [[ "$1" == "--apply" ]]; then
    action="create"
    action_name="Applying"
    extra_action="--setup-user=$user"
  else
    action="remove"
    action_name="Removing"
    extra_action=""
  fi

  echo -n "$action_name chrooted environment on $2: "
  "$PRODUCT_ROOT_D"/admin/sbin/chrootmng --"$action"                   \
                                         --source="$CHROOT_ROOT_D"     \
                                         --target="$HTTPD_VHOSTS_D/$2" \
                                         "$extra_action"
  # Clean-up if files were changed
  if [ "$action" != "create" ]; then
    if [[ -d "${HTTPD_VHOSTS_D:?}/${2:?}/bin" ]]; then
      rm -rf "${HTTPD_VHOSTS_D:?}/${2:?}/bin"
    fi
    if [[ -d "${HTTPD_VHOSTS_D:?}/${2:?}/lib" ]]; then
      rm -rf "${HTTPD_VHOSTS_D:?}/${2:?}/lib"
    fi
    if [[ -d "${HTTPD_VHOSTS_D:?}/${2:?}/lib64" ]]; then
      rm -rf "${HTTPD_VHOSTS_D:?}/${2:?}/lib64"
    fi
    if [[ -d "${HTTPD_VHOSTS_D:?}/${2:?}/dev" ]]; then
      rm -rf "${HTTPD_VHOSTS_D:?}/${2:?}/dev"
    fi
    if [[ -d "${HTTPD_VHOSTS_D:?}/${2:?}/usr" ]]; then
      rm -rf "${HTTPD_VHOSTS_D:?}/${2:?}/usr"
    fi
  fi
  echo -e "\\e[32mDone!\\e[m Action have been completed."
}

###########################################################
# Function `full_rebuild()`
# Recreates chroot template and reapplies it
# Input   : None
# Output  : None
# Globals : COPY, CHROOT_ROOT_D
full_rebuild() {
  local program domains domain
  domains="$(all_domains)"
  installed_progs="$CHROOT_ROOT_D/bin/*"
  for domain in $domains; do
    apply_template "remove" "$domain"
  done
  echo "Removing old template"
  rm -rf "${CHROOT_ROOT_D:?}/"
  echo "Installing new template"
  install_chroot_base
  if [[ -n "${installed_progs// }" ]]; then
    echo Reinstalling programs
    for program in $installed_progs; do
      echo "Installing $(basename "$program")"
      install_chroot_program "$(basename "$program")"
    done
  fi
  for domain in $domains; do
    apply_template "--apply" "$domain"
  done
  echo -e "\\e[32mDone!\\e[m Successfully rebuilt and reappplied template."
  exit 0
}

###########################################################
# Function `main()`
# Installs almost default chroot template
# Input   : $@ array (Initial args)
# Output  : None
# Globals : None
main() {
  local program programs action domain list
  case "$1" in
    --install|--update)
      install_chroot_base && \
      completed
    ;;
    --rebuild)
      full_rebuild
      exit 0
    ;;
    --add)
      shift
      programs="$*"
      for program in $programs; do
        if ! install_chroot_program "$program"; then
          err "$program was not installed due to the previous errors."
        else
          completed
        fi
      done
    ;;
    --devices)
      shift
      list="$*"
      if [[ -z "$list" ]]; then
        err "Space-separated list of devices of word 'all' was expected."
      fi
      for dev in $list; do
        add_device "$dev"
      done
      completed
    ;;
    --locales)
      locale_init
      completed
    ;;
    --termcap)
      termcap_init
      completed
    ;;
    --apply|--remove)
      action="$1"
      shift
      list="$*"
      if [[ -z "$list" ]]; then
        err "Space-separated list of domain names or word 'all' was expected"
      elif [[ "$list" = "all" ]]; then
        list="$(all_domains)"
      fi
      for domain in $list; do
        # skips if domain does not exist or has no chrooted shell enabled
        apply_template "$action" "$domain"
      done
    ;;
    --help|"")
      usage
      exit 0
    ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
    ;;
  esac
  exit 0
}

init
main "$@"
