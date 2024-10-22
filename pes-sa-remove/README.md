<h1>Remove obsolete entries from Plesk Email Security's SpamAssassin database</h1>
<h2>Overview</h2>
<p>This script is designed to check for obsolete entries from Plesk Email Security's SpamAssassin database, i.e. mailboxes that had been removed from the server after Plesk Email Security was uninstalled.</p>
<p>There is an option to automatically remove those entries to get rid of the related issues, e.g. inability to reinstall Plesk Email Security.</p>
<h2>Usage</h2>
<p>The script can be run as follows:</p>
<pre class=""><code class="">plesk php pes-sa-remove.php
</code></pre>
<p>This will show the list of affected mailboxes.</p>
<p>The script accepts the following arguments:</p>
<ul>
<li>
<p><code>-f</code>, <code>--fix</code>: If this option is defined, the affected mailboxes will be removed from the SpamAssassin table.</p>
</li>
<li>
<p><code>-h</code>, <code>--help</code>: Shows available options.</p>
</li>
</ul>
<h2>Requirements</h2>
<p>The script requires Plesk PHP.</p>
<h2>Note</h2>
<p>Please ensure that you have the necessary permissions to read and write to the directory and files before running the script.</p>
