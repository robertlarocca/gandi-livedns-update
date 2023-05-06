#!/bin/sh

# Copyright (c) 2023 Robert LaRocca https://www.laroccx.com

# Update Gandi LiveDNS with the current dynamically assigned IP addresses.

# Packages must be installed when using a OpenWrt based distro:
#   opkg update
#   opkg install bind-dig ca-bundle curl openssl-util
#
# Packages must be installed when using a Debian based distro:
#   apt update
#   apt install curl

# Script version and release
script_version='2.3.2'
script_release='beta'  # options devel, beta, release, stable

require_root_privileges() {
	if [[ "$(whoami)" != "root" ]]; then
		# logger -i "Error: gandi-livedns-update must be run as root!"
		echo "Error: gandi-livedns-update must be run as root!" 2>&1
		exit 2
	fi
}

require_user_privileges() {
	if [[ "$(whoami)" == "root" ]]; then
		# logger -i "Error: gandi-livedns-update must be run as normal user!"
		echo "Error: gandi-livedns-update must be run as normal user!" 2>&1
		exit 2
	fi
}

show_help_message() {
	cat <<-EOF_XYZ
	Usage: gandi-livedns-update [OPTION] [RECORD] [DOMAIN]...
	Update Gandi LiveDNS with the current host IPv4 and IPv6 addresses.

	The domain name and record to update may be specified as standard input
	[stdin] or configured as variables along with other script settings in
	the configuration file: /etc/gandi-livedns-update.conf

	Options:
	 -a, all	update the IPv4 and IPv6 addresses
	 -4, ipv4	update only the IPv4 address
	 -6, ipv6	update only the IPv6 address

	 version	show version information
	 help		how this help message

	Examples:
	 gandi-livedns-update all
	 gandi-livedns-update all git example.com
	 gandi-livedns-update -4 mail example.com
	 gandi-livedns-update inet mail example.com
	 gandi-livedns-update -6 voip example.com
	 gandi-livedns-update list

	Exit status:
	 0 - ok
	 1 - minor issue
	 2 - serious error

	Copyright (c) $(date +%Y) Robert LaRocca, https://www.laroccx.com
	License: The MIT License (MIT)
	Source: https://github.com/robertlarocca/gandi-livedns-update
	EOF_XYZ
}

show_version_information() {
	cat <<-EOF_XYZ
	gandi-livedns-update $script_version-$script_release
	Copyright (c) $(date +%Y) Robert LaRocca, https://www.laroccx.com
	License: The MIT License (MIT)
	Source: https://github.com/robertlarocca/gandi-livedns-update
	EOF_XYZ
}

check_binary_exists() {
	local binary_command="$1"
	if [[ ! -x "$(which $binary_command)" ]]; then
		if [[ -x "/lib/command-not-found" ]]; then
		/lib/command-not-found "$binary_command"
		else
		cat <<-EOF_XYZ >&2
		Command '$binary_command' not found, but might be installed with:
		apt install "$binary_command"   # or
		dnf install "$binary_command"   # or
		opkg install "$binary_command"  # or
		snap install "$binary_command"  # or
		yum install "$binary_command"
		See your Linux documentation for which 'package manager' to use.
		EOF_XYZ
		fi
		exit 1
	fi
}

error_unrecognized_option() {
	cat <<-EOF_XYZ 2>&1
	gandi-livedns-update: unrecognized option '$1'
	Try 'gandi-livedns-update --help' for more information.
	EOF_XYZ
	exit 2
}

# ----- Required global variables ----- #

record="$2"
domain="$3"
fulldomain="$record.$domain"

# DNS
bootstrap_dns="1.1.1.1"
bootstrap_dns6="2606:4700:4700::1111"
lookup="ifconfig.co"

# IPv4
ipv4_address=$(curl --ssl-reqd -s4 "$lookup")
ipv4_previous=$(dig @"$bootstrap_dns" A +short "$fulldomain")

# IPv6
ipv6_address=$(curl --ssl-reqd -s6 "$lookup")
ipv6_previous=$(dig @"$bootstrap_dns6" AAAA +short "$fulldomain")

# Logging
log_prefix="$(date +"%b %d %H:%M:%S") $HOSTNAME ->"

# ----- Required global variables ----- #

check_config() {
	if [[ -f /etc/gandi-livedns-update.conf ]]; then
		source /etc/gandi-livedns-update.conf
		if [[ -z $apikey ]]; then
			echo "$log_prefix Failed to set credentials: apikey" 2>&1
			exit 2
		elif [[ -z $record ]]; then
			echo "$log_prefix Failed to set record." 2>&1
		elif [[ -z $domain ]]; then
			echo "$log_prefix Failed to set domain." 2>&1
		fi
	else
		cat <<-"EOF_XYZ" > /etc/gandi-livedns-update.conf
		# /etc/gandi-livedns-update.conf

		# Manage your API authentication key using the
		# Gandi.net dashboard at https://account.gandi.net

		# Your credentials for authenticating with Gandi LiveDNS:
		# apikey="EXAMPLE0000zg5MiEyMzQ1Nj"

		# Manage your domain records using the Gandi.net
		# dashboard at https://admin.gandi.net/domain

		# Setting domain and record here will override the commadline:
		# domain="example.com"
		# record="www"

		# Lookup services are used to reverse lookup your current IP addresses:
		lookup="ifconfig.co"

		# Bootstrap DNS servers are used to resolve the lookup service address:
		bootstrap_dns="1.1.1.1"
		bootstrap_dns6="2606:4700:4700::1111"

		EOF_XYZ

		chown root:root /etc/gandi-livedns-update.*
		chmod 0600 /etc/gandi-livedns-update.*
	fi
}

check_lookup() {
	if [[ -z $ipv4_address ]] && [[ -z $ipv6_address ]]; then
		echo "$log_prefix Failed to resolve: $lookup" 2>&1
		exit 2
	fi
}

update_ipv4_address() {
	local objects="{'rrset_ttl': 600,'rrset_values': ['$ipv4_address']}"
	local livedns="https://dns.api.gandi.net/api/v5"

	if [[ -n $ipv4_address ]]; then
		if [[ "$ipv4_address" = "$ipv4_previous" ]]; then
			echo "$log_prefix Not updating $fulldomain A record"
		else
			curl \
				-XPUT \
				-d "$objects" \
				-H "X-Api-Key: $apikey" \
				-H "Content-Type: application/json" \
				"$livedns/domains/$domain/records/$record/A" \
				> /dev/null 2>&1
			echo "$log_prefix Updating $fulldomain A record to $ipv4_address"
		fi
	fi
}

update_ipv6_address() {
	local objects="{'rrset_ttl': 600,'rrset_values': ['$ipv6_address']}"
	local livedns="https://dns.api.gandi.net/api/v5"

	if [[ -n $ipv6_address ]]; then
		if [[ "$ipv6_address" = "$ipv6_previous" ]]; then
			echo "$log_prefix Not updating $fulldomain AAAA record"
		else
			curl \
				-XPUT \
				-d "$objects" \
				-H "X-Api-Key: $apikey" \
				-H "Content-Type: application/json" \
				"$livedns/domains/$domain/records/$record/AAAA" \
				> /dev/null 2>&1
			echo "$log_prefix Updating $fulldomain AAAA record to $ipv6_address"
		fi
	fi
}

check_binary_exists curl
check_binary_exists dig

# Options
case $1 in
all | -a)
	check_config
	check_lookup
	update_ipv4_address
	update_ipv6_address
	;;
inet | inet4 | -4)
	check_config
	check_lookup
	update_ipv4_address
	;;
inet6 | -6)
	check_config
	check_lookup
	update_ipv6_address
	;;
version)
	show_version_information
	;;
help | --help)
	show_help_message
	;;
*)
	if [[ -z $1 ]]; then
		check_config
		check_lookup
		update_ipv4_address
		update_ipv6_address
	else
		error_unrecognized_option "$1"
	fi
	;;
esac

unset $apikey 2> /dev/null
exit 0

# vi: syntax=sh ts=2 noexpandtab
