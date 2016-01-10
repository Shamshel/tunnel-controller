#!/bin/bash

function help
{
	echo "$0: an openvpn tunnel controller"
	echo "$0 [-c config] <-p server> [options]"
	echo "This script must be run as super-user"
	echo "options:"
	echo ""
	echo "-h, --help	show brief help"
	echo "-s 'a srv.ovpn'	set default ovpn server"
#	echo "-b a,b	set backup opvn server(s)"
#	echo "-p a,b	set control program(s)"
	echo "-c	sourced config file"
#	echo "-e	ISP name (case insensitive)"
#	echo "-v	VPN name (case insensitive)"
	echo "-i	integrity check interval (s)"
#	echo "-l [1,2,3]	log level"
#	echo "-f	log file (defaults to syslog)"
	echo "-1 \"command\"	startup command"
	echo "-2 \"command\"	stop command"

	exit

}

#
# Traps ctrl_c interrupt
#
# Sets interrupt flag, to be used in monitor loop.
#
function ctrl_c
{
	echo ""
	echo "Caught interrupt, exiting..."
	interrupt=true
}

#
# Exits after function, if that function failed.
# 
# Parameters are function to be called, and its
# arguments.
#
# Returns 0 on success, exits with error otherwise.
function exit_on_fail
{
	"$@"

	if [ $? != 0 ]
	then
		exit 1
	fi

	return 0
}

#
# Retries function specified number of times.
#
# First parameter needs to be retry limit. Remaining parameters
# are the executed function and its parameters.
#
# Returns 0 on success, 1 otherwise
#
function retry_on_fail
{
	local retries=$1
	
	shift

	while [ $retries -gt 0 ]
	do
		"$@"

		if [ $? != 0 ]
		then
			(( retries-- ))
		else
			return 0
		fi
	done

	return 1
}

#
# Setup configuration file symlink.
#
# OpenVPN service looks for /etc/openvpn/login.conf on start.
#
# Takes one argument, the name of the config file to symlink.
# Returns 0 if successful, 1 upon error.
#
function setConfig
{
	if [ -L $openvpn_master_config_path ]
	then
		echo "Cleaning up old symlink."
		rm $openvpn_master_config_path
	fi

	if [ -e $openvpn_master_config_path ]
	then
		echo "Config file already exists!"
		echo "File $openvpn_master_config_path is not a symlink, exiting."
		return 1
	fi

	if [ ! -e "$openvpn_config_directory""$1" ]
	then
		echo "Config file "$1" does not exist."
		return -1
	fi

	ln -s "$openvpn_config_directory""$1" "$openvpn_master_config_path"

	return $?
}

#
# Starts OpenVPN tunnel and waits until IP changes
#
# Sets tunnel_ip to the ending value before returning.
#
# Takes one argument, the initial IP address.
#
# Returns 0 if tunnel setup is successful, 1 otherwise.
# OpenVPN dumps errors to /var/log/syslog, check there if this
# constantly fails.
#
function startTunnel
{
	local pre_tunnel_ip=$1
	tunnel_ip=-1
	# Start openVPN tunnel 
	service openvpn start

	local retries=5

	while [ $retries -gt 0 ]
	do
		tunnel_ip=$(externalip)
		if [ "$tunnel_ip" = "$pre_tunnel_ip" ]
		then
			(( retries-- ))
			sleep 5
		else
			break
		fi
	done

	if [ $retries -eq 0 ]
	then
		echo "Exceeded number of retries!"
		echo "Unable to establish tunnel."
		return 1
	else
		echo "Tunneled IP: $tunnel_ip"
	fi

	return 0
}

#
# Stops OpenVPN tunnel and waits until IP changes.
#
# Sets post_tunnel_ip with the changed ip address.
#
# Takes the current IP as an argument.
#
# Returns 0 if the ip changes, 1 otherwise.
#
function stopTunnel
{
	local current_ip=$(externalip)
	local new_ip=$1

	service openvpn stop

	local retries=5

	while [ $retries -gt 0 ]
	do
		new_ip=$(externalip)
		if [ "$new_ip" = "$current_ip" ]
		then
			(( retries-- ))
			sleep 5
		else
			break
		fi
	done

	if [ $retries -eq 0 ]
	then
		echo "Exceeded number of retries!"
		echo "Unable to close tunnel."
		return 1
	else
		post_tunnel_ip=$new_ip
		echo "Post-tunnel IP: $post_tunnel_ip"
	fi

	return 0
}

#
# Restarts tunnel and controlled program in the
# correct order.
#
# Takes no arguments.
#
# Returns 0 if successful, 1 otherwise.
#
function restartTunnel
{
	exit_on_fail stopProgram

	exit_on_fail stopTunnel

	exit_on_fail startTunnel

	exit_on_fail startProgram
}

#
# Starts program to be tunneled
#
# Takes a string to be executed.
#
# Returns the value of the executed string.
#
function startProgram
{
	eval $start_command

	if [ $? != 0 ]
	then
		echo "Unable to start the program: \"$start_command\"."
		return 1
	else
		echo "Program started."
		return 0
	fi
}

#
# Stops program to be tunneled
#
# Takes string to be executed.
#
# Returns the value of the executed string.
#
function stopProgram
{
	eval $stop_command

	if [ $? != 0 ]
	then
		echo "Unable to stop the program: \"$stop_command\"."
		return 1
	else
		echo "Program stopped."
		return 0
	fi

}

#
# Monitors for an IP change.
# Assume IP change means tunnel failed (for now) 
#
# takes no parameters
#
# returns 0 if exited on interrupt, 1 otherwise.
#
function monitorTunnel
{
	local current_ip=$(externalip)

	echo "Monitoring tunnel, use Ctrl+c to exit."

	while true
	do
		if [ $interrupt = true ]
		then
			echo "Ending monitor cycle."

			return 0
		fi

		if [ "$current_ip" != "$tunnel_ip" ]
		then
			echo "Tunnel crashed! attempting reconnect."

			retry_on_fail 5 restartTunnel
			
		else
			echo "Tunnel still up, sleeping."
			sleep $integ_check_interval
		fi
	done
}

####### configuratio and parsing #######

# Detect if running as root
if [ "$EUID" -ne 0 ]
then
	help
fi

# Default settings
openvpn_root="/etc/openvpn/"
openvpn_config_directory="/etc/openvpn/pia/"
openvpn_master_config="login.conf"
integ_check_interval=60

# Source config file
if [ $# -gt 0 ]
then
	if [ "$1" = "-c" ]
	then
		shift
		if [ $# -gt 0 ]
		then
			if [ -e "$1" ]
			then
				config_file="$1"
				source "$config_file"

				shift
			else
				echo "could not open config \"$config_file\""

				exit 1
			fi
		else
			echo "no config file specified"

			exit 1
		fi
	fi
fi

# Parse arguments
while [ $# -gt 0 ]
do
	case "$1" in
		-h|--help)
			help
			;;	
		-s)
			shift
			if [ $# -gt 0 ]
			then
				default_server="$1"
			else
				echo "no primary server specified"
			fi
			;;
		-b)
			;;
		-p)
			;;
		-c)
			echo "Config file must be specified first."
			echo "Unpredictable configs may result otherwise."
			exit 1
			;;
		-e)
			;;
		-v)
			;;
		-i)
			;;
		-l)
			;;
		-f)
			;;
		-1)
			shift
			if [ $# -gt 0 ]
			then
				start_command="$1"
			else
				echo "no start command specified"
			fi
			;;
		-2)
			shift
			if [ $# -gt 0 ]
			then
				stop_command="$1"
			else
				echo "no stop command specified"
			fi
			;;
		*)
			echo "argument \"$1\" not recognized."
			echo ""
			help
			;;
		esac
	shift
done

interrupt=false
openvpn_master_config_path="$openvpn_root""$openvpn_master_config"

########### "main" ###########

exit_on_fail setConfig "$default_server"

pre_tunnel_ip=$(externalip)

echo "Pre-tunnel IP: $pre_tunnel_ip"

exit_on_fail startTunnel $pre_tunnel_ip

exit_on_fail startProgram

echo "Beginning monitor cycle."

trap ctrl_c INT

monitorTunnel

stopProgram

stopTunnel $tunnel_ip



if [ "$post_tunnel_ip" = "$pre_tunnel_ip" ]
then
	echo "Returned to original IP address."
	exit 0
else
	echo "Post-tunnel IP is different than the original IP!"
	exit 1
fi
