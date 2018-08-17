#!/bin/sh

# Copyright (c) 2018 Robert LaRocca

# Use of this source code is governed by an MIT-style license that can be
# found in the projects LICENSE file or https://www.laroccx.io/LICENSE.md

SCRIPTVERSION="0.3.5-devel"
SCRIPTNAME=$(basename -s .sh $0)

# Add your DNS record and domain name
# https://www.gandi.net/domain
#
record="www"
domain="example.com"
fulldomain=$record.$domain

# Add your Gandi API authentication token
# https://account.gandi.net
#
apikey="0FsZpAx9n0kEuQsqt4Ar5EWc"
# The /etc/gandi-livedns.secret file take precedence
#
if [ -e /etc/gandi-livedns.secret ]; then
	secret=$(cat /etc/gandi-livedns.secret)
	if [ ! -z $secret ]; then
		authToken=$secret
	else
		authToken=$apikey
	fi
fi

# Packages must be installed when using OpenWrt based distros
#	$ opkg install curl bind-dig openssl-util ca-bundle
#
# The curl package also needs to be installed when using Ubuntu
#	$ apt-get update && apt-get --yes install curl
#
resolver="http://me.gandi.net"
inet_addr=$(curl -s4 $resolver)
inet6_addr=$(curl -s6 $resolver)
inet_prev=$(dig A +short $fulldomain)
inet6_prev=$(dig AAAA +short $fulldomain)

# Needed for logging
#
datelog=$(date +"%b %d %H:%M:%S")
hostnamelog=$(hostname -f)

root_check()
{
if [ $(id -u) != 0 ]; then
	printf "$datelog $hostnamelog $SCRIPTNAME: Error root privilege is needed!\n"
	exit 1
fi
}

resolve_check()
{
if [ -z $inet_addr ] && [ -z $inet6_addr ]; then
	printf "$datelog $hostnamelog $SCRIPTNAME: Error couldn't resolve: $resolver\n"
	exit 1
fi
};

update_inet_addr()
{
local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet_addr'"]}'
local livedns="https://dns.api.gandi.net/api/v5"

if [ -n $inet_addr ]; then
	if [ "$inet_addr == $inet_prev" ]; then
		printf "$datelog $hostnamelog $SCRIPTNAME: Not updating A record.\n"
	else
		curl -XPUT -d "$objects" \
		-H "X-Api-Key: $authToken" \
		-H "Content-Type: application/json" \
		"$livedns/domains/$domain/records/$record/A" \
		> /dev/null 2>&1
		printf "$datelog $hostnamelog $SCRIPTNAME: Updating A record with $inet_addr\n"
	fi
fi
};

update_inet6_addr()
{
local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet6_addr'"]}'
local livedns="https://dns.api.gandi.net/api/v5"

if [ -n $inet6_addr ]; then
	if [ "$inet6_addr == $inet6_prev" ]; then
		printf "$datelog $hostnamelog $SCRIPTNAME: Not updating AAAA record.\n"
	else
		curl -XPUT -d "$objects" \
		-H "X-Api-Key: $authToken" \
		-H "Content-Type: application/json" \
		"$livedns/domains/$domain/records/$record/AAAA" \
		> /dev/null 2>&1
		printf "$datelog $hostnamelog $SCRIPTNAME: Updating AAAA record with $inet6_addr\n"
	fi
fi
};

command_help()
{
cat <<EOF
Usage:	$SCRIPTNAME [-a46l] [--help] [--version] HOSTNAME

Update LiveDNS using this machines current IP address. The HOSTNAME option
may be specified using standard input, although most options are configured by
editing /etc/$SCRIPTNAME.secret and /etc/$SCRIPTNAME.conf files.

  -a, --all	update both IPv4 and IPv6 external network addresses
  -4, --four	update only the IPv4 address
  -6, --six	update only the IPv6 address
  -l, --list	list current IP addresses and exit
  --help	print	command usage and exit
  --version	print version and copyright information

Examples:
  $SCRIPTNAME -a git
  $SCRIPTNAME --four mail
  $SCRIPTNAME --six www
  $SCRIPTNAME -l
  
Source:
$SCRIPTNAME, version $SCRIPTVERSION-$(uname)
Copyright (c) 2018 Robert LaRocca
Source <https://github.com/robertlarocca/gandi-livedns-dynamic-updater>
EOF
};

command_options()
{
case $1 in
-h|--help)
	command_help
	;;
-V)
	printf "$SCRIPTNAME, version $SCRIPTVERSION-$(uname)\n"
	printf "Copyright (c) 2018 Robert LaRocca\n"
	;;
-6)
	root_check
	resolve_check
	update_inet6_addr
	;;
-4)
	root_check
	resolve_check
	update_inet_addr
	;;
-l)
	printf "$datelog $hostnamelog $SCRIPTNAME: IPv4 address $inet_addr\n"
	printf "$datelog $hostnamelog $SCRIPTNAME: IPv6 address $inet6_addr\n"
	;;
-u|*)
	if [ ! -z $1 ]; then
		if [ "-u == $1" ]; then
			root_check
			resolve_check
			update_inet_addr
			update_inet6_addr
		else
		printf "$SCRIPTNAME: unrecognized option '$1'\n"
			command_help
		fi
	else
		root_check
		resolve_check
		update_inet_addr
		update_inet6_addr
	fi
	;;
esac
};

command_options $1
exit 0

