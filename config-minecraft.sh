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

# Variables
PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)

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
sudo useradd -r -m -U -d /mnt/minecraft -s /bin/bash minecraft

echo "[+] Switching Minecraft User"
# Changing to minecraft user to install minecraft
sudo su minecraft
echo "User:" $(whoami)

echo "[+] Setting Minecraft User Environment"
# Creating directorys for Minecrat
mkdir -p /mnt/minecraft/backups
mkdir -p /mnt/minecraft/tools
mkdir -p /mnt/minecraft/server

# Cloneing down MCRCON
git clone https://github.com/Tiiffi/mcrcon.git /mnt/minecraft/tools/mcrcon
cd /mnt/minecraft/tools/mcrcon
# Performing MCRCON build
gcc -std=gnu11 -pedantic -Wall -Wextra -O2 -s -o mcrcon mcrcon.c
# run ./mcrcon -v to test build if required
# Downloading Minecraft
wget https://launcher.mojang.com/v1/objects/125e5adf40c659fd3bce3e66e67a16bb49ecc1b9/server.jar -P /mnt/minecraft/server
# Creating Backup Script
cat > /mnt/minecraft/tools/backup1.sh <<EOF
#!/bin/bash

function rcon {
/mnt/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p $PASSWORD "$1"
}

rcon "save-off"
rcon "save-all"
tar -cvpzf /mnt/minecraft/backups/server-$(date +%F-%H-%M).tar.gz /mnt/minecraft/server
rcon "save-on"

## Delete older backups
find /mnt/minecraft/backups/ -type f -mtime +31 -name '*.gz' -delete
EOF
# Setting execute permissions backup.sh
chown -R minecraft:minecraft /mnt/minecraft/
chmod +x /mnt/minecraft/tools/backup.sh
# Creating and accepting EULA
cat > /mnt/minecraft/server/eula.txt <<EOF
#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://account.mojang.com/documents/minecraft_eula).
#Sat Jan 01 10:54:04 UTC 2022
eula=true
EOF
# Creating Server Properties File
cat > /mnt/minecraft/server/server.properties <<EOF
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
sudo cat >/etc/systemd/system/minecraft.service <<EOF
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
WorkingDirectory=/mnt/minecraft/server
ExecStart=/usr/bin/java -Xmx2048M -Xms2048M -jar server.jar nogui
ExecStop=/mnt/minecraft/tools/mcrcon/mcrcon -H 127.0.0.1 -P 25575 -p $PASSWORD stop

[Install]
WantedBy=multi-user.target
EOF
# Reloading Systemd configuration
sudo systemctl daemon-reload

echo "[+] Starting Minecraft"
## Starting Minecraft
sudo systemctl start minecraft

echo "[+] Creating Minecraft local firewall rules"
## Adding firewall rule
sudo ufw allow 25565/tcp

echo "[+] Creating cronjob for backup"
## Adding firewall rule
sudo (crontab -l ; echo "0 23 * * * /mnt/minecraft/tools/backup.sh") | crontab

echo "[+] Setup completed"
