# docker-openvpn
This is a simple OpenVPN server implemented inside a docker container. Here are the main features:

1. It uses Alpine image which makes it extremely lightweight.
2. It uses UDP and AES-256-GCM, AES-128-GCM, and AES-256-CBC.
2. You can configure it on the first start by passing the server timezone, server IP, server port and the number of certificates you want to have.
4. If you manually stop the container, it will automatically configure itself when you start it again.

## How to build the image?
To build the image, cd to the root of the project and use the following command:

`$ docker build -t IMAGE_NAME .`

Replace IMAGE_NAME with the name you wish for your image.

## How to run the server?
If you're running the server for the first time, there are some options you need to pass to the server to configure it. You don't need to pass anything on later starts. 

This image accept 4 inputs to configure itself on the first start. You have to pass them with the following order:

1. the timezone of the location of the server
2. server IP
3. server port (the port you want the server to listen on)
4. the number of certificates you wish to be generated for you

There also other options that you need to set:

1. You need to provide `-v` option to bind a volume to the container. This way you can easily access your certificates.
2. You need to expose the port that your server listens on. You can use `-p` option for this.
3. You also need to allow your container to adjust network settings to route packets. You can use `--cap-add` for this. 

**example**: Consider I want to run a server with the following conditions:

- It runs in Berlin. 
- Server IP is 160.160.160.160
- The server port is 2200
- and I want 5 certificates generated for my users. 

This will be the command then:

`$ docker run -v openvpn:/etc/openvpn -p 2200:2200/udp --cap-add=NET_ADMIN alpine-openvpn Europe/Berlin 160.160.160.160 2200 5`

If you use a Docker volume like the one I used in the above example, then your certificates will be available at:

`/var/lib/docker/volumes/openvpn/_data/client-certificates/files'

If you use a bind mount, then your certificates will be at:

`PATH_TO_DIR/client-certificates/files'
