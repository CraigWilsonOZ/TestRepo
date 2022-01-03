#!/bin/sh
#set -eu -o pipefail # fail on error and report it, debug all lines

echo "MineCraft base install and configuration (Tested on Ubuntu 20.04 LTS)"
echo "Checking for sudo access."
sudo -n true
test $? -eq 0 || exit 1 "you should have sudo privilege to run this script"

echo "you have 5 seconds to proceed ..."
echo "or"
echo "hit Ctrl+C to quit"
echo -e "\n"
sleep 6

## Checking if script has recorded a completed flag to stop overwriting configuration
if test -f /datadrive/minecraft/.mc.done;
then
    echo "File flag exists"
    exit
fi

# Variables
PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)

# Mounting Data Drive
fstab=/etc/fstab

# SCSI LUN - 4 numbers a:b:c:d
# a = Hostadapter ID
# b = SCSI channel
# c = Device ID
# d = LUN

if ! grep -q "minecraft" $fstab;
then
    echo "Listing current disks"
    lsblk -o NAME,HCTL,SIZE,MOUNTPOINT | grep -i "1:0:0:0"
    ls -d /sys/block/sd*/device/scsi_device/* |awk -F '[:/]' '{print "/dev/"$4,"- SCSI",$7":"$9}'
    echo "Creating device name"
    LUN=1
    DISKSYSTEMPATH=$(ls -d /sys/block/sd*/device/scsi_device/* |grep 1.0.0.0 |awk -F '[/]' '{print "/dev/"$4'})
    echo $DISKSYSTEMPATH
    echo "Creating Partions"
    sudo parted $DISKSYSTEMPATH --script mklabel gpt mkpart xfspart xfs 0% 100%
    sudo mkfs.xfs $DISKSYSTEMPATH -f
    sudo partprobe $DISKSYSTEMPATH
    
    # DISKSYSTEMPATH=$DISKSYSTEMPATH$LUN
    # echo $DISKSYSTEMPATH
    
    echo "Creating mount point"
    sudo mkdir /datadrive

    echo "Finding UUID"
    sudo blkid
    UUID=$(sudo blkid |grep $DISKSYSTEMPATH | awk -F '[:"]' '{print $3}')
    echo $UUID
    echo "Updating FSTAB"
    FSTABUPDATE="UUID=${UUID}   /datadrive   xfs   defaults,nofail   1   2"
    echo $FSTABUPDATE
    echo "# minecraft" >> /etc/fstab
    echo $FSTABUPDATE >> /etc/fstab

    echo "Mounting drive for use"
    sudo mount $DISKSYSTEMPATH /datadrive
else
    echo "Entry in fstab exists."
fi

# Updating server install and Python Configuration
echo "[+] Performing Update to system"
# APT Update and Upgrade
sudo apt update && sudo apt -y upgrade
sudo apt install -y python2 && sudo update-alternatives --remove-all python && sudo update-alternatives --install /usr/bin/python python /usr/bin/python2 1

echo "[+] Installing Git Build-Essentials and OpenJDK"
# Installing required software
sudo apt install git build-essential -y
sudo apt install openjdk-17-jre-headless -y

echo "[+] Creating Minecraft User"
# Creating user to run Minecraft under
sudo useradd -r -m -U -d /datadrive/minecraft -s /bin/bash minecraft

echo "[+] Switching Minecraft User"
# Changing to minecraft user to install minecraft
sudo su minecraft
echo "User:" $(whoami)

echo "[+] Setting Minecraft User Environment"
# Creating directorys for Minecrat
mkdir -p /datadrive/minecraft/backups
mkdir -p /datadrive/minecraft/tools
mkdir -p /datadrive/minecraft/server

# Cloneing down MCRCON
git clone https://github.com/Tiiffi/mcrcon.git /datadrive/minecraft/tools/mcrcon
cd /datadrive/minecraft/tools/mcrcon
# Performing MCRCON build
gcc -std=gnu11 -pedantic -Wall -Wextra -O2 -s -o mcrcon mcrcon.c
# run ./mcrcon -v to test build if required
# Downloading Minecraft
wget https://launcher.mojang.com/v1/objects/125e5adf40c659fd3bce3e66e67a16bb49ecc1b9/server.jar -P /datadrive/minecraft/server
# Creating Backup Script
cat > /datadrive/minecraft/tools/backup.sh <<EOF
#!/bin/bash

function rcon {
/datadrive/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p $PASSWORD "\$1"
}

rcon "save-off"
rcon "save-all"
tar -cvpzf /datadrive/minecraft/backups/server-\$(date +%F-%H-%M).tar.gz /datadrive/minecraft/server
rcon "save-on"

## Delete older backups
find /datadrive/minecraft/backups/ -type f -mtime +31 -name '*.gz' -delete
EOF

# Creating and accepting EULA
cat > /datadrive/minecraft/server/eula.txt <<EOF
#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://account.mojang.com/documents/minecraft_eula).
#Sat Jan 01 10:54:04 UTC 2022
eula=true
EOF
# Creating Server Properties File
cat > /datadrive/minecraft/server/server.properties <<EOF
#Minecraft server properties
#Sat Jan 01 18:59:06 UTC 2022
enable-jmx-monitoring=false
rcon.port=25575
enable-command-block=false
gamemode=survival
enable-query=false
level-name=world
motd=A Minecraft Server
query.port=25565
pvp=true
difficulty=easy
network-compression-threshold=256
max-tick-time=60000
require-resource-pack=false
max-players=50
use-native-transport=true
online-mode=true
enable-status=true
allow-flight=false
broadcast-rcon-to-ops=true
view-distance=10
server-ip=
resource-pack-prompt=
allow-nether=true
server-port=25565
enable-rcon=true
sync-chunk-writes=true
op-permission-level=4
prevent-proxy-connections=false
hide-online-players=false
resource-pack=
entity-broadcast-range-percentage=100
simulation-distance=10
rcon.password=$PASSWORD
player-idle-timeout=0
force-gamemode=false
rate-limit=0
hardcore=false
white-list=false
broadcast-console-to-ops=true
spawn-npcs=true
spawn-animals=true
function-permission-level=2
text-filtering-config=
spawn-monsters=true
enforce-whitelist=false
resource-pack-sha1=
spawn-protection=16
max-world-size=29999984EOF
EOF

echo "[+] Create Systemd Unit File"
## Creating SystemD service
sudo cat > /etc/systemd/system/minecraft.service <<EOF
[Unit]
Description=Minecraft Server
After=network.target

[Service]
User=minecraft
Nice=1
KillMode=none
SuccessExitStatus=0 1
ProtectHome=true
ProtectSystem=full
PrivateDevices=true
NoNewPrivileges=true
WorkingDirectory=/datadrive/minecraft/server
ExecStart=/usr/bin/java -Xmx2048M -Xms2048M -jar server.jar nogui
ExecStop=/datadrive/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p $PASSWORD stop

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Create RCON Connection script"
## Creating connection to rcon
sudo cat > /datadrive/minecraft/tools/connect-mcrcon.sh <<EOF
#!/bin/bash

/datadrive/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p $PASSWORD

EOF

echo "[+] Creating file to record completed setup"
## Adding crontab rule
sudo touch /datadrive/minecraft/.mc.done

# Setting execute permissions backup.sh and ownership
chown -R minecraft:minecraft /datadrive/minecraft/
chmod +x /datadrive/minecraft/tools/backup.sh
chmod +x /datadrive/minecraft/tools/connect-mcrcon.sh

# Reloading Systemd configuration
sudo systemctl daemon-reload

echo "[+] Starting Minecraft"
## Starting Minecraft
sudo systemctl start minecraft

echo "[+] Creating Minecraft local firewall rules"
## Adding firewall rule
sudo ufw allow 25565/tcp

echo "[+] Creating cronjob for backup"
## Adding crontab rule
sudo crontab -l ; echo "0 22 * * * /datadrive/minecraft/tools/backup.sh" | crontab

echo "[+] Setup completed"
