#!/bin/sh

# Copyright (c) 2018 Robert LaRocca

# Use of this source code is governed by an MIT-style license that can be
# found in the projects LICENSE file or https://www.laroccx.com/LICENSE.md

SCRIPTVERSION="0.4-devel"

# require root privileges
require_root_privileges() {
	if [[ "$UID" != "0" ]]; then
		logger -i "Error: $(basename "$0") must be run as root!"
		echo "Error: $(basename "$0") must be run as root!"
		exit 1
	fi
};

require_root_privileges

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
if [[ -e /etc/gandi-livedns.secret ]]; then
	source /etc/gandi-livedns.secret
	if [[ ! -z $secret ]]; then
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

# Used for logging
time_stamp=$(date +"%b %d %H:%M:%S")
host_name=$(hostname -f)
script_name=$(basename -s .sh $0)
rubber_stamp="$time_stamp $host_name $script_name"

resolve_check() {
if [[ -z $inet_addr ]] && [[ -z $inet6_addr ]]; then
	echo "$rubber_stamp: Error couldn't resolve: $resolver"
	exit 1
fi
};

update_inet_addr() {
local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet_addr'"]}'
local livedns="https://dns.api.gandi.net/api/v5"

if [[ -n $inet_addr ]]; then
	if [[ "$inet_addr" = "$inet_prev" ]]; then
		echo "$rubber_stamp: Not updating A record."
	else
		curl -XPUT -d "$objects" \
		-H "X-Api-Key: $auth_token" \
		-H "Content-Type: application/json" \
		"$livedns/domains/$domain/records/$record/A" \
		> /dev/null 2>&1
		echo "$rubber_stamp: Updating A record with $inet_addr"
	fi
fi
};

update_inet6_addr() {
local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet6_addr'"]}'
local livedns="https://dns.api.gandi.net/api/v5"

if [[ -n $inet6_addr ]]; then
	if [[ "$inet6_addr" = "$inet6_prev" ]]; then
		echo "$rubber_stamp: Not updating AAAA record."
	else
		curl -XPUT -d "$objects" \
		-H "X-Api-Key: $auth_token" \
		-H "Content-Type: application/json" \
		"$livedns/domains/$domain/records/$record/AAAA" \
		> /dev/null 2>&1
		echo "$rubber_stamp: Updating AAAA record with $inet6_addr"
	fi
fi
};

command_help() {
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
 $script_name --ipv4 mail
 $script_name --ipv6 www
 $script_name -l

Version:
$script_name, version $SCRIPTVERSION-$(uname)
Copyright (c) 2018 Robert LaRocca
Source <https://github.com/robertlarocca/gandi-livedns-dynamic-updater>
EOF
};

command_options() {
case $1 in
-6 | --ipv6)
	resolve_check
	update_inet6_addr
	;;
-4 | --ipv4)
	resolve_check
	update_inet_addr
	;;
-l | --list)
	echo "$rubber_stamp: IPv4 address $inet_addr"
	echo "$rubber_stamp: IPv6 address $inet6_addr"
	;;
-H | --help)
	command_help
	;;
-V | --version)
	echo "$script_name, version $SCRIPTVERSION-$(uname)"
	echo "Copyright (c) 2018-$(date +%Y) Robert LaRocca"
	;;
*)
	if [[ ! -z $1 ]]; then
		if [[ "-a = $1" ]] || [[ "--all = $1" ]]; then
			resolve_check
			update_inet_addr
			update_inet6_addr
		else
		echo "$script_name: unrecognized option '$1'"
			command_help
		fi
	else
		resolve_check
		update_inet_addr
		update_inet6_addr
	fi
	;;
esac
};

command_options $1

exit 0
