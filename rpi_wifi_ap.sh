#!/bin/bash

yes_no()
{
read answer

if [[ $answer == "y" || $answer == "Y" || $answer == "yes" || $answer == "Yes" || $answer == "YES" ]]
then
    echo
else
    exit
fi
}

###############################################################################################
ap_setup()
{
cat << MSG
Specify your subnet:
(e.g: 192.168.10.0)
MSG


subnet=""
while [ -z $subnet ]
do
    read answer
    subnet=$(expr match "$answer" '\([0-9]*.[0-9]*.[0-9].\)')
done

echo "subnet is $subnet.0/24"
echo


cat << MSG
Specify the SSID (Name of the wireless network):
(e.g: Bob_Wifi)
MSG

while [ -z $ssid ]
do
    read ssid
done

echo "ssid is $ssid"
echo


echo "Specify the password for your network:"
while [ ${#password} -lt 8 ]
do
    read password
    if [ ${#password} -lt 8 ]
    then
        echo "password too short"
    fi
done

echo "password is $password"
echo


apt-get update
apt-get install hostapd dnsmasq -y

echo "dhcp-range=$subnet.50,$subnet.150,255.255.255.0" >> /etc/dnsmasq.conf

cat << EOF > /etc/network/interfaces
auto lo

iface lo inet loopback
iface eth0 inet dhcp

iface wlan0 inet static
  address $subnet.1
  netmask 255.255.255.0
EOF

cat << EOF > /etc/hostapd/hostapd.conf
interface=wlan0
driver=rtl871xdrv
ssid=$ssid
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$password
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" >> /etc/default/hostapd

ifconfig wlan0 $subnet.1/24

wget -c http://www.adafruit.com/downloads/adafruit_hostapd.zip
unzip adafruit_hostapd.zip
mv /usr/sbin/hostapd /usr/sbin/hostapd.ORIG
mv hostapd /usr/sbin
chmod 755 /usr/sbin/hostapd

update-rc.d hostapd enable
update-rc.d dnsmasq enable

service hostapd restart
service dnsmasq restart

}
###############################################################################################
nat_setup()
{
echo "Do you want to configure NAT ? (y/n)"

yes_no

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo 1 > /proc/sys/net/ipv4/ip_forward

iptables -F
iptables -t nat -F

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

iptables -t nat -S
iptables -S

iptables-save > /etc/iptables.ipv4.nat

echo "up iptables-restore < /etc/iptables.ipv4.nat" >> /etc/network/interfaces
}

###############################################################################################
tor_setup()
{
echo "Do you want to configure your Pi as ToR anonymizing middlebox ? (y/n)"

yes_no

wlan0_ip=$(ifconfig wlan0|egrep -o "addr:([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"|sed "s/addr://")

apt-get install tor -y

cat << EOF > /etc/tor/torrc
Log notice file /var/log/tor/notices.log
VirtualAddrNetwork 10.192.0.0/10
AutomapHostsSuffixes .onion,.exit
AutomapHostsOnResolve 1
TransPort 9040
TransListenAddress $wlan0_ip
DNSPort 53
DNSListenAddress $wlan0_ip
EOF

iptables -F
iptables -t nat -F

iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 22 -j REDIRECT --to-ports 22
iptables -t nat -A PREROUTING -i wlan0 -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A PREROUTING -i wlan0 -p tcp --syn -j REDIRECT --to-ports 9040

iptables -t nat -L

iptables-save > /etc/iptables.ipv4.nat

touch /var/log/tor/notices.log
chown debian-tor /var/log/tor/notices.log
chmod 644 /var/log/tor/notices.log

update-rc.d tor enable

service tor restart
}

cat << INTRO
-----------------------------
This script will help you configure your Raspberry Pi as
a wireless acces point.

***
***
Run it as root, or with sudo,
and reboot your Pi once you're done.

THIS WILL ERASE YOUR NETWORK CONFIGURATION.
***
***
-----------------------------

 1 - Configure wifi access point. 
 2 - Setup NAT. (only if you want access to the internet)
 3 - Setup Tor anonymizing middlebox. (requires NAT)
INTRO

echo -n "Choice: "
read answer

case "$answer" in

    1) ap_setup
    ;;
    2) nat_setup
    ;;
    3) tor_setup
    ;;
esac

