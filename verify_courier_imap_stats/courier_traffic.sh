#!/usr/bin/env python3
### Copyright 1999-2026. WebPros International GmbH.

###############################################################################
# This script calculates traffic usage for Courier IMAP and POP3 from logs
# Requirements : python 3.x, argparse, datetime
# Version: 1.0
##########################################################################

import argparse
import datetime

class Recv:
    def __init__(self):
        self.pop3 = 0
        self.imap = 0

class Sent:
    def __init__(self):
        self.pop3 = 0
        self.imap = 0

class User:
    def __init__(self):
        self.name = ''
        self.received = Recv()
        self.sent = Sent()

    def sum(self):
        return (
            self.received.pop3 +
            self.received.imap +
            self.sent.pop3 +
            self.sent.imap
        )

class Domain:
    def __init__(self):
        self.name = ''
        self.users = []

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        'maillog',
        help = 'Log file which will be used to extract traffic usage',
        type = argparse.FileType('r', errors='ignore')
    )
    parser.add_argument(
        '--start',
        help = 'The start date of calculation in DD-MM format',
        type = valid_date,
        default = datetime.datetime.now(),
        action = 'store'
    )
    parser.add_argument(
        '--end',
        help = 'The end date of calculation in DD-MM format',
        type = valid_date,
        default = None,
        action = 'store'
    )
    parser.add_argument(
        '--domain',
        help = 'Filter only specified domain records',
        type = str,
        default = None,
        action = 'store'
    )
    parser.add_argument(
        '--unit',
        help = 'Convert traffic from bytes',
        choices = ['B', 'KB', 'MB', 'GB'],
        default = 'B',
        action = 'store'
    )
    parser.add_argument(
        '-v', '--verbose',
        help = 'Show verbose traffic information',
        default = False,
        action = 'store_true'
    )
    args = parser.parse_args()
    if not args.end:
        args.end = args.start
    
    # Normalize year to 1900 to match legacy logic
    args.start = args.start.replace(year = 1900)
    args.end = args.end.replace(year = 1900)

    requirements = ['courier', 'user', 'rcvd', 'sent']
    complete_sum = 0

    with args.maillog as log:
        # Calculate day difference using 1970 reference to avoid leap year/boundary issues
        date_range = args.end.replace(year = 1970).date() - args.start.replace(year = 1970).date()
        
        for delta in range(date_range.days + 1):
            domains = []
            log.seek(0)
            target_date = args.start.date() + datetime.timedelta(delta)
            
            # Legacy format used specific string formatting; preserved here
            print("Statistics for {0:%d} {0:%b}".format(target_date))
            
            for line in log:
                # 1. Filter Check
                if not all(string in line for string in requirements):
                    continue
                elif args.domain and args.domain not in line:
                    continue

                line_contents = line.split()
                
                # 2. Date Parsing
                try:
                    # Assumes Syslog format "Mon DD"
                    line_date_str = '-'.join(line_contents[0:2])
                    line_date = datetime.datetime.strptime(line_date_str, '%b-%d')
                except (ValueError, IndexError):
                    continue

                # Match date (ignoring year)
                if target_date != line_date.date():
                    continue

                # 3. Content Extraction (Preserving legacy slicing [5:-1])
                try:
                    mailbox = ''.join([x[5:-1] for x in line_contents if 'user' in x])
                    if '@' not in mailbox: continue
                    
                    current_user = mailbox.split('@')[0]
                    current_domain = mailbox.split('@')[1]
                    received = ''.join([x[5:-1] for x in line_contents if 'rcvd' in x])
                    sent = ''.join([x[5:-1] for x in line_contents if 'sent' in x])
                except (IndexError, ValueError):
                    continue

                # 4. Object Management
                domain = next((d for d in domains if d.name == current_domain), None)
                if not domain:
                    domain = Domain()
                    domain.name = current_domain
                    domains.append(domain)

                user = next((u for u in domain.users if u.name == current_user), None)
                if not user:
                    user = User()
                    user.name = current_user
                    domain.users.append(user)

                # 5. Accumulation
                # Matches legacy logic relying on index 4 for service name
                if len(line_contents) > 4 and 'pop3' in line_contents[4]:
                    user.received.pop3 += int(received)
                    user.sent.pop3 += int(sent)
                else:
                    user.received.imap += int(received)
                    user.sent.imap += int(sent)

            # 6. Output Generation
            if len(domains) > 0:
                for domain in domains:
                    domain_total = 0
                    print("  Domain {0}".format(domain.name))
                    for user in domain.users:
                        print("    User {0}".format(user.name))
                        if args.verbose:
                            print("      POP3 received: {0:.2f} {1}".format(convert_to(user.received.pop3, args.unit), args.unit))
                            print("      IMAP received: {0:.2f} {1}".format(convert_to(user.received.imap, args.unit), args.unit))
                            print("      POP3 sent: {0:.2f} {1}".format(convert_to(user.sent.pop3, args.unit), args.unit))
                            print("      IMAP sent: {0:.2f} {1}".format(convert_to(user.sent.imap, args.unit), args.unit))

                        user_total = user.sum()
                        domain_total += user_total
                        print("    Total: {0:.2f} {1}".format(convert_to(user_total, args.unit), args.unit))
                    
                    print("  Total: {0:.2f} {1}".format(convert_to(domain_total, args.unit), args.unit))
                    complete_sum += domain_total
            else:
                print("No statistics available with such filters")
                
    print("\nTotal: {0:.2f} {1}".format(convert_to(complete_sum, args.unit), args.unit))

def convert_to(traffic_bytes, unit):
    if unit == 'KB':
        return traffic_bytes / 1024
    elif unit == 'MB':
        return traffic_bytes / 1048576
    elif unit == 'GB':
        return traffic_bytes / 1073741824
    else:
        return traffic_bytes

def valid_date(date):
    try:
        return datetime.datetime.strptime(date, "%d-%m")
    except:
        raise argparse.ArgumentTypeError(
            "Not a valid date: '{0}'".format(date)
        )

if __name__ == "__main__":
    main()