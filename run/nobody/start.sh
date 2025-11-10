#!/usr/bin/dumb-init /bin/bash

# CONFIG_PLACEHOLDER

# create env var for display (note display number must match for tigervnc)
export DISPLAY=:0

prepare_x_sockets() {
	for dir in /tmp/.X11-unix /tmp/.ICE-unix; do
		if [[ ! -d "${dir}" ]]; then
			install -d -m 1777 "${dir}"
		else
			chmod 1777 "${dir}" || true
		fi
	done
	# remove stale sockets for this display without deleting the directories
	rm -f "/tmp/.X11-unix/X0" 2>/dev/null || true
	find /tmp/.ICE-unix -type s -name 'ICE-unix-*' -delete 2>/dev/null || true
}

require_vnc_password() {
	if [[ -z "${VNC_PASSWORD:-}" ]]; then
		echo "[error] ENABLE_VNC requires VNC_PASSWORD to be set." >&2
		return 1
	fi
	local password_length="${#VNC_PASSWORD}"
	if [[ "${password_length}" -lt 8 ]]; then
		echo "[error] ENABLE_VNC requires VNC_PASSWORD to be at least 8 characters long." >&2
		return 1
	fi
	return 0
}

start_vnc_stack() {
	prepare_x_sockets
	if ! require_vnc_password; then
		return 1
	fi

	# vnc start command
	vnc_start="Xvnc :0 -depth 24"

	# if a password is specified then generate password file in /home/nobody/.vnc/passwd
	# else append insecure flag to command line
	echo "[info] Configuring VNC password (length OK)."
	echo -e "${VNC_PASSWORD}\n${VNC_PASSWORD}\nn" | vncpasswd 1>&- 2>&-
	vnc_start="${vnc_start} -PasswordFile=${HOME}/.vnc/passwd"

	# if defined then set title for the web ui tab
	if [[ -n "${WEBPAGE_TITLE}" ]]; then
		vnc_start="${vnc_start} -Desktop='${WEBPAGE_TITLE}'"
	fi

	# Get the container's IP address, excluding the loopback interface
	IP_ADDRESS=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

	# Check if an IP address was found
	if [ -n "$IP_ADDRESS" ]; then
		# Export the IP address as an environment variable
		export CONTAINER_IP="$IP_ADDRESS"
		echo "CONTAINER_IP environment variable set to: $CONTAINER_IP"
	else
		echo "No IP address found for the container."
		return 1
	fi

	# start tigervnc (vnc server) - note the port that it runs on is 5900 + display number (i.e. 5900 + 0 in the case below).
	LOG_ROOT="/home/container/logs"
	mkdir -p "${LOG_ROOT}"
	VNC_LOG="${LOG_ROOT}/vnc-server.log"
	NOVNC_LOG="${LOG_ROOT}/novnc.log"
	XFCE_LOG="${LOG_ROOT}/xfce-session.log"

	eval "${vnc_start}" >>"${VNC_LOG}" 2>&1 &

	# starts novnc (web vnc client) - note also starts websockify to connect novnc to tigervnc server
	/usr/sbin/websockify --web /usr/share/webapps/novnc/ 6080 localhost:5900 >>"${NOVNC_LOG}" 2>&1 &

	# Launch Xfce in the background.
	dbus-launch startxfce4 >>"${XFCE_LOG}" 2>&1 &
}

# STARTCMD_PLACEHOLDER

# optionally launch the desktop stack
enable_vnc="${ENABLE_VNC:-no}"
case "${enable_vnc,,}" in
	yes|true|1|on|"")
		if ! start_vnc_stack; then
			echo "[error] ENABLE_VNC=${enable_vnc} but the VNC stack could not start." >&2
			exit 1
		fi
		;;
	*)
		echo "[info] ENABLE_VNC=${enable_vnc} -> skipping TigerVNC/novnc startup"
		;;
esac

# run cat in foreground, this prevents start.sh script from exiting and ending all background processes
cat
