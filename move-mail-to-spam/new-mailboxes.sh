#!/bin/bash
### Copyright 1999-2022. Plesk International GmbH.

###############################################################################
# This script helps to configure SpamAssassin to move spam messages to the Spam folder automatically
# Requirements : bash 3.x
# Version      : 1.0
#########

plesk bin spamassassin -u ${NEW_MAILNAME} -status true
plesk bin spamassassin -u ${NEW_MAILNAME} -action move
