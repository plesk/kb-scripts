<?php

/**
  * Connects to the psa database
  *
  * @throws \Exception if instance could not be spawned
  * @throws \Exception if timeout cannot be set
  * @throws \Exception if connection failed for some reason
  * @throws \Exception if UTF8 cannot be set for the session
  *
  * @return \mysqli database handler
  */
function get_psa_sql_handle()
{
    $password = trim(file_get_contents('/etc/psa/.psa.shadow'));
    $mysql = mysqli_init();
    if (!$mysql) {
        throw new \Exception('Failed to init MySQLi instance!');
    }
    if (!$mysql->options(MYSQLI_OPT_CONNECT_TIMEOUT, 10)) {
        throw new \Exception('Failed to configure connection timeout!');
    }
    /* @ here is for Plesk with upgraded MySQL/MariaDB instances */
    if (! @$mysql->real_connect(
        'p:localhost',
        'admin',
        $password,
        'psa',
        3306
    )) {
    throw new \Exception('Connection to Plesk database failed: ' . mysqli_connect_error());
    }
    if (!$mysql->set_charset('UTF8')) {
        throw new \Exception('Failed to set charset to UTF8: ' . $mysql->error);
    }
    return $mysql;
}

/**
  * Runs a query against the psa database and returns domain hosting relation
  *
  * @param \mysqli $sql_handle  Database handle opened against psa
  *
  * @throws \Exception if database query failed
  *
  * @return (bool|string)[]  See below
  *
  * $return [
  *     'name'    string  Domain name
  *     'hasPhp'  bool    Domain has PHP enabled
  *     'handler' string  PHP handler name
  * ]
  */
function get_domain_php_binding($sql_handle)
{
    $domains = [];
    $result = $sql_handle->query('
        SELECT d.name, h.php, h.php_handler_id
        FROM domains d
        LEFT JOIN hosting h
        ON d.id = h.dom_id
    ');
    if ($result === false) {
        throw new \Exception('Failed to query relations from the database: ' . $sql_handle->error);
    }
    while ($row = $result->fetch_assoc()) {
        $domains[] = [
            'name' => idn_to_ascii($row['name']),
            'hasPhp' => $row['php'] === 'true',
            'handler' => $row['php_handler_id'],
        ];
    }
    return $domains;
}

/**
  * Extracts data about PHP handlers from the server (filtering out only FPM)
  *
  * @return string[]  See below
  *
  * $return [
  *     'id'          string  Unique identificator of the handler in Plesk
  *     'path'        string  Path to the FPM executable
  *     'clipath'     string  Path to the CLI executable
  *     'phpini'      string  Path to the php.ini
  *     'version'     string  PHP version
  *     'displayname' string  Template string for user-friendly display
  *     'type'        string  Always 'fpm'
  *     'system'      bool    Is provided by the OS
  *     'service'     string  systemd service name
  *     'poold'       string  Location of the FPM pools
  * ]
  */
function get_php_handler_info()
{
    $config = json_decode(file_get_contents('/etc/psa/php_versions.json'), true);
    if (json_last_error() !== 0) {
        throw new \Exception('Failed parsing /etc/psa/php_versions.json with error code: ' . json_last_error());
    }
    /* Only FPM has files stored on the filesystem */
    return array_filter($config['php'], function ($handler) {
        return $handler['type'] === 'fpm' && $handler['poold'] !== '';
    });
}

/**
  * Checks whether configuration files stored on FS are expected to be there
  *
  * @param array $handler    @see get_php_handler_info() return type
  * @param array $domains    @see get_domain_php_binding() return type
  * @param bool  $disabled   Should the domains with PHP disabled be displayed as well
  */
function find_and_display_extra_configs($handler, $domains, $disabled = false)
{
    $conffiles = [];
    $iter = new DirectoryIterator($handler['poold']);
    foreach ($iter as $file) {
        if ($file->isDot() || !$file->isFile() || $file->getExtension() !== 'conf') {
       	    continue;
        }
        $conffiles[] = [
            'domain' => substr($file->getBasename(), 0, -5),
            'filepath' => $file->getPathname()
        ];
    }
    foreach ($conffiles as $entry) {
        $domain = array_values(array_filter($domains, function ($domain) use ($entry) {
            return $entry['domain'] === $domain['name'];
        }))[0];

        if ($domain === null) {
            echo '[CRIT] Orphan file ' . $entry['filepath']
                . ' exists for the domain ' . $entry['domain']
                . ' not present in Plesk' . PHP_EOL;
            continue;
        }

        if (!$domain['hasPhp'] && $disabled) {
            echo '[NOTE] File ' . $entry['filepath']
                . ' exists for the domain ' . $entry['domain']
                . ' with PHP disabled' . PHP_EOL;
            continue;
        }

        if ($domain['handler'] !== $handler['id']) {
            echo '[CRIT] File ' . $entry['filepath']
                . ' may cause PHP failure: domain ' . $entry['domain']
                . ' has "' . $domain['handler'] . '" handler specified'
                . ', but this file is used to configure "' . $handler['id']
                . '" handler!' . PHP_EOL;
        }
    }
}

/**
  * Runs sanity checks on environment
  *
  * @throws \Exception if the script was executed on Windows
  * @throws \Exception if the script was executed with non-root account
  */
function perform_sanity_checks()
{
    if (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN') {
        throw new \Exception('This script does not support Windows');
    }
    if (posix_geteuid() !== 0) {
        throw new \Exception('This script requires superuser rights');
    }
}

function main()
{
    perform_sanity_checks();
    $displayDisabled = array_key_exists(
        'show-disabled',
        getopt('', ['show-disabled'])
    );

    $mysql = get_psa_sql_handle();
    $domains = get_domain_php_binding($mysql);
    $handlers = get_php_handler_info();
    foreach ($handlers as $handler) {
        find_and_display_extra_configs($handler, $domains, $displayDisabled);
    }
}

main();
