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
	echo "-b a,b	set backup opvn server(s)"
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

function get_external_ip
{
	externalip=$(wget http://ipinfo.io/ip -qO -)
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
# Removes the first item and shifts the remaining array contents
#
# Modifies global variable 'backup_servers'
#
# Returns 0 on success, 1 otherwise
#
function backup_servers_pop_front
{
	local tmp=''
	local len=${#backup_servers[@]}

	if [ $len -gt 0 ]
	then
		unset backup_servers[0]

		for i in $(seq 1 $(($len-1)));
		do
			tmp=${backup_servers[$i]}
			backup_servers[$(($i-1))]="$tmp"
		done

		unset backup_servers[$((len-1))]
		return 0
	fi

	return 1
}

#
# Pushes the first argument to the back of backup_servers
#
# Pushes first argument to the end of backup_servers
#
# Returns 0 on success, 1 otherwise
#
function backup_servers_push_back
{
	local len=${#backup_servers[@]}

	backup_servers[$len]="$1"

	if [ $(($len+1)) -eq ${#backup_servers[@]} ]
	then
		return 0
	fi

	return 1
}

#
# Changes primary server to next backup server in
# the array and pops current default server to
# the end of the backup_servers list
#
# Takes no arguments
#
# Modifies the backup array by popping first next
# available server and pushing the current primary
# server to the end.
#
# Returns 0 on success, 1 otherwise
#
function change_default_server
{
	local tmp=$default_server

	if [ ${#backup_servers[@]} -gt 0 ]
	then
		echo "changing server from $default_server to ${backup_servers[0]}"

		default_server=${backup_servers[0]}

		backup_servers_pop_front
		backup_servers_push_back $tmp

		return 0
	fi

	return 1
}

#
# Setup configuration file symlink.
#
# OpenVPN service looks for /etc/openvpn/login.conf on start.
#
# Takes one argument, the name of the config file to symlink.
#
# Returns 0 if successful, 1 upon error.
#
function set_config
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
		return 1
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
function start_tunnel
{
	local pre_tunnel_ip=$1
	tunnel_ip=-1
	# Start openVPN tunnel 
	service openvpn start

	local retries=5

	while [ $retries -gt 0 ]
	do
		get_external_ip
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
		return 0
	fi
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
function stop_tunnel
{
	get_external_ip
	local current_ip=$(externalip)
	local new_ip=$1

	service openvpn stop

	local retries=5

	while [ $retries -gt 0 ]
	do
		get_external_ip
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
function restart_tunnel
{
	stop_program

	stop_tunnel

	start_tunnel $pre_tunnel_ip

	if [  $? -eq 1 ]
	then
		return 1
	fi

	start_program

	if [  $? -eq 1 ]
	then
		return 1
	fi

	return 0
}

#
# Starts program to be tunneled
#
# Takes a string to be executed.
#
# Returns the value of the executed string.
#
function start_program
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
function stop_program
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
function monitor_tunnel
{
	get_external_ip
	local current_ip=$(externalip)
	local status=0

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

			status=1

			while [ $status -eq 1 ]
			do
				restart_tunnel

				status=$?

				# change default server, if possible
				if [ $status -eq 1 ]
				then
					echo "Unable to restart using server $default_server"

					change_default_server

					set_config "$default_server"

					echo "Changed to $default_server, reattempting"
				fi
			done

			echo "Tunnel back up, IP: $tunnel_ip"
			
		else
			echo "Tunnel still up, sleeping."
			sleep $integ_check_interval
		fi

		get_external_ip
		current_ip=$(externalip)
	done
}

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

########### main ###########

exit_on_fail set_config "$default_server"

get_external_ip
pre_tunnel_ip=$(externalip)

echo "Pre-tunnel IP: $pre_tunnel_ip"

exit_on_fail start_tunnel $pre_tunnel_ip

exit_on_fail start_program

echo "Beginning monitor cycle."

trap ctrl_c INT

monitor_tunnel

stop_program

stop_tunnel $tunnel_ip

if [ "$post_tunnel_ip" = "$pre_tunnel_ip" ]
then
	echo "Returned to original IP address."
	exit 0
else
	echo "Post-tunnel IP is different than the original IP!"
	exit 1
fi
