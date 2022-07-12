#!/bin/sh

SERVER_DIR=/etc/openvpn/server

if [[ -f $SERVER_DIR/config-status ]]
then

	VALUE=$(cat $SERVER_DIR/config-status)

	if [[ "$VALUE" == "OK" ]]
	then

		# Since the node disappears when container stops, we need to recreate it on restarts

		mkdir -p /dev/net
		if [[ ! -c /dev/net/tun ]]
		then
			mknod /dev/net/tun c 10 200
		fi

		# set iptables rules again since they've been removed when container stopped

		INTERFACE=$(ip route list default | cut -f 5 -d " ")
		SERVER_PORT=$(grep "port" /etc/openvpn/server/server.conf | cut -d' ' -f2)

		iptables -A INPUT -i $INTERFACE -m state --state NEW -p udp --dport $SERVER_PORT -j ACCEPT
		iptables -A INPUT -i tun0 -j ACCEPT
		iptables -A FORWARD -i tun0 -j ACCEPT
		iptables -A FORWARD -i tun0 -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
		iptables -A FORWARD -i $INTERFACE -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
		iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $INTERFACE -j MASQUERADE
		iptables -A OUTPUT -o tun0 -j ACCEPT

		# Start the service

		openvpn --config $SERVER_DIR/server.conf
	fi
else
	
	# First of all, let's count the inputs

	if [[ $# -ne 4 ]]; then
        echo "You must enter four arguments: The first one must be your timezone, eg. Asia/Tehran, the second one must be the server IP, the third one must be the server port and the last one must be the number of certificates you wish to be generated automatically."
        exit 1
	fi
	
	TZ=${1}
	SERVER_IP=${2}
	SERVER_PORT=${3}
	NUM=${4}

	export SERVER_DIR TZ SERVER_IP SERVER_PORT NUM
	mkdir $SERVER_DIR
	./setup-openvpn.sh
fi

