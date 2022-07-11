#!/bin/bash

# assign the inputs to variables

export DEBIAN_FRONTEND=noninteractive
export EASYRSA_BATCH=1

EASYRSA_DIR=/usr/share/easy-rsa
CERTIFICATES_DIR=/etc/openvpn/client-certificates
BASE_CONFIG=$CERTIFICATES_DIR/base.conf
KEY_DIR=$CERTIFICATES_DIR/keys
OUTPUT_DIR=$CERTIFICATES_DIR/files

# Setup user timezone

ln -sf /usr/share/zoneinfo/$TZ  /etc/localtime
dpkg-reconfigure -f noninteractive tzdata


# Setup CA and server certificate

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

echo "tls-auth $SERVER_DIR/ta.key 0
cipher AES-256-CBC
auth SHA256
dh $SERVER_DIR/dh.pem
user nobody
group nogroup
push \"redirect-gateway def1 bypass-dhcp\"
push \"dhcp-option DNS 208.67.222.222\"
push \"dhcp-option DNS 208.67.220.220\"
port $SERVER_PORT
proto udp
explicit-exit-notify 1
dev tun
ca $SERVER_DIR/ca.crt
cert $SERVER_DIR/server.crt
key $SERVER_DIR/server.key
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp.txt
keepalive 10 120
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
verb 3" >> $SERVER_DIR/server.conf


# Adjust network settings

sed -i "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/" /etc/sysctl.conf
sysctl -p


# Configure iptables

INTERFACE=$(ip route list default | cut -f 5 -d " ")
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi
iptables -A INPUT -i $INTERFACE -m state --state NEW -p udp --dport $SERVER_PORT -j ACCEPT
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $INTERFACE -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $INTERFACE -j MASQUERADE
iptables -A OUTPUT -o tun0 -j ACCEPT

# Define a function to create certificates cause we need to iterate

make_certificates() {

mkdir -p $CERTIFICATES_DIR/keys
mkdir -p $CERTIFICATES_DIR/files

echo "client
remote $SERVER_IP $SERVER_PORT
proto udp
dev tun
nobind
persist-key
persist-tun
remote-cert-tls server
tls-auth ta.key 1
user nobody
group nogroup
ca ca.crt
cert client.crt
key client.key
cipher AES-256-CBC
auth SHA256
key-direction 1
verb 3" > $CERTIFICATES_DIR/base.conf

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

# Create the certificates

make_certificates $NUM

# Create a status file in server dir to let the parent script know it's safe to start the service in later calls
echo "OK" > $SERVER_DIR/server-config

# Finally, if everything went right, start the server
openvpn --config $SERVER_DIR/server.conf


