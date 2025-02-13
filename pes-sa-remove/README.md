Remove obsolete entries from Plesk Email Security's SpamAssassin database
=========================================================================

Overview
--------

This script is designed to check for obsolete entries from Plesk Email Security's SpamAssassin database, i.e. mailboxes that had been removed from the server after Plesk Email Security was uninstalled.

There is an option to automatically remove those entries to get rid of the related issues, e.g. inability to reinstall Plesk Email Security.

Usage
-----

The script can be run as follows:

    plesk php pes-sa-remove.php
    

This will show the list of affected mailboxes.

The script accepts the following arguments:

*   `-f`, `--fix`: If this option is defined, the affected mailboxes will be removed from the SpamAssassin table.
    
*   `-h`, `--help`: Shows available options.
    

Requirements
------------

The script requires Plesk PHP.

Note
----

Please ensure that you have the necessary permissions to read and write to the directory and files before running the script.