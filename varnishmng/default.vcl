#########################################################################
###               The perfect Varnish 4.x+ configuration              ###
### for WordPress, Joomla, Drupal & other (common) CMS based websites ###
#########################################################################

######################
#
# UPDATED on December 15th, 2021
#
# Configuration Notes:
# 1. Default dynamic content caching respects your backend's cache-control HTTP header.
#    If however you need to enforce a different cache-control TTL,
#    do a search for "180" and replace with the new value in seconds.
#    Stale cache is served for up to 24 hours.
# 2. Make sure you update the "backend default { ... }" section with the correct IP and port
#
######################

# Varnish Reference:
# See the VCL chapters in the User-Guide at https://varnish-cache.org/docs/

# Marker to tell the VCL compiler that this VCL has been adapted to the new 4.1 format
vcl 4.1;

# Imports
import std;

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "127.0.0.1"; # UPDATE this only if the web server is not on the same machine
    .port = "8080";      # UPDATE 8080 with your web server's (internal) port
}

sub vcl_recv {

    /*
    # === The following are disabled by default - enable if you understand what you're doing ===
    # Blocks
    if (req.http.user-agent ~ "^$" && req.http.referer ~ "^$") {
        return (synth(204, "No content"));
    }
    if (req.http.user-agent ~ "(ahrefs|domaincrawler|dotbot|mj12bot|semrush)") {
        return (synth(204, "Bot blocked"));
    }

    # List domains/subdomains to exclude from caching
    if (req.http.host ~ "(domain1.tld|sub.domain2.tld)") {
        return (pass);
    }
    */

    # LetsEncrypt Certbot passthrough
    if (req.url ~ "^/\.well-known/acme-challenge/") {
        return (pass);
    }

    # Forward client's IP to the backend
    if (req.restarts == 0) {
        if (req.http.X-Real-IP) {
            set req.http.X-Forwarded-For = req.http.X-Real-IP;
        } else if (req.http.X-Forwarded-For) {
            set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    }

    # httpoxy
    unset req.http.proxy;

    # Normalize the query arguments (but exclude for WordPress' backend)
    if (req.url !~ "wp-admin") {
        set req.url = std.querysort(req.url);
    }

    # Non-RFC2616 or CONNECT which is weird.
    if (
        req.method != "GET" &&
        req.method != "HEAD" &&
        req.method != "PUT" &&
        req.method != "POST" &&
        req.method != "TRACE" &&
        req.method != "OPTIONS" &&
        req.method != "DELETE"
    ) {
        return (pipe);
    }

    # We only deal with GET and HEAD by default
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # === URL manipulation ===
    # Remove tracking query string parameters associated with analytics/social services, useless for our backend
    if (req.url ~ "(\?|&)(_bta_[a-z]+|cof|cx|fbclid|gclid|ie|mc_[a-z]+|origin|siteurl|utm_[a-z]+|zanpid)=") {
        set req.url = regsuball(req.url, "(_bta_[a-z]+|cof|cx|fbclid|gclid|ie|mc_[a-z]+|origin|siteurl|utm_[a-z]+|zanpid)=[-_A-z0-9+()%.]+&?", "");
        set req.url = regsub(req.url, "[?|&]+$", "");
    }

    # Strip a trailing ? if it exists
    if (req.url ~ "\?$") {
        set req.url = regsub(req.url, "\?$", "");
    }

    # Strip hash, server doesn't need it.
    if (req.url ~ "\#") {
        set req.url = regsub(req.url, "\#.*$", "");
    }

    # === Generic cookie manipulation ===
    # Collapse multiple cookie headers into one
    std.collect(req.http.Cookie);

    # Remove common cookies associated with analytics/social services (inc. WordPress test cookies)
    set req.http.Cookie = regsuball(req.http.Cookie, "(has_js|__utm.|_ga|_gat|utmctr|utmcmd.|utmccn.|__gads|__qc.|__atuv.|wp-settings-1|wp-settings-time-1|wordpress_test_cookie)=[^;]+(; )?", "");

    # Remove a ";" prefix in the cookie if present
    set req.http.Cookie = regsuball(req.http.Cookie, "^;\s*", "");

    # Remove blank cookies
    if (req.http.cookie ~ "^\s*$") {
        unset req.http.cookie;
    }

    # Check for the custom "X-Logged-In" header (used by K2 and other apps) to identify
    # if the visitor is a guest, then unset any cookie (including session cookies) provided
    # it's not a POST request.
    if (req.http.X-Logged-In == "False" && req.method != "POST") {
        unset req.http.Cookie;
    }

    # === DO NOT CACHE ===
    # Don't cache HTTP authorization/authentication pages and pages with certain headers or cookies
    if (
        req.http.Authorization ||
        req.http.Authenticate ||
        req.http.X-Logged-In == "True" ||
        req.http.Cookie ~ "userID" ||
        req.http.Cookie ~ "joomla_[a-zA-Z0-9_]+" ||
        req.http.Cookie ~ "(wordpress_[a-zA-Z0-9_]+|wp-postpass|comment_author_[a-zA-Z0-9_]+|woocommerce_cart_hash|woocommerce_items_in_cart|wp_woocommerce_session_[a-zA-Z0-9]+)"
    ) {
        #set req.http.Cache-Control = "private, max-age=0, no-cache, no-store";
        #set req.http.Expires = "Mon, 01 Jan 2001 00:00:00 GMT";
        #set req.http.Pragma = "no-cache";
        return (pass);
    }

    # Exclude the following paths (e.g. backend admins, user pages or ad URLs that require tracking)
    # In Joomla specifically, you are advised to create specific entry points (URLs) for users to
    # interact with the site (either common user logins or even commenting), e.g. make a menu item
    # to point to a user login page (e.g. /login), including all related functionality such as
    # password reset, email reminder and so on.
    if (
        req.url ~ "^/addons" ||
        req.url ~ "^/administrator" ||
        req.url ~ "^/cart" ||
        req.url ~ "^/checkout" ||
        req.url ~ "^/component/banners" ||
        req.url ~ "^/component/socialconnect" ||
        req.url ~ "^/component/users" ||
        req.url ~ "^/connect" ||
        req.url ~ "^/contact" ||
        req.url ~ "^/login" ||
        req.url ~ "^/logout" ||
        req.url ~ "^/lost-password" ||
        req.url ~ "^/my-account" ||
        req.url ~ "^/register" ||
        req.url ~ "^/signin" ||
        req.url ~ "^/signup" ||
        req.url ~ "^/wc-api" ||
        req.url ~ "^/wp-admin" ||
        req.url ~ "^/wp-login.php" ||
        req.url ~ "^\?add-to-cart=" ||
        req.url ~ "^\?wc-api="
    ) {
        #set req.http.Cache-Control = "private, max-age=0, no-cache, no-store";
        #set req.http.Expires = "Mon, 01 Jan 2001 00:00:00 GMT";
        #set req.http.Pragma = "no-cache";
        return (pass);
    }

    # Don't cache ajax requests
    if (req.http.X-Requested-With == "XMLHttpRequest" || req.url ~ "nocache") {
        #set req.http.Cache-Control = "private, max-age=0, no-cache, no-store";
        #set req.http.Expires = "Mon, 01 Jan 2001 00:00:00 GMT";
        #set req.http.Pragma = "no-cache";
        return (pass);
    }

    # === STATIC FILES ===
    # Properly handle different encoding types
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf)$") {
            # No point in compressing these
            unset req.http.Accept-Encoding;
        } elseif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elseif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unknown algorithm (aka crappy browser)
            unset req.http.Accept-Encoding;
        }
    }

    # Remove all cookies for static files & deliver directly
    if (req.url ~ "^[^?]*\.(7z|avi|bmp|bz2|css|csv|doc|docx|eot|flac|flv|gif|gz|ico|jpeg|jpg|js|less|mka|mkv|mov|mp3|mp4|mpeg|mpg|odt|ogg|ogm|opus|otf|pdf|png|ppt|pptx|rar|rtf|svg|svgz|swf|tar|tbz|tgz|ttf|txt|txz|wav|webm|webp|woff|woff2|xls|xlsx|xml|xz|zip)(\?.*)?$") {
        unset req.http.Cookie;
        return (hash);
    }

    return (hash);

}

sub vcl_backend_response {

    /*
    # === The following are disabled by default - enable if you understand what you're doing ===
    # List domains/subdomains to exclude from caching
    if (bereq.http.host ~ "(domain1.tld|sub.domain2.tld)") {
        set beresp.uncacheable = true;
        return (deliver);
    }
    */

    # Don't cache 50x responses
    if (
        beresp.status == 500 ||
        beresp.status == 502 ||
        beresp.status == 503 ||
        beresp.status == 504
    ) {
        return (abandon);
    }

    # === DO NOT CACHE ===
    # Exclude the following paths (e.g. backend admins, user pages or ad URLs that require tracking)
    # In Joomla specifically, you are advised to create specific entry points (URLs) for users to
    # interact with the site (either common user logins or even commenting), e.g. make a menu item
    # to point to a user login page (e.g. /login), including all related functionality such as
    # password reset, email reminder and so on.
    if (
        bereq.url ~ "^/addons" ||
        bereq.url ~ "^/administrator" ||
        bereq.url ~ "^/cart" ||
        bereq.url ~ "^/checkout" ||
        bereq.url ~ "^/component/banners" ||
        bereq.url ~ "^/component/socialconnect" ||
        bereq.url ~ "^/component/users" ||
        bereq.url ~ "^/connect" ||
        bereq.url ~ "^/contact" ||
        bereq.url ~ "^/login" ||
        bereq.url ~ "^/logout" ||
        bereq.url ~ "^/lost-password" ||
        bereq.url ~ "^/my-account" ||
        bereq.url ~ "^/register" ||
        bereq.url ~ "^/signin" ||
        bereq.url ~ "^/signup" ||
        bereq.url ~ "^/wc-api" ||
        bereq.url ~ "^/wp-admin" ||
        bereq.url ~ "^/wp-login.php" ||
        bereq.url ~ "^\?add-to-cart=" ||
        bereq.url ~ "^\?wc-api="
    ) {
        #set beresp.http.Cache-Control = "private, max-age=0, no-cache, no-store";
        #set beresp.http.Expires = "Mon, 01 Jan 2001 00:00:00 GMT";
        #set beresp.http.Pragma = "no-cache";
        set beresp.uncacheable = true;
        return (deliver);
    }

    # Don't cache HTTP authorization/authentication pages and pages with certain headers or cookies
    if (
        bereq.http.Authorization ||
        bereq.http.Authenticate ||
        bereq.http.X-Logged-In == "True" ||
        bereq.http.Cookie ~ "userID" ||
        bereq.http.Cookie ~ "joomla_[a-zA-Z0-9_]+" ||
        bereq.http.Cookie ~ "(wordpress_[a-zA-Z0-9_]+|wp-postpass|comment_author_[a-zA-Z0-9_]+|woocommerce_cart_hash|woocommerce_items_in_cart|wp_woocommerce_session_[a-zA-Z0-9]+)"
    ) {
        #set beresp.http.Cache-Control = "private, max-age=0, no-cache, no-store";
        #set beresp.http.Expires = "Mon, 01 Jan 2001 00:00:00 GMT";
        #set beresp.http.Pragma = "no-cache";
        set beresp.uncacheable = true;
        return (deliver);
    }

    # Don't cache ajax requests
    if (beresp.http.X-Requested-With == "XMLHttpRequest" || bereq.url ~ "nocache") {
        #set beresp.http.Cache-Control = "private, max-age=0, no-cache, no-store";
        #set beresp.http.Expires = "Mon, 01 Jan 2001 00:00:00 GMT";
        #set beresp.http.Pragma = "no-cache";
        set beresp.uncacheable = true;
        return (deliver);
    }

    # Don't cache backend response to posted requests
    if (bereq.method == "POST") {
        set beresp.uncacheable = true;
        return (deliver);
    }

    # Ok, we're cool & ready to cache things
    # so let's clean up some headers and cookies
    # to maximize caching.

    # Check for the custom "X-Logged-In" header to identify if the visitor is a guest,
    # then unset any cookie (including session cookies) provided it's not a POST request.
    if (beresp.http.X-Logged-In == "False" && bereq.method != "POST") {
        unset beresp.http.Set-Cookie;
    }

    # Unset the "pragma" header (suggested)
    unset beresp.http.Pragma;

    # Unset the "vary" header (suggested)
    unset beresp.http.Vary;

    # Unset the "etag" header (optional)
    #unset beresp.http.etag;

    # Allow stale content, in case the backend goes down
    set beresp.grace = 24h;

    # Enforce your own cache TTL (optional)
    #set beresp.ttl = 180s;

    # Modify "expires" header (optional)
    #set beresp.http.Expires = "" + (now + beresp.ttl);

    # If your backend server does not set the right caching headers for static assets,
    # you can set them below (uncomment first and change 604800 - which 1 week - to whatever you
    # want (in seconds)
    #if (bereq.url ~ "\.(ico|jpg|jpeg|gif|png|bmp|webp|tiff|svg|svgz|pdf|mp3|flac|ogg|mid|midi|wav|mp4|webm|mkv|ogv|wmv|eot|otf|woff|ttf|rss|atom|zip|7z|tgz|gz|rar|bz2|tar|exe|doc|docx|xls|xlsx|ppt|pptx|rtf|odt|ods|odp)(\?[a-zA-Z0-9=]+)$") {
    #    set beresp.http.Cache-Control = "public, max-age=604800";
    #}

    if (bereq.url ~ "^[^?]*\.(7z|avi|bmp|bz2|css|csv|doc|docx|eot|flac|flv|gif|gz|ico|jpeg|jpg|js|less|mka|mkv|mov|mp3|mp4|mpeg|mpg|odt|ogg|ogm|opus|otf|pdf|png|ppt|pptx|rar|rtf|svg|svgz|swf|tar|tbz|tgz|ttf|txt|txz|wav|webm|webp|woff|woff2|xls|xlsx|xml|xz|zip)(\?.*)?$") {
        unset beresp.http.set-cookie;
        set beresp.do_stream = true;
    }

    # We have content to cache, but it's got no-cache or other Cache-Control values sent
    # So let's reset it to our main caching time (180s as used in this example configuration)
    # The additional parameters specified (stale-while-revalidate & stale-if-error) are used
    # by modern browsers to better control caching. Set these to twice & four times your main
    # cache time respectively.
    # This final setting will normalize cache-control headers for CMSs like Joomla
    # which set max-age=0 even when the CMS' cache is enabled.
    if (beresp.http.Cache-Control !~ "max-age" || beresp.http.Cache-Control ~ "max-age=0") {
        set beresp.http.Cache-Control = "public, max-age=180, stale-while-revalidate=360, stale-if-error=43200";
    }

    # Optionally set a larger TTL for pages with less than 180s of cache TTL
    #if (beresp.ttl < 180s) {
    #    set beresp.http.Cache-Control = "public, max-age=180, stale-while-revalidate=360, stale-if-error=43200";
    #}

    return (deliver);

}

sub vcl_deliver {

    /*
    # === The following are disabled by default - enable if you understand what you're doing ===
    # Send a special header for excluded domains/subdomains only
    # The if statement can be identical to the ones in the vcl_recv() and vcl_backend_response() functions above
    if (req.http.host ~ "(domain1.tld|sub.domain2.tld)") {
        set resp.http.X-Domain-Status = "EXCLUDED";
    }

    # Enforce redirect to HTTPS for specified domains/subdomains only
    if (
        req.http.host ~ "(domain3.tld|sub.domain4.tld)" &&
        req.http.X-Forwarded-Proto !~ "(?i)https"
    ) {
        set resp.http.Location = "https://" + req.http.host + req.url;
        set resp.status = 301;
    }
    */

    # Send special headers that indicate the cache status of each web page
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }

    return (deliver);

}
