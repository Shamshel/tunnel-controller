# Tunnel-controller
##### This bash script is intented to maintain a program as long as a VPN tunnel is maintained.

The script operates by collecting external ip information, activating an OpenVPN connection, collecting new ip information, and then checking if the external ip of the system ever reverts. If the tunnel collapses, the controlled program is terminated, and then the tunnel is re-activated, if possible.

## Install Instructions:

The script can be run from anywhere in the system, assuming run as root, and the default absolute, paths are used. By default, the program looks in the path "/etc/openvpn/pia/" for the openvpn config files.  For example, if the desired default server is configured in the file "US East.ovpn", then the program will attempt to create the simlink "/etc/openvpn/login.conf -> /etc/openvpn/pia/US\ East.ovpn" before attempting to activate the command specified in the "start_command" option.  Be sure to modifiy tunnel-controller.conf to reflect the desired default server, failover servers, and start and stop commands.

In *the author's* configuration, config files live at "/etc/openvpn/pia/", and all config files end with the line "auth-user-pass login.txt". The file "login.txt" lives at "/etc/openvpn/login.txt" and contains the following:

> username

> password

Unfortunately, this does mean that the username and password is stored in plaintext, which is bad, but in my case, the password and username were randomly generated, compartmentalizing the potential damage of a leak.

Note that if the external ip of the machine does not change after OpenVPN activation, the program will assume the tunnel activation failed.

## TODO:
### Primary Features:
* [X] CLI argument parsing
* [X] Source'd config script
* [X] Tunnel activation
* [X] Program activation/deactivation
* [X] Tunnel collapse detection (polling IP)
* [X] Tunnel reconnect

### Secondary Features:
* [X] Ctrl+c interception/graceful shutdown
* [X] Secondary tunnel failover
* [ ] DNS dig and whois ip reverse-lookup for collapse detection
* [ ] Keyword whitelist/blacklist with whois lookup
* [ ] Instructions or program modification to run without super-user

### Bugs:
* TBD

### Current config options:
* default_server - Primary VPN server connection config file.
* backup_servers - A bash array of backup VPN server config files. Ex: ("server a.ovpn" "server b.ovpn")
* start_command - Bash string used to start the protected program.
* end_command - Bash string used to stop the protected program.
* integ_check_interval - Seconds between IP change detection routines.
* openvpn_root - Path to the OpenVPN config root (defaults to "/etc/openvpn/").
* openvpn_config_directory - Path to the .ovpn templates (defaults to "/etc/openvpn/pia/").
* openvpn_master_config - Name of the symlinked ovpn config file (defaults to "login.conf"). This config file is placed in the "ovpn_root" directory. When running, this symlink looks like "login.conf->/etc/openvpn/pia/server.ovpn".
