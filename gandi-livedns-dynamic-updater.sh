#!/bin/sh

# Copyright (c) 2018 Robert LaRocca

# Use of this source code is governed by an MIT-style license that can be
# found in the projects LICENSE file or https://www.laroccx.io/LICENSE.md

SCRIPTVERSION="0.4-devel"

# Add your DNS record and domain name
# https://www.gandi.net/domain
#
record=$2					# www
domain="example.com"		# gandi.net
fulldomain=$record.$domain	# www.gandi.net

# Add your Gandi API authentication token
# https://account.gandi.net
#
apikey="Top-Secret-LiveDNS-API-Token"
# The /etc/gandi-livedns.secret file take precedence
#
if [ -e /etc/gandi-livedns.secret ]; then
	secret=$(cat /etc/gandi-livedns.secret)
	if [ ! -z $secret ]; then
		auth_token=$secret
	else
		auth_token=$apikey
	fi
fi

# Packages must be installed when using OpenWrt based distros
#	$ opkg install curl bind-dig openssl-util ca-bundle
#
# The curl package also needs to be installed when using Ubuntu
#	$ apt-get update && apt-get --yes install curl
#
resolver="ifconfig.co"
inet_addr=$(curl --ssl-reqd -s4 $resolver)
inet6_addr=$(curl --ssl-reqd -s6 $resolver)
inet_prev=$(dig A +short $fulldomain)
inet6_prev=$(dig AAAA +short $fulldomain)

# used for logging
#
time_stamp=$(date +"%b %d %H:%M:%S")
host_name=$(hostname -f)
script_name=$(basename -s .sh $0)
rubber_stamp="$time_stamp $host_name $script_name"

root_check()
{
if [ $(id -u) != 0 ]; then
	printf "$rubber_stamp: Error root privilege is needed!\n"
	exit 1
fi
}

resolve_check()
{
if [ -z $inet_addr ] && [ -z $inet6_addr ]; then
	printf "$rubber_stamp: Error couldn't resolve: $resolver\n"
	exit 1
fi
};

update_inet_addr()
{
local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet_addr'"]}'
local livedns="https://dns.api.gandi.net/api/v5"

if [ -n $inet_addr ]; then
	if [ "$inet_addr == $inet_prev" ]; then
		printf "$rubber_stamp: Not updating A record.\n"
	else
		curl -XPUT -d "$objects" \
		-H "X-Api-Key: $auth_token" \
		-H "Content-Type: application/json" \
		"$livedns/domains/$domain/records/$record/A" \
		> /dev/null 2>&1
		printf "$rubber_stamp: Updating A record with $inet_addr\n"
	fi
fi
};

update_inet6_addr()
{
local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet6_addr'"]}'
local livedns="https://dns.api.gandi.net/api/v5"

if [ -n $inet6_addr ]; then
	if [ "$inet6_addr == $inet6_prev" ]; then
		printf "$rubber_stamp: Not updating AAAA record.\n"
	else
		curl -XPUT -d "$objects" \
		-H "X-Api-Key: $auth_token" \
		-H "Content-Type: application/json" \
		"$livedns/domains/$domain/records/$record/AAAA" \
		> /dev/null 2>&1
		printf "$rubber_stamp: Updating AAAA record with $inet6_addr\n"
	fi
fi
};

command_help()
{
cat <<EOF
Usage:	$script_name [-a46l] HOSTNAME [--help] [--version]

Update LiveDNS using this machines current IP address. The HOSTNAME option
may be specified using standard input, although most options are configured by
editing /etc/$script_name.secret and /etc/$script_name.conf files.

  -a, --all	update both IPv4 and IPv6 external network addresses
  -4, --ipv4	update only the IPv4 address
  -6, --ipv6	update only the IPv6 address
  -l, --list	list current IP addresses and exit
  --help	print command usage and exit
  --version	print version and copyright information

Examples:
  $script_name -a git
  $script_name --four mail
  $script_name --six www
  $script_name -l
  
Version:
$script_name, version $SCRIPTVERSION-$(uname)
Copyright (c) 2018 Robert LaRocca
Source <https://github.com/robertlarocca/gandi-livedns-dynamic-updater>
EOF
};

command_options()
{
case $1 in
--help)
	command_help
	;;
--version)
	printf "$script_name, version $SCRIPTVERSION-$(uname)\n"
	printf "Copyright (c) 2018 Robert LaRocca\n"
	;;
-6|--six)
	root_check
	resolve_check
	update_inet6_addr
	;;
-4|--four)
	root_check
	resolve_check
	update_inet_addr
	;;
-l|--list)
	printf "$rubber_stamp: IPv4 address $inet_addr\n"
	printf "$rubber_stamp: IPv6 address $inet6_addr\n"
	;;
*)
	if [ ! -z $1 ]; then
		if [ "-a == $1" ] || [ "--all == $1" ]; then
			root_check
			resolve_check
			update_inet_addr
			update_inet6_addr
		else
		printf "$script_name: unrecognized option '$1'\n"
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

