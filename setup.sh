#!/bin/bash

##########################################################################
# Script Name: setup.sh
# Date : 08.03.2024
# Description: This script is made to setup a working deployment environment rapidly.
# What does it do?
# - Install all dependencies (Docker, Fail2Ban)
# - Create a new user
# - Create a new folder in /opt/ directory
# - Generate an SSH key pair for the user
# - Add the public key to the authorized keys
# - Update the SSH config to use a non-default port
# - Setup Fail2Ban with provided/default configuration file
# - Setup Cowrie honeypot with provided/default configuration file
# - Setup cron jobs with provided configuration file

#
# If we need to rapidly deploy the project on a new server, we can use this 
# script to achieve that.
#
# Usage: ./setup.sh -u <user> -f <folder> [options]
# Options:
#   -u <user>                   Specify the user
#   -f <folder>                 Specify the folder name created in /opt/ directory (e.g. /opt/<folder>)
#   -fc <fail2ban_config_file>   Specify the Fail2Ban config file (default: $FAIL2BAN_CONFIG_FILE)
#   -cc <cowrie_config_file>     Specify the Cowrie config file (default: $COWRIE_CONFIG_FILE)
#   -cd <cowrie_db_file>         Specify the Cowrie database file (default: $COWRIE_DB_FILE)
#   -cs <cowrie_ssh_port>        Specify the Cowrie SSH port (default: $COWRIE_SSH_PORT)
#   -s <ssh_port>               Specify the SSH port (default: $SSH_PORT)
#   -c <cron_file>              Specify the cron file (default: $CRON_FILE)
#   -d <debug>                  Enable debug mode (default: 0)
# Example:
#   ./setup.sh -u myadmin -f myproject  
#   ./setup.sh -u myadmin -f myproject -cs 22 -s 8888 // listen to port 22 for cowrie and 8888 for ssh 
# 
# Notes : 
#	- The script will always create the folder in /opt/ directory.
#   - The private key will be generated in /home/<user>/.ssh/id_rsa and should
#     be removed after copying it to a safer place (e.g. password manager).
#   - The cowrie honeypot will be recreated even if it already exists.
##########################################################################


# functions

usage() {
    echo "Usage: $0 -u <user> -f <folder> [options]"
    echo "Options:"
    echo "  -u <user>                   Specify the user"
    echo "  -f <folder>                 Specify the folder name created in /opt/ directory (e.g. /opt/<folder>)"
    echo "  -fc <fail2ban_config_file>   Specify the Fail2Ban config file (default: $FAIL2BAN_CONFIG_FILE)"
    echo "  -cc <cowrie_config_file>     Specify the Cowrie config file (default: $COWRIE_CONFIG_FILE)"
    echo "  -cd <cowrie_db_file>         Specify the Cowrie database file (default: $COWRIE_DB_FILE)"
    echo "  -cs <cowrie_ssh_port>        Specify the Cowrie SSH port (default: $COWRIE_SSH_PORT)"
    echo "  -s <ssh_port>               Specify the SSH port (default: $SSH_PORT)"
    echo "  -c <cron_file>              Specify the cron file (default: $CRON_FILE)"
    echo "  -d <debug>                  Enable debug mode (default: 0)" # Not implemented yet
    exit 1
}

warning() {
    echo -e "${O}[⚠ WARNING]${NC} You might get disconnected from ssh when using this script."
    echo -e "${O}[⚠ WARNING]${NC} Make sure the provided ssh port($SSH_PORT) is open in the firewall.\n"

	read -p "Press enter to continue..."
}

todo(){
    echo -e "\n${O}[TODO]${NC} After running this script, you should do the following:"
    echo -e "${O}2.${NC} Copy the private key from ${P}/home/$USER/.ssh/id_rsa${NC} to a safer place and remove it from the server."
    echo -e "${O}3.${NC} Test logging in with ${P}$USER${NC} using the new ssh port ${P}$SSH_PORT${NC}."
    echo -e "${O}4.${NC} Test the cowrie honeypot by trying to login on port ${P}$COWRIE_SSH_PORT${NC}."
    echo -e "${O}5.${NC} Test fail2ban by trying to login to the server multiple times. \n"
}

# args
USER=""
FOLDER=""
FAIL2BAN_CONFIG_FILE="./fail2ban.conf"
COWRIE_CONFIG_FILE="./cowrie.conf"
COWRIE_DB_FILE="./cowrie.db"
COWRIE_SSH_PORT="22"
SSH_PORT="1234"
CRON_FILE="./cron.conf"
DEBUG=0

# constants
SSH_CONFIG_FILE=/etc/ssh/sshd_config
R='\033[31m'
G='\033[32m'
B='\033[36m'
O='\033[33m'
P='\033[35m'
NC='\033[0m'


# warning
warning

# check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${R}[ERROR]${NC} This script must be run as root." 1>&2
    exit 1
fi


# parse args
while getopts ":u:f:fc:cc:cd:cs:s:c:" opt; do
  case ${opt} in
    u )
      USER=$OPTARG
      ;;
    f )
      FOLDER=$OPTARG	
      ;;
    fc )
      FAIL2BAN_CONFIG_FILE=$OPTARG	
      ;;
    cc )
      COWRIE_CONFIG_FILE=$OPTARG	
      ;;
    cd )
      COWRIE_DB_FILE=$OPTARG
      ;;
    cs )
      COWRIE_SSH_PORT=$OPTARG	
      ;;
    s )
      SSH_PORT=$OPTARG
      ;;
    c )
      CRON_FILE=$OPTARG
      ;;
    d )
      DEBUG=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      usage
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      usage
      ;;
  esac
done

# check if required args are provided
if [ -z "$USER" ] || [ -z "$FOLDER" ]; then
    echo "Both -u (user) and -f (folder) options are required."
    usage
fi


echo -e "${B}[SETUP]${NC} Starting the setup process..."

# [APT] intsall all dependencies

# [DOCKER] install docker if not already installed
if ! command -v docker &> /dev/null; then
    echo -e "${B}[DOCKER]${NC} Package not found, installing..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo -e "${G}[DOCKER]${NC} Installation completed."
else
    echo -e "${O}[DOCKER]${NC} Package is already installed, proceeding..."
fi

if ! command -v fail2ban-client &> /dev/null; then
    echo -e "${B}[FAIL2BAN]${NC} Package not found, installing..."
    apt-get install -y fail2ban
    echo -e "${G}[FAIL2BAN]${NC} Installation completed."
else
    echo -e "${O}[FAIL2BAN]${NC} Package is already installed, proceeding..."
fi

# [USER] prompt for the user's password
echo -e "${B}[PASSWORD]${NC} Enter the password for the user $USER"
read -s PASSWORD
echo -e "${B}[PASSWORD]${NC} Confirm the password for the user $USER"
read -s PASSWORD_CONFIRM

# check if the passwords match
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo -e "${R}[PASSWORD]${NC} Passwords do not match, exiting..."
    exit 1
fi

# create the user if it doesn't already exist
if ! id -u $USER &> /dev/null; then
    echo -e "${B}[USER]${NC} Creating user $USER..."
    useradd -m -p $(openssl passwd -1 $PASSWORD) $USER -s /bin/bash
else
    echo -e "${O}[USER]${NC} User $USER already exists, proceeding..."
fi


# create the docker group if it doesn't already exist
if ! getent group docker > /dev/null; then
    groupadd docker
    echo -e "${B}[USER]${NC} *docker* group created."
else
    echo -e "${O}[USER]${NC} *docker* group already exists, proceeding..."
fi


# add the user to the docker group if not already added
if ! groups $USER | grep &> /dev/null "\bdocker\b"; then
    usermod -aG docker $USER
    echo -e "${G}[USER]${NC} $USER added to *docker* group."
else
    echo -e "${O}[USER]${NC} $USER is already a member of *docker* group, proceeding..."
fi

# create the folder if it doesn't already exist
mkdir -p /opt/$FOLDER

# give the user ownership of the folder
chown $USER:$USER /opt/$FOLDER

# generate the ssh key pair if it doesn't already exist
if [ ! -f /home/$USER/.ssh/id_rsa ]; then
    sudo -u $USER ssh-keygen -t rsa -b 4096 -f /home/$USER/.ssh/id_rsa -N ""
    echo -e "${G}[USER]${NC} SSH key pair generated."
else
    echo -e "${O}[USER]${NC} SSH key pair already exists, proceeding..."
fi

# add the public key to the authorized keys
if [ ! -f /home/$USER/.ssh/authorized_keys ]; then
    sudo -u $USER touch /home/$USER/.ssh/authorized_keys
    sudo -u $USER chmod 600 /home/$USER/.ssh/authorized_keys
    echo -e "${G}[USER]${NC} *authorized_keys* file created."
else
    echo -e "${O}[USER]${NC} *authorized_keys* file already exists, proceeding..."
fi

# append the public key to the authorized keys
cat /home/$USER/.ssh/id_rsa.pub >> /home/$USER/.ssh/authorized_keys


# [SSH] update ssh config to use a non-default port
if grep -q "^#Port 22$" "$SSH_CONFIG_FILE"; then
    sed -i "s/^#Port 22$/Port $SSH_PORT/" "$SSH_CONFIG_FILE"
    systemctl restart sshd
    echo -e "${G}[SSH]${NC} SSH server port changed to $SSH_PORT"
elif grep -q "^Port [0-9]" "$SSH_CONFIG_FILE"; then
    sed -i "s/^Port [0-9]*/Port $SSH_PORT/" "$SSH_CONFIG_FILE"
    systemctl restart sshd
    echo -e "${G}[SSH]${NC} SSH server port changed to $SSH_PORT"
fi


# [FAIL2BAN] setup Fail2Ban with provided configuration file
if [ -f "$FAIL2BAN_CONFIG_FILE" ]; then
    echo -e "${B}[FAIL2BAN]${NC} Setting up Fail2Ban..."
    # replace the #SSH_PORT placeholder with the actual port
    FAIL2BAN_CONFIG_UPDATED=$(sed "s/#SSH_PORT/$SSH_PORT/" "$FAIL2BAN_CONFIG_FILE")
    echo "$FAIL2BAN_CONFIG_UPDATED" > /etc/fail2ban/jail.local
    systemctl restart fail2ban
    echo -e "${G}[FAIL2BAN]${NC} Fail2Ban setup completed."
else
    echo -e "${R}[FAIL2BAN]${NC} Configuration file not found, proceeding..."
fi


# [COWRIE] setup cowrie honeypot with provided configuration file
if [ -f "$COWRIE_CONFIG_FILE" ] && [ -f "$COWRIE_DB_FILE" ]; then
    echo -e "${B}[COWRIE]${NC} Setting up Cowrie honeypot..."
    docker rm -f cowrie 2>/dev/null
    docker run -d --name cowrie -v "$COWRIE_CONFIG_FILE":/cowrie/cowrie-git/etc/cowrie.cfg -v "$COWRIE_DB_FILE":/cowrie/cowrie-git/etc/userdb.txt -p "$COWRIE_SSH_PORT":2222 cowrie/cowrie
    echo -e "${G}[COWRIE]${NC} Cowrie honeypot setup completed."
else
    echo -e "${R}[COWRIE]${NC} Configuration file not found, proceeding..."
fi


# [CRON] setup cron jobs with provided configuration file
if [ -f "$CRON_FILE" ]; then
    echo -e "${B}[CRON]${NC} Setting up cron jobs..."
    crontab -u $USER $CRON_FILE
    echo -e "${G}[CRON]${NC} Cron jobs setup completed."
else
    echo -e "${R}[CRON]${NC} Configuration file not found, proceeding..."
fi


echo -e "${G}[SETUP]${NC} Setup process completed."

#todo after setup
todo