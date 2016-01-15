# Tunnel-controller
##### This bash script is intented to maintain a program as long as a VPN tunnel is maintained.

The script operates by collecting external ip information, activating an OpenVPN connection, collecting new ip information, and then checking if the external ip of the system ever reverts. If the tunnel collapses, the controlled program is terminated, and then the tunnel is re-activated, if possible.

## TODO:
### Primary Features:
* [X] CLI argument parsing
* [X] Source'd config script
* [X]Tunnel activation
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
