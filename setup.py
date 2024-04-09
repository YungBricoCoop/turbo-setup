import typer
from typing_extensions import Annotated


def main(
    user: Annotated[str, typer.Option(help="User used to deploy the app")],
):
    print("Starting setup...")
    print(f"User: {user}")
    #TODO: Implement all the same steps as the setup.sh script

if __name__ == "__main__":
    typer.run(main)