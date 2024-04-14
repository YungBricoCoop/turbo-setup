import os
import sys
import typer
from random import randint
from typing_extensions import Annotated
from rich import print


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

def get_random_ssh_port():
    return randint(1024, 10000)


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


if __name__ == "__main__":
    typer.run(main)
