<?php
// Copyright 1999-2018. Plesk International GmbH. All rights reserved.

/* 
 * Compatibility info:
 * Plesk for Windows: 12.5 and newer
 * Plesk for Linux:   12.0 and newer
 * Supported PHP:     PHP 5.3+, PHP 7.0+

 * Limitations:
 * pm_Hook_ActionLog summaries are not translated
 *
 * Latest versions can be found in https://support.plesk.com/hc/en-us/articles/115000203794
 */

$lmsg_arr = array();

class AbstractLayer
{
    private $psa_connection = null;
    private $is_windows = false;
    private $version = 0;

    function __construct()
    {
        if (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN') {
            $this->is_windows = true;
        } else if (PHP_OS === 'Linux') {
            $this->is_windows = false;
        } else {
            throw new Exception("This script is intended for Linux and Windows only!");
        }
        $this->_getVersion();
        $this->sourceTranslations();
        $this->establishConnection();
    }

    /*
     * function getRootDir()
     * Gets correct Plesk directory depending on OS
     * @param void
     *
     * @return void
     */
    private function getRootDir()
    {
        if ($this->is_windows) {
            $envdir = getenv('plesk_dir');
            if (!is_readable($envdir)) {
                throw new Exception('Could not find Plesk installation directory!');
            }
            return $envdir;
        } else {
            return '/usr/local/psa/';
        }
    }

    /*
     * function sourceTranslations()
     * Sources translation files for Plesk actions
     * @param void
     *
     * @global array lmsg_arr
     *
     * @return void
     */
    private function sourceTranslations()
    {
        global $lmsg_arr;
        $path = $this->getRootDir() . ($this->is_windows ?
            '\admin\plib\locales\en-US\common_messages_en-US.php' :
            '/admin/plib/locales/en-US/common_messages_en-US.php');
        if (!is_readable($path)) {
            throw new Exception('Failed to read ' . $path);
        }
        include_once $path;
    }

    /*
     * function getPassword
     * Extracts password for Plesk database based on OS
     * @param void
     *
     * @return string
     */
    private function getPassword()
    {
        $sql_password = '';
        if ($this->is_windows) {
            $version = $this->getVersion();
            if ($version >= 17800) {
                exec('plesk sbin psadb -g', $password, $rval);
                if ($rval) {
                    throw new Exception('Failed to extract Plesk database password!');
                }
                $sql_password = $password[0];
            } else {
                if ($version >= 12500) {
                    exec('plesk sbin plesksrvclient -get -nogui', $password, $rval);
                } else {
                    exec('"' . $this->getRootDir() . '\admin\bin\plesksrvclient.exe" -get -nogui', $password, $rval);
                }
                if ($rval) {
                    throw new Exception('Failed to extract Plesk database password!');
                }
                $sql_password = substr($password[0], 22);
            }
        } else {
            $sql_password = trim(file_get_contents('/etc/psa/.psa.shadow'));
        }
        return $sql_password;
    }

    /*
     * function establishConnection()
     * Connects to Plesk database
     * @param void
     *
     * @return void
     */
    private function establishConnection()
    {
        $sql_password = $this->getPassword();
        $port = $this->getPort();
        $mysql = mysqli_init();
        if (!$mysql) {
            throw new Exception('Failed to init MySQLi instance!');
        }
        if (!$mysql->options(MYSQLI_OPT_CONNECT_TIMEOUT, 10)) {
            throw new Exception('Failed to configure connection timeout!');
        }
        // @ here is for Plesk with upgraded MySQL/MariaDB instances
        if (! @$mysql->real_connect($this->findServerAddress(), 'admin', $sql_password, 'psa', $port)) {
            throw new Exception('Connection to Plesk database failed: ' . mysqli_connect_error());
        }
        if (!$mysql->set_charset('UTF8')) {
            throw new Exception('Failed to set charset to UTF8: ' . $mysql->error);
        }
        $this->psa_connection = $mysql;
    }

    /*
     * function getPort()
     * Returns correct port based on OS
     * @param void
     *
     * @return int: port
     */
    private function getPort()
    {
        return $this->is_windows ? 8306 : 3306;
    }

    /*
     * function findServerAddress()
     * Finds correct address to use (127.0.0.1/localhost/::1)
     * @params void
     *
     * @return string: address
     *
     * @throws Exception
     */
    private function findServerAddress()
    {
        $addresses = array('localhost', '::1', '127.0.0.1');
        foreach ($addresses as $address) {
            @ $socket = fsockopen($address, $this->getPort(), $err, $errstr, 5);
            fclose($socket);
            if (!$err) {
                return $address;
            }
        }
        throw new Exception('Failed to get MySQL server address');
    }

    /*
     * function _getVersion()
     * Extracts Plesk version from version file
     * @param void
     *
     * @return void
     */
    private function _getVersion()
    {
        $path = $this->getRootDir() . 'version';
        if (!is_readable($path)) {
            throw new Exception('Failed to read ' . $path);
        } else {
            $file = file_get_contents($path);
            // We will receive Plesk version as 5 numbers: "17811"
            $version_array = explode(' ', $file);
            $this->version = intval(filter_var(
                $version_array[0],
                FILTER_SANITIZE_NUMBER_INT
            ));
        }
    }

    /*
     * function getConnection()
     * @param void
     *
     * @return class mysqli
     */
    public function getConnection()
    {
        return $this->psa_connection;
    }

    /*
     * function getVersion()
     * @param void
     *
     * @return int: Plesk version (17811 for 17.8.11 and so on)
     */
    public function getVersion()
    {
        return $this->version;
    }
}

class ActionLogEvent 
{
    public $actionId = 0;
    public $ipAddress = '';
    public $user = '';
    public $date = '';
    public $actionName = '';
    public $values = '';

    /*
     * function __construct()
     * @param int id
     * @param string ip
     * @param string user
     * @param string date
     * @param string summary
     * @param string description: '\n'-separated list of values
     * @param string old_value: '\n'-separated list of values
     * @param string new_value: '\n'-separated list of values
     *
     * @global lmsg_arr
     *
     * @return ActionLogEvent
     */
    function __construct($id, $ip, $user, $date, $summary, $description, $old_value, $new_value)
    {
        global $lmsg_arr;
        $this->actionId = $id;
        $this->ipAddress = $ip;
        $this->user = $user;
        $this->date = $date;
        if (isset($lmsg_arr['actionlog__event_' . $summary])) {
            $this->actionName = $lmsg_arr['actionlog__event_' . $summary];
        } else {
            $this->actionName = $summary;
        }
        $old_values = explode("\n", $old_value);
        $new_values = explode("\n", $new_value);
        $descriptions = explode("\n", $description);
        for ($i = 0; $i < count($old_values); ++$i) {
            $this->values .= '\'' . $descriptions[$i] . '\': '
                . '\'' . $old_values[$i] . '\' => '
                . '\'' . $new_values[$i] . '\'';
            if ($i !== count($old_values) - 1) {
                $this->values .= ', ';
            }
        }
    }

    /*
     * function display()
     * Returns correctly styled string
     *
     * @param void
     *
     * @return string
     */
    public function display()
    {
        return $this->ipAddress . ' '
            . $this->user . ' ['
            . $this->date . '] \''
            . $this->actionName . '\' ('
            . $this->values . ')';
    }

}

class EventExtractor
{
    private $events = array();
    private $abstract_layer = null;
    private $datefrom = null;
    private $dateto = null;

    /*
     * function __construct()
     * @param AbstractLayer
     * @param DateTime datefrom
     * @param DateTime dateto
     *
     * @return EventExtractor
     */
    function __construct($abstractlayer, $datefrom, $dateto)
    {
        $this->abstract_layer = $abstractlayer;
        $this->datefrom = $datefrom;
        $this->dateto = $dateto;
        if ($this->abstract_layer->getVersion() < 17800) {
            $this->extractOld();
        } else {
            $this->extractCurrent();
        }
    }

    /*
     * function display()
     * @param void
     * 
     * @return string: all action log events
     */
    public function display() 
    {
        $rval = '';
        foreach ($this->events as $event) {
            $rval .= $event->display() . "\n";
        }
        return $rval;
    }

    /*
     * function extractOld()
     * Extracts rows from log_actions, for Plesk before 17.8
     * @param void
     *
     * @return void
     */
    private function extractOld() 
    {
        $action_log = $this->abstract_layer->getConnection()->prepare(
            'SELECT
            log_actions.id,
            log_actions.ip_address,
            log_actions.user,
            log_actions.date,
            actions.descr,
            GROUP_CONCAT(log_components.component SEPARATOR \'\\n\'),
            GROUP_CONCAT(log_components.old_value SEPARATOR \'\\n\'),
            GROUP_CONCAT(log_components.new_value SEPARATOR \'\\n\')
            FROM log_actions
            LEFT JOIN log_components
            ON log_actions.id = log_components.action_id
            LEFT JOIN actions
            ON log_actions.action_id = actions.id
            WHERE log_actions.date
            BETWEEN \'' . $this->datefrom->format('Y-m-d H:i:s') . '\'
            AND \'' . $this->dateto->format('Y-m-d H:i:s') . '\'
            GROUP BY log_actions.id'
        );
        $action_log->execute();
        if (!$action_log) {
            die('Failed to extract action log: ' . $this->abstract_layer->getConnection()->error);
        }
        $action_log->bind_result($id, $ip, $user, $date, $summary, $description, $old_value, $new_value);
        while ($row = $action_log->fetch()) {
            $this->events[] = new ActionLogEvent($id, $ip, $user, $date, $summary, $description, $old_value, $new_value);
        }
    }

    /*
     * function extractCurrent()
     * Extracts rows from log_actions, for Plesk 17.8 and newer
     * @param void
     *
     * @return void
     */
    private function extractCurrent() 
    {
        $action_log = $this->abstract_layer->getConnection()->prepare(
            'SELECT
            log_actions.id,
            log_actions.ip_address,
            log_actions.user,
            log_actions.date,
            log_actions.action_name,
            GROUP_CONCAT(log_components.component SEPARATOR \'\\n\'),
            GROUP_CONCAT(log_components.old_value SEPARATOR \'\\n\'),
            GROUP_CONCAT(log_components.new_value SEPARATOR \'\\n\')
            FROM log_actions
            LEFT JOIN log_components
            ON log_actions.id = log_components.action_id
            WHERE log_actions.date
            BETWEEN \'' . $this->datefrom->format('Y-m-d H:i:s') . '\'
            AND \'' . $this->dateto->format('Y-m-d H:i:s') . '\'
            GROUP BY log_actions.id'
        );
        $action_log->execute();
        if (!$action_log) {
            die('Failed to extract action log: ' . $this->abstract_layer->getConnection()->error);
        }
        $action_log->bind_result($id, $ip, $user, $date, $summary, $description, $old_value, $new_value);
        while ($row = $action_log->fetch()) {
            $this->events[] = new ActionLogEvent($id, $ip, $user, $date, $summary, $description, $old_value, $new_value);
        }
    }
}

/*
 * function argparse()
 * Parses argv and starts main() with correct info
 * @param array 'getopt_arr': array with getopt results
 *
 * @return void
 */
function argparse($getopt_arr)
{
    // @ here is to suppress warning about "It is not safe to rely on the system's timezone settings"
    @ date_default_timezone_set(date_default_timezone_get());
    $datefrom = new DateTime();
    $datefrom->modify('first day of this month');
    $dateto = new DateTime();
    $file_handler = null;
    if (isset($getopt_arr['f'])) {
        $datefrom = DateTime::createFromFormat('d-m-Y', $getopt_arr['f']);
        if ($datefrom === FALSE) {
            echo "Failed to parse `from` date\n";
            usage();
        }
    }
    if (isset($getopt_arr['t'])) {
        $dateto = DateTime::createFromFormat('d-m-Y', $getopt_arr['t']);
        if ($dateto === FALSE) {
            echo "Failed to parse `to` date\n";
            usage();
        }
    }
    if (isset($getopt_arr['o'])) {
        $file_handler = fopen($getopt_arr['o'], 'w') or die('Failed to open ' . $getopt_arr['o'] . " for writing\n");
    }
    $datefrom->setTime(0, 0, 0);
    $dateto->setTime(23, 59, 59);
    main($datefrom, $dateto, $file_handler);
}

/*
 * function main()
 * @param DateTime 'datefrom': first date to include in report
 * @param DateTime 'dateto': last date to include in report
 * @param resource|null 'output': file to save report to, if null, STDOUT will be used instead
 *
 * @return void
 */ 
function main($datefrom, $dateto, $output)
{
    $extractor = new EventExtractor(new AbstractLayer(), $datefrom, $dateto);
    if (is_null($output)){
        print $extractor->display();
    } else {
        fwrite($output, $extractor->display());
        fclose($output);
    }
}

function usage()
{
    $script_name = basename(__FILE__);
    print <<<EOH
$script_name: Extract Plesk Action Log from CLI
Version: 1.3

Usage:
    $script_name -f STARTDATE -t ENDDATE -o <FILE>

        Options:
    -f <DATE>   Sets start date for the Action Log, optional
                Expects input in format DD-MM-YYYY
                If omitted, uses beginning of the month

    -t <DATE>   Sets end date for the Action Log, optional
                Expects input in format DD-MM-YYYY
                If omitted, uses current date

    -o <FILE>   Sets output file, optional
                If omitted, uses terminal's STDOUT

    -h          Shows this help message

EOH;
    exit(1);
}

$options = getopt('f:t:o:h');
if (isset($options['h'])) {
    usage();
}

argparse($options);

// argparse -> main
