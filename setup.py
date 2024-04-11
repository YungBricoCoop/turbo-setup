import os
import sys
import typer
from typing_extensions import Annotated
from rich import print


def print_error(category, message: str, exit_after=True):
    print(f"[red][{category}][/] {message}")
    if exit_after:
        sys.exit(1)


def print_warning(category, message: str):
    print(f"[yellow][{category}][/] {message}")


def print_info(category, message: str):
    print(f"[purple][{category}][/] {message}")


def check_root():
    if os.getuid() == 0:
        return True

    print_error("PERMISSION", "Please run this script as root")


def main(
    user: Annotated[str, typer.Option(help="User used to deploy the app")],
):
    print_info("INFO", "Starting setup...")
    check_root()


if __name__ == "__main__":
    typer.run(main)
