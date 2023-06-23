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
script_version='2.5.3'
script_release='beta'  # options devel, beta, release, stable

# Uncomment to enable bash xtrace mode.
set -xv

# ----- Required global variables ----- #

record="$2"
domain="$3"
fulldomain="$record.$domain"

log_prefix="$(date +"%b %d %H:%M:%S") $HOSTNAME ->"

# ----- Required global variables ----- #

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
	[stdin] or configured as variables along with other settings in the
	default /etc/gandi-livedns-update.conf configuration file.

	Options:
	 -a, all        update the IPv4 and IPv6 addresses
	 -4, ipv4       update only the IPv4 address
	 -6, ipv6       update only the IPv6 address

	 version        show version information
	 help           how this help message

	Examples:
	 gandi-livedns-update all bot example.com
	 gandi-livedns-update -4 chat example.com
	 gandi-livedns-update ipv4 stun example.com
	 gandi-livedns-update -6 voip example.com
	 gandi-livedns-update ipv6 www example.com

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

check_config() {
	if [[ -f "/etc/gandi-livedns-update.conf" ]]; then
		source /etc/gandi-livedns-update.conf
	else
		cat <<-"EOF_XYZ" > /etc/gandi-livedns-update.conf
		# /etc/gandi-livedns-update.conf

		# Manage your API authentication key using the
		# Gandi.net dashboard at https://account.gandi.net

		# Uncomment to add credentials for the Gandi LiveDNS API:
		# apikey="EXAMPLE000zg5MiEyzQ1Nj"

		# Manage your domain records using the Gandi.net
		# dashboard at https://admin.gandi.net/domain

		# Setting domain and record here will override the commadline:
		# domain="example.com"
		# record="www"

		# Service used to reverse lookup current IP addresses:
		bootstrap_lookup="ifconfig.co"

		# Bootstrap DNS servers are used to resolve the lookup service address:
		bootstrap_dns="1.1.1.1"
		bootstrap_dns6="2606:4700:4700::1111"

		EOF_XYZ

		chown root:root /etc/gandi-livedns-update.conf
		chmod 0600 /etc/gandi-livedns-update.conf
	fi

	if [[ -z "$apikey" ]]; then
		echo "$log_prefix Failed to set object: apikey" 2>&1
		exit 2
	elif [[ -z "$domain" ]]; then
		echo "$log_prefix Failed to set object: domain" 2>&1
		exit 2
	elif [[ -z "$record" ]]; then
		echo "$log_prefix Failed to set object: record" 2>&1
		exit 2
	fi
}

check_lookup() {
	ipv4_address=$(curl --ssl-reqd -s4 "$bootstrap_lookup")
	ipv6_address=$(curl --ssl-reqd -s6 "$bootstrap_lookup")

	if [[ -z "$ipv4_address" ]] && [[ -z "$ipv6_address" ]]; then
		echo "$log_prefix Failed to resolve: $bootstrap_lookup" 2>&1
		exit 2
	fi
}

# Used to check if IPv4 and IPv6 should be force updated!
force="$*"

update_ipv4_address() {
	if [[ "$force" =~ "--force" ]]; then
		ipv4_previous="force-update"
	else
		ipv4_previous=$(dig @"$bootstrap_dns" A +short "$fulldomain")
	fi

	local objects="{\"rrset_values\":[\"$ipv4_address\"],\"rrset_ttl\":600}"
	local livedns="https://api.gandi.net/v5/livedns"

	if [[ -n "$ipv4_address" ]]; then
		if [[ "$ipv4_address" = "$ipv4_previous" ]]; then
			echo "$log_prefix Not updating $fulldomain A record"
		else
			curl -X PUT \
				"$livedns/domains/$domain/records/$record/A" \
				-H "authorization: Apikey $apikey" \
				-H "content-type: application/json" \
				-d "$objects" > /dev/null 2>&1

			echo "$log_prefix Updating $fulldomain A record to $ipv4_address"
		fi
	fi
}

update_ipv6_address() {
	if [[ "$force" =~ "--force" ]]; then
		ipv6_previous="force-update"
	else
		ipv6_previous=$(dig @"$bootstrap_dns6" AAAA +short "$fulldomain")
	fi

	local objects="{\"rrset_values\":[\"$ipv6_address\"],\"rrset_ttl\":600}"
	local livedns="https://api.gandi.net/v5/livedns"

	if [[ -n "$ipv6_address" ]]; then
		if [[ "$ipv6_address" = "$ipv6_previous" ]]; then
			echo "$log_prefix Not updating $fulldomain AAAA record"
		else
			curl -X PUT \
				"$livedns/domains/$domain/records/$record/AAAA" \
				-H "authorization: Apikey $apikey" \
				-H "content-type: application/json" \
				-d "$objects" > /dev/null 2>&1

			echo "$log_prefix Updating $fulldomain AAAA record to $ipv6_address"
		fi
	fi
}

check_binary_exists curl
check_binary_exists dig

# Options
case "$1" in
all | -a)
	check_config
	check_lookup
	update_ipv4_address
	update_ipv6_address
	;;
inet | inet4 | ipv4 | -4)
	check_config
	check_lookup
	update_ipv4_address
	;;
inet6 | ipv6 | -6)
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
	# Default
	if [[ -z "$1" ]]; then
		check_config
		check_lookup
		update_ipv4_address
		update_ipv6_address
	else
		error_unrecognized_option "$*"
	fi
	;;
esac

unset "$apikey" 2> /dev/null
exit 0

# vi: syntax=sh ts=2 noexpandtab
