#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This pre-upgrade helper script prepares Plesk and the system for the upgrade
# Requirements : bash 3.x, mysql-client, GNU coreutils
# Version      : 1.0
#########



#default values

product_default_conf()
{

PRODUCT_ROOT_D=/opt/psa
PRODUCT_RC_D=/etc/init.d
PRODUCT_ETC_D=/opt/psa/etc
PLESK_LIBEXEC_DIR=/usr/lib/plesk-9.0
HTTPD_VHOSTS_D=/var/www/vhosts
HTTPD_CONF_D=/etc/apache2
HTTPD_INCLUDE_D=/etc/apache2/conf-enabled
HTTPD_BIN=/usr/sbin/apache2
HTTPD_LOG_D=/var/log/apache2
HTTPD_SERVICE=apache2
QMAIL_ROOT_D=/var/qmail
PLESK_MAILNAMES_D=/var/qmail/mailnames
RBLSMTPD=/usr/sbin/rblsmtpd
NAMED_RUN_ROOT_D=/var/named/run-root
NAMED_OPTIONS_CONF=
NAMED_ZONES_CONF=
WEB_STAT=/usr/bin/webalizer
MYSQL_VAR_D=/var/lib/mysql
MYSQL_BIN_D=/usr/bin
MYSQL_SOCKET=/var/run/mysqld/mysqld.sock
PGSQL_DATA_D=/var/lib/postgresql/9.4/main
PGSQL_CONF_D=/etc/postgresql/9.4/main
PGSQL_BIN_D=/usr/lib/postgresql/9.4/bin
DUMP_D=/var/lib/psa/dumps
DUMP_TMP_D=/tmp
MAILMAN_ROOT_D=/usr/lib/mailman
MAILMAN_VAR_D=/var/lib/mailman
PYTHON_BIN=/usr/bin/python
DRWEB_ROOT_D=/opt/drweb
DRWEB_ETC_D=/etc/drweb
GPG_BIN=/usr/bin/gpg
TAR_BIN=/usr/lib/plesk-9.0/sw-tar
AWSTATS_ETC_D=/etc/awstats
AWSTATS_BIN_D=/usr/lib/cgi-bin
AWSTATS_TOOLS_D=/usr/share/awstats/tools
AWSTATS_DOC_D=/usr/share/awstats
OPENSSL_BIN=/usr/bin/openssl
LIB_SSL_PATH=/lib/libssl.so
LIB_CRYPTO_PATH=/lib/libcrypto.so
CLIENT_PHP_BIN=/opt/psa/bin/php-cli
SNI_SUPPORT=true
APS_DB_DRIVER_LIBRARY=/usr/lib/x86_64-linux-gnu/libmysqlserver.so.2
IPv6_DISABLED=false
SA_MAX_MAIL_SIZE=256000

}

true apache_status_linux_debian

apache_status_linux_debian()
{
	get_pid "/usr/sbin/apache2" false
	local pid=$common_var
	if test "$pid" -ne 1; then
# running
		return 0
	fi
	return 1
}

set_apsc_params()
{
	odbc_config_bin="/usr/bin/odbc_config" # present at least on CentOS 5
	if [ -x "$odbc_config_bin" ]; then
		odbc_dsn_conf=`$odbc_config_bin --odbcini 2>> "$product_log"`
		odbc_drivers_conf=`$odbc_config_bin --odbcinstini 2>> "$product_log"`
	fi
	if [ -z "$odbc_dsn_conf" ]; then
		odbc_dsn_conf="/etc/odbc.ini"
	fi
	if [ -z "$odbc_drivers_conf" ]; then
		odbc_drivers_conf="/etc/odbcinst.ini"
	fi

	odbc_isql_bin="/usr/bin/isql"
	odbc_iusql_bin="/usr/bin/iusql"

	odbc_mysql_drivers="/usr/lib/x86_64-linux-gnu/odbc/libmyodbc5w-plesk.so"
	for d in $odbc_mysql_drivers; do
		[ -s $d ] || continue
		odbc_mysql_driver="$d"
		break
	done

	if [ -z "$odbc_mysql_driver" ]; then
		die "No ODBC MySQL mysql drivers found, trying $odbc_mysql_drivers"
	fi

	if [ -s "/usr/lib/x86_64-linux-gnu/sw/libmysqlserver.so.2.0" ]; then
		apsc_driver_library="/usr/lib/x86_64-linux-gnu/sw/libmysqlserver.so.2.0"
	elif [ -s "/usr/lib/x86_64-linux-gnu/libmysqlserver.so.2.0" ]; then
		apsc_driver_library="/usr/lib/x86_64-linux-gnu/libmysqlserver.so.2.0"
	else
		die "find MySQL mysql platform driver for APSC"
	fi
}

check_ini_section_exists()
{
	local section="$1"
	local file="$2"
	grep -q "\[$section\]" "$file" >/dev/null 2>&1
}

check_odbc_driver_exists()
{
	# We could use odbcinst here, but it wouldn't save us much trouble
	local driver="$1"
	check_ini_section_exists "$driver" "$odbc_drivers_conf"
}

remove_ini_section()
{
	local section="$1"
	local file="$2"
	[ -r "$file" ] || return 0
	awk "/\[.*\]/ { del = 0 } /\[$section\]/ { del = 1 } ( del != 1 ) { print }" "$file" > "$file.new" && \
	mv -f "$file.new" "$file"
}

remove_odbc_driver()
{
	local driver="$1"
	remove_ini_section "$driver" "$odbc_drivers_conf"
}

apsc_try_create_odbc_driver()
{
	check_odbc_driver_exists "$apsc_odbc_driver_name" && return 1

	local odbc_mysql_driver64=
	if echo "$odbc_mysql_driver" | grep -q lib64 2>/dev/null ; then
		odbc_mysql_driver64="$odbc_mysql_driver"
	fi

	cp -f "$odbc_drivers_conf" "$odbc_drivers_conf.new" && \
	cat <<EOF >> "$odbc_drivers_conf.new" && mv -f "$odbc_drivers_conf.new" "$odbc_drivers_conf"
[$apsc_odbc_driver_name]
Description = MySQL driver for Plesk
Driver      = $odbc_mysql_driver
Setup       = 
FileUsage   = 1
Driver64    = $odbc_mysql_driver64
Setup64     = 
UsageCount  = 1

EOF
	local rc="$?"
	[ "$rc" -eq 0 ] || rm -f "$odbc_drivers_conf.new"
	return "$rc"
}

apsc_modify_odbc_driver()
{
	# just remove the one that bothers us
	remove_odbc_driver "$apsc_odbc_driver_name"
}

# vim:ft=sh:
### Copyright 1999-2022. Plesk International GmbH.
# vim: ft=sh

distupgrade_add_message()
{
	if [ -z "$DISTUPGRADE_MESSAGES" ]; then
		DISTUPGRADE_MESSAGES="$*"
	else
		DISTUPGRADE_MESSAGES="$DISTUPGRADE_MESSAGES\n$*"
	fi
}

distupgrade_show_messages()
{
	printf "\n$DISTUPGRADE_MESSAGES\n"
}

distupgrade_check_utility()
{
	if ! which "$1" >/dev/null 2>&1 ; then
		echo "$1 utility is not available. Dist-upgrade will not continue. Install it and rerun the script."
		return 1
	fi
	return 0
}

distupgrade_deb_prepare()
{
	product_default_conf

	export PLESK_INSTALLER_VERBOSE=1
	export PLESK_INSTALLER_DEBUG=1
	export DEBIAN_FRONTEND=noninteractive
	export LANG=C LANGUAGE=C LC_ALL=C

	backup_suffix="saved_by_plesk_distupgrade_from_$PREV_CODENAME"

	aptitude_env="env DEBIAN_FRONTEND=noninteractive LANG=C LANGUAGE=C LC_ALL=C"
	aptitude_options="--assume-yes -o Dpkg::options::=--force-confdef -o Dpkg::Options::=--force-confnew -o APT::Get::AllowUnauthenticated=true $ADDITIONAL_APTITUDE_OPTIONS"
	if [ "$USE_APT_GET" = "yes" ]; then
		distupgrade_check_utility "apt-get" || return 1
		aptitude="$aptitude_env apt-get"
		get_available_updates()
		{
			# capture only packages which goes after 'will be upgraded:'
			# ```
			# The following packages will be upgraded:
			#   base-files bind9 bind9-host bind9utils...
			#   libcurl3-gnutls libdb5.3 libdns-export100...
			#   libisccfg-export90 libisccfg90
			# ```
			$aptitude --show-upgraded --dry-run upgrade | sed -ne '/will be upgraded:/,/^\S/ { /^\s/p }' | xargs
			return ${PIPESTATUS[0]}
		}
		reinstall_opt="install --reinstall"
	else
		distupgrade_check_utility "aptitude" || return 1
		aptitude="$aptitude_env aptitude"
		aptitude_options="--allow-untrusted $aptitude_options"
		get_available_updates()
		{
			$aptitude search -F '%p' --disable-columns '~U'
		}
		reinstall_opt="reinstall"
	fi

	sources_list="/etc/apt/sources.list"
	sources_list_d="/etc/apt/sources.list.d"
	sources_list_ai_back="$sources_list.ai_back"
	backup_sources_list_d="/etc/apt"

	autoinstaller="$PRODUCT_ROOT_D/admin/sbin/autoinstaller"

	bootstrapper_flag="/tmp/pp-bootstrapper-mode.flag"

	apache_disabled_modules_path="/var/lib/plesk/distupgrade_apache_disabled_modules.txt"

	wdservice_bin="$PRODUCT_ROOT_D/admin/sbin/modules/watchdog/wdservice"
	wdservice_conf_d="$PRODUCT_ROOT_D/etc/modules/watchdog"
	watchdod_active_flag_path="/var/lib/plesk/distupgrade_watchdog_active.flag"

	stagedir="$PRODUCT_ROOT_D/tmp/distupgrade_$PREV_CODENAME"
	[ -d "$stagedir" ] || mkdir -p "$stagedir"

	DISTUPGRADE_MESSAGES=""

	[ "$opt_debug" = "0" ] || set -x
}

distupgrade_deb_switch_sh_to_bash()
{
	echo "dash dash/sh boolean false" | debconf-set-selections
	$aptitude_env dpkg-reconfigure dash
}

distupgrade_deb_accept()
{
	[ ! -f "$stagedir/middle_update.flag" ] || return 0

	echo ""
	echo "You are about to perform dist-upgrade from $DIST_NAME $PREV_VERSION ($PREV_CODENAME) to $DIST_NAME $NEXT_VERSION ($NEXT_CODENAME)."
	echo "Make sure that you understand the changes that will be made to your system and the risks associated with dist-upgrade."
	echo "Please read the following KB article: https://kb.plesk.com/en/126808 before proceeding."
	echo ""
	echo "Press any key to continue, or press CTRL+C to cancel."
	echo ""

	read answer

	return 0
}

distupgrade_deb_set_up()
{
	touch "$bootstrapper_flag"
	distupgrade_deb_hold_packages $packages_to_exclude
}

distupgrade_deb_tear_down()
{
	distupgrade_deb_unhold_packages $packages_to_exclude
	rm -f "$bootstrapper_flag"
}

distupgrade_deb_check_updates()
{
	if [ -e "$sources_list.$backup_suffix" ]; then
		distupgrade_add_message "Skip checking if latest packages are installed since $sources_list has been already updated"
		return 0
	fi

	$aptitude update || return $?

	local available_updates
	available_updates="`get_available_updates`"
	[ "$?" = "0" ] || return 1
	if [ -n "$available_updates" ]; then
		echo "The following packages are not up-to-date:"
		echo $available_updates
		echo "You should install the latest updates before performing dist-upgrade"
		return 1
	fi
	return 0
}

distupgrade_backup_file()
{
	local file="$1"
	local dry_run="${2:-}"
	local backup_path
	if expr match "$file" "/etc/init.d/" >/dev/null; then
		# save init scripts in /etc to avoid conflicts with insserv
		local backup_dir="/etc/init.d.$backup_suffix"
		[ ! -z "$dry_run" ] || mkdir -p "$backup_dir"
		backup_path="$backup_dir/`basename $file`"
	else
		backup_path="$file.$backup_suffix"
	fi
	[ ! -z "$dry_run" ] || cp -f "$file" "$backup_path"
	echo "$backup_path"
}

distupgrade_deb_revert_packages_configuration()
{
	local packages="$PACKAGE_CONGIFS_TO_REVERT"
	local revert_packages=""
	local revert_configs=""

	local backup_path

	[ -n "$packages" ] || return 0

	for p in $packages; do
		local pi=`echo $p | cut -f 1 -d@`
		local configs="`echo $p | cut -f2- -d@ | tr @ ' '`"
		if dpkg -s "$pi" >/dev/null 2>&1; then
			for conf in $configs; do
				[ -e "$conf" ] || continue
				if [ -e "$conf.$backup_suffix" ]; then
					distupgrade_add_message "Config file '$conf' is already reverted. Skip."
					continue
				fi
				backup_path=`distupgrade_backup_file "$conf"`
				rm -f "$conf"
				revert_packages="$revert_packages $pi"
				revert_configs="$revert_configs $conf"

				distupgrade_add_message "Config file '$conf' is reverted to package state. User version of file is saved in '$backup_path'."
			done
		fi
	done
	[ -n "$revert_packages" ] || return 0
	$aptitude $aptitude_options -o Dpkg::Options::="--force-confmiss" $reinstall_opt $revert_packages

	for conf in $revert_configs; do
		if [ ! -e $conf ]; then
			distupgrade_add_message "Config file '$conf' is missed after reverting. Restore user version."
			backup_path=`distupgrade_backup_file "$conf" --dry-run`
			if ! cp "$backup_path" "$conf"; then
				distupgrade_add_message "Can't restore user version from '$conf.$backup_suffix'"
				return 1
			fi
		fi
	done
}

distupgrade_deb_save_files()
{
	local files="$FILES_TO_SAVE"
	[ -n "$files" ] || return 0
	for f in $files; do
		if [ -e "$f.$backup_suffix" ]; then
			distupgrade_add_message "File '$f.$backup_suffix' exists. Skip saving '$f'."
		else
			cp "$f" "$f.$backup_suffix"
			distupgrade_add_message "File '$f' is stored to '$f.$backup_suffix'."
		fi
	done
}

distupgrade_deb_restore_files()
{
	local files="$FILES_TO_SAVE"
	[ -n "$files" ] || return 0
	for f in $files; do
		cp -f "$f" "$f.dpkg-new"
		cp -f "$f.$backup_suffix" "$f"
		distupgrade_add_message "File '$f' is restored from '$f.$backup_suffix'. Installed version saved in '$f.dpkg-new'."
	done
}

distupgrade_deb_remove_files_pre()
{
	local files="$REMOVE_FILES_PRE"
	[ -n "$files" ] || return 0
	for f in $files; do
		if expr match "$f" "-" > /dev/null; then
			# "-/path/to/file" -- marked to remove. No message is required.
			f=`echo $f | cut -c 2-`
			rm -f "$f"
		elif [ -e "$f" ]; then
			# "/path/to/file" -- marked to rename (backup)
			mv "$f" "$f.$backup_suffix"
			distupgrade_add_message "File '$f' is renamed to '$f.$backup_suffix'."
		fi
	done
}

distupgrade_deb_handle_mailman_queue()
{
	local unshunt="/var/lib/mailman/bin/unshunt"
	local qfiles_d="/var/lib/mailman/qfiles"
	local workaround_unshunt="$1"

	[ -d "$qfiles_d" ] || return 0

	if [ "$workaround_unshunt" -gt 0  -a -x "$unshunt" ]; then
		"$unshunt"
	fi

	local files="`find "$qfiles_d" -type f`"

	if [ -n "$files" ] ; then
		if [ "$workaround_unshunt" -gt 0 ]; then
			rm -f $files
		else
			echo "The directory "$qfiles_d" contains files. It needs to be empty for the upgrade to work properly."
			return 1
		fi
 	fi
}

distupgrade_deb_stop_watchdog_pre()
{
	rm -f "$watchdod_active_flag_path"
	if [ -x "$wdservice_bin" ]; then
		if "$wdservice_bin" monit status | grep -q 'is active' && \
			"$wdservice_bin" wdcollect status | grep -q 'is active'; then
			touch "$watchdod_active_flag_path"
		fi
		"$wdservice_bin" monit stop "$wdservice_conf_d/monitrc" || true
		"$wdservice_bin" wdcollect stop "$wdservice_conf_d/wdcollect.inc.php" || true
	fi
}

distupgrade_deb_start_watchdog_post()
{
	if [ -x "$wdservice_bin" -a -e "$watchdod_active_flag_path" ]; then
		"$wdservice_bin" monit start "$wdservice_conf_d/monitrc" || true
		"$wdservice_bin" wdcollect start "$wdservice_conf_d/wdcollect.inc.php" || true
		rm -f "$watchdod_active_flag_path"
	fi
}

distupgrade_deb_fix_aps_db_driver_library()
{
	set_apsc_params
	if [ ! -f "$apsc_driver_library" ];	then
		echo "find MySQL platform driver library"
		return 1
	fi
	conf_setval "/etc/psa/psa.conf" APS_DB_DRIVER_LIBRARY "$apsc_driver_library"

	apsc_odbc_driver_name="MySQL"

	apsc_modify_odbc_driver
	apsc_try_create_odbc_driver
}

distupgrade_deb_fix_named_initscript()
{
	read_conf
	set_named_params

	pleskrc named stop
	debian_fix_named_iniscript
	sysconfig_named
	pleskrc named restart
}

distupgrade_deb_force_install_packages()
{
	local packages="$PACKAGES_TO_FORCE_INSTALL"
	local forced_packages=""

	[ -n "$packages" ] || return 0

	for p in $packages; do
		local pi=`echo $p | cut -f 1 -d@`
		local pu
		if expr match "$p" ".*@" >/dev/null 2>&1; then
			pu=`echo $p | cut -f 2 -d@`
		else
			pu="$pi"
		fi
		if dpkg -s "$pi" >/dev/null 2>&1; then
			forced_packages="$forced_packages $pu"
		fi
	done
	$aptitude update || return $?
	$aptitude $aptitude_options install $forced_packages
}

distupgrade_deb_pre_install_packages()
{
	local packages="$PACKAGES_TO_INSTALL_PRE"
	[ -n "$packages" ] || return 0
	$aptitude $aptitude_options install $packages
}

distupgrade_deb_post_install_packages()
{
	local packages="$PACKAGES_TO_INSTALL_POST"
	local forced_packages=""

	[ -n "$packages" ] || return 0

	for p in $packages; do
		local pi=`echo $p | cut -f 1 -d@`
		local pu=`echo $p | cut -f 2 -d@`
		if dpkg -s "$pi" >/dev/null 2>&1; then
			forced_packages="$forced_packages $pu"
		fi
	done
	[ "`arch`" != "x86_64" ] || dpkg --add-architecture i386
	$aptitude update || return $?
	$aptitude $aptitude_options install $forced_packages || return $?
	[ "`arch`" != "x86_64" ] || dpkg --remove-architecture i386
}
distupgrade_deb_post_remove_packages()
{
	local packages="$PACKAGES_TO_REMOVE_POST"
	[ -n "$packages" ] || return 0
	$aptitude $aptitude_options remove --purge $packages
}

distupgrade_deb_cleanup_apache_configuration()
{
	local modules="$APACHE_MODULES_TO_DISABLE"
	local enabled_modules_d="/etc/apache2/mods-enabled"
	local disabled_modules=""

	local httpd_modules_ctl="$PRODUCT_ROOT_D/admin/sbin/httpd_modules_ctl"

	[ -n "$modules" ] || return 0

	for m in $modules; do
		if [ -x "$httpd_modules_ctl" ]; then
			"$httpd_modules_ctl" --status --all-modules | egrep "^$m\s+on" || continue
		fi
		a2dismod "$m"
		rm -f "$enabled_modules_d/$m.conf"
		rm -f "$enabled_modules_d/$m.load"

		distupgrade_add_message "Apache module '$m' has been disabled."
		disabled_modules="$disabled_modules $m"
	done
	echo $disabled_modules >> $apache_disabled_modules_path
}

distupgrade_deb_restore_apache_configuration()
{
	[ -s "$apache_disabled_modules_path" ] || return 0

	local modules="`cat $apache_disabled_modules_path`"

	for m in $modules; do
		a2enmod "$m"
		distupgrade_add_message "Apache module '$m' has been enabled."
	done

	rm -f "$apache_disabled_modules_path"

	conf_setval "/etc/psa/psa.conf" HTTPD_INCLUDE_D "/etc/apache2/conf-enabled"
}

distupgrade_deb_upgrade_apt_repo()
{
	local path="$1"
	local suffix="$2"
# source.list entry format : deb [ options ] uri distribution [component1] [component2] [...]
	perl -i$suffix -pale "if (\$F[0] eq 'deb' || \$F[0] eq 'deb-src') { \$F[\$F[1] =~ /^\[/ ? 3 : 2] =~ s/$PREV_CODENAME/$NEXT_CODENAME/g; \$_ = join ' ', @F }" "$path"
}

distupgrade_deb_upgrade_apt_repos()
{
	if [ ! -e "$sources_list.$backup_suffix" ]; then
		cp -f "$sources_list" "$sources_list.$backup_suffix"
		"$autoinstaller" --skip-cleanup --check-updates
		rm -f "$sources_list_ai_back"

		distupgrade_deb_upgrade_apt_repo "$sources_list"
		distupgrade_add_message "'$sources_list' has been updated: '$PREV_CODENAME' is replaced with '$NEXT_CODENAME', Plesk repositories were added. Original file is saved in '$sources_list.$backup_suffix'."
	else
		distupgrade_add_message "'$sources_list' has been already updated. Skip."
	fi

	if ls "$sources_list_d"/*.list > /dev/null 2>&1; then
		for list in "$sources_list_d"/*.list; do
			local backup="$backup_sources_list_d"/$(basename "$list")."$backup_suffix"
			if [ ! -e "$backup" ]; then
				cp -f "$list" "$backup"
				distupgrade_deb_upgrade_apt_repo "$list"
				distupgrade_add_message "'$list' has been updated: '$PREV_CODENAME' is replaced with '$NEXT_CODENAME'. Original file is saved in '$backup'."
			else
				distupgrade_add_message "'$list' has been already updated. Skip."
			fi
		done
	fi
}

distupgrade_deb_check_plesk_packages_have_updates()
{
	local out_of_date
	out_of_date=`$autoinstaller --select-product plesk --select-release-current --show-components | perl -nale \
		'print $F[0] if $F[0] =~ /common|panel|engine/ && $F[1] eq "[upgrade]"'`
	
	if [ -n "$out_of_date" ]; then
		echo "Some of the essential Plesk components are not up-to-date:" $out_of_date
		echo "You may either upgrade them manually or rerun this utility with option --skip-check-latest"

		return 1
	fi
}

distupgrade_deb_hold_packages()
{
	for p in "$@"; do
		echo "$p hold" | dpkg --set-selections
	done
}

distupgrade_deb_unhold_packages()
{
	for p in "$@"; do
		echo "$p install" | dpkg --set-selections
	done
}

distupgrade_deb_work_pre()
{
	if [ ! -e "$sources_list.$backup_suffix" ]; then
# It's rather dangerous to perform any apt-related actions in pre-stage if sources.list is updated to the next release
		$aptitude update || return $?
		distupgrade_deb_revert_packages_configuration
		$aptitude $aptitude_options dist-upgrade || return $?
	fi
	distupgrade_deb_stop_watchdog_pre
	distupgrade_deb_cleanup_apache_configuration
	distupgrade_deb_remove_files_pre
	distupgrade_deb_save_files
	distupgrade_deb_upgrade_apt_repos

	for func in $DISTUPGRADE_ADDITIONAL_ACTION_PRE; do
		$func || return $?
	done
}

distupgrade_deb_work_post()
{
	distupgrade_deb_post_install_packages
	distupgrade_deb_post_remove_packages
	distupgrade_deb_restore_files
	distupgrade_deb_restore_apache_configuration
	distupgrade_deb_fix_aps_db_driver_library
	distupgrade_deb_fix_named_initscript

# restore mail logging configuration in syslog
	select_maillog

	for func in $DISTUPGRADE_ADDITIONAL_ACTION_POST; do
		$func || return $?
	done

	# restore user's sources.lsit
	mv -f "$sources_list.$backup_suffix" "$sources_list"
	distupgrade_deb_upgrade_apt_repo  "$sources_list" ".$backup_suffix"
	distupgrade_add_message "'$sources_list' has been updated: '$PREV_CODENAME' is replaced with '$NEXT_CODENAME'. Original file is saved in '$sources_list.$backup_suffix'"

	/opt/psa/bootstrapper/pp17.8.11-bootstrapper/bootstrapper.sh post-install BASE || {
		echo "Bootstrapper post-install actions for component base failed"
		return 1
	}
	/opt/psa/bootstrapper/pp17.8.11-bootstrapper/bootstrapper.sh repair || {
		echo "Bootstrapper repair actions failed"
		return 1
	}
	service psa restart

	"$autoinstaller" --select-product plesk --select-release-current --upgrade-installed-components --reinstall-patch || {
		echo "Upgrade of installed Plesk components failed"
		return 1
	}
	distupgrade_deb_start_watchdog_post
}

distupgrade_deb_parse_args()
{
	local PN=`basename $0`
	shift
	local TEMP="`getopt -o hx:ds --long help,exclude:,debug,skip-check-latest,workaround-mailman-unshunt -n "$PN" -- "$@"`"
	if [ $? -ne 0 ] ; then echo "Error during parsing command line arguments." >&2 ; exit 1 ; fi
	eval set -- "$TEMP"

	local usage=" usage:
-x, --exclude <package>       keep packages from upgrading
-s, --skip-check-latest       skip check for the latest packages are installed
--workaround-mailman-unshunt  unshunt messages in mailman queue before upgrade
-d, --debug                   enable debug logging
-h, --help                    show this help
"

	packages_to_exclude=""
	opt_debug=0
	opt_skip_check_latest=0
	opt_workaround_mailman_unshunt=0

	while true; do
		case "$1" in
			-x|--exclude) packages_to_exclude="$packages_to_exclude $2"; shift 2;;
			-s|--skip-check-latest) opt_skip_check_latest=1; shift;;
			--workaround-mailman-unshunt) opt_workaround_mailman_unshunt=1; shift;;
			-d|--debug) opt_debug=1; shift;;
			-h|--help) echo "$usage"; exit 0;;
			--) shift; break ;;
			*) echo "Unexpected option: $1"; exit 1;;
		esac
	done
}

distupgrade_error_message()
{
	local stage="$1"
	echo "Some error during dist-upgrade $stage stage have occurred."
	echo "Check $DISTUPGRADE_LOG for error details."
	echo "Visit $DISTUPGRADE_DOC for information about troubleshooting and recovering from failed dist-upgrade."
}

distupgrade_deb_main_pre()
{
	[ ! -f "$stagedir/pre.flag" ] || return 0

	distupgrade_deb_parse_args "$@" && \
	distupgrade_deb_prepare && \
	distupgrade_deb_switch_sh_to_bash && \
# before-distupgrade checks in user-mode:
	{ [ "$opt_skip_check_latest" -gt 0 ] || distupgrade_deb_check_updates; } && \
	distupgrade_deb_handle_mailman_queue $opt_workaround_mailman_unshunt && \
#
	distupgrade_deb_set_up && \
	distupgrade_deb_work_pre && \
	distupgrade_show_messages || \
	{ distupgrade_error_message "pre"; return 1; }

	echo "Now you can perform dist-upgrade to $NEXT_CODENAME using any method you like."
	[ -z "$HELP_URL" ] || echo "You can visit $HELP_URL for more information."
	[ -z "$DISTUPGRADE_POST_SCRIPT" ] || echo "After system dist-upgrade is finished run '$DISTUPGRADE_POST_SCRIPT'."

	touch -f "$stagedir/pre.flag"
}

distupgrade_deb_main_middle()
{
	[ ! -f "$stagedir/middle.flag" ] || return 0

	if [ ! -f "$stagedir/middle_update.flag" ]; then
		$aptitude update && \
		distupgrade_deb_pre_install_packages || return $?
		touch "$stagedir/middle_update.flag"
	fi

	$aptitude $aptitude_options upgrade
	local upgrade_ret=$?
	if [ "$upgrade_ret" -ne "0" ]; then
# workaround for PPP-12052 Postgresql dist-upgrade failed
		echo "Safe-upgrade step failed with exit code $upgrade_ret. Trying to rerun safe-upgrade step."
		$aptitude $aptitude_options upgrade || return $?
	fi

	distupgrade_deb_force_install_packages && \
	$aptitude $aptitude_options $APTITUDE_DISTUPGRADE_NEW_ADD_OPTS dist-upgrade || \
	{ distupgrade_error_message "middle"; return 1; }

	touch -f "$stagedir/middle.flag"
}

distupgrade_deb_main_post()
{
	[ ! -f "$stagedir/post.flag" ] || return 0

	distupgrade_deb_parse_args "$@" && \
	distupgrade_deb_prepare && \
	{ [ "$opt_skip_check_latest" -gt 0 ] || distupgrade_deb_check_plesk_packages_have_updates; } && \
	distupgrade_deb_work_post && \
	distupgrade_deb_tear_down && \
	distupgrade_show_messages || \
	{ distupgrade_error_message "post"; return 1; }

	touch -f "$stagedir/post.flag"

	echo "Plesk distupgrade finished."
	echo "If problems occur, please check $DISTUPGRADE_LOG for errors."
}

distupgrade_deb_main()
{
	distupgrade_deb_parse_args "$@" && \
	distupgrade_deb_prepare && \
	distupgrade_deb_accept && \
	"$DISTUPGRADE_PRE_SCRIPT" --skip-check-latest "$@" || return $?
	distupgrade_deb_main_middle || return $?
	"$DISTUPGRADE_POST_SCRIPT" --skip-check-latest "$@" || return $?
}

distupgrade_deb_run()
{
	DISTUPGRADE_LOG="$1"
	local func="$2"

	shift 2

	log_transaction_start "Distupgrade" "Distupgrade" "$DISTUPGRADE_LOG"
	"$func" "$@" 2>&1 | tee -a "$DISTUPGRADE_LOG"
	exit "${PIPESTATUS[0]}"
}

true drweb_status
drweb_status()
{
	local pidfile="/var/drweb/run/drwebd.pid"
	if [ ! -r "$pidfile" ]; then
		p_echo "drweb is stopped (no pidfile found)"
		return 1
	fi

	local pid=$(head -1 "$pidfile" 2>/dev/null)
	if  [ -z "$pid" ]; then
		p_echo "drweb is stopped (wrong pidfile)"
		return 1
	fi

	if kill -0 "$pid" 2>/dev/null || ps -p "$pid" >/dev/null 2>&1 ; then
		p_echo "drwebd (pid $pid) is running..."
		return 0
	fi
	p_echo "drwebd is stopped"
	return 1
}

### Copyright 1999-2022. Plesk International GmbH.
# vim:ft=sh
# Usage:  pleskrc <service> <action>
pleskrc()
{
	[ 2 -le $# ] || die "Not enough arguments"

	local service_name=$1
	local action=$2
	local ret=0
	local inten
	shift
	shift

	# Now check redefined functions
	if test "$machine" = "linux" && is_function "${service_name}_${action}_${machine}_${linux_distr}"; then
		"${service_name}_${action}_${machine}_${linux_distr}" "$@"
		return $?
	elif is_function "${service_name}_${action}_${machine}"; then
		"${service_name}_${action}_${machine}" "$@"
		return $?
	elif is_function "${service_name}_${action}"; then
		"${service_name}_${action}" "$@"
		return $?
	fi

	# Not redefined - call default action
	eval "service=\$${service_name}_service"
	[ -n "$service" ] || die "$action $service_name service (Empty service name for '$service_name')"

	inten="$action service $service"
	[ "$action" = "status" -o "$action" = "exists" ] || echo_try "$inten"

	service_ctl "$action" "$service" "$service_name"

	ret="$?"
	if [ "$action" != "status" -a "${action}" != "exists" ]; then
		if [ "$ret" -eq 0 ]; then
			suc
		else
			if [ -x "/bin/systemctl" ]; then
				p_echo "`/bin/systemctl -l status \"${service}.service\" | awk 'BEGIN {s=0} s==1 {s=2} /^$/ {s=1} s==2 {print}'`"
			fi
			warn "$inten"
		fi
	fi

	return $ret
}

# NOTE:
#	Function service_ctl is just helper for pleskrc().
#	Do not call it directly, use pleskrc()!!!
service_ctl()
{
	local action=$1
	local service=$2
	local service_name=$3

	if [ "$action" != "exists" ]; then
		_service_exec $service exists;
		if [ "$?" != "0" ]; then
			warn "attempt to ${inten} - control script doesn't exist or isn't executable"
			return 1
		fi
	fi

	case "$action" in
		start)
			pleskrc "$service_name" status || _service_exec "$service" "$action"
			;;
		stop)
			! pleskrc "$service_name" status || _service_exec "$service" "$action"
			;;
		restart)
			if pleskrc "$service_name" status; then
				_service_exec "$service" "$action"
			else
				_service_exec "$service" start
			fi
			;;
		reload)
			! pleskrc "$service_name" status || _service_exec "$service" "$action"
			;;
		status)
			_service_exec "$service" status
			;;
		try-restart)
			if [ -x "/bin/systemctl" ]; then
				_service_exec "$service" "$action"
			else
				! pleskrc "$service_name" status || _service_exec "$service" "restart"
			fi
			;;
		try-reload)
			! pleskrc "$service_name" status || _service_exec "$service" "reload"
			;;
		reload-or-restart)
			if [ -x "/bin/systemctl" ]; then
				_service_exec "$service" "$action"
			elif pleskrc "$service_name" status; then
				_service_exec "$service" "reload"
			else
				_service_exec "$service" "start"
			fi
			;;
		*)
			_service_exec "$service" "$action"
			;;
	esac >> "$product_log"
}

_service_exec()
{
	local service=$1
	local action=$2

	local action_cmd
	local sysvinit_service="/etc/init.d/$service"

	if [ -x "/bin/systemctl" ]; then
		case "${action}" in
			exists)
				if /bin/systemctl list-unit-files | awk 'BEGIN { rc = 1 } $1 == "'$service'.service" { rc = 0;} END { exit rc }'; then
					return 0 # systemd unit
				elif [ -x "$sysvinit_service" ]; then
					return 0 # sysvinit compat
				fi
				return 1 # not found
				;;
			status)
				action="is-active"
				;;
			reload|graceful)
				action='reload-or-try-restart'
				;;
		esac
		/bin/systemctl "$action" "${service}.service"
	elif  [ -x "/sbin/initctl" -a -e "/etc/init/$service.conf" ]; then  # upstart (ubuntu)
		if [ "$action" = "status" ]; then
			/sbin/initctl status "$service" | grep -qE ' ([0-9]+)$' && return 0 || return 1
		elif [ "$action" = "exists" ]; then
			return 0
		else
			/sbin/initctl "$action" "$service"
		fi
	else
		if [ -x "/usr/sbin/invoke-rc.d" ]; then
			action_cmd="/usr/sbin/invoke-rc.d $service"
		elif [ -x "/sbin/service" ]; then
			action_cmd="/sbin/service $service"
		elif [ -x "/usr/sbin/service" ]; then
			action_cmd="/usr/sbin/service $service"
		else
			action_cmd="$sysvinit_service"
		fi

		if [ "$action" = "exists" ]; then
			[ -x "$sysvinit_service" ] && return 0 || return 1
		else
			$action_cmd $action 2>/dev/null
		fi
	fi
}

is_function()
{
	local type_output=$(type -t "$1")
	test "X${type_output}" = "Xfunction"
}

# echo message to product log, unless debug
p_echo()
{
    if [ -n "$PLESK_INSTALLER_DEBUG" -o -n "$PLESK_INSTALLER_VERBOSE" -o -z "$product_log" ] ; then
        echo "$@" >&2
    else
        echo "$@" >> "$product_log" 2>&1
    fi
}

# echo message to product log without new line, unless debug
pnnl_echo()
{
    if [ -n "$PLESK_INSTALLER_DEBUG" -o -n "$PLESK_INSTALLER_VERBOSE" -o -z "$product_log" ] ; then
        echo -n "$*" >&2
    else
        echo -n "$*" >> "$product_log" 2>&1
    fi
}

die()
{
	PACKAGE_SCRIPT_FAILED="$*"

	report_problem \
		"ERROR while trying to $*" \
		"Check the error reason(see log file: ${product_log}), fix and try again"

	selinux_close

	exit 1
}

warn()
{
	local inten
	inten="$1"
	p_echo
	p_echo "WARNING!"
	pnnl_echo "Some problems are found during $inten"
	p_echo "(see log file: ${product_log})"
	p_echo
	p_echo "Continue..."
	p_echo

	product_log_tail | send_error_report_with_input "Warning: $inten"

	[ -n "$PLESK_INSTALLER_DEBUG" -o -n "$PLESK_INSTALLER_VERBOSE" ] || \
	product_log_tail
}

# Use this function to report failed actions.
# Typical report should contain
# - reason or problem description (example: file copying failed)
# - how to resolve or investigate problem (example: check file permissions, free disk space)
# - how to re-run action (example: perform specific command, restart bootstrapper script, run installation again)
report_problem()
{
	[ -n "$product_problems_log" ] || product_problems_log="/dev/stderr"

	p_echo
	if [ "0$problems_occured" -eq 0 ]; then
		echo "***** $process problem report *****" >> "$product_problems_log" 2>&1
	fi
	for problem_message in "$@"; do
		p_echo "$problem_message"
		echo "$problem_message" >> "$product_problems_log" 2>&1
	done
	p_echo

	product_log_tail | send_error_report_with_input "Problem: $@"

	[ -n "$PLESK_INSTALLER_DEBUG" -o -n "$PLESK_INSTALLER_VERBOSE" ] || \
		product_log_tail

	problems_occured=1
}

echo_try()
{
	msg="$*"
	pnnl_echo " Trying to $msg... "
}

suc()
{
	p_echo "done"
}

# do not call it w/o input! Use send_error_report in these cases.
send_error_report_with_input()
{
	get_product_versions
	{
		echo "$@"
		echo ""
		if [ -n "$error_report_context" ]; then
			echo "Context: $error_report_context"
			echo ""
		fi
		if [ -n "$RP_LOADED_PATCHES" ]; then
			echo "Loaded runtime patches: $RP_LOADED_PATCHES"
			echo ""
		fi
		cat -
	} | $PRODUCT_ROOT_D/admin/bin/send-error-report --version "$product_this_version" install >/dev/null 2>&1
}
### Copyright 1999-2022. Plesk International GmbH.
reexec_with_clean_env()
{
	# Usage: call this function as 'reexec_with_clean_env "$@"' at the start of a script.
	#        Don't use with scripts that require sensitive environment variables.
	#        Don't put the call under any input/output redirection.
	# Purpose: make sure the script is executed with a sane environment.

	export LANG=C LC_MESSAGES=C LC_ALL=C
	export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
	umask 022

	[ -z "$PLESK_INSTALLER_ENV_CLEANED" ] || { unset PLESK_INSTALLER_ENV_CLEANED; return 0; }
	[ -n "$BASH" ] || exec /bin/bash "$0" "$@"

	# N.B.: the following code requires Bash. On Dash it would cause syntax error upon parse w/o eval.
	eval '
	local extra_vars=()                     # list of variables to preserve
	for var in "${!PLESK_@}"; do            # enumerate all PLESK_* variables
		extra_vars+=("$var=${!var}")
	done
	extra_vars+=("PLESK_INSTALLER_ENV_CLEANED=1")

	# Exec self with clean env except for extra_vars, shell opts, and arguments.
	exec /usr/bin/env -i "${extra_vars[@]}" /bin/bash ${-:+-$-} "$0" "$@" || {
		echo "Failed to reexec self ($0) with clean environment" >&2
		exit 91		# Just some relatively unique error code
	}
	'
}
### Copyright 1999-2022. Plesk International GmbH.

# vim:ft=sh

mk_backup()
{
	local target dup opts
	target="$1"
	dup="$2"
	opts="$3"

	if [ -L "$target" ]; then
		rm "$target"
	elif [ -$opts "$target" ]; then
		if [ ! -$opts "$target.$product_suffo" ]; then
			case "$dup" in
				mv)
					mv -f $target $target.$product_suffo || die "mv -f $target $target.$product_suffo"
					;;
				cp)
					cp -fp $target $target.$product_suffo || die "cp -fp $target $target.$product_suffo"
					;;
				*)
					p_echo " mk_backup: wrong option -- must be 'cp' or 'mv'"
					die "mk_backup"
					;;
			esac
		else
			case "$dup" in
				mv)
					mv -f $target $target.$product_suff || die "mv -f $target $target.$product_suff"
					;;
				cp)
					cp -fp $target $target.$product_suff || die "cp -fp $target $target.$product_suff"
					;;
				*)
					p_echo " mk_backup: wrong option -- must be 'cp' or 'mv'"
					die "mk_backup"
					;;
			esac
		fi
	else
		case "$opts" in
			f|d)
				;;
			*)
				p_echo " mk_backup: wrong option -- must be 'f' or 'd'"
				die "mk_backup"
				;;
		esac
	fi
}

# accumulates chown and chmod
set_ac()
{
	local u_owner g_owner perms node
	u_owner="$1"
	g_owner="$2"
	perms="$3"
	node="$4"

	# A very small optimization - replacing of two execs by one,
	#    it works only if the following conditions are observed:
	#       - u_owner is username (not UID);
	#       - g_owner is group (not GID);
	#       - perms is in octal mode.
	# If some conditions aren't observed,
	#    optimization doesn't work,
	#    but it doesn't break function
	[ "$(stat -c '%U:%G 0%a' $node)" != "$u_owner:$g_owner $perms" ] || return 0
	chown $u_owner:$g_owner $node || die "chown $u_owner:$g_owner $node"
	chmod $perms $node || die "chmod $perms $node"
}

detect_vz()
{
	[ -z "$PLESK_VZ_RESULT" ] || return $PLESK_VZ_RESULT

	PLESK_VZ_RESULT=1
	PLESK_VZ=0
	PLESK_VE_HW_NODE=0
	PLESK_VZ_TYPE=

	local issue_file="/etc/issue"
	local vzcheck_file="/proc/self/status"
	[ -f "$vzcheck_file" ] || return 1

	local env_id=`sed -ne 's|^envID\:[[:space:]]*\([[:digit:]]\+\)$|\1|p' "$vzcheck_file"`
	[ -n "$env_id" ] || return 1
	if [ "$env_id" = "0" ]; then
		# Either VZ/OpenVZ HW node or unjailed CloudLinux
		PLESK_VE_HW_NODE=1
		return 1
	fi

	if grep -q "CloudLinux" "$issue_file" >/dev/null 2>&1 ; then
		return 1
	fi

	if [ -f "/proc/vz/veredir" ]; then
		PLESK_VZ_TYPE="vz"
	elif [ -d "/proc/vz" ]; then
		PLESK_VZ_TYPE="openvz"
	fi

	PLESK_VZ=1
	PLESK_VZ_RESULT=0
	return 0
}
### Copyright 1999-2022. Plesk International GmbH.
#-*- vim:syntax=sh

product_log_name_ex()
{
	local aux_descr="$1"
	local action="${CUSTOM_LOG_ACTION_NAME-installation}"

	if [ -n "$aux_descr" ]; then
		aux_descr="_${aux_descr}"
	fi

	if [ -n "$CUSTOM_LOG_NAME" ]; then
		echo "${CUSTOM_LOG_NAME}${action:+_$action}${aux_descr}.log"
	else
		echo "plesk_17.8.11${action:+_$action}${aux_descr}.log"
	fi
}

product_log_name()
{
	product_log_name_ex
}

product_problems_log_name()
{
	product_log_name_ex "problems"
}

problems_log_tail()
{
	[ -f "$product_problems_log" ] || return 0
	tac "$product_problems_log" | awk '/^START/ { exit } { print }' | tac
}

product_log_tail()
{
	[ -f "$product_log" ] || return 0
	{
		tac "$product_log" | awk '/^START/ { exit } { print }' | tac
	} 2>/dev/null
}

cleanup_problems_log()
{
	[ -f "$product_problems_log" ] || return 0
	touch "$product_problems_log.tmp"
	chmod 0600 "$product_problems_log.tmp"
	awk 'BEGIN 						{ st = "" } 
		 /^START/ 					{ st=$0; next } 
		 /^STOP/ && (st ~ /^START/) { st=""; next } 
		 (st != "") 				{ print st; st="" } 
		 							{ print }
		' "$product_problems_log" > "$product_problems_log.tmp" && \
	mv -f "$product_problems_log.tmp" "$product_problems_log" || \
	rm -f "$product_problems_log.tmp"
	
	if [ ! -s "$product_problems_log" ]; then 
		rm -f "$product_problems_log"
	fi
}

mktemp_log()
{
	local logname="$1"
	local dir="$2"

	if [ "${logname:0:1}" != "/" ]; then
		logname="$dir/$logname"
	fi
	dir="`dirname $logname`"
	if [ ! -d "$dir" ]; then
		mkdir -p "$dir" || { echo "Unable to create log directory : $dir"; exit 1; }
		if [ "$EUID" -eq "0" ]; then
			set_ac root root 0700 "$dir"
		fi
	fi

	if [ "${logname%XXX}" != "$logname" ]; then
		mktemp "$logname"
	else
		echo "$logname"
	fi
}

log_is_in_dev()
{
	test "${1:0:5}" = "/dev/"
}

start_writing_logfile()
{
	local logfile="$1"
	local title="$2"
	! log_is_in_dev "$logfile" || return 0
	echo "START $title" >> "$logfile" || { echo "Cannot write installation log $logfile" >&2; exit 1; }
	[ "$EUID" -ne "0" ] || set_ac root root 0600 "$logfile"
}

create_product_log_symlink()
{
	local logfile="$1"
	local prevdir="$2"

	local prevlog="$prevdir/`basename $logfile`"
	[ -e "$prevlog" ] || ln -sf "$logfile" "$prevlog"
}

log_start()
{
	true product_log_name product_problems_log_name mktemp_log

	local title="$1"
	local custom_log="$2"
	local custom_problems_log="$3"

	local product_log_dir="/var/log/plesk/install"

	product_log="$product_log_dir/`product_log_name`"
	product_problems_log="$product_log_dir/`product_problems_log_name`"
	problems_occured=0

	# init product log
	[ ! -n "$custom_log" ] || product_log="$custom_log"
	product_log=`mktemp_log "$product_log" "$product_log_dir"`

	# init problems log
	if [ -n "$custom_problems_log" ]; then
		product_problems_log=`mktemp_log "$custom_problems_log" "$product_log_dir"`
	elif [ -n "$custom_log" ]; then
		product_problems_log="$product_log"
	else
		product_problems_log=`mktemp_log "$product_problems_log" "$product_log_dir"`
	fi

	# write starting message into logs
	start_writing_logfile "$product_log" "$title"
	if [ "$product_log" != "$product_problems_log" ]; then
		start_writing_logfile "$product_problems_log" "$title"
	fi

	# create compat symlinks if logs are written to default localtions
	if [ -z "$custom_log" -a -z "$CUSTOM_LOG_NAME" ]; then
		create_product_log_symlink "$product_log" "/tmp"
		[ ! -z "$custom_problems_log" ] || create_product_log_symlink "$product_problems_log" "/tmp"
	fi

	is_function profiler_setup && profiler_setup "$title" || :
}

log_transaction_start()
{
	LOG_TRANSACTION_TITLE="$1"
	LOG_TRANSACTION_SUBJECT="$2"
	local log_transaction_custom_logfile="$3"
	local log_transaction_custom_problems_logfile="$4"

	transaction_begin autocommit
	log_start "$LOG_TRANSACTION_TITLE" "$log_transaction_custom_logfile" "$log_transaction_custom_problems_logfile"
	transaction_add_commit_action "log_transaction_stop"
}

log_transaction_stop()
{
	log_stop "$LOG_TRANSACTION_TITLE" "$LOG_TRANSACTION_SUBJECT"
}

log_stop()
{
	local title="$1"
	local subject="$2"

	if [ "$product_log" = "$product_problems_log" ] || \
			log_is_in_dev "$product_problems_log"; then
		[ -e "$product_log" ] && echo "STOP $title" >>"$product_log"
		is_function profiler_stop && profiler_stop || :
		return
	fi

	if [ -z "$subject" ]; then
		subject="[${title}]"
	fi

	# check if problems are non-empty, check for problems_occured
	local status
	local problem_lines="`problems_log_tail | wc -l`"
	if [ "$problem_lines" -eq 0 ]; then
		status="completed successfully"
	else
		if [ $problems_occured -ne 0 ]; then
			status="failed"
		else
			status="completed with warnings"
		fi
	fi

	if [ -e "$product_log" ]; then
		p_echo
		p_echo "**** $subject $status."
		p_echo
	fi

	if [ "$problem_lines" -ne 0 ]; then
		[ ! -e "$product_log" ] || problems_log_tail >>"$product_log" 2>&1
		problems_log_tail
	fi

	[ ! -e "$product_log" ] || echo "STOP $title" >>"$product_log"
	if [ $problems_occured -ne 0 ]; then
		echo "STOP $title: PROBLEMS FOUND" >>"$product_problems_log"
	else
		[ ! -s "$product_problems_log" ] || echo "STOP $title: OK" >>"$product_problems_log"
	fi

	if [ "X${PLESK_INSTALLER_KEEP_PROBLEMS_LOG}" = "X" ]; then
		cleanup_problems_log
	fi

	# remove symlink to problems log if the log was removed
	local linkpath="/tmp/`basename $product_problems_log`"
	if [ -L "$linkpath" -a ! -e "$linkpath" ]; then
		rm -f "$linkpath"
	fi

	is_function profiler_stop && profiler_stop || :
}
### Copyright 1999-2022. Plesk International GmbH.

get_pid()
{
	local i

	local ex_f="$1"
	local opt="$2"
	local owner="$3"

	local min_num="1"

	# Use pidof by default, bug 121868, except for FreeBSD - 140182
	if type pidof >/dev/null 2>&1 && [ "$os" != "BSD" ]; then
		for pid in `pidof -o $$ -o $PPID -o %PPID -x $ex_f`; do
			# Check for owner
			[ "$opt" = "true" -a "$owner" != "`ps -p $pid -o ruser=`" ] && continue
			min_num=$pid
			break
		done
		common_var=$min_num
		return $min_num
	fi

	case "$opt" in
		false)
			for i in `$ps_long | grep $ex_f | grep -v grep | grep -v httpsdctl | grep -v apachectl | awk '{print $2}' -`; do
				min_num=$i
				break
			done
			;;
		true)
			for i in `$ps_long | grep $ex_f | grep -v grep | grep -v httpsdctl | grep -v apachectl | grep "$owner" | awk '{print $2}' -`; do
				min_num=$i
				break
			done
			;;
		*)
			p_echo "get_pid: wrong parameter"
			die "get_pid $ex_f $opt $owner"
			;;
	esac

	common_var=$min_num
	return $min_num
}

### Copyright 1999-2022. Plesk International GmbH.
get_userID()
{
# try to get UID
	common_var=`id -u "$1" 2>/dev/null` 

# if id returns 0 the all is ok
	test "$?" -eq "0" -a -n "$common_var"
}

get_groupID()
{
# try to get GID, id -g doesn't show groups without users
	common_var=`getent group $1 2>/dev/null | awk -F':' '{print $3}'`

# We have non-empty value if success
	test -n "$common_var"
}

read_conf()
{
	[ -n "$prod_conf_t" ] || prod_conf_t=/etc/psa/psa.conf

	if [ -s $prod_conf_t ]; then
		tmp_var=`perl -e 'undef $/; $_=<>; s/#.*$//gm;
		         s/^\s*(\S+)\s*/$1=/mg;
		         print' $prod_conf_t`
		eval $tmp_var
	else
		if [ "X$do_upgrade" = "X1" ]; then
			p_echo "Unable to find product configuration file: $prod_conf_t. Default values will be used."
			return 1
		fi
	fi
	return 0
}

# setup new value for parameter
# $1 config file name $2 paramater name, $3 parameter value
conf_setval()
{
	local filename="$1"
	local varname="$2"
	local varvalue="$3"

	oldval="`conf_getvar $filename $varname`"
	[ "$oldval" != "$3" ] || return 0

	cat "$1" | awk -v varname="$varname" -v varvalue="$varvalue" \
		'BEGIN { f = 0 }
		{ if ($1 == varname) { f = 1; print varname "\t" varvalue } else { print $0 } }
		END { if (f == 0) { print "\n" varname "\t" varvalue } }' \
			> "$filename.new" && \
	mv -f "$filename.new" "$filename" && \
	chmod 644 "$filename"
}

# A set of functions for work with config variables
# $1 is config file name, $2 is variable name, $3 is variable value

conf_getvar()
{
	cat $1 | perl -n -e '$p="'$2'"; print $1 if m/^$p\s+(.*)/'
}
### Copyright 1999-2022. Plesk International GmbH.

#-*- vim:ft=sh

register_service() {

	[ -n "$1" ] || die "register_service: service name not specified"
	local inten="register service $1"
	echo_try "$inten"

	{
		if [ -x "/bin/systemctl" ]; then
			/bin/systemctl enable "$1.service"
			/bin/systemctl --system daemon-reload >/dev/null 2>&1
		fi


		if  [ -x "/sbin/initctl" -a -e "/etc/init/$1.conf" ]; then  # upstart (ubuntu)
			[ ! -e "/etc/init/$1.override" ] || sed -i "/^manual$/d" "/etc/init/$1.override"
		else
			# update-rc.d for Debian/Ubuntu (not SuSE)
			/usr/sbin/update-rc.d "$1" defaults
		fi



		local rs_db="$PRODUCT_ROOT_D/admin/sbin/register_service_db"
		[ ! -x "$rs_db" ] || "$rs_db" -a "$@"
	}

	suc
}

selinux_close()
{
	if [ -z "$SELINUX_ENFORCE" -o "$SELINUX_ENFORCE" = "Disabled" ]; then
		return
	fi

	setenforce "$SELINUX_ENFORCE"
}
### Copyright 1999-2022. Plesk International GmbH.
# -*- vim:syntax=sh

set_syslog_params()
{
	syslog_conf_ng="/etc/syslog-ng/syslog-ng.conf"

	syslog_conf=""
	for config in rsyslog.conf rsyslog.early.conf syslog.conf; do
		[ -f "/etc/$config" ] && syslog_conf="$syslog_conf /etc/$config"
	done

	syslog_service=""
	syslog_binary=""

	# Make sure the sequence of services is correlate with binaries
	local syslog_services="syslog sysklogd rsyslog syslog-ng"
	local syslog_binaries="syslogd syslogd rsyslogd syslog-ng"

	for service in $syslog_services; do
		[ -f "/lib/systemd/system/${service}.service" ] && \
			syslog_service="$service" && break
	done

	for binary in $syslog_binaries; do
		for bin_path in /sbin /usr/sbin; do
			[ -x "$bin_path/${binary}" ] && \
				syslog_binary="$bin_path/${binary}" && break
		done
		[ -n "$syslog_binary" ] && break
	done

}

true syslog_status_linux_debian
syslog_status_linux_debian()
{
	get_pid "$syslog_binary" false
	local pid=$common_var
	if test "$pid" -ne 1; then
		# running
		return 0
	fi
	return 1
}

true syslog_reload_linux_suse
true syslog_reload

syslog_reload_linux_suse()
{
	if [ "$syslog_service" = "rsyslog" -a "$syslog_binary" = "/sbin/rsyslogd" ]; then
		# Suse 13.1 man 8 rsyslogd:
		# So it is advised to use HUP only for closing files, and a "real restart" (e.g. /etc/rc.d/rsyslogd restart) to activate configuration changes.
		service_ctl restart $syslog_service syslog
	else
		service_ctl reload $syslog_service syslog
	fi
}

syslog_reload()
{
	# set_syslog_params must be called in outed function

	if [ "X$syslog_service" = "Xrsyslog" ]; then
		# Bug 142129
		# rsyslog service registration is necessary
		# it is workaround on default rsyslog service registration behaviour
		register_service rsyslog
		# then we restart it
	fi

	detect_vz
	if [ "$syslog_service" = "syslog" -o "$syslog_service" = "rsyslog" ] && [ "$PLESK_VZ" = "1" ]; then
		# 146355 - rsyslog/syslog service returns false on VZ
		service_ctl restart $syslog_service syslog
	elif [ "X$syslog_service" = "Xrsyslog" ]; then
		service_ctl restart $syslog_service syslog
	else
		service_ctl reload $syslog_service syslog
	fi
}

get_product_versions()
{
	local prod_root_d="/opt/psa"
	
	product_name="psa"
	product_this_version="17.8.11"
	product_this_version_tag="testing"
	if [ -z "$product_prev_version" ]; then
		if [ -r "$prod_root_d/version.upg" ]; then
			product_prev_version=`awk '{ print $1 }' "$prod_root_d/version.upg"`
		elif [ -r "$prod_root_d/version" ]; then
			product_prev_version=`awk '{ print $1 }' "$prod_root_d/version"`
		else
			product_prev_version="$product_this_version"
		fi
	fi
}

true exim_status_linux_debian
exim_status_linux_debian()
{
	get_pid /usr/lib/exim/exim3 false
	local pid=$common_var

	if test "$pid" -ne 1; then
		#running
		return 0;
	fi
	return 1
}

#Invoke mysql
mysql()
{
	mysql_anydb -D$mysql_db_name "$@"
}

mysql_anydb()
{
	(
		export MYSQL_PWD="$mysql_passwd"
		$mysql_client $mysql_host $mysql_user $mysql_args "$@" 2>>"$product_log"
		local status=$?

		if [ $status -gt 0 ]; then
			$mysql_client $mysql_host $mysql_user $mysql_args -D$mysql_db_name $mysql_args_raw -e "SHOW ENGINE innodb status" >>"$product_log" 2>&1
		fi
		unset MYSQL_PWD
		return $status
	)
}
### Copyright 1999-2022. Plesk International GmbH.
# -*- vim:ft=sh

# MySQL service action handlers

true mysql_start_linux_suse
mysql_start_linux_suse()
{
	local rc
	
	inten="start service mysql"
	echo_try "$inten"

	service_ctl start $mysql_service mysql
	rc="$?"

	# bug 52690. MySQL init script reports failure if protected mysqld is running (true for SuSE >= 11.3)
	if [ "$rc" -ne 0 ]; then
		local mysqld_bin="/usr/sbin/mysqld"
		killall -TERM mysqld >> $product_log 2>&1
		if [ -x "$mysqld_bin" ]; then
			for i in 2 4 8 16 32; do
				get_pid "$mysqld_bin" false
				local pid="$common_var"
				if test "$pid" -eq 1; then
					break
				fi
				killall -TERM mysqld >> $product_log 2>&1
				sleep $i
			done
		fi
		service_ctl start $mysql_service mysql
		rc="$?"
	fi

	[ "$rc" -eq 0 ] && suc || warn "$inten"
	return $rc
}

###	FIXME: probably need var service_restart warn
true mysql_stop
mysql_stop()
{
	local op_result i

	inten="stop MySQL server"
	echo_try $inten

	service_ctl stop $mysql_service mysql
	op_result=$?

	if [ "X$linux_distr" = "Xdebian" ]; then
		# Debian has well designed mysql stopping code
		[ "$op_result" -eq 0 ] || die $inten
		suc
		return 0
	fi

	for i in 2 4 6 8 16; do
		if ! mysql_status ; then
			suc
			return 0
		fi

		# I just want to be sure that mysql really stopped
		killall -TERM mysqld mysql safe_mysqld mysqld_safe >> $product_log 2>&1

		sleep $i
	done

	die "$inten"
}

true mysql_status
mysql_status()
{
	local file

    #Check with native script first
	#debian script always return 0. bug #111825
	[ "X$linux_distr" = "Xdebian" ] && msqld_status_supported="no"
	
	if [ -z "$msqld_status_supported" ]; then
		msqld_status_supported="yes"
	fi

	if [ "$msqld_status_supported" = "yes" ]; then
		service_ctl status $mysql_service mysql && return 0
	fi

	if [  "$msqld_status_supported" = "no" ]; then
		# MySQL AB packages
		file="/usr/sbin/mysqld"
	fi

    if [ -x "$file" ]; then
		#standard build and debian
		get_pid "$file" false
		pid=$common_var
		if test "$pid" -ne 1; then
			echo "$file (pid $pid) is running..." >>$product_log 2>&1
			return 0
		else
			echo "$file is stopped" >>$product_log 2>&1
			return 1
		fi
	fi

	return 1
}
### Copyright 1999-2022. Plesk International GmbH.
#-*- vim:syntax=sh

set_named_params()
{
	# set up default values
	bind_UID=53
	bind_GID=53
	bind_user="bind";
	bind_group="bind";

	# get UID of named user, if exists
	if get_userID $bind_user; then
		bind_UID=$common_var;
	fi

	# get GID of named group, if exists
	if get_groupID $bind_group; then
		bind_GID=$common_var;
	fi

	# path to directory of internal named
	NAMED_ROOT_D="${PRODUCT_ROOT_D:?'PRODUCT_ROOT_D is undefined'}/named"

	# path to directory of named pid file
	bind_run="${NAMED_RUN_ROOT_D:?'NAMED_RUN_ROOT_D is undefined'}/var/run/named"

	named_service="bind9"
	named_log="/dev/null"

	# path to named config file
	named_conf="/etc/named.conf"
	named_run_root_template="/opt/psa/var/run-root.tar"
	rndc_conf="/etc/rndc.conf"
	rndc_namedb_conf="/etc/namedb/rndc.conf"
	rndc_bind_conf="/etc/bind/rndc.conf"

	#140025. Restrict CPU cores for Bind
	bind_number_of_workers=2
}

sysconfig_named_debian()
{
	local named_sysconf_file named_sysconf_files config_rebuild

	named_sysconf_files=/etc/default/bind9
	# use .systemd syffix for systemd specific sysconfigs
	named_sysconf_files+=" /etc/default/bind9.systemd"

	for named_sysconf_file in $named_sysconf_files; do
		config_rebuild=0

		if [ -f "${named_sysconf_file}" ]; then

			# check presence of required run-root option
			cat ${named_sysconf_file} | sed -e 's|#.*$||g' | grep -E "^[[:space:]]*OPTIONS\=.*[[:space:]]\-t[[:space:]]*${NAMED_RUN_ROOT_D}" > /dev/null 2>&1
			[ $? -eq 0 ] || config_rebuild=1

			# check presence of required config file option
			cat ${named_sysconf_file} | sed -e 's|#.*$||g' | grep -E "^[[:space:]]*OPTIONS\=.*[[:space:]]\-c[[:space:]]*${named_conf}" > /dev/null 2>&1
			[ $? -eq 0 ] || config_rebuild=1

			# check presence of bind user option
			cat ${named_sysconf_file} | sed -e 's|#.*$||g' | grep -E "^[[:space:]]*OPTIONS\=.*[[:space:]]\-u[[:space:]]*${bind_user}" > /dev/null 2>&1
			[ $? -eq 0 ] || config_rebuild=1

			# check presence of workers number
			cat ${named_sysconf_file} | sed -e 's|#.*$||g' | grep -E "^[[:space:]]*OPTIONS\=.*[[:space:]]\-n[[:space:]]" > /dev/null 2>&1
			[ $? -eq 0 ] || config_rebuild=1

		else
			config_rebuild=1
		fi

		if [ 0${config_rebuild} -gt 0 ]; then

			[ ! -f ${named_sysconf_file} ] || mk_backup ${named_sysconf_file} mv f

			if expr match "${named_sysconf_file}" ".*\.systemd" >/dev/null 2>&1; then
				# For systemd we don't use ${OPTIONS}, and add -f (foreground)
				echo "OPTIONS=\"-f -t ${NAMED_RUN_ROOT_D}  -c ${named_conf} -u ${bind_user} -n ${bind_number_of_workers}\"" > ${named_sysconf_file}
			else
				echo "OPTIONS=\"\${OPTIONS} -t ${NAMED_RUN_ROOT_D}  -c ${named_conf} -u ${bind_user} -n ${bind_number_of_workers}\"" > ${named_sysconf_file}
			fi
		fi
	done
}

sysconfig_named()
{
	register_service "$named_service"
	sysconfig_named_debian

	return 0
}

debian_fix_named_iniscript()
{
	start_script="/etc/init.d/bind9"
	if [ -f $start_script ]; then
		# replace pidfile path to the one in chroot; ensure named is dead after 'rndc stop'
		# be carefull not to make replacements more than one time
		sed -e 's|/var/run/bind/run/named.pid|/var/named/run-root/var/run/named/named.pid|g' \
			-e 's|\([^a-zA-Z0-9_.]\)/var/run/named/named.pid|\1/var/named/run-root/var/run/named/named.pid|g' \
			-e '/killall\|rndc stop -p/!    s|\(/usr/sbin/rndc stop\)|\1 ; sleep 1 ; killall -9 named|g' \
			-e '/killall/!                  s|\(/usr/sbin/rndc stop -p\s*\)| ( \1 ; sleep 1 ; killall -9 named ) 2>/dev/null |g' \
			< "$start_script" > "$start_script.tmp" &&
		mv -f "$start_script.tmp" "$start_script" &&
		chmod 755 "$start_script"
	fi
}


true named_status_linux_debian
named_status_linux_debian()
{
    get_pid "/usr/sbin/named" false
    local pid=$common_var
    if test "$pid" -ne 1; then
# running
		return 0
    fi
    return 1
}

true postfix_status
postfix_status()
{
	# here be dragons.
	# the practical experience shows that simple checking of status of
	# Postfix "master" process is not enough. So we read Postfix master
	# process pid file if any, then try to look for a process with
	# name ``qmgr'' and parent pid being equal to
	# the pid read from the pidfile. If pgrep finds such a process
	# it returns 0, if not its exit status is non-zero.
	# pgrep is portable enough to prefer it to "hand-made" alternatives
	# such as famous ``ps | grep $name | grep -v grep...'' pipes
	# bug 147822. do not interrupt installation for FreeBSD

	[ -f "/var/spool/postfix/pid/master.pid" ] || return 1

	local ppid

	read ppid </var/spool/postfix/pid/master.pid 2>/dev/null
	if [ $? -ne 0 -o -z "$ppid" ]; then
		# not found or other error
		return 1;
	fi
	pgrep -P $ppid qmgr >/dev/null 2>/dev/null
}
### Copyright 1999-2022. Plesk International GmbH.
#-*- vim:syntax=sh

maillog_create_compat_symlink()
{
	mkdir -p "$PRODUCT_ROOT_D/var/log"
	[ -e "$PRODUCT_ROOT_D/var/log/maillog" -a ! -L "$PRODUCT_ROOT_D/var/log/maillog" ] || ln -sf "$mail_log" "$PRODUCT_ROOT_D/var/log/maillog"
}

select_maillog()
{
	local mail_log inten
	mail_log="/var/log/maillog"
	inten="set maillog file to $mail_log"

	set_syslog_params



	touch $mail_log
	chmod 0640 $mail_log

	local rsyslog_mail_log="${mail_log}"

	for config in $syslog_conf; do
		if [ -f "$config" ]; then
			if [ "${config}" = "/etc/rsyslog.conf" ]; then
				set_maillog $config "${rsyslog_mail_log}" "${inten}" >> $product_log 2>&1
			else
				set_maillog $config "${mail_log}" "${inten}" >> $product_log 2>&1
			fi
		fi
	done

	[ -f $syslog_conf_ng ] && set_maillog_ng "$mail_log" "$inten"  >> "$product_log" 2>&1

	pleskrc syslog reload
	maillog_create_compat_symlink
}

_set_maillog_ng_change()
{
    local conf_file mail_log inten bak_ext

    conf_file=$1
    mail_log=$2
    inten=$3
    bak_ext=$4

    echo_try "$inten"

    local mloc_cmd mloc_arg
    local ws
    ws=$(echo -ne " \t")

    ## Set log to $mail_log
    mloc_cmd="-e"
    mloc_arg='s|^\(['"$ws"']*destination['"$ws"']\+mail['"$ws"']*{[^"]*"\)[^"]*\(.*\)$|\1'"$mail_log"'\2|'

    ## By default SuSE-9.3 and SuSE-10 syslog-ng settings
    ## doesn't allow any 'mail' log messages to be put into
    ## /var/log/messages. We wish to allow mail.warn to pass
    ## through the filter, so we need to tune the conditions...
    ## So we change
    ## filter f_messages   { not facility(news, mail) and not filter(f_iptables); };
    ## to
    ## filter f_messages   { not (facility(news) or filter(f_iptables)) or filter(f_mailwarn); };
    ##
    ## I'm not sure if the whole filter is well optimized though
    ##
    ## Here I don't try to perform a sofisticated replace. The proper way
    ## would require a deep analisys of the current configuration and
    ## I don't see any sense to do it at this time, probably once in a future...

    local mfmt_cmd mfmt_arg
    mfmt_cmd=-e
    mfmt_arg='s|^\(['"$ws"']*filter['"$ws"']\+f_messages['"$ws"']*{\).*|\1 not (facility(news) or filter(f_iptables)) or filter(f_mailwarn); };|'

    ## now execute the entire command *IN-PLACE*
    ## all modern sed's (well at least on supported systems
    ## do support this option.

    ## One HAVE NOT TO quite mail_log_expr and mf_expr below!
    sed $mloc_cmd "$mloc_arg" $mfmt_cmd "$mfmt_arg" "-i$bak_ext" "$conf_file" || die "$intent"
}

set_maillog_ng() {
    local mail_log intent
    mail_log=$1
    intent=$2

	if [ -f "${syslog_conf_ng}.in" ]; then
	    _set_maillog_ng_change "${syslog_conf_ng}.in" "$mail_log" "$intent" ".bak" && \
		/sbin/SuSEconfig --module syslog-ng
	else
# Modest SuSE 1.20 doens't rule syslog through SuSE-config, bug 118238
		_set_maillog_ng_change "${syslog_conf_ng}" "$mail_log" "$intent" ".bak"
	fi

}

set_maillog()
{
	local syslog_conf mail_log inten mail_log_str log_str num
	syslog_conf=$1
	mail_log=$2
	inten=$3

	mail_log_str="-$mail_log"

	echo_try "$inten"

	log_str="^mail.*[[:space:]]*$mail_log*"
	grep "$log_str" $syslog_conf > /dev/null
	if [ "$?" -ne 0 ]; then
		grep '^mail\.\*' $syslog_conf > /dev/null
		if [ "$?" -eq 0 ]; then
			## if line "mail.*       ..." is exist then
			## replace this with new line
			grep -q '^mail\.\*.*;' $syslog_conf
			if [ $? -eq 0 ]; then
				sed -e "s|^mail\.\*.*\(;.*\)$|mail.*					$mail_log_str\1|" \
					< $syslog_conf > $syslog_conf.tmp
			else
				sed -e "s|^mail\.\*.*$|mail.*						$mail_log_str|" \
					< $syslog_conf > $syslog_conf.tmp
			fi
			mv -f $syslog_conf.tmp $syslog_conf
		else
			## if line "mail.*       ..." is NOT exist then
			## search "*.       ..." line
			num=`awk '{if ((my==0) && (index($1, "*.") == 1)) {my=1; print FNR;}}' < $syslog_conf`
			if [ "0$num" -gt "0" ]; then
				## if line "*.       ..." is exist then
				## disable all lines beginning with "mail."
				## and insert new line "mail.*      ..." before this
				sed -e 's/^\(mail\.\)/#\1/' \
					-e ''${num}'i\
					mail.*						'$mail_log_str'' \
					< $syslog_conf > $syslog_conf.tmp && \
				mv -f $syslog_conf.tmp $syslog_conf || die "$inten"
			else
				## if line "*.       ..." is NOT exist then
				## disable all lines beginning with "mail."
				## and insert new line "mail.*      ..." at the end of file
				sed -e 's/^\(mail\.\)/#\1/'	< $syslog_conf > $syslog_conf.tmp && \
				echo "mail.*						$mail_log_str" >> $syslog_conf.tmp && \
				mv -f $syslog_conf.tmp $syslog_conf || die "$inten"
			fi
		fi
	fi

	sed -e 's|\(^.*\)maili\none\;\(.*\)|\1\2|g' < $syslog_conf > $syslog_conf.tmp &&\
           mv -f $syslog_conf.tmp $syslog_conf || die "$inten"
	echo 'mail.none			-/var/log/messages' >> /var/log/messages 

	suc
}

### Copyright 1999-2022. Plesk International GmbH.
transaction_begin()
{
	[ -n "$TRANSACTION_STARTED" ] && die "Another transaction in progress!"
	TRANSACTION_STARTED="true"
	TRANSACTION_ROLLBACK_FUNCS=
	TRANSACTION_COMMIT_FUNCS=
	local transaction_autocommit="$1"
	if [ -n "$transaction_autocommit" ]; then
		trap "transaction_commit" PIPE EXIT
		trap "transaction_rollback" HUP INT QUIT TERM
	else
		trap "transaction_rollback" HUP PIPE INT QUIT TERM EXIT
	fi
}

transaction_rollback()
{
	[ -z "$TRANSACTION_STARTED" ] && die "Transaction is not started!"
	# perform rollback actions
	local f
	for f in ${TRANSACTION_ROLLBACK_FUNCS}; do
		"$f"
	done
	TRANSACTION_STARTED=
	TRANSACTION_ROLLBACK_FUNCS=
	TRANSACTION_COMMIT_FUNCS=
	trap - HUP PIPE INT QUIT TERM EXIT
	exit 1
}

transaction_commit()
{
	[ -z "$TRANSACTION_STARTED" ] && die "Transaction is not started!"
	# perform commit actions
	local f
	for f in ${TRANSACTION_COMMIT_FUNCS}; do
		"$f"
	done
	TRANSACTION_STARTED=
	TRANSACTION_ROLLBACK_FUNCS=
	TRANSACTION_COMMIT_FUNCS=
	trap - HUP PIPE INT QUIT TERM EXIT
}

transaction_add_commit_action()
{
	[ -z "$TRANSACTION_STARTED" ] && die "Transaction is not started!"
	# FIFO commit order
	[ -z "$TRANSACTION_COMMIT_FUNCS" ] \
		&& TRANSACTION_COMMIT_FUNCS="$1" \
		|| TRANSACTION_COMMIT_FUNCS="$TRANSACTION_COMMIT_FUNCS $1"
}

### Copyright 1999-2022. Plesk International GmbH.
# vim: ft=sh

reexec_with_clean_env "$@"

true distupgrade_deb_main distupgrade_deb_main_pre distupgrade_deb_main_post distupgrade_deb_run

DIST_NAME="Debian"
PREV_CODENAME="jessie"
PREV_VERSION="8"
NEXT_CODENAME="stretch"
NEXT_VERSION="9"

HELP_URL="https://www.debian.org/releases/stretch/amd64/release-notes/ch-upgrading.html"

USE_APT_GET="yes"

PACKAGE_CONGIFS_TO_REVERT="apache2@/etc/apache2/apache2.conf rsyslog@/etc/rsyslog.conf apache2@/etc/apache2/mods-available/ssl.conf@/etc/apache2/envvars bind9@/etc/init.d/bind9"
PACKAGES_TO_FORCE_INSTALL="psa-php5-configurator@psa-php-configurator plesk-libmaodbc"
PACKAGES_TO_INSTALL_PRE="sw-engine sw-engine-cli-2.24 mariadb-server"
PACKAGES_TO_REMOVE_POST="libapache2-mod-proxy-psa sw-tar plesk-libmyodbc psa-phpfpm-configurator"

FILES_TO_SAVE="/etc/apache2/ports.conf"

DISTUPGRADE_ADDITIONAL_ACTION_PRE="debian_8_9_stop_mysql debian_8_9_filter_php_versions"

debian_8_9_stop_mysql()
{
	# Sometimes new mariadb package scriplets fails to stop old mysql so stop it manually.
	/bin/systemctl stop mysql
}

# We do not support PHP < 7.0 for stretch
# and apt does not like to have unaccessible repos in its configs
debian_8_9_filter_php_versions()
{
	local repofile="/etc/apt/sources.list.d/plesk.list"
	sed -i 's|^\(deb.*PHP5.*\)|#\1|g' $repofile
}
DISTUPGRADE_PRE_SCRIPT="/opt/psa/bin/distupgrade.helper.deb8-deb9_pre.x64.sh"
DISTUPGRADE_POST_SCRIPT="/opt/psa/bin/distupgrade.helper.deb8-deb9_post.x64.sh"
DISTUPGRADE_DOC="https://docs.plesk.com/en-US/current/administrator-guide/server-administration/distupgrade-support.74627/"

distupgrade_deb_run "/var/log/plesk/install/plesk-distupgrade.log" distupgrade_deb_main_pre "$0" "$@"
