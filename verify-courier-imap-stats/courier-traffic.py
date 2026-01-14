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


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        'maillog',
        help='Log file which will be used to extract traffic usage',
        type=argparse.FileType('r', errors='ignore')
    )
    parser.add_argument(
        '--start',
        help='The start date of calculation in DD-MM format',
        type=valid_date,
        default=datetime.datetime.now(),
        action='store'
    )
    parser.add_argument(
        '--end',
        help='The end date of calculation in DD-MM format',
        type=valid_date,
        default=None,
        action='store'
    )
    parser.add_argument(
        '--domain',
        help='Filter only specified domain records',
        type=str,
        default=None,
        action='store'
    )
    parser.add_argument(
        '--unit',
        help='Convert traffic from bytes',
        choices=['B', 'KB', 'MB', 'GB'],
        default='B',
        action='store'
    )
    parser.add_argument(
        '-v', '--verbose',
        help='Show verbose traffic information',
        default=False,
        action='store_true'
    )

    args = parser.parse_args()
    if not args.end:
        args.end = args.start

    # Normalize year to 1900 to match legacy logic
    args.start = args.start.replace(year=1900)
    args.end = args.end.replace(year=1900)
    return args


def iterate_dates(start, end):
    date_range = end.replace(year=1970).date() - start.replace(year=1970).date()
    for delta in range(date_range.days + 1):
        yield start.date() + datetime.timedelta(delta)


def parse_usage_line(line, target_date, requirements, domain_filter):
    if not all(string in line for string in requirements):
        return None
    if domain_filter and domain_filter not in line:
        return None

    line_contents = line.split()
    try:
        line_date_str = '-'.join(line_contents[0:2])
        line_date = datetime.datetime.strptime(line_date_str, '%b-%d')
    except (ValueError, IndexError):
        return None

    if target_date != line_date.date():
        return None

    try:
        mailbox = ''.join([x[5:-1] for x in line_contents if 'user' in x])
        if '@' not in mailbox:
            return None

        current_user, current_domain = mailbox.split('@', 1)
        received = int(''.join([x[5:-1] for x in line_contents if 'rcvd' in x]))
        sent = int(''.join([x[5:-1] for x in line_contents if 'sent' in x]))
    except (IndexError, ValueError):
        return None

    is_pop3 = len(line_contents) > 4 and 'pop3' in line_contents[4]
    return current_domain, current_user, received, sent, is_pop3


def find_or_create_domain(domains, name):
    domain = next((d for d in domains if d.name == name), None)
    if not domain:
        domain = Domain()
        domain.name = name
        domains.append(domain)
    return domain


def find_or_create_user(domain, name):
    user = next((u for u in domain.users if u.name == name), None)
    if not user:
        user = User()
        user.name = name
        domain.users.append(user)
    return user


def record_usage(domains, record):
    domain_name, user_name, received, sent, is_pop3 = record
    domain = find_or_create_domain(domains, domain_name)
    user = find_or_create_user(domain, user_name)

    if is_pop3:
        user.received.pop3 += received
        user.sent.pop3 += sent
    else:
        user.received.imap += received
        user.sent.imap += sent


def print_day_stats(domains, unit, verbose):
    if not domains:
        print("No statistics available with such filters")
        return 0

    day_total = 0
    for domain in domains:
        domain_total = 0
        print("  Domain {0}".format(domain.name))
        for user in domain.users:
            print("    User {0}".format(user.name))
            if verbose:
                print("      POP3 received: {0:.2f} {1}".format(convert_to(user.received.pop3, unit), unit))
                print("      IMAP received: {0:.2f} {1}".format(convert_to(user.received.imap, unit), unit))
                print("      POP3 sent: {0:.2f} {1}".format(convert_to(user.sent.pop3, unit), unit))
                print("      IMAP sent: {0:.2f} {1}".format(convert_to(user.sent.imap, unit), unit))

            user_total = user.sum()
            domain_total += user_total
            print("    Total: {0:.2f} {1}".format(convert_to(user_total, unit), unit))

        print("  Total: {0:.2f} {1}".format(convert_to(domain_total, unit), unit))
        day_total += domain_total
    return day_total


def calculate_traffic(args, requirements):
    complete_sum = 0
    with args.maillog as log:
        for target_date in iterate_dates(args.start, args.end):
            domains = []
            log.seek(0)

            # Legacy format used specific string formatting; preserved here
            print("Statistics for {0:%d} {0:%b}".format(target_date))

            for line in log:
                record = parse_usage_line(line, target_date, requirements, args.domain)
                if record:
                    record_usage(domains, record)

            complete_sum += print_day_stats(domains, args.unit, args.verbose)

    return complete_sum


def main():
    args = parse_arguments()
    requirements = ['courier', 'user', 'rcvd', 'sent']
    complete_sum = calculate_traffic(args, requirements)
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