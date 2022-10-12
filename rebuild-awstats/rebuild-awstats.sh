#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script recalculates AWStats web-statistics of previous months in Plesk
# Requirements : bash 3.x, mysql-client, GNU coreutils
# Version      : 1.0
#########

usage() {
cat <<USAGE
Rebuild AWstats static pages from available log files.

Usage: $0 [options] [<domains...>]

Options:
    -A
    --all-domains
        Process all domains. If this option is not specified, then list of 
        domains to process must be provided.

    -F
    --from-scratch
        Remove contents of webstat/ and webstat-ssl/ directories before 
        rebuilding statistics pages (originals are saved with numeric 
        suffix). Statistics will be rebuilt from logs only, only for
        period covered by log files. If this parameter is not used, then 
        statistics is recalculated beginning on the month on which log files 
        start (if log starts in the middle of the month, then statistics
        for first half of the month will not be present.)
		
	-R
	--rebuild
		Rebuilds the HTML files for AWStats.

    -h
    --help
        This message.

Look for additional details here: <https://kb.plesk.com/en/115476>

USAGE
}



# MySQL query function
# Input: SQL query
# Output: result of SQL query
mysqlq() {
    MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysql -uadmin -Ns -Dpsa -e"$1"
    if [ $? -ne 0 ] ; then
        echo "ERROR: cannot query database"
        exit 1
    fi
}

# Recreate nav.html for domain
# Input: path to webstat/ or webstat-ssl/ directory
# Output: none
update_nav() {
    local dir=$1

    cat <<HEADER > $dir/nav.html
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
<title>Navigation</title>
<link href="general.css" rel="stylesheet" type="text/css">

<style type="text/css">
<!--
body {
        margin: 0;
        padding: 4px;
        font-family: Tahoma, Verdana, Arial, Helvetica, sans-serif;
        font-size: 12px;
        background-color: #6E89DD;
        color: #FFFFFF;
        text-align:center;
        font-weight:bold;
}

input, select {
        font-family: Tahoma, Verdana, Arial, Helvetica, sans-serif;
        font-size: 12px;
        font-weight:normal;
}

-->
</style>

<script language="JavaScript">
<!-- hide
function change_page()
{
    top.mainFrame.location= document.periodForm.periodSelect.value + '/index.html';
}
// -->
</script>

</head>

<body>
<form name="periodForm" action="" method="get">

Select period
<select name="periodSelect" ONCHANGE="change_page()">
<option value="current">Current</option>
HEADER

    find $dir -mindepth 1 -maxdepth 1 -type d -exec basename '{}' \; | sort | \
    while read m ; do
        echo "<option value=\"$m\">$m</option>" >> $dir/nav.html
    done

    cat <<FOOTER >>$dir/nav.html
</select>

</form>
</body>
</html>
FOOTER
}

# Print out all months in provided range in format %Y-%m
# Input: value in one of following formats: m, m/y, m1-m2, m1-m2/y, m1/y1-m2/y2, y, y1-y2
# Output: range of dates in format YYYY-mm
make_date_range() {
    perl -e '
my $arg = $ARGV[0];
my ($m1, $m2, $y1, $y2);

if ($arg =~ m/(\d+)\/(\d{4})-(\d+)\/(\d{4})/) {
    ($m1, $m2, $y1, $y2) = ($1, $3, $2, $4);    
} elsif ($arg =~ m/(\d+)(?:-(\d+))?(?:\/(\d{4})(?:-(\d{4}))?)?/) {
    ($m1, $m2, $y1, $y2) = ($1, $2, $3, $4);

    if ($m1 > 12) {
        $y1 = $m1; $m1 = 0;
    }

    if ($m2 > 12) {
        $y2 = $m2; $m2 = 0;
    }
} else {
    exit 1;
}

if ($y1 == 0) {
    $y1 = (localtime(time))[5] + 1900;
}

if ($y2 == 0) {
    $y2 = $y1;
}

if ($m1 == 0) {
    $m1 = 1; 
    $m2 = 12;
}

if ($m2 == 0) {
    $m2 = $m1;
}

exit 1 if ($y2 < $y1 || ($y1 == $y2 && $m2 < $m1));

while ($y1 <= $y2) {
    while ($m1 <= 12) {
        printf "%.4d-%.2d\n", $y1, $m1;
        last if ($y1 == $y2 && $m1 == $m2);
        $m1++
    }

    $y1++;
    $m1 = 1;
}

exit 0;
' "$1"
}

# Return month out of string in format %Y-%m
# Input: date in format YYYY-mm
# Output: month in format m
month() {
    echo "$1" | cut -d- -f2 | sed 's/^0//'
}

# Return year out of string in format %Y-%m
# Input: date in format YYYY-mm
# Output: year in format YYYY
year() {
    echo "$1" | cut -d- -f1
}

# Save webstat directories for domain
# Input: domain name, ssl flag
save_webstat_dirs() {
    local domain=$1 has_ssl=$2
    local n=1
    local dir=$HTTPD_VHOSTS_D/$domain/statistics/webstat

    if [ `pleskver` -ge 115 ] ; then
        dir=$HTTPD_VHOSTS_D/system/$domain/statistics/webstat
    fi

    while [ -d $dir.$n ] ; do
        n=$[n + 1]
    done

    echo "  Saving: $(basename $dir)* --> $(basename $dir)*.$n"
    cp -a $dir $dir.$n

    if [ "$has_ssl" == "true" ] ; then
        cp -a ${dir}-ssl ${dir}-ssl.$n
    fi
}

# Merge logs using AWstats' logresolvemerge.pl
merge_logs() {
    $AWSTATS_TOOLS_D/logresolvemerge.pl "$@" 
}

# Rebuild AWStats' static pages for domain for certain month
# Input: AWstats command with options, domain name, year (YYYY), month (m), destination directory for generated pages, SSL flag
rebuild_pages() {
    local awstats_cmd=$1 domain=$2 y=$3 m=$4 dest_dir=$5 ssl=$6
    local type="http"

    if [ "$ssl" == "true" ] ; then
        type=https
    fi

    [ ! -d $dest_dir ] && mkdir $dest_dir

    awstats_opts="-staticlinks -configdir=$PRODUCT_ROOT_D/etc/awstats -config=${domain}-${type}"

    $awstats_cmd $awstats_opts -month=$m -year=$y -output > $dest_dir/awstats.${domain}-${type}.html
    ln -s $dest_dir/awstats.${domain}-${type}.html $dest_dir/index.html 2>/dev/null
    for output in alldomains allhosts lasthosts unknownip allrobots downloads\
                  lastrobots session urldetail urlentry urlexit osdetail \
                  unknownos refererse refererpages keyphrases keywords errors404 ; do
        $awstats_cmd $awstats_opts -month=$m -year=$y -output=$output > $dest_dir/awstats.${domain}-${type}.$output.html
    done
}

# Update nav.html, create index.html and make 'current' symlink to point to current month
# Input: path to webstat or webstat-ssl directory
finalize() {
    local dir=$1

    update_nav $dir
    rm -f $dir/current
    ln -s `date +%Y-%m` $dir/current

    if [ ! -f $dir/index.html ] ; then
        cat <<INDEX > $dir/index.html
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
<title>AWStats for domain</title>
</head>

<frameset rows="30,*" cols="*" framespacing="0" frameborder="no" border="0">
  <frame src="nav.html" name="topFrame" scrolling="No" noresize="noresize" id="topFrame" title="topFrame">
  <frame src="current/index.html" name="mainFrame" id="mainFrame" title="mainFrame">
</frameset>
<noframes>
<body>
</body>
</noframes>
</html>
INDEX
    fi
}

pleskver() {
    ver=`perl -lne 'print "$1$2" if /^(\d+)\.(\d+)/' /usr/local/psa/version`

    if [ -z "$ver" ] ; then
        echo 0
    else
        echo $ver
    fi
}

if [ -z "$1" ] ; then
    usage 
    exit 0
fi

all_domains=0
from_scratch=0
rebuild=0

opts=`getopt -o "ARFh" --long "all-domains,from-scratch,help,rebuild" -n "$0" -- "$@"`

eval set -- "$opts"

while true ; do
    case "$1" in
        -A|--all-domains)
            all_domains=1
            domains=`mysqlq "SELECT d.name FROM domains d, hosting h WHERE d.id = h.dom_id AND h.webstat = 'awstats'"`
            shift
            ;;
        -F|--from-scratch)
            from_scratch=1
            shift
            ;;
		-R|--rebuild)
			rebuild=1
			#echo "REBUILD"
			shift
			;;
        -h|--help)
            exit 0
            ;;
        --) shift ; break ;;
        *) 
            echo "Unknown option: $1" 
            exit 1
            ;;
    esac
done

if [ $all_domains -ne 1 ] ; then
    domains="$@"
fi

if [ -z "$domains" ] ; then
    echo "ERROR: no domains were specified for processing."
    exit 1
fi

AWSTATS_BIN_D=`grep ^AWSTATS_BIN_D /etc/psa/psa.conf | awk '{print $2}'`
AWSTATS_TOOLS_D=`grep ^AWSTATS_TOOLS_D /etc/psa/psa.conf | awk '{print $2}'`
HTTPD_VHOSTS_D=`grep ^HTTPD_VHOSTS_D /etc/psa/psa.conf | awk '{print $2}'`
PRODUCT_ROOT_D=`grep ^PRODUCT_ROOT_D /etc/psa/psa.conf | awk '{print $2}'`
awstats=$AWSTATS_BIN_D/awstats.pl

if [ ! -x $awstats ] ; then
    echo "ERROR $awstats cannot be executed."
    exit 1
fi

for domain in $domains ; do
    echo === $domain

    if [ `pleskver` -ge 115 ] ; then
        domain_stat_dir="$HTTPD_VHOSTS_D/system/$domain/statistics"
    else
        domain_stat_dir="$HTTPD_VHOSTS_D/$domain/statistics"
    fi

    # check if domain has webstat = 'awstats'
    webstat=`mysqlq "SELECT h.webstat FROM hosting h, domains d WHERE d.id = h.dom_id AND d.name = '$domain'"`
    if [ -z "$webstat" -o "$webstat" != "awstats" ] ; then
        echo "WARNING: domain $domain does not exist or has non-AWstats statistics engine. Skipping..."
        continue
    fi

    # SSL?
    has_ssl=`mysqlq "SELECT h.ssl FROM hosting h, domains d WHERE d.id = h.dom_id and d.name = '$domain'"`

    awstats_gen_opts="-staticlinks -configdir=$PRODUCT_ROOT_D/etc/awstats -config=${domain}-http"
    awstats_gen_opts_ssl="-staticlinks -configdir=$PRODUCT_ROOT_D/etc/awstats -config=${domain}-https"

    # save previous AWstats data
    save_webstat_dirs $domain $has_ssl
	
	#if [ $rebuild -ne 1 ] ; then
	#	echo "REBUILD 1"
	#else
	#	echo "REBUILD 0"
	#fi
	
	
	if [ $rebuild -ne 1 ] ; then
		# merge logs
		http_log=$domain_stat_dir/http.log
		https_log=$domain_stat_dir/https.log

		merge_logs $domain_stat_dir/logs/access_log.processed* $domain_stat_dir/logs/access_log > $http_log
		
		if [ "$?" -ne 0 ] ; then
			echo "ERROR: failed to merge access_log*. Skipping domain."
			continue
		fi

		if [ "$has_ssl" == "true" ] ; then
			merge_logs $domain_stat_dir/logs/access_ssl_log.processed* $domain_stat_dir/logs/access_ssl_log > $https_log

			if [ "$?" -ne 0 ] ; then
				echo "WARNING: failed to merge access_ssl_log* logs. Skipping SSL statistics rebuild."
				has_ssl="false"
			fi
		fi
	
	
		# determine logs' date boundaries
		log_first_rec_dtime=`head -n 1 $http_log | awk -F'[[/:]' '{print $3,$2,$4}'`
		log_begin_date=`date -d "$log_first_rec_dtime" +%m/%Y`
		date_range=`make_date_range "$log_begin_date-$(date +%m/%Y)"`

		echo "  Logs begin on: $log_first_rec_dtime"

		if [ $from_scratch -ne 0 ] ; then
			rm -rf $domain_stat_dir/webstat/*
			rm -rf $domain_stat_dir/webstat-ssl/*
		else 
			# remove .txt files for period covered by logs
			for d in $date_range ; do
				m=`month $d`
				y=`year $d`

				rm -f $domain_stat_dir/webstat/awstats`printf "%.2d%4d" $m $y`.$domain-http* 2>/dev/null
				rm -f $domain_stat_dir/webstat-ssl/awstats`printf "%.2d%4d" $m $y`.$domain-http* 2>/dev/null
			done
		fi

		# parse logs
		echo -n "    access_log* (new/old/corrupted): "
		$awstats $awstats_gen_opts -LogFile=$http_log 2>&1 | awk '/new qualified/ {new=$2} /old records/ {old=$2} /corrupted records/ {corr=$2} END {printf "%d/%d/%d\n", new, old, corr}'

		if [ "$has_ssl" == "true" ] ; then
			echo -n "    access_ssl_log* (new/old/corrupted): "
			$awstats $awstats_gen_opts_ssl -LogFile=$https_log 2>&1 | awk '/new qualified/ {new=$2} /old records/ {old=$2} /corrupted records/ {corr=$2} END {printf "%d/%d/%d\n", new, old, corr}'
		fi
	fi
	
    # rebuild static pages for re-calculated months
    echo "  Rebuilding static pages: "
    
	if [ $rebuild -ne 0 ] ; then
		#echo "  Rebuilding all data files: "
		
		# Getting all months and years available
		ls -lahn $HTTPD_VHOSTS_D/system/$domain/statistics/webstat*/ | grep awstats | awk '{print $9}' | sort | uniq | sed "s/awstats//" | sed "s/.$domain-https.txt//" | cut -c1-2 > months.txt
        ls -lahn $HTTPD_VHOSTS_D/system/$domain/statistics/webstat*/ | grep awstats | awk '{print $9}' | sort | uniq | sed "s/awstats//" | sed "s/.$domain-https.txt//" | cut -c3-6 > years.txt
		# Doing calculation
		id=0
		declare -a months
		declare -a years

		lines=`cat months.txt`
		for line in $lines; do
				months[$id]=$line
				((id++))
		done
		id=0
		lines=`cat years.txt`
		for line in $lines; do
				years[$id]=$line
				((id++))
		done

		#echo -n "Starting loop"
		done=0
		#echo -n "Result before: $done -gt $id"
		while [ $done -lt $id ]
		do
			m=${months[$done]}
			y=${years[$done]}
			dest_dir=$domain_stat_dir/webstat/$y-$m
			rebuild_pages "$awstats" "$domain" "$y" "${m#0}" "$dest_dir"
			echo "    $m-$y: Rebuilding non-SSL "

			if [ "$has_ssl" == "true" ] ; then
				dest_dir=$domain_stat_dir/webstat-ssl/$y-$m
				rebuild_pages "$awstats" "$domain" "$y" "${m#0}" "$dest_dir" "$has_ssl"
				echo "    $m-$y: Rebuilding SSL "
			fi
			((done++))
		done

		#echo -n "Result now: $done -gt $id"
	
	else
		for d in $date_range ; do
			y=`year $d`
			m=`month $d`

			printf "%.4d-%.2d " $y $m

			dest_dir=$domain_stat_dir/webstat/$y-$(printf "%.2d" $m)
			rebuild_pages "$awstats" "$domain" "$y" "$m" "$dest_dir"

			if [ "$has_ssl" == "true" ] ; then
				dest_dir=$domain_stat_dir/webstat-ssl/$y-$(printf "%.2d" $m)
				rebuild_pages "$awstats" "$domain" "$y" "$m" "$dest_dir" "$has_ssl"
			fi
		done
	fi
    echo "Successfully rebuild all html files."

    # update nav.html, move 'current' symlink to current month and re-create index.html if missing
    finalize $domain_stat_dir/webstat

    if [ "$has_ssl" == "true" ] ; then
        finalize $domain_stat_dir/webstat-ssl
    fi

    # cleanup
    rm -f $http_log $https_log
done

