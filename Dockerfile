# Set the base image
FROM alpine:latest

RUN apk add tzdata openvpn easy-rsa iptables

COPY start-openvpn.sh /start-openvpn.sh
COPY setup-openvpn.sh /setup-openvpn.sh

ENTRYPOINT ["/start-openvpn.sh"]
