# Summary
GEPROXY is a configuration for a server to act as a reverse proxy between contest machines and the public internet, while also managing the private network on which all the machines operate. It is installed through an ansible script, as described in [development](#Development) and [context](#Contest). Then, 6 docker contains are ran which are explained in [containers](#containers). Certain variables have to be set in the [environment variables](.env), which are explained in [environment variables](#environment variables)

# Installation
## Development 
1. Create two VM's running an ubuntu server installation. One shall act as GEPROXY and the other as a contest machine
- [Linux] Connect your GEPROXY and contest machine over a network that doesn't use DHCP, since we will be running our own.
- [Windows] Simon?
2. `git clone https://github.com/GEHACK/geproxy-ng.git` clone the repository
- [Linux] Clone the repository on your own machine.
- [Windows] Clone the repository on the GEPROXY VM.
3. Create a `.env` file and add the following variables:
```
SSL_CERT_LOC=/etc/nginx/ssl/gehack.nl/gehack.nl.crt
SSL_KEY_LOC=/etc/nginx/ssl/gehack.nl/gehack.nl.key

PRIVATE_INTERFACE=br-geproxy
```
4. From the `geproxy-ng` folder, run ansible to install GEPROXY on the server, where USERNAME is the username of your GEPROXY machine, and IP it's IP connecting it to the internet. 
- [Linux] `ansible-playbook -K install.yaml -i local -u=[USERNAME]` and in [install.yaml](install.yaml) add `hosts = localhost`
- [Windows] `ansible-playbook -K install.yaml --connection=local, u=[USERNAME]`

5. BECOME password = `[ROOT PASSWORD]`
6. Run `$ cd /opt/geproxy && docker compose up -d` on the GEPROXY server

At this point, all the docker services should be running. This can be checked with `docker compose ps | less -S`. If so, any machines that are on the same private network as GEPROXY should be connected to the private network. To check, run `ip r` on the contest machine, and check whether the machine has an ip of the form `10.0.x.x`

If not, and the machine still has an ip of the form `192.168.x.x`, follow these steps:
1. `sudo dhclient -r` to forget the current IP address
2. `sudo dhclient enp1s0`, replace `enp1s0` with the interface of your machine.

## Contest
1. Have the physical GEPROXY server ready. 
2. _TODO_

# How does GEPROXY run
GEPROXY runs 6 docker containers. These are [AptCacherNg](#ACNG), [dnsmasq](#dnsmasq), [user-data](#user-data), [nginx](#nginx), [pixie](#pixie), [devdocs](#devdocs). 
### nginx
Nginx is the proxy service for GEPROXY.
The container is dependent on `pixie`, since [] and `devdocs`, since nginx must refer all contest machines to [docs?.gehack.nl] idkidk. 

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
ACNG is AptCacherNg, a caching proxy. It is used to create a local cache of a Debian system. ACNG is used to speed up the process of booting all the contest machines. Normally, all machines have to proxy through GEPROXY to obtain a download of their system, but with ACNG this system is downloaded only once, and then the contest machines  can simply get it from there.
The port through which ACNG is accessed is found in [`$ACNG_PORT`](#Env)  
### pixie
Pixie is a custom tool that provides imaging, contest layout management, and printing proxy services for programming contests.
Only requirement is the private IP, which is the network that Pixie will operate on. Further documentation can be found on `github.com/tuupke/pixie`
### devdocs
Devdocs downloads the documentation for the languages defined in the environment variable [$LANGUAGES](#LANGUAGES). 
Practically all languages are included in devdocs, so if any other langudevdocs
Devdocs downloads the documentation for the languages defined in the environment variable [$LANGUAGES](#LANGUAGES). 
Practically all languages are included in devdocs, so if any other languages ever is more prevalent and documentation is needed, add it to the env variable. ages ever is more prevalent and documentation is needed, add it to the env variable. 
### dnsmasq
Dnsmasq is the DHCP server within the private network. 
It operates on the `$BIND_INTERFACE` as defined by [`$PRIVATE_INTERFACE`](#Env), using the IP defined by [`$PRIVATE_IP`](#Env), and the DOMAIN [`$DOMAIN`](#Env).   
Dnsmasq will only listen to requests from the given interface. 
There is also TFTP and DHCP-boot enabled, enabling dnsmasq to transfer files to other machines within the private network, such as bootfiles for pxe boot. Therefore the files within `.pxe` are also included in the dnsmasq container.
The line `network_mode: host` is very important, since Docker runs in its own network, which makes DHCP want to serve within that network. With `network_mode: host` the docker container shares its network namespace with the host machine, so the DHCP server can actually distribute addresses to the contest machines. 
### user-data
user-data is used to set data to the contest machines. The container runs, creates the cloud-init file and then quits again. For this, it uses the four `MACHINE` environment variables in [Variables](#Env). 

## Connection
### netplan
GEPROXY requires a custom netplan, which works the following way:
1. The (alphabetically) first private_interface of GEPROXY will serve as the interface to the public internet. It will have enabled DHCP *NOTE: If you are running a development instance of GEPROXY, make sure that the first interface in your VM is a NAT network connected to your own machine*
2. All of the other private_interfaces will have DHCP disabled, and will be grouped into a single bridge device called `br_geproxy`. It will run on the addresses `10.1.0.1/16` 
### routing
There is a last folder routing, which includes three playbooks to run with ansible. The inventory file included has only localhost, so the scripts will run only on GEPROXY.
1. `disableinternet.yaml`: Apply the state `absent` to stop ip-forwarding **something something figure out**
2. `enableinternet.yaml`: samesies
3. `generateNetplan.sh`: Generate a new netplan according to the explanation [above](#netplan)

# Env
| Variable | Default | Usage | Description |
| ---- | ---- | ---- | ---- |
| `ACNG_PORT` | `3142` | [acng](#ACNG) | The port on which ACNG listens |
| `PRIVATE_INTERFACE` | `lo` - Never change this, to make sure you don't break all internet everywhere. | [dnsmasq](#dnsmasq) | The interface for the DNS/DHCP server |
| `PRIVATE_IP` | `10.1.0.1` | [acng](#ACNG), [pixie](#pixie), [dnsmasq](#dnsmasq) | IP of private network |
| `DOMAIN` | `progcont` | [nginx](#nginx), [dnsmasq](#dnsmasq) | Domain on which all data is for nginx |
| `DOMJUDGE_URL` | `judge.gehack.nl` | [nginx](#nginx) | Location of DomJudge |
| `LANGUAGES` | `openjdk@17 c cpp python@3.10` | [devdocs](#devdocs) | Available languages in documentation |
| `GITHUB_USERNAMES` | `tuupke` | [user-data](#user-data) | GitHub accounts to import SSH keys from |
| `MACHINE_HOSTNAME` | `machine` | [user-data](#user-data) | Hostname for contest machines |
| `MACHINE_PASSWORD` | `$2a$12$6EyKyPDuHQcHIF7Abawva.pCLQhGs0r 3NybeiMVgaKTDPbm.a7b6` | [user-data](#user-data) | Password for contest machines |
| `MACHINE_USERNAME` | `admin` | [user-data](#user-data) | Username for contest machines |
| `PRINTER_MAC` | `aa:bb:cc:dd:ee:ff` | [dnsmasq](#dnsmasq) | Address for the printer. |
| `SSL_CERT_LOC` | `empty` | [nginx](#nginx) | Location of SSL certificate to use HTTPS |
| `SSL_CERT_MINIMUM_DAYS` | `7` | [nginx](#nginx) | Minimum amount of days left in expiry date to use HTTPS |
| `SSL_KEY_LOC` | `empty` | [nginx](#nginx) | Location of SSL key to use HTTPS |
| `SUBDOMAINS` | `empty` | [nginx](#nginx) | Pass any subdomains to check whether they are included in the SSL certificate. |

# Weird Things
- The `$DOMAIN: gehack.nl` is hardcoded in `configure.sh`
- `/dnsmasq/dnsmasq.leases` is fully empty, never gets filled (afaik)
- There is no `$PRIVATE_IP` in `embed.ipxe.template`, but it is envsubsted into it
- `br-geproxy` is hardcoded into `netplan.j2`, even though it's an environment variable for `PRIVATE_INTERFACE`
- `10.1.0.1/16` is hardcoded in some places though its also `$PRIVATE_IP` 
- Printer address is hard-coded into systems, if printer were to change, you cant edit the MAC-address?
- Why do we have both `interface=` and `listen-address=` in the dnsmasq conf, while they seem to be the same thing
