#!/bin/bash

# generateNetplan.sh extracts all available networkinterfaces and attempts to create a bridge between all but the (alphabetical) first.
# it is useful when a device has multiple interfaces which are going to be used.

# Retrieve and sort all network interfaces, assuming the names are at the end of the string and do not contain any spaces.
interfaces=$(lshw -class network | grep 'logical name' | grep -o '[^ ]*$' | sort -h)

# Generate the preamble
cat <<EOT
network:
  version: 2
  renderer: networkd
  ethernets:
EOT

allowDHCP="yes"
for i in ${interfaces}; do
  # Register all interfaces, ensuring that only the (alphabetical) first one interface is
  # used to request (external) dhcp. All others will be bonded together into a single
  # bridge device.
  cat <<EOT
    ${i}:
      dhcp4: ${allowDHCP}
EOT

  allowDHCP="no"
done

# Strip away the first network interface and 'join' the others into a single comma separated string
# to be registered as the interfaces of the bridge device.
remaining=$(echo -n "${interfaces}" | tail -n +2 | tr "\n" ',')

# Add the bridge device config
cat <<EOT
  bridges:
    br-geproxy:
      interfaces: [${remaining}]
      dhcp4: false
      addresses: [10.1.0.1/16]
      nameservers:
        addresses: [1.1.1.1]
EOT
