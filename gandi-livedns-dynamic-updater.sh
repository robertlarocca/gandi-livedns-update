#!/bin/sh

# Copyright (c) 2023 Robert LaRocca https://www.laroccx.com

# Update Gandi LiveDNS with the current IPv4 and IPv6 addresses.

# Packages must be installed when using a OpenWrt based distro:
#   opkg update
#   opkg install bind-dig ca-bundle curl openssl-util
#
# Packages must be installed when using a Debian based distro:
#   apt update
#   apt install curl

# Script version and release
script_version='2.1.0'
script_release='devel'  # options devel, beta, release, stable

require_root_privileges() {
	if [[ "$USER" != "root" ]]; then
		if [[ -x "$(which logger)" ]]; then
			logger -i "Error: gandi-livedns must be run as root!"
		fi
		echo "Error: gandi-livedns must be run as root!" >&2
		exit 2
	fi
}

show_help_message() {
	cat <<-EOF_XYZ
	Usage: gandi-livedns [OPTION] [RECORD] [DOMAIN]...
	Update Gandi LiveDNS with the current host IPv4 and IPv6 addresses.

	The domain name and record to update may be specified as standard input
	[stdin] or configured as variables along with other script settings in
	the configuration file: /etc/gandi-livedns.conf

	Options:
	 all - update the IPv4 and IPv6 address
	 inet - update only the IPv4 address
	 inet6 - update only the IPv6 address

	 list - show the current IPv4 and IPv6 addresses

	 version - show version information
	 help - show this help message

	Examples:
	 gandi-livedns all
	 gandi-livedns all git example.com
	 gandi-livedns inet mail example.com
	 gandi-livedns inet6 voip example.com
	 gandi-livedns list

	Exit status:
	 0 - ok
	 1 - minor issue
	 2 - serious error

	Copyright (c) $(date +%Y) Robert LaRocca, https://www.laroccx.com
	License: The MIT License (MIT)
	Source: https://github.com/robertlarocca/gandi-livedns-dynamic-updater
	EOF_XYZ
}

show_version_information() {
	cat <<-EOF_XYZ
	gandi-livedns $script_version-$script_release
	Copyright (c) $(date +%Y) Robert LaRocca, https://www.laroccx.com
	License: The MIT License (MIT)
	Source: https://github.com/robertlarocca/gandi-livedns-dynamic-updater
	EOF_XYZ
}

error_unrecognized_option() {
	cat <<-EOF_XYZ
	gandi-livedns: unrecognized option '$1'
	Try 'gandi-livedns --help' for more information.
	EOF_XYZ
	exit 2
}

# --- Required global variables --- #

domain="$3"
record="$2"
fulldomain="$record.$domain"

# DNS
bootstrap_dns="1.1.1.1"
bootstrap_dns6="2606:4700:4700::1111"
lookup="ifconfig.co"

# IPv4
inet_addr=$(curl --ssl-reqd -s4 "$lookup")
inet_prev=$(dig @"$bootstrap_dns" A +short "$fulldomain")

# IPv6
inet6_addr=$(curl --ssl-reqd -s6 "$lookup")
inet6_prev=$(dig @"$bootstrap_dns6" AAAA +short "$fulldomain")

# Logging
log_prefix="$(date +"%b %d %H:%M:%S") $HOSTNAME ->"

# --- Required global variables --- #

if [[ -f /etc/gandi-livedns.conf ]]; then
	source /etc/gandi-livedns.conf
	if [[ -z $apikey ]]; then
		echo "$log_prefix Failed to set credentials: apikey" >&2
	elif [[ -z $domain ]]; then
		echo "$log_prefix Failed to set domain." >&2
	elif [[ -z $record ]]; then
		echo "$log_prefix Failed to set record." >&2
	fi
	exit 2
else
	cat <<-EOF_XYZ > /etc/gandi-livedns.conf
	# /etc/gandi-livedns.conf

	# Manage your API authentication key using the
	# Gandi.net dashboard: https://account.gandi.net

	# Your credentials for authenticating with Gandi LiveDNS.
	; apikey="EXAMPLE0000zg5MiEyMzQ1Nj"

	# Manage your domain records using the Gandi.net
	# dashboard: https://admin.gandi.net/domain

	# Setting domain and record here will override passing from commadline.
	; domain="example.com"
	; record="www"

	# Lookup services are used to reverse lookup your current IP addresses.
	lookup="ifconfig.co"

	# Bootstrap DNS servers are used to resolve the lookup service addresses.
	bootstrap_dns="1.1.1.1"
	bootstrap_dns6="2606:4700:4700::1111"

	EOF_XYZ

	chown root:root /etc/gandi-livedns.conf
	chmod 0640 /etc/gandi-livedns.conf
fi

resolve_check() {
	if {[ -z $inet_addr ]} && [[ -z $inet6_addr ]]; then
		echo "$log_prefix Failed to resolve: $lookup" >&2
		exit 2
	fi
}

update_inet_addr() {
	local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet_addr'"]}'
	local livedns="https://dns.api.gandi.net/api/v5"

	if [[ -n $inet_addr ]]; then
		if [[ "$inet_addr" = "$inet_prev" ]]; then
			echo "$log_prefix Not updating $fulldomain A record"
		else
			curl -XPUT -d "$objects" \
				-H "X-Api-Key: $apikey" \
				-H "Content-Type: application/json" \
				"$livedns/domains/$domain/records/$record/A" \
				> /dev/null 2>&1
			echo "$log_prefix Updating $fulldomain A record to $inet_addr"
		fi
	fi
}

update_inet6_addr() {
	local objects='{"rrset_ttl": 600,"rrset_values": ["'$inet6_addr'"]}'
	local livedns="https://dns.api.gandi.net/api/v5"

	if [[ -n $inet6_addr ]]; then
		if [[ "$inet6_addr" = "$inet6_prev" ]]; then
			echo "$log_prefix Not updating $fulldomain AAAA record"
		else
			curl -XPUT -d "$objects" \
				-H "X-Api-Key: $apikey" \
				-H "Content-Type: application/json" \
				"$livedns/domains/$domain/records/$record/AAAA" \
				> /dev/null 2>&1
			echo "$log_prefix Updating $fulldomain AAAA record to $inet6_addr"
		fi
	fi
}

show_fulldomain_information(){
	if [[ -n "$fulldomain" ]]; then
		echo "$fulldomain"
		echo "  ^"
		echo "  |"
	elif [[ -n "$inet_prev" ]]; then
		echo "$inet_prev"
	elif [[ -n "$inet6_prev" ]]; then
		echo $inet6_prev
	fi
}

show_extra_information(){
	if [[ -n "$fulldomain" ]]; then
		nslookup "$fulldomain" "$bootstrap_dns"
	elif [[ -n "$fulldomain" ]]; then
		curl --ssl-reqd -s4 "$lookup"/json
		echo
	fi
}

# Options
case $1 in
all)
	resolve_check
	update_inet_addr
	update_inet6_addr
	;;
inet)
	resolve_check
	update_inet_addr
	;;
inet6)
	resolve_check
	update_inet6_addr
	;;
list)
	show_fulldomain_information
	;;
extra)
	# Not a documented option or even shown in help message.
	show_nslookup_information
	;;
version)
	show_version_information
	;;
help | --help)
	show_help_message
	;;
*)
	if [[ -z $1 ]]; then
		resolve_check
		update_inet_addr
		update_inet6_addr
	else
		error_unrecognized_option "$1"
	fi
	;;
esac

unset $apikey 2> /dev/null
exit 0

# vi: syntax=sh ts=2 noexpandtab
