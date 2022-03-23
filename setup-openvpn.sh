#!/bin/bash

# Define variables and functions

if [[ $# -ne 3 ]]; then
        echo "You must enter three arguments. ehe first one must be your timezone, eg. Asia/Tehran. The second one must be server IP and the last one must be the number of certificates you wish to be generated automatically."
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export EASYRSA_BATCH=1

TZ=${1}
SERVER_IP=${2}
NUM=${3}
SERVER_DIR=/etc/openvpn/server
EASYRSA_DIR=/etc/openvpn/easy-rsa
CERTIFICATES_DIR=/etc/openvpn/client-certificates
BASE_CONFIG=$CERTIFICATES_DIR/base.conf
KEY_DIR=$CERTIFICATES_DIR/keys
OUTPUT_DIR=$CERTIFICATES_DIR/files

make_certificates() {

    mkdir -p $CERTIFICATES_DIR/keys
    mkdir -p $CERTIFICATES_DIR/files
    echo "client" > $CERTIFICATES_DIR/base.conf
    echo "remote $SERVER_IP 1194" >> $CERTIFICATES_DIR/base.conf
    echo "proto udp" >> $CERTIFICATES_DIR/base.conf
    echo "dev tun" >> $CERTIFICATES_DIR/base.conf
    echo "nobind" >> $CERTIFICATES_DIR/base.conf
    echo "persist-key" >> $CERTIFICATES_DIR/base.conf
    echo "persist-tun" >> $CERTIFICATES_DIR/base.conf
    echo "remote-cert-tls server" >> $CERTIFICATES_DIR/base.conf
    echo "tls-auth ta.key 1" >> $CERTIFICATES_DIR/base.conf
    echo "user nobody" >> $CERTIFICATES_DIR/base.conf
    echo "group nogroup" >> $CERTIFICATES_DIR/base.conf
    echo "ca ca.crt" >> $CERTIFICATES_DIR/base.conf
    echo "cert client.crt" >> $CERTIFICATES_DIR/base.conf
    echo "key client.key" >> $CERTIFICATES_DIR/base.conf
    echo "cipher AES-256-CBC" >> $CERTIFICATES_DIR/base.conf
    echo "auth SHA256" >> $CERTIFICATES_DIR/base.conf
    echo "key-direction 1" >> $CERTIFICATES_DIR/base.conf
    echo "verb 3" >> $CERTIFICATES_DIR/base.conf


    for ((i=0; i<$NUM; i++)); do

        $EASYRSA_DIR/easyrsa gen-req client$i nopass
	$EASYRSA_DIR/easyrsa sign-req client client$i
	cp /pki/issued/client$i.crt $CERTIFICATES_DIR/keys
	cp /pki/private/client$i.key $CERTIFICATES_DIR/keys
	cp $SERVER_DIR/ta.key $CERTIFICATES_DIR/keys
	cp $SERVER_DIR/ca.crt $CERTIFICATES_DIR/keys
	cat ${BASE_CONFIG} \
	    <(echo -e "<ca>") \
  	    ${KEY_DIR}/ca.crt \
	    <(echo -e "</ca>\n<cert>") \
	    ${KEY_DIR}/client$i.crt \
	    <(echo -e "</cert>\n<key>") \
	    ${KEY_DIR}/client$i.key \
	    <(echo -e "</key>\n<tls-auth>") \
	    ${KEY_DIR}/ta.key \
	    <(echo -e "</tls-auth>") \
	    > ${OUTPUT_DIR}/client$i.ovpn	

    done    
}

# Setup container & install necessary packages

apt update
apt dist-upgrade -y
apt autoremove -y

if [[ ! -f "/etc/timezone" ]]; then
	echo $TZ > /etc/timezone
	apt install -y tzdata
fi

apt install -y openvpn easy-rsa iptables

# Setup CA and server certificate
mkdir /etc/openvpn/easy-rsa
ln -s /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/
echo -e 'set_var EASYRSA_ALGO "ec"\nset_var EASYRSA_DIGEST "sha256"' > $EASYRSA_DIR/vars
$EASYRSA_DIR/easyrsa init-pki
dd if=/dev/urandom of=pki/.rnd bs=256 count=1
$EASYRSA_DIR/easyrsa build-ca nopass
$EASYRSA_DIR/easyrsa gen-req server nopass
$EASYRSA_DIR/easyrsa sign-req server server
cp /pki/ca.crt $SERVER_DIR
cp /pki/issued/server.crt $SERVER_DIR
cp /pki/private/server.key $SERVER_DIR
$EASYRSA_DIR/easyrsa gen-dh
cp /pki/dh.pem $SERVER_DIR
openvpn --genkey --secret $SERVER_DIR/ta.key

# Configure OpenVPN server
echo "tls-auth $SERVER_DIR/ta.key 0" > $SERVER_DIR/server.conf
echo "cipher AES-256-CBC" >> $SERVER_DIR/server.conf
echo "auth SHA256" >> $SERVER_DIR/server.conf
echo "dh $SERVER_DIR/dh.pem" >> $SERVER_DIR/server.conf
echo "user nobody" >> $SERVER_DIR/server.conf
echo "group nogroup" >> $SERVER_DIR/server.conf
echo 'push "redirect-gateway def1 bypass-dhcp"' >> $SERVER_DIR/server.conf
echo 'push "dhcp-option DNS 208.67.222.222"' >> $SERVER_DIR/server.conf
echo 'push "dhcp-option DNS 208.67.220.220"' >> $SERVER_DIR/server.conf
echo "port 1194" >> $SERVER_DIR/server.conf
echo "proto udp" >> $SERVER_DIR/server.conf
echo "explicit-exit-notify 1" >> $SERVER_DIR/server.conf
echo "dev tun" >> $SERVER_DIR/server.conf
echo "ca $SERVER_DIR/ca.crt" >> $SERVER_DIR/server.conf
echo "cert $SERVER_DIR/server.crt" >> $SERVER_DIR/server.conf
echo "key $SERVER_DIR//server.key" >> $SERVER_DIR/server.conf
echo "server 10.8.0.0 255.255.255.0" >> $SERVER_DIR/server.conf
echo "ifconfig-pool-persist /var/log/openvpn/ipp.txt" >> $SERVER_DIR/server.conf
echo "keepalive 10 120" >> $SERVER_DIR/server.conf
echo "persist-key" >> $SERVER_DIR/server.conf
echo "persist-tun" >> $SERVER_DIR/server.conf
echo "status /var/log/openvpn/openvpn-status.log" >> $SERVER_DIR/server.conf
echo "verb 3" >> $SERVER_DIR/server.conf

# Adjust network settings
sed -i "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/" /etc/sysctl.conf
sysctl -p

# Configure iptables
INTERFACE=$(ip route list default | cut -f 5 -d " ")
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi
iptables -A INPUT -i $INTERFACE -m state --state NEW -p udp --dport 1194 -j ACCEPT
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $INTERFACE -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $INTERFACE -j MASQUERADE
iptables -A OUTPUT -o tun0 -j ACCEPT

make_certificates
openvpn --config $SERVER_DIR/server.conf
