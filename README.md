This bash script is intented to run a program as long as a tunnel is maintained.

The script operates by collecting external ip information, activating an OpenVPN connection collecting new ip information, and then checking if the external ip of the system ever reverts. If the tunnel collapses, the controlled program is terminated, and then the tunnel is re-activated, if possible.

TODO:
Primary Features:
x	CLI argument parsing
x	Source'd config script
x	Tunnel activation
x	Program activation/deactivation
x	Tunnel collapse detection (polling IP)
x	Tunnel reconnect

Secondary Features
x	Ctrl+c interception/graceful shutdown
	Secondary tunnel connection
	DNS dig and whois ip lookup
	Keyword whitelist/blacklist with WHOIS lookup

Bugs:
	TBD

Current config options:
	default_server		Primary VPN server connection config file.
	start_command		Bash string used to start the protected program.
	end_command		Bash string used to stop the protected program.
	integ_check_interval	Seconds between IP change detection routines.
	openvpn_root		Path to the OpenVPN config files root (defaults to "/etc/openvpn/").
	openvpn_config_directory	Path to the .ovpn templates (defaults to "/etc/openvpn/pia/").
	openvpn_master_config	Name of the symlinked ovpn config file (defaults to "login.conf"). This config file is placed in the "ovpn_root" directory
