#!/bin/bash

SERVER_DIR=/etc/openvpn/server

if [[ -f $SERVER_DIR/config-status ]]
then

	VALUE=$(cat $SERVER_DIR/config-status)

	if [[ "$VALUE" == "OK" ]]
	then
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
	./setup-openvpn.sh
fi

