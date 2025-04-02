#!/bin/bash
### Copyright 1999-2024. Plesk International GmbH.

# Script from Plesk KB article https://support.plesk.com/hc/en-us/articles/12376925289879
# Allows installing varnish webserver along with Plesk environment and configure domains to use it.
# Requirements : bash 3.x, GNU coreutils, mysql client
# Version      : 1.0


# Constants and variables
PATH=$PATH:/usr/bin:/usr/sbin:/bin
varnishConfigSrc="https://raw.githubusercontent.com/plesk/kb-scripts/master/varnishmng/default.vcl"
varnishConfig="/etc/varnish/default.vcl"
MYSQL_PASSWORD=`cat /etc/psa/.psa.shadow`


# Functions
function sqlQuery(){ # Handling PSA queries with this one.
    MYSQL_PWD=$MYSQL_PASSWORD mysql -Ns -uadmin -D psa -e "$@"
}

function die(){
  echo -e "\\e[31mERROR\\e[m: $*" >&2
  exit 1
}

function info(){
  echo -e "\\e[32mINFO\\e[m: $*"
}

function isLiteSpeedInUse(){ # Checking the backend webserver unit status in order to see if it's powered with LiteSpeed or not. Exiting if it is.
  case "$osFamilyType" in
    "rhel")
    webServerInfo=$(systemctl status httpd 2>/dev/null | egrep -iE '(lsws|litespeed)')
    ;;
    "debian")
    webServerInfo=$(systemctl status apache2 2>/dev/null | egrep -iE '(lsws|litespeed)')
    ;;
  esac
  if [ ! -z "$webServerInfo" ] ; then
    die "Litespeed is in use on this server.
    The script is intended to be used with default Apache2(httpd)+Nginx webservers bundle."
  fi
}

function osFamilyDetect(){ # Detects OS family. Returns rather "rhel" or "debian"
	RH=("rhel" "redhat" "centos" "alma" "rocky" "cloudlinux")
	DE=("ubuntu" "debian")

	idLike=$(cat /etc/os-release |egrep -iE '(ID_LIKE|ID=)') # on debian there is no ID_LIKE constant in that file. Therefore, egrepping multiple patterns

	# Rhel-based checks
	for val in "${RH[@]}" ; do
		case "$idLike" in
			*"$val"*) osFamily="rhel" ;;
		esac
	done

	# Debian-based checks
	for val in "${DE[@]}" ; do
		case "$idLike" in
			*"$val"*) osFamily="debian" ;;
		esac
	done

  echo "$osFamily"
}
osFamilyType=$(osFamilyDetect) # Fetching this right away

function isPoweredByCentOs(){ # CentOS 7 has a deprecated repository which only contains varnish 4, hence we will be using a packagecloud.io, as suggested here: https://varnish-cache.org/docs/6.0/installation/install.html#source-or-packages
  if [ "$osFamilyType" == "rhel" ] ; then
    centosRelease=$(yum info centos-release | grep "Version" | awk '{print $3}' 2>/dev/null)
  fi
  if [ "$centosRelease" == "7" ] ; then
    echo "1" # That's it, script is running on CentOS7
  fi
}

function centOsRepoMng(){ # epel repo contains varnish 4.X which we're not going to use
  repoFile="/etc/yum.repos.d/varnish60lts.repo"
  if [ "$1" == "add" ] ; then
    mkdir /etc/yum.repos.d 2>/dev/null
    echo -ne "[varnish60lts]
name=varnishcache_varnish60lts
baseurl=https://packagecloud.io/varnishcache/varnish60lts/el/7/x86_64
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/varnishcache/varnish60lts/gpgkey
sslverify=0
metadata_expire=300" > "$repoFile"
  fi
  if [ "$1" == "del" ] ; then
    rm -rf "$repoFile" 2>/dev/null
  fi
}

function centOsSystemdTweak(){ # https proxy we're not going to use wants port 8443. That of course, we cannot afford.
  sed -i 's/8443/8444/' /lib/systemd/system/varnish.service && systemctl daemon-reload
}



function refreshPkgCache(){
  case "$osFamilyType" in
    "rhel")
      yum makecache
    ;;
    "debian")
      apt-get update
    ;;
    *)
    ;;
  esac
}

function handleNeedRestart(){ # To avoid prompts on debian-based OS with the "needrestart" package.
  case $1 in
    "lock")
    if [ -d /etc/needrestart ] ; then
      mkdir /etc/needrestart/conf.d 2>/dev/null
      printf "\$nrconf{restart} = 'l';\n\$nrconf{kernelhints} = 0;\n" >> /etc/needrestart/conf.d/noPrompt.conf
    fi
    ;;
    "release")
    rm -rf /etc/needrestart/conf.d/noPrompt.conf 2>/dev/null
    ;;
    *)
  esac
}

function installPkg(){ # Varnish package installation.
    case "$osFamilyType" in
      "rhel")
        if [ `isPoweredByCentOs` == "1" ] ; then # Centos-specific section start
          refreshPkgCache
          centOsRepoMng add
          yum install -y $1
          centOsRepoMng del
          centOsSystemdTweak
          systemctl enable varnish
          systemctl start varnish
        else # Centos-specific section end
          yum install -y $1
          systemctl enable varnish
          systemctl start varnish
        fi
      ;;
      "debian")
        handleNeedRestart lock
        apt-get install -y $1
        systemctl enable varnish
        systemctl start varnish
        handleNeedRestart release
      ;;
      *)
      ;;
    esac
}



function validateVarnishInstallation(){ # Checking if package's files are in place and systemd unit is running. Exiting otherwise.
  varnishExists=$(which varnishd)
  if [ -z "$varnishExists" ] ; then
    die "varnishd binary is missing. The package was not installed or corrupted. Exiting ..."
  fi

  varnishStatusCheck
  info "Varnish package has been installed and the unit is running."
  sePolicy
}

function varnishStatusCheck(){
 systemctl is-active --quiet varnish
  varnishIsUp=$(echo $?)
  if [ "$varnishIsUp" != '0' ] ; then
    die "The systemd unit 'varnish' is down. Review it's status manually.
    1. Make sure it is installed
    2. Check configuration file consistency: /etc/varnish/default.vcl
    3. Check the systemd unit status for possible errors with 'systemctl status varnish' "
  fi
}

function sePolicy(){ # Selinux tweak
      if [ ! -z `which getenforce` ] ; then
          seMode=$(getenforce)
      fi
      if [ "$seMode" == "Enforcing" ] ; then
          info "Applying Selinux policy for varnishd ... "
          setsebool -P varnishd_connect_any 1
          systemctl restart varnish
      else
          info "Selinux is not in use, skipping ... "
      fi
}

function checkApacheBindings(){ # Returns "0" if apache is listening on localhost. Terminates script otherwise.
  if [[ `sqlQuery "select val from misc where param='apacheListenLocalhost'"` == 'true' ]] ; then
    echo "0"
  else
    if [[ `sqlQuery "select val from misc where param='apacheListenLocalhost'"` == 'false' ]] ;then
    die "Apache is not listening on localhost. This can be changed with the following command: plesk bin apache --listen-on-localhost true
    \nMind that this will cause recreation of apache2 and nginx vhost configuration files and might take a while."
    else
        if [[ -z `sqlQuery "select val from misc where param='apacheListenLocalhost'"` ]] ; then
            die "Failed to detect apache2 bindings. Either you're running unsupported version of Plesk or the request to PSA fails. Exiting ..."
        fi
    fi
  fi
}

function domainStatusCheck(){
  if [[ ! -z `sqlQuery "select * from domains where name='$1'"` ]] ; then # Making sure domain exists
    true
  else
    die "Domain $1 does not exist, exiting ..."
  fi

  if [[ `sqlQuery "select status from domains where name='$1'"` != "0" ]] ; then # Domain is not suspended
    die "Domain is suspended, exiting ..."
  fi

  if [[ `sqlQuery "select htype from domains where name='$1'"` != "vrt_hst" ]] ; then # Domain has hosting type enabled
    die "Domain isn't configured for the website hosting. First switch hosting type to 'Website' ..."
  fi

  if [ `domainProxyModeCheck "$1"` != "1" ] ; then # Proxy mode is ON for the domain
    die "Domain does not have proxy mode enabled. Make sure to enable Proxy Mode in:\nDomains > $1 > Hosting > Apache & Nginx Settings"
  fi

  }

function domainProxyModeCheck(){
  proxyModeStatus=$(sqlQuery "select wssp.value from WebServerSettingsParameters wssp
                              join domains d
                              join dom_param dp
                              where d.id=dp.dom_id
                              and dp.param='webServerSettingsId'
                              and dp.val=wssp.webServerSettingsId
                              and wssp.name='nginxProxyMode'
                              and d.name='$1'")
  if [ "$proxyModeStatus" == "true" ] ; then
    echo "1"
  else
    echo "0"
  fi
}

function deployVarnishConfig(){
  cat /dev/null > $varnishConfig
  curl -sSLo $varnishConfig https://gist.githubusercontent.com/fevangelou/84d2ce05896cab5f730a/raw/79614fe6d417abaebf05abb623cc2e04941967db/for_Varnish_4.x_or_newer_default.vcl
  if [[ -z `grep "backend default" $varnishConfig` ]] ; then
    die "Configuration file wasn't downloaded properly. Exiting ..."
  else
    echo "Configuration /etc/varnish/default.vcl deployed."
  fi
  # Also perhaps it's a good idea to have that default.vcl stored in Plesk or my personal repo?
}


function sanityChecks(){
  if [[ -z `sqlQuery "select * from misc limit 1" 2>/dev/null` ]] ; then
    die "SQL Connection failed. Make sure the PSA database is accessible and Plesk is operational. Exiting ..."
  fi

  if [ "$osFamilyType" != "debian" ] && [ "$osFamilyType" != "rhel" ] ; then # we've failed to detect OS family. Can't proceed.
    die "Failed to detect OS family type. Exiting..."
  fi

  isLiteSpeedInUse
}

function restartVarnish(){
  systemctl restart varnish
  sleep 2
  varnishStatusCheck
}

function reloadApache(){
  if [ "$osFamilyType" == "debian" ] ; then
    systemctl reload apache2
    else
  if [ "$osFamilyType" == "rhel" ] ; then
    systemctl reload httpd
  fi
  fi
}

function reloadNginx(){
  systemctl reload nginx
}

function changeVarnishPort(){
  sed -i "/.port =/c\    .port = \"$1\";" $varnishConfig
}

function changeVarnishIp(){
  sed -i "/.host =/c\    .host = \"$1\";" $varnishConfig
}

function mngDomainRedirects(){ # $1 - domain name, $2 - true/false
  plesk bin domain -u $1 -ssl-redirect $2 1>/dev/null
}

function availableDomainsList(){
  sqlQuery "select name from domains where htype='vrt_hst' and status='0'"
}


function addDomainNginxConf(){
  domNginxConf="$(grep HTTPD_VHOSTS_D /etc/psa/psa.conf | awk {'print $2'})/system/$1/conf/vhost_nginx.conf"
  if [ -z `grep PLESK-VARNISH-BEGIN $domNginxConf 2>/dev/null` ] ; then
    echo -ne "\n#PLESK-VARNISH-BEGIN
location ~ ^/.* {
proxy_pass http://0.0.0.0:6081;
proxy_set_header Host              \$host;
proxy_set_header X-Real-IP         \$remote_addr;
proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;}
#PLESK-VARNISH-END" >> $domNginxConf
fi

}

function addDomainApacheConf(){
  domApacheConf="$(grep HTTPD_VHOSTS_D /etc/psa/psa.conf |awk {'print $2'})/system/$1/conf/vhost.conf"
  if [ -z `grep PLESK-VARNISH-BEGIN $domApacheConf 2>/dev/null` ] ; then
    echo -ne "\n#PLESK-VARNISH-BEGIN#
SetEnvIf X-Forwarded-Proto "https" HTTPS=on
Header append Vary: X-Forwarded-Proto

<IfModule mod_rewrite.c>
	RewriteEngine on
	RewriteCond %{HTTPS} !=on
	RewriteCond %{HTTP:X-Forwarded-Proto} !https [NC]
	RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</IfModule>
#PLESK-VARNISH-END#" >> $domApacheConf
fi
}

function delDomainNginxConf(){
  domNginxConf="$(grep HTTPD_VHOSTS_D /etc/psa/psa.conf | awk {'print $2'})/system/$1/conf/vhost_nginx.conf"
  sed -i '/PLESK-VARNISH-BEGIN/,/PLESK-VARNISH-END/d' $domNginxConf 2>/dev/null
}

function delDomainApacheConf(){
  domApacheConf="$(grep HTTPD_VHOSTS_D /etc/psa/psa.conf |awk {'print $2'})/system/$1/conf/vhost.conf"
  sed -i '/PLESK-VARNISH-BEGIN/,/PLESK-VARNISH-END/d' $domApacheConf 2>/dev/null
}

function enableVarnishOnDomain(){
    varnishStatusCheck
    domainStatusCheck $1
    mngDomainRedirects $1 false
    addDomainApacheConf $1
    addDomainNginxConf $1
    reloadApache && reloadNginx
}

function disableVarnishOnDomain(){
    domainStatusCheck $1
    mngDomainRedirects $1 true
    delDomainNginxConf $1
    delDomainApacheConf $1
    reloadApache && reloadNginx
}

function menuDisableVarnishOnDomain(){
  menuDomainSelect
  disableVarnishOnDomain "$selectedDomain"
}

function menuEnableVarnishOnDomain(){
  menuDomainSelect
  enableVarnishOnDomain "$selectedDomain"
}


function menuDomainSelect(){
  domList=$(availableDomainsList)
  readarray -t lines < <(echo "$domList")
      echo -e "List of active domains with enabled hosting, select one: "
      select selectedDomain in "${lines[@]}"; do
        [[ -n $selectedDomain ]] || { echo "Wrong input. Select valid domain." >&2; continue; }
      break
      done
  read -r selectedFromArray <<<"$selectedDomain"
}

function configureVarnish(){
  deployVarnishConfig
  changeVarnishPort "7080"
  if [[ `checkApacheBindings` == "0" ]] ; then # Setting varnish to proxy content from 127.0.0.1 if apache in Plesk listening on it.
    changeVarnishIp "127.0.0.1"
  fi
  restartVarnish
}

function installVarnish(){
  refreshPkgCache
  installPkg varnish
  validateVarnishInstallation
  configureVarnish
}
sanityChecks # Making sure the environment is ready

function help(){
  cat <<HELP
  List of arguments:
  --install                           Install varnish package including requirements
                                      and configure it. Applies Selinux policies if
                                      Selinux is in use.
                                      Example: ./varnishMng.sh --install


  --enable-cache <domain>             Enables varnish cache on domain. Domain name is passed as extra argument.
                                      Example: ./varnishMng.sh --enable-cache example.com

  --disable-cache <domain>            Disables varnish cache on domain. Domain name is passed as extra argument.
                                      Example: ./varnishMng.sh --disable-cache example.com
HELP
startupMenu
}

function startupMenu(){
  info "Currently supported CMS by the script-provided varnish config are:
WordPress 6.0+
Joomla 3.6+ with https://github.com/joomlaworks/url-normalizer installed."
  echo -ne "
\n\nPlesk varnish management script
1) Install varnish
2) Enable varnish cache on domain
3) Disable varnish cache on domain
4) Help (information about argument for the script usage without interactive menu)
5) Exit\n"
  read -p "Select an option: " o
  case "$o" in
    1) installVarnish ;;
    2) menuEnableVarnishOnDomain ;;
    3) menuDisableVarnishOnDomain ;;
    4) help ;;
    5) exit 0 ;;
    *) die "Wrong input. Exiting ..."
  esac
}




function nonInteractive(){
  if [ "$1" == "--install" ] ; then
    installVarnish && exit 0
  else
    if [ "$1" == "--enable-cache" ] ; then
      enableVarnishOnDomain "$2" && exit 0
  else
    if [ "$1" == "--disable-cache" ] ; then
      disableVarnishOnDomain "$2" && exit 0
    fi
  fi
  fi
}

# User-interaction starts here
nonInteractive $@
startupMenu