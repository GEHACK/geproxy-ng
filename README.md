# Summary
GEPROXY is a configuration for a server to act as a reverse proxy between contest machines and the public internet, while also managing the private network on which all the machines operate. It is installed through an ansible script, as described in [#Development](#Development) and [#Context](#Contest). Then, 6 docker containers are ran which are explained in [#Containers](#containers). 
# Installation
For the installation, all editable variables can be defined in [defaults.yaml](defaults.yaml). Explanation of the variables can be found in [#Configurables](#Configurables)
## Development 
1. Create two VM's running an ubuntu server installation. One shall act as GEPROXY and the other as a contest machine
2. Connect your GEPROXY and contest machine over a virtual network that doesn't use DHCP, since we will be running our own.
3. Clone the repository:  `$ git clone https://github.com/GEHACK/geproxy-ng.git`
- [Linux] Clone the repository on your own machine.
- [Windows] Clone the repository on the GEPROXY VM.
4. Create a `.env` file and add at least the following variables:
```
SSL_CERT_LOC=/etc/nginx/ssl/gehack.nl/gehack.nl.crt
SSL_KEY_LOC=/etc/nginx/ssl/gehack.nl/gehack.nl.key

PRIVATE_INTERFACE=br-geproxy
```
4. From the `geproxy-ng` folder, run ansible to install GEPROXY on the server, where USERNAME is the username of your GEPROXY machine,[ and IP it's IP connecting it to the internet. ]
- [Linux] `$ ansible-playbook -K install.yaml -i local -u [USERNAME]` and in [install.yaml](install.yaml) add `hosts = localhost`
- [Windows] `$ ansible-playbook -c local -i localhost, -K -u [USERNAME] install.yaml
1. BECOME password = `[ROOT PASSWORD]
2. Run `$ cd /opt/geproxy && docker compose up -d` on the GEPROXY server

At this point, all the docker services should be running. This can be checked with `$ docker compose ps | less -S`. You must be able to see 5 containers, the ones mentioned below in [#Containers](#containers), except for the `user-data` container. If so, any machines that are on the same private network as GEPROXY should be connected to the private network. To check, run `$ ip a` on the contest machine, and check whether the main interface (often `enp1s0`) has an ip of the form `10.0.x.x`

If not, and the machine still has an ip of the form `192.168.x.x`, follow these steps:
1. `$ sudo dhclient -r` to forget the current IP address
2. `$ sudo dhclient [enp1s0]`, replace `[enp1s0]` with the interface of your machine.
## Contest
1. Get a physical server.
2. Make sure that the server has a connection to the internet so you can connect to it.
3. If GEPROXY is already installed, you are done. If not, follow the steps of `development` from step 2.
## Without Ansible
Instead of installing GEPROXY using Ansible, it can also be installed manually. 
#### Requirements
- `$ sudo apt-get install ca-certificates curl gnupg lsb-release lshw rsync pxelinux syslinux-common make binutils perl liblzma-dev python3-netaddr mtools gcc`
- `$ sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose`
- Add the user to the docker group
	1. `$ sudo groupadd docker`
	2. `$ sudo usermod -aG docker $USER`
- Create a fitting `netplan`, can use the `netplan.j2` as a guide
#### Installation
1. Clone the repository:  `$ git clone https://github.com/GEHACK/geproxy-ng.git`
2. Enter the geproxy folder with `$ cd geproxy-ng`
- Download the ubuntu iso to `$ geproxy-ng/pxe/ubunto.iso` from `https://releases.ubuntu.com/22.04.3/ubuntu-22.04.3-live-server-amd64.iso`
- Update the ipxe module: `$ git submodule update --init --recursive ipxe`
- Generate the bootloader in `geproxy-ng/ipxe/src/` with `$ make clean bin/undionly.kpxe EMBED=/opt/geproxy/pxe/embed.ipxe`, and move it to `geproxy-ng/pxe`
3. Create an `.env` file, following the `.env.example` file
4. Run `$ docker compose up -d` on the GEPROXY server
# How does GEPROXY run
GEPROXY runs 6 docker containers. These are [AptCacherNg](#ACNG), [dnsmasq](#dnsmasq), [user-data](#user-data), [nginx](#nginx), [pixie](#pixie) and [devdocs](#devdocs). 
### nginx
Nginx is the proxy service for GEPROXY.

**Functions**:
- `configure.sh`: Listen on port 80 for any incoming traffic, and send it to gehack.nl. It will check for the availability of an SSL key and an SSL certificate, using the locations given in [`$SSL_CERT_LOC`](#Env) and [`$SSL_KEY_LOC`](#Env). It will also check the expiry date of the SSL certificate if found, which must be greater than [`$SSL_CERT_MINIMUM_DAYS`](#Env). If any of these checks are violated, Nginx will fall back to HTTP when connecting to `gehack.nl`
  - Redirect Configurations: 

| File           | From                   | To  |
| -------------- | ---------------------- | --- |
| `default.conf` | `cloud-init.${DOMAIN}` | `/var/www/html`    |
| `docs.conf`    | `docs.${DOMAIN}`       | `http://devdocs:9292/`    |
| `judge.conf`   | `judge.${DOMAIN}`      | `https://${DOMJUDGE_REMOTE}/`    |
| `pixie.conf`   | `pixie.${DOMAIN}`                       | `http://pixie:4000/`    |
Since the `cloud-init` is referred to the machine itself, the files for booting through pxe in `.pxe` are included in the nginx container. 
### ACNG
ACNG is AptCacherNg, a caching proxy. It is used to create a local cache of a Debian system. ACNG is used to speed up the process of booting all the contest machines. Normally, all machines have to proxy through GEPROXY to obtain a download of their system, but with ACNG this system is downloaded only once, and then the contest machines can simply get it from there.
The port through which ACNG is accessed is found in [`$ACNG_PORT`](#Env)  
### pixie
Pixie is a custom tool that provides imaging, contest layout management, and printing proxy services for programming contests.
Only requirement is the private IP, which is the network that Pixie will operate on. Further documentation can be found [here](https://github.com/tuupke/pixie)
### devdocs
Devdocs downloads the documentation for the languages defined in the environment variable [$LANGUAGES](#LANGUAGES). 
Practically all languages are included in devdocs, so if any other languages ever is more prevalent and documentation is needed, add it to the env variable.
### dnsmasq
Dnsmasq is the DHCP server within the private network. 
Dnsmasq will only listen to requests from the given interface in environment variable `PRIVATE_INTERFACE`, which is set to `private_interface` from [#Env](#Env) 
There is also TFTP and DHCP-boot enabled, enabling dnsmasq to transfer files to other machines within the private network, such as bootfiles for pxe boot. Therefore the files within `.pxe` are also included in the dnsmasq container.
The line `network_mode: host` is very important, since Docker runs in its own network, which makes DHCP want to serve within that network. With `network_mode: host` the docker container shares its network namespace with the host machine, so the DHCP server can actually distribute addresses to the contest machines. 
### user-data
user-data is used to set data to the contest machines. The container runs, creates the cloud-init file and then quits again. For this, it uses the four `MACHINE` environment variables in [Variables](#Env). 
This container sets up the cloud config, containing the machines credentials, some ssh settings, and a full partitioning such that devices that have incompatible file systems by default can also be used.  
*NOTE: If you do not see this container enabled after starting all containers, this is correct. The container configures the cloud config, after which it will stop.*

## Connection
### netplan
GEPROXY requires a custom netplan, which works the following way:
1. The (alphabetically) first private_interface of GEPROXY will serve as the interface to the public internet. It will have enabled DHCP.
   *NOTE: If you are running a development instance of GEPROXY, make sure that the first interface in your VM is a NAT network connected to your own machine*
3. All of the other private_interfaces will have DHCP disabled, and will be grouped into a single bridge device called `br_geproxy`. It will operate on the addresses `10.1.0.1/16` 
### routing
There is a last folder routing, which includes three playbooks to run with ansible. The inventory file included has only localhost, so the scripts will run only on GEPROXY.
1. `disableinternet.yaml`: Disables internet
2. `enableinternet.yaml`: Enables internet
3. `generateNetplan.sh`: Generate a new netplan according to the explanation [above](#netplan)

## Configurables
GEPROXY can be configured using the following environment variables. These are used in the [install.yaml](install.yaml) file. Importantly, many are also used in the [env.j2](env.j2) file, such that the environment variables defined in that can be used for the [docker-compose](docker-compose.yaml)

| **Variable**            | **Default**                    | **Description**                                                                                                                 |
| ----------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| private_cidr            | `10.1.0.1/16`                  | The CIDR range on which the private network is ran.                                                                             |
| leases_min_start        | `100`                          | The lowest value from which the subnet can start leasing IP addresses.                                                          |
| private_interface       | `br-geproxy`                   | The interface dnsmasq will bind to.                                                                                             |
| dns_resolver            | `1.1.1.1`                      | The DNS server dnsmasq will bind to.                                                                                            |
| static_macs             | `[]`                           | All of the static macs used for the contest, often used for the printer                                                         |
| domain                  | `progcont`                     | Domain on which all data is for nginx. Defaut on progcont such that you dont accidentally kill all internet                     |
| machine_hostname        | `machine`                      | Hostname for contest machines                                                                                                   |
| machine_username        | `admin`                        | Username for contest machines                                                                                                   |
| machine_password        | `passwordpassword hashed?`     | Password for contest machines                                                                                                   |
| github_usernames        | `tuupke`                       | Whose keys will have access to `machine_username`'s account. For contest, set this to the people that will be doing maintenance |
| ccs_host                | `domjudge.org/demoweb`         | Internet location of DomJudge                                                                                                   |
| acng_port               | `3142`                         | The port on which ACNG listens                                                                                                  |
| languages               | `openjdk@17 c cpp python@3.10` | Available languages in documentation                                                                                            |
| cert_minimum_days_valid | `7`                            | After how many days the certificate expires                                                                                     |
