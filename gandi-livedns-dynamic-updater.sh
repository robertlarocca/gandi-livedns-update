#!/bin/bash

# Copyright (c) 2018 Robert LaRocca

record="www"
domain="example.com"
fulldomain=$record.$domain

# Get your API key
# https://doc.livedns.gandi.net/#id5
apikey="0FsZpAx9n0kEuQsqt4Ar5EWcqX"
secret=$(cat /etc/gandi-livedns.secret)
authToken=$secret

inetAgent="http://me.gandi.net"
inet_addr=$(curl -s4 $inetAgent)
inet6_addr=$(curl -s6 $inetAgent)
inet_prev=$(dig A +short $fulldomain)
inet6_prev=$(dig AAAA +short $fulldomain)

if [[ $(id -u) != 0 ]]; then
    printf "$0: Error root privilege is needed!\n"
    exit 1
fi

error_check()
{
if [[ -z $inet_addr ]] && [[ -z $inet6_addr ]]; then
    printf "$0: Error couldn't resolve: $inetAgent\n"
    exit 1
fi
};

update_inet_addr()
{
local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet_addr'"]}'
local livedns="https://dns.api.gandi.net/api/v5"

if [[ -n $inet_addr ]]; then
    if [[ $inet_addr == $inet_prev ]]; then
        printf "$0: Not updating A record.\n"
    else
        curl -XPUT -d "$objects" \
        -H "X-Api-Key: $authToken" \
        -H "Content-Type: application/json" \
        "$livedns/domains/$domain/records/$record/A" \
        > /dev/null 2>&1
        printf "$0: Updating A record with $inet_addr\n"
    fi
fi
};

update_inet6_addr()
{
local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet6_addr'"]}'
local livedns="https://dns.api.gandi.net/api/v5"

if [[ -n $inet6_addr ]]; then
    if [[ $inet6_addr == $inet6_prev ]]; then
        printf "$0: Not updating AAAA record.\n"
    else
        curl -XPUT -d "$objects" \
        -H "X-Api-Key: $authToken" \
        -H "Content-Type: application/json" \
        "$livedns/domains/$domain/records/$record/AAAA" \
        > /dev/null 2>&1
        printf "$0: Updating AAAA record with $inet6_addr\n"
    fi
fi
};

user_standard_input()
{
case $1 in
--4only)
    date -Iseconds
    error_check
    update_inet_addr
    echo # used for logging
    ;;
--6only)
    date -Iseconds
    error_check
    update_inet6_addr
    echo # used for logging
    ;;
--update|*)
    date -Iseconds
    error_check
    update_inet_addr
    update_inet6_addr
    echo # used for logging
    ;;
esac
};

user_standard_input $1

exit 0
