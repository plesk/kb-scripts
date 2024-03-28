<?php
/*
 * Copyright 1999-2024. Plesk International GmbH. All rights reserved.
 * This script provides an ability for mass password reset of Plesk entities.
 *
 * Requirements: Plesk Obsidian 18.0.50 or above, PHP 8.0+
 */

declare(strict_types=1);

const DEBUG = 0; // allow to dump sql logs to output
const PRE_UPGRADE_SCRIPT_VERSION = '18.0.50.0'; //script version

class PleskPasswordChanger
{
    private readonly string $pleskDir;

    public function __construct(
        private readonly GetOpt $options,
        private readonly Log $log,
        private readonly Util $util,
        private readonly PleskDb $db,
    ) {
        $this->pleskDir = $this->util->getPleskRootPath();
    }

    public function changeAllPasswords(string $newAdminPassword = ''): void
    {
        $this->logToCsv(
            'entity_type',
            'new_password',
            'owner_name',
            'owner_type',
            'owner_login',
            'owner_email',
            'domain',
            'entity_login',
            'entity_id',
        );

        if ($this->options->hasFlag('--resellers', '--exclude-resellers')) {
            $this->changeForResellers();
        }

        if ($this->options->hasFlag('--clients', '--exclude-clients')) {
            $this->changeForClients();
        }

        if ($this->options->hasFlag('--users')) {
            $this->changeForUsers();
        }

        if ($this->options->hasFlag('--domains')) {
            $this->changeForDomains();
        }

        if ($this->options->hasFlag('--dbusers')) {
            $this->changeForDatabaseUsersAccounts();
        }

        if ($this->options->hasFlag('--additionalftpaccounts')) {
            $this->changeForAdditionalFTPaccounts();
        }

        if ($this->options->hasFlag('--mailaccounts')) {
            $this->changeForMailAccounts();
        }

        if ($this->options->hasFlag('--webusers')) {
            $this->changeForWebUsers();
        }

        if ($this->options->hasFlag('--clean-up-sessions')) {
            $this->cleanUpSessions();
        }

        if ($this->options->hasFlag('--additionaladmins')) {
            $this->changeForApsc();
        }

        if ($this->options->hasFlag('--admin')) {
            $this->changeForAdmin($newAdminPassword);
        }
    }

    public function changeForClients(): void
    {
        $this->log->step('Change password for clients...', true);
        $sql = <<<EOL
            SELECT
                cl.id,
                res.login AS owner_login,
                res.cname AS owner_name,
                res.email AS owner_email,
                res.type AS owner_type,
                cl.id,
                cl.login,
                cl.email
            FROM clients AS cl, clients AS res
            WHERE cl.parent_id = res.id
                AND cl.type = 'client'
        EOL;
        foreach ($this->db->fetchAll($sql) as $client) {
            $newPassword = $this->getNewPassword();
            $output = $this->util->execPleskUtility('client', ['-u', $client['login'], '-passwd', ''], [
                'PSA_PASSWORD' => $newPassword,
            ]);

            if ($output['code'] !== 0) {
                $this->logExecutionFailure('Update hosting panel user', $output);
                continue;
            }

            if (isset($client['owner_login'])) {
                $this->logToCsv(
                    'customer',
                    $newPassword,
                    $client['owner_name'],
                    $client['owner_type'],
                    $client['owner_login'],
                    $client['owner_email'],
                    '',
                    $client['login'],
                    $client['id'],
                );
            } else {
                $this->logToCsv('customer', $newPassword, '', '', '', '', '', $client['login'], $client['id']);
            }

            $this->log->info("Client login: {$client['login']} Email: {$client['email']} New password: {$newPassword}");
        }
    }

    private function changeForApsc(): void
    {
        if (! $this->util->isLinux()) {
            return;
        }

        $this->log->step('Change password for apsc database...', true);
        $output = $this->util->execPleskUtility('sw-engine-pleskrun', [
            "{$this->pleskDir}/admin/plib/scripts/check_apsc_connection.php",
        ]);

        if ($output['stdout'] === 'connection ok') {
            $this->log->info('apsc connection is OK. Skip password changing.');
            return;
        }

        $newPassword = $this->getNewPassword();
        $this->db->query("SET PASSWORD FOR 'apsc'@'localhost' = PASSWORD('{$newPassword}')");

        $output = $this->util->execPleskUtility('sw-engine-pleskrun', [
            "{$this->pleskDir}/admin/plib/scripts/register_apsc_database.php",
            '--register',
            '-host',
            'localhost',
            '-port',
            '3306',
            '-database',
            'apsc',
            '-login',
            'apsc',
            '-password',
            $newPassword,
        ]);

        if (trim($output['stdout']) === 'APSC database has been registered successfully') {
            $this->log->info('apsc database login: apsc New password: ' . $newPassword);
            return;
        }

        $this->logExecutionFailure('update password for apsc database', $output);
    }

    private function cleanUpSessions(): void
    {
        $this->log->step('Clean up all user sessions in Plesk database...', true);
        $this->db->query('DELETE FROM sessions');
    }

    private function changeForAdmin(string $newPassword = ''): void
    {
        if ($newPassword === '') {
            $newPassword = $this->getNewPassword();
        }

        $this->log->step('Change password for admin...', true);
        $output = $this->util->execPleskUtility('admin', ['--set-admin-password', '-passwd', ''], [
            'PSA_PASSWORD' => $newPassword,
        ]);

        if ($output['code'] !== 0) {
            $this->logExecutionFailure('change admin\'s password', $output);
            return;
        }

        $this->logToCsv('admin', $newPassword, '', '', '', '', '', 'admin', '');
        $this->log->info('New admin password: ' . $newPassword);
        $this->options->setNewAdminDbPasswd($newPassword);
    }

    private function changeForAdditionalAdmins(): void
    {
        $this->log->step('Change password for additional administrators accounts...', true);
        $sql = <<<SQL
            SELECT id, login, aemail
            FROM admin_aliases
        SQL;
        foreach ($this->db->fetchAll($sql) as $addadmin) {
            $newPassword = $this->getNewPassword();
            $output = $this->util->execPleskUtility('admin_alias', ['-u', $addadmin['login'], '-passwd', ''], [
                'PSA_PASSWORD' => $newPassword,
            ]);

            if ($output['code'] !== 0) {
                $this->logExecutionFailure('update additional administrator', $output);
                continue;
            }

            $this->logToCsv(
                'additionaladmin',
                $newPassword,
                '',
                '',
                '',
                '',
                '',
                $addadmin['login'],
                $addadmin['id'],
            );

            $this->log->info(
                "Additional administrator login: {$addadmin['login']} Email: {$addadmin['aemail']} New password: {$newPassword}"
            );
        }
    }

    private function changeForResellers(): void
    {
        $this->log->step('Change password for resellers...', true);
        $sql = <<<SQL
            SELECT clients.id, clients.login, clients.email
            FROM clients
            WHERE type = 'reseller'
        SQL;
        foreach ($this->db->fetchAll($sql) as $reseller) {
            $newPassword = $this->getNewPassword();
            $output = $this->util->execPleskUtility('reseller', ['-u', $reseller['login'], '-passwd', ''], [
                'PSA_PASSWORD' => $newPassword,
            ]);

            if ($output['code'] !== 0) {
                $this->logExecutionFailure('update reseller', $output);
                continue;
            }

            $this->logToCsv('reseller', $newPassword, '', '', '', '', '', $reseller['login'], $reseller['id']);
            $this->log->info(
                "Reseller login: {$reseller['login']} Email: {$reseller['email']} New password: {$newPassword}"
            );
        }
    }

    private function changeForUsers(): void
    {
        $this->log->step('Change password for users...', true);
        $sql = <<<SQL
            SELECT
                smb_users.id,
                smb_users.login,
                smb_users.email,
                clients.login AS owner_login,
                clients.cname AS owner_name,
                clients.type AS owner_type,
                clients.email AS owner_email
            FROM smb_users, clients
            WHERE smb_users.ownerId = clients.id
                AND smb_users.login NOT IN (SELECT login FROM clients)
        SQL;
        foreach ($this->db->fetchAll($sql) as $user) {
            $newPassword = $this->getNewPassword();
            $output = $this->util->execPleskUtility('user', ['-u', $user['login'], '-passwd', ''], [
                'PSA_PASSWORD' => $newPassword,
            ]);

            if ($output['code'] !== 0) {
                $this->logExecutionFailure('Update hosting panel user', $output);
                continue;
            }

            $this->logToCsv(
                'hosting panel user',
                $newPassword,
                $user['owner_name'],
                $user['owner_type'],
                $user['owner_login'],
                $user['owner_email'],
                '',
                $user['login'],
                $user['id'],
            );

            $this->log->info('Hosting Panel User: ' . $user['login'] . ' New password: ' . $newPassword);
        }
    }

    private function changeForDomains(): void
    {
        $this->log->step('Change password for FTP users of domains...', true);
        $sql = <<<SQL
            SELECT
                domains.id,
                domains.name,
                sys_users.login,
                clients.login AS owner_login,
                clients.cname AS owner_name,
                clients.type AS owner_type,
                clients.email AS owner_email
            FROM domains, hosting, sys_users, clients
            WHERE domains.id = hosting.dom_id
                AND hosting.sys_user_id = sys_users.id
                AND clients.id = domains.cl_id
            GROUP BY sys_users.login
        SQL;
        foreach ($this->db->fetchAll($sql) as $domain) {
            $newPassword = $this->getNewPassword();
            $output = $this->util->execPleskUtility('domain', ['-u', $domain['name'], '-passwd', ''], [
                'PSA_PASSWORD' => $newPassword,
            ]);

            if ($output['code'] !== 0) {
                $this->logExecutionFailure('Update domain FTP account', $output);
                continue;
            }

            $this->logToCsv(
                'domain FTP account',
                $newPassword,
                $domain['owner_name'],
                $domain['owner_type'],
                $domain['owner_login'],
                $domain['owner_email'],
                $domain['name'],
                $domain['login'],
                $domain['id'],
            );

            $this->log->info("FTP user {$domain['login']} for domain {$domain['name']} New password: {$newPassword}");
        }
    }

    private function changeForAdditionalFTPaccounts(): void
    {
        $this->log->step('Change password for additional FTP accounts...', true);
        $sql = <<<SQL
            SELECT
                sys_users.id,
                sys_users.login,
                domains.name,
                clients.login AS owner_login,
                clients.cname AS owner_name,
                'client' AS owner_type,
                clients.email AS owner_email
            FROM ftp_users, sys_users, domains, clients
            WHERE ftp_users.sys_user_id = sys_users.id
                AND ftp_users.dom_id = domains.id
                AND clients.id = domains.cl_id
        SQL;
        foreach ($this->db->fetchAll($sql) as $account) {
            $newPassword = $this->getNewPassword();
            $output = $this->util->execPleskUtility('ftpsubaccount', [
                '-u',
                $account['login'],
                '-passwd',
                '',
                '-domain',
                $account['name'],
            ], [
                'PSA_PASSWORD' => $newPassword,
            ]);

            if ($output['code'] !== 0) {
                $this->logExecutionFailure('Update additional FTP account', $output);
                continue;
            }

            $this->logToCsv(
                'additional FTP account',
                $newPassword,
                $account['owner_name'],
                $account['owner_type'],
                $account['owner_login'],
                $account['owner_email'],
                $account['name'],
                $account['login'],
                $account['id'],
            );

            $this->log->info(
                "Domain: {$account['name']} Additional FTP account: {$account['login']} New password: {$newPassword}"
            );
        }
    }

    private function changeForWebUsers(): void
    {
        $this->log->step('Change password for web users of domains...', true);
        $sql = <<<SQL
            SELECT
                sys_users.id,
                sys_users.login,
                domains.name,
                clients.login AS owner_login,
                clients.cname AS owner_name,
                clients.type AS owner_type,
                clients.email AS owner_email
            FROM web_users, sys_users, clients, domains
            WHERE web_users.sys_user_id = sys_users.id
                AND web_users.dom_id = domains.id
                AND clients.id = domains.cl_id
        SQL;
        foreach ($this->db->fetchAll($sql) as $webuser) {
            $newPassword = $this->getNewPassword();
            $output = $this->util->execPleskUtility('webuser', [
                '-u',
                $webuser['login'],
                '-passwd',
                '',
                '-domain',
                $webuser['name'],
            ], [
                'PSA_PASSWORD' => $newPassword,
            ]);

            if ($output['code'] !== 0) {
                $this->logExecutionFailure('Update web user', $output);
                continue;
            }

            $this->logToCsv(
                'web user',
                $newPassword,
                $webuser['owner_name'],
                $webuser['owner_type'],
                $webuser['owner_login'],
                $webuser['owner_email'],
                $webuser['name'],
                $webuser['login'],
                $webuser['id'],
            );

            $this->log->info("Web user {$webuser['login']} for domain {$webuser['name']} New password: {$newPassword}");
        }
    }

    private function changeForMailAccounts(): void
    {
        $this->log->step('Change password for mail accounts...', true);
        $sql = <<<SQL
            SELECT
                mail.id,
                mail.mail_name,
                domains.name,
                clients.login AS owner_login,
                clients.cname AS owner_name,
                clients.type AS owner_type,
                clients.email AS owner_email
            FROM mail, domains, clients
            WHERE mail.dom_id = domains.id
                AND (mail.userId = 0 OR mail.userId IS NULL)
                AND clients.id = domains.cl_id
        SQL;
        foreach ($this->db->fetchAll($sql) as $account) {
            $newPassword = $this->getNewPassword();
            $output = $this->util->execPleskUtility('mail', [
                '-u',
                $account['mail_name'] . '@' . $account['name'],
                '-passwd',
                '',
            ], [
                'PSA_PASSWORD' => $newPassword,
            ]);

            if ($output['code'] !== 0) {
                $this->logExecutionFailure('Update mail account', $output);
                continue;
            }

            $this->logToCsv(
                'mail account',
                $newPassword,
                $account['owner_name'],
                $account['owner_type'],
                $account['owner_login'],
                $account['owner_email'],
                $account['name'],
                $account['mail_name'],
                $account['id'],
            );

            $this->log->info("Mail account: {$account['mail_name']}@{$account['name']} New password: {$newPassword}");
        }
    }

    private function changeForDatabaseUsersAccounts(): void
    {
        $this->log->step('Change password for database users...', true);
        $sql = <<<SQL
            SELECT
                domains.name AS domain_name,
                clients.login AS owner_login,
                clients.pname AS owner_name,
                clients.type AS owner_type,
                clients.email AS owner_email,
                db_users.id,
                data_bases.name,
                data_bases.type,
                DatabaseServers.host,
                DatabaseServers.port,
                db_users.login
            FROM domains, clients, db_users, data_bases, DatabaseServers
            WHERE db_users.db_id = data_bases.id
                AND data_bases.dom_id = domains.id
                AND clients.id = domains.cl_id
                AND DatabaseServers.id = data_bases.db_server_id
        SQL;
        foreach ($this->db->fetchAll($sql) as $dbuser) {
            $newPassword = $this->getNewPassword();
            $output = $this->util->execPleskUtility('database', [
                '-u',
                $dbuser['name'],
                '-update_user',
                $dbuser['login'],
                '-passwd',
                '',
            ], [
                'PSA_PASSWORD' => $newPassword,
            ]);

            if ($output['code'] !== 0) {
                $this->logExecutionFailure('Update database user', $output);
                continue;
            }

            $this->logToCsv(
                'dbuser',
                $newPassword,
                $dbuser['owner_name'],
                $dbuser['owner_type'],
                $dbuser['owner_login'],
                $dbuser['owner_email'],
                $dbuser['domain_name'],
                $dbuser['login'],
                $dbuser['id'],
            );

            $this->log->info(
                "{$dbuser['type']} database {$dbuser['name']} user on {$dbuser['host']}: "
                . "{$dbuser['port']} with login {$dbuser['login']} on domain {$dbuser['domain_name']} New password: {$newPassword}",
            );
        }
    }

    private function getNewPassword(): string
    {
        $length = 16;
        $patterns = [];
        $patterns[] = '1234567890';
        $patterns[] = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        $patterns[] = 'abcdefghijklmnopqrstuvwxyz';

        $passwordString = '';
        foreach ($patterns as $pattern) {
            $passwordString .= substr(str_shuffle($pattern), 0, (int)($length / count($patterns)));
        }

        $passwordString .= substr(str_shuffle('@#%^*'), 0);
        return str_shuffle($passwordString);
    }

    private function logToCsv(
        string $entityType,
        string $newPassword,
        mixed $ownerName,
        mixed $ownerType,
        mixed $ownerLogin,
        mixed $ownerEmail,
        mixed $domain,
        mixed $entityLogin,
        mixed $entityId,
    ) {
        $log = implode(';', [
            (string) $ownerName,
            (string) $ownerType,
            (string) $ownerLogin,
            (string) $ownerEmail,
            (string) $domain,
            $entityType,
            (string) $entityLogin,
            (string) $entityId,
            $newPassword,
        ]) . PHP_EOL;
        $this->log->write(__DIR__ . '/new_plesk_passwords.csv', $log);
    }

    private function logExecutionFailure(string $action, array $result): void
    {
        $this->log->warning(
            "Failed to {$action} using command {$result['cmd']}: code: [{$result['code']}], stdout: [{$result['stdout']}], stderr: [{$result['stderr']}]",
        );
    }
}

class PleskInstallation
{
    public function __construct(
        private readonly Util $util,
        private readonly Log $log
    ) {
    }

    public function validate()
    {
        if (! $this->isInstalled()) {
            $this->log->fatal('Plesk installation is not found.');
        }

        if (version_compare('18.0.50', $this->getVersion(), '>')) {
            $this->log->fatal(
                'Currently installed Plesk version is too low. This script only supports Plesk 18.0.50 and newer.'
            );
        }
    }

    public function isInstalled(): bool
    {
        $rootPath = $this->util->getPleskRootPath();
        return ! empty($rootPath) && file_exists($rootPath);
    }

    public function getVersion(): string
    {
        return explode(' ', file_get_contents($this->util->getPleskRootPath() . '/version'))[0];
    }
}

class Log
{
    private const FATAL_ERROR = 'FATAL_ERROR';

    private const ERROR = 'ERROR';

    private const WARNING = 'WARNING';

    private const INFO = 'INFO';

    private readonly string $logFile;

    private int $errorCount = 0;

    private int $warningCount = 0;

    public function __construct()
    {
        $this->logFile = __DIR__ . '/mass_password_reset_tool.log';
        @unlink($this->logFile);
    }

    public function getErrorCount(): int
    {
        return $this->errorCount;
    }

    public function getWarningCount(): int
    {
        return $this->warningCount;
    }

    public function fatal(string $msg): void
    {
        $this->log($msg, self::FATAL_ERROR);
    }

    public function error(string $msg): void
    {
        $this->log($msg, self::ERROR);
    }

    public function warning(string $msg): void
    {
        $this->log($msg, self::WARNING);
    }

    public function step(string $msg, bool $useNumber = false): void
    {
        static $step = 1;

        if ($useNumber) {
            $msg = '==> STEP ' . $step . ": {$msg}";
            $step++;
        } else {
            $msg = "==> {$msg}";
        }

        $this->log($msg, self::INFO, PHP_EOL);
    }

    public function resultOk(): void
    {
        $msg = 'Result: OK';
        $this->info($msg);
    }

    public function info(string $msg): void
    {
        $this->log($msg, self::INFO);
    }

    public function dumpStatistics(): void
    {
        $str = 'Found errors: ' . $this->errorCount
            . '; Found warnings: ' . $this->warningCount
        ;
        echo PHP_EOL . $str . PHP_EOL . PHP_EOL;
    }

    public function write(string $file, string $content, string $mode = 'a+'): void
    {
        $fp = fopen($file, $mode);
        fwrite($fp, $content);
        fclose($fp);
    }

    private function log(string $msg, string $type, string $newLine = ''): void
    {
        $date = date('Y-m-d h:i:s');
        $log = $newLine . "[{$date}][{$type}] {$msg}" . PHP_EOL;

        if ($type === self::ERROR || $type === self::FATAL_ERROR) {
            $this->errorCount++;
            fwrite(STDERR, $log);
        } elseif ($type === self::WARNING) {
            $this->warningCount++;
            fwrite(STDERR, $log);
        } elseif ($type === self::INFO) {
            //:INFO: Dump to output and write log to the file
            echo $log;
        }

        $this->write($this->logFile, $log);

        //:INFO: Terminate the process if have the fatal error
        if ($type === self::FATAL_ERROR) {
            exit(1);
        }
    }
}

class PleskDb
{
    private readonly PDO $db;

    public function __construct(
        private readonly Log $log,
        private readonly Util $util,
        private readonly GetOpt $options,
    ) {
        $dbParams = $this->getDbParams();
        $this->db = new PDO(
            "mysql:host={$dbParams['host']};dbname={$dbParams['db']};port={$dbParams['port']}",
            $dbParams['login'],
            $dbParams['passwd'],
            [
                PDO::ERRMODE_EXCEPTION => true,
            ],
        );
    }

    public function fetchAll(string $sql): Generator
    {
        if (DEBUG !== 0) {
            $this->log->info($sql);
        }

        $query = $this->db->query($sql);
        $query->execute();
        while ($row = $query->fetch()) {
            yield $row;
        }
    }

    public function query(string $sql): void
    {
        $query = $this->db->query($sql);
        $query->execute();
    }

    private function getDbParams(): array
    {
        return [
            'db' => trim($this->util->getPleskDbName()),
            'port' => $this->util->getPleskDbPort(),
            'login' => trim($this->util->getPleskDbLogin()),
            'passwd' => trim($this->options->getDbPasswd()),
            'host' => trim($this->util->getPleskDbHost()),
        ];
    }
}

class Util
{
    private readonly string $pleskRoot;

    private readonly bool $isWindows;

    private readonly string $osArch;

    public function __construct(
        private readonly Log $log,
    ) {
        $this->isWindows = strtoupper(substr(PHP_OS, 0, 3)) === 'WIN';
        if ($this->isWindows) {
            $this->osArch = 'x86_64';
        }

        $this->pleskRoot = $this->isLinux() ? '/usr/local/psa' : $this->regPleskQuery('PRODUCT_ROOT_D', true);
        if ($this->isWindows) {
            return;
        }

        $osInfo = json_decode($this->execPleskUtility('osdetect', isSbin: true)['stdout'], true, 512, JSON_THROW_ON_ERROR);
        $this->osArch = $osInfo['arch'];
    }

    public function isWindows(): bool
    {
        return $this->isWindows;
    }

    public function isLinux(): bool
    {
        return ! $this->isWindows;
    }

    public function getPleskDbName(): string
    {
        $dbName = 'psa';
        if ($this->isWindows()) {
            $dbName = $this->regPleskQuery('mySQLDBName');
        }

        return $dbName;
    }

    public function getPleskDbLogin(): string
    {
        $dbLogin = 'admin';
        if ($this->isWindows()) {
            $dbLogin = $this->regPleskQuery('PLESK_DATABASE_LOGIN');
        }

        return $dbLogin;
    }

    public function getPleskDbHost(): string
    {
        $dbHost = 'localhost';
        if ($this->isWindows()) {
            $dbHost = $this->regPleskQuery('MySQL_DB_HOST');
        }

        return $dbHost;
    }

    public function getPleskDbPort(): int
    {
        $dbPort = 3306;
        if ($this->isWindows()) {
            $dbPort = $this->regPleskQuery('MYSQL_PORT');
        }

        return (int) $dbPort;
    }

    public function regPleskQuery(string $key, bool $returnResult = false): string|false
    {
        $output = $this->exec([
            'REG',
            'QUERY',
            $this->osArch === 'x86_64'
                ? 'HKLM\SOFTWARE\Wow6432Node\Plesk\Psa Config\Config'
                : 'HKLM\SOFTWARE\Plesk\Psa Config\Config',
            '/v',
            $key,
        ]);

        if ($returnResult && $output['code'] !== 0) {
            return false;
        }

        if ($output['code'] !== 0) {
            $this->log->fatal(
                "Unable to get '{$key}' from registry: stdout [{$output['stdout']}] stderr [{$output['stderr']}]"
            );
        }

        if (! preg_match("/\w+\s+REG_SZ\s+(.*)/i", trim($output['stdout']), $matches)) {
            $this->log->fatal('Unable to macth registry value by key ' . $key . '. Output: ' . trim($output['stdout']));
        }

        return $matches[1];
    }

    public function retrieveAdminMySQLDbPassword(): string
    {
        if ($this->isLinux()) {
            return file_get_contents('/etc/psa/.psa.shadow');
        }

        return $this->exec([
            "{$this->pleskRoot}\\admin\\bin64\\psadb.exe",
            '--get-admin-password',
        ])['stdout'];
    }

    public function getPleskRootPath(): string
    {
        return $this->pleskRoot;
    }

    /**
     * @return array{code: int, stdout: string, stderr: string, cmd: string}
     */
    public function exec(array $cmd, array $env = []): array
    {
        if (DEBUG !== 0) {
            $this->log->info(implode(', ', $cmd));
        }

        $stdout = tempnam(sys_get_temp_dir(), 'out');
        $stderr = tempnam(sys_get_temp_dir(), 'err');
        $pipes = [];
        $descriptors = [
            0 => ['pipe', 'r'],
            1 => ['file', $stdout, 'w'],
            2 => ['file', $stderr, 'w'],
        ];

        $proc = proc_open(command: $cmd, descriptor_spec: $descriptors, pipes: $pipes, env_vars: $env, options: [
            'bypass_shell' => true,
            'create_process_group' => true,
        ]);

        fclose($pipes[0]);
        $data = [
            'code' => proc_close($proc),
            'stdout' => file_get_contents($stdout),
            'stderr' => file_get_contents($stderr),
            'cmd' => implode(' ', array_map('escapeshellarg', $cmd)),
        ];

        unlink($stdout);
        unlink($stderr);

        return $data;
    }

    /**
     * @return array{code: int, stdout: string, stderr: string, cmd: string}
     */
    public function execPleskUtility(string $utility, array $args = [], array $env = [], bool $isSbin = false): array
    {
        $path = $this->pleskRoot;
        if ($this->isWindows) {
            if ($isSbin) {
                $path .= '\\admin';
            }

            $path .= "\\bin\\{$utility}.exe";
            $env = array_merge(getenv(), $env);
        } else {
            if ($isSbin) {
                $path .= '/admin';
            }

            $path .= "/bin/{$utility}";
        }

        return $this->exec(array_merge([$path], $args), $env);
    }
}

class GetOpt
{
    private array $argv;

    private string $adminDbPasswd;

    private string $newAdminPasswd = '';

    public function __construct(
        private readonly Util $util,
    ) {
        $this->argv = $_SERVER['argv'];
        $this->adminDbPasswd = empty($this->argv[1])
            ? $this->util->retrieveAdminMySQLDbPassword()
            : $this->argv[1];

        if (! empty($this->argv[2]) && ! preg_match('/^--/', (string) $this->argv[2])) {
            $this->newAdminPasswd = $this->argv[2];
        }

        if (! strpos(implode(' ', $this->argv), ' --')) {
            $this->argv[] = '--all'; // if there is no any arguments like --something, than treat this as --all
        }
    }

    public function validate(): void
    {
        if (empty($this->adminDbPasswd)) {
            fwrite(STDERR, 'Please, specify Plesk database password');
            $this->helpUsage();
        }

        if (in_array('-h', $this->argv, true) || in_array('--help', $this->argv, true)) {
            $this->helpUsage();
        }
    }

    public function hasFlag(string $flag, ?string $excludeFlag = null): bool
    {
        if (in_array('--all', $this->argv, true)) {
            return true;
        }

        if ($excludeFlag !== null) {
            return in_array($flag, $this->argv, true);
        }

        return ! in_array($excludeFlag, $this->argv, true) && in_array($flag, $this->argv, true);
    }

    public function setNewAdminDbPasswd(string $adminDbPasswd): void
    {
        $this->adminDbPasswd = $adminDbPasswd;
    }

    public function getDbPasswd(): string
    {
        return $this->adminDbPasswd;
    }

    public function getNewAdminPasswd(): string
    {
        return $this->newAdminPasswd;
    }

    public function helpUsage(): never
    {
        echo PHP_EOL . "Usage: {$this->argv[0]} <plesk_db_admin_password> [new_plesk_db_admin_password] [options]" . PHP_EOL;
        echo 'Options: --all - [default] change passwords for all supported entities and clean up sessions table in Plesk database' . PHP_EOL;
        echo '         --admin - change password for admin' . PHP_EOL;
        echo '         --apsc - change password for apsc database' . PHP_EOL;
        echo '         --clean-up-sessions - clean up sessions table in Plesk database' . PHP_EOL;
        echo '         --additionaladmins - change passwords for additional administrators accounts' . PHP_EOL;
        echo '         --resellers - change passwords for resellers' . PHP_EOL;
        echo '         --clients - change passwords for clients' . PHP_EOL;
        echo '         --domains - change passwords for main FTP account of domains' . PHP_EOL;
        echo '         --users - change passwords for hosting panel users' . PHP_EOL;
        echo '         --additionalftpaccounts - change passwords for additional FTP accounts for domains' . PHP_EOL;
        echo '         --dbusers - change passwords for database users.' . PHP_EOL;
        echo '         --webusers - change passwords for webusers' . PHP_EOL;
        echo '         --mailaccounts - change passwords for mail accounts' . PHP_EOL;
        exit(1);
    }
}

if (str_starts_with(PHP_SAPI, 'cgi')) {
    //:INFO: set max execution time 1hr
    @set_time_limit(3600);
}

date_default_timezone_set(@date_default_timezone_get());

$log = new Log();
$util = new Util($log);
$getopt = new GetOpt($util);
$getopt->validate();

//:INFO: Validate Plesk installation
$pleskInstallation = new PleskInstallation($util, $log);
$pleskInstallation->validate();

//:INFO: Need to make sure that given db password is valid
$log->step('Validate given db password');
$db = new PleskDb($log, $util, $getopt);
$log->resultOk();

//:INFO: Dump script version
$log->step('Plesk Password Changer version: ' . PRE_UPGRADE_SCRIPT_VERSION);

$PleskPasswordChanger = new PleskPasswordChanger($getopt, $log, $util, $db);
$PleskPasswordChanger->changeAllPasswords($getopt->getNewAdminPasswd());

$log->dumpStatistics();

if ($log->getErrorCount() > 0 || $log->getWarningCount() > 0) {
    exit(1);
}
