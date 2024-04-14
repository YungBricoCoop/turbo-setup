import os
import pwd
import grp
import sys
import typer
from random import randint
from typing_extensions import Annotated
from rich import print
import subprocess
import getpass

GROUP = "docker"
FAIL2BAN_CONFIG_FILE = "./fail2ban.conf"
COWRIE_CONFIG_FILE = "./cowrie.conf"
COWRIE_DB_FILE = "./cowrie.db"
COWRIE_SSH_PORT = "22"
CRON_FILE = "./cron.conf"
DEBUG = False


def print_error(category, message: str, debug: bool = False, exit_after=True) -> None:
    if debug:
        category = f"{category} (DEBUG)"
    print(f"[red][{category}][/] {message}")
    if exit_after:
        sys.exit(1)


def print_warning(category, message: str, debug: bool = False) -> None:
    if debug:
        category = f"{category} (DEBUG)"
    print(f"[yellow][{category}][/] {message}")


def print_info(category, message: str, debug: bool = False) -> None:
    if debug:
        category = f"{category} (DEBUG)"
    print(f"[purple][{category}][/] {message}")


def check_root():
    if os.getuid() == 0:
        return True
    print_error("REQUIREMENTS", "Please run this script as root")

def check_os():
    if sys.platform.startswith("linux"): 
        if 'ubuntu' not in os.popen('cat /etc/os-release').read().lower():
            print_warning("REQUIREMENTS", "This script was tested on Ubuntu 22.04. It may not work on other OS versions.")
        
        return True

    print_error("REQUIREMENTS", "This script only works on [b]Linux[/]")

# -------------------- [UTILS] --------------------

def get_random_ssh_port():
    return randint(1024, 10000)

def create_group(group: str):
    try:
        grp.getgrnam(group)
        print_warning("GROUP", f"{group} already exists, proceeding...")
    except KeyError:
        os.system(f"sudo groupadd {group}")
        print_info("GROUP", f"{group} created.")

def create_user(user: str, group: str):
    try:
        pwd.getpwnam(user)
        print_warning("USER", f"{user} already exists, proceeding...")
    except KeyError:
        os.system(f"sudo useradd -m {user} -s /bin/bash")
        os.system(f"sudo usermod -aG {group} {user}")
        
        print_info("USER", f"{user} created.")

def create_folder(folder: str):
    try:
        os.makedirs(folder)
        print_info("FOLDER", f"{folder} created.")
    except FileExistsError:
        print_warning("FOLDER", f"{folder} already exists, proceeding...")

def chown_folder(folder: str, user: str):
    os.system(f"sudo chown {user}:{user} {folder}")
    print_info("FOLDER", f"{folder} permissions set to {user}")

def chmod_file(file: str, mode: str):
    os.system(f"sudo chmod {mode} {file}")
    print_info("FILE", f"{file} permissions set to {mode}")

def create_symlink(source: str, destination: str):
    try:
        os.symlink(source, destination)
        print_info("SYMLINK", f"{source} symlinked to {destination}")
    except FileExistsError:
        print_warning("SYMLINK", f"{destination} already exists, proceeding...")

def create_deployment_folder(folder: str, user: str):
    destination = f"/opt/{folder}"
    home_destination = f"/home/{user}/{folder}"
    create_folder(destination)
    create_symlink(destination, home_destination)
    chown_folder(destination, user)
    chown_folder(home_destination, user)
    
def create_file(file: str):
    try:
        os.system(f"touch {file}")
        print_info("FILE", f"{file} created.")
    except FileExistsError:
        print_warning("FILE", f"{file} already exists, proceeding...")

def generate_ssh_key_pair(user: str):
    ssh_key_path = f"/home/{user}/.ssh/id_rsa"
    ssh_pub_key_path = f"{ssh_key_path}.pub"
    if not os.path.isfile(ssh_key_path):
        os.system(f"sudo -u {user} ssh-keygen -t rsa -b 4096 -f {ssh_key_path} -N ''")
        print_info("USER", "SSH key pair generated.")
    else:
        print_warning("USER", "SSH key pair already exists, proceeding...")

    authorized_keys_path = f"/home/{user}/.ssh/authorized_keys"
    if not os.path.isfile(authorized_keys_path):
        create_file(authorized_keys_path)
        chmod_file(authorized_keys_path, "600")
        print_info("USER", "*authorized_keys* file created.")
    else:
        print_warning("USER", "*authorized_keys* file already exists, proceeding...")

    with open(ssh_pub_key_path, "r") as ssh_pub_key:
        with open(authorized_keys_path, "a") as authorized_keys:
            authorized_keys.write(ssh_pub_key.read())

def update_ssh_config(ssh_port: str):
    ssh_config_file = "/etc/ssh/sshd_config"
    default_ssh_port = "22"
    current_port = "22"

    if not os.path.isfile(ssh_config_file):
        print_error("SSH", f"SSH config file not found: {ssh_config_file}")
    
    with open(ssh_config_file, "r") as ssh_config:
        lines = ssh_config.readlines()
        for i, line in enumerate(lines):
            if line.lower().startswith("#port 22"):
                lines[i] = f"Port {ssh_port}\n"
                break
            
            elif line.lower().startswith("port "):
                current_port = line.split(" ")[1].strip()
                break
    
    if current_port == default_ssh_port:
        with open(ssh_config_file, "w") as ssh_config:
            ssh_config.writelines(lines)
            print_info("SSH", f"SSH server port changed to {ssh_port}")
    
        os.system("sudo systemctl restart sshd")
        print_info("SSH", "SSH server restarted.")
    else:
        print_warning("SSH", f"Port is already set to {current_port}, proceeding...")

def main(
    user: Annotated[str, typer.Argument(help="User used to deploy the app")],
    folder: Annotated[
        str, typer.Argument(help="Folder name created in /opt/ directory")
    ],
    ssh_port: Annotated[
        str, typer.Option(help="SSH port", default_factory=get_random_ssh_port)
    ],
    fail2ban_config_file: Annotated[
        str, typer.Option(help="Fail2Ban config file")
    ] = FAIL2BAN_CONFIG_FILE,
    cowrie_config_file: Annotated[
        str, typer.Option(help="Cowrie config file")
    ] = COWRIE_CONFIG_FILE,
    cowrie_db_file: Annotated[
        str, typer.Option(help="Cowrie database file")
    ] = COWRIE_DB_FILE,
    cowrie_ssh_port: Annotated[
        str, typer.Option(help="Cowrie SSH port")
    ] = COWRIE_SSH_PORT,
    cron_file: Annotated[str, typer.Option(help="Cron file")] = CRON_FILE,
    debug: Annotated[bool, typer.Option(help="Enable debug mode")] = DEBUG,
):
    print_info("INFO", "Starting setup...")
    
    check_os()
    check_root()

    create_group(GROUP)
    create_user(user, GROUP)

    create_deployment_folder(folder, user)

    generate_ssh_key_pair(user)
    update_ssh_config(ssh_port)


if __name__ == "__main__":
    typer.run(main)
