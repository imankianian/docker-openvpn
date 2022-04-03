# Set the base image
FROM ubuntu:latest

RUN apt update && \
    apt dist-upgrade -y && \
    apt autoremove -y && \
    apt install -y openvpn easy-rsa iptables 

COPY setup-openvpn.sh /setup-openvpn.sh

ENTRYPOINT ["/setup-openvpn.sh"]
