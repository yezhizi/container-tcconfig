import argparse
import sys
import contcfg
from contcfg import ConNetServer, ConNetController

__version__ = contcfg.__version__


def handle_exception(func):
    """Decorator to handle exceptions for server operations."""

    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except ConnectionRefusedError:
            print("Connection refused. Server may not be running.")
        except Exception as e:
            print(f"Error: {e}")
            sys.exit(1)

    return wrapper


@handle_exception
def start_server(args):
    server = ConNetServer(
        args.min_rate,
        args.max_rate,
        args.interval,
        rate_unit="mbit",
        interval_unit="min",
        _run_with_sudo=args.run_with_sudo,
    )
    server.start()


@handle_exception
def ctrl(args):
    sender = ConNetController(
        _socket_path=args.socket_path, _run_with_sudo=args.run_with_sudo
    )
    if args.ctrl_command == "add":
        sender.add_container(args.container)
    elif args.ctrl_command == "del":
        sender.del_container(args.container)
    elif args.ctrl_command == "add-all":
        sender.add_all_containers(args.prefix)
    sender.stop()


@handle_exception
def stop_server(args):
    sender = ConNetController(
        _socket_path=args.socket_path, _run_with_sudo=args.run_with_sudo
    )
    sender.stop_server()


def create_parser():
    """Creates and returns the argument parser."""
    parser = argparse.ArgumentParser(description="Container Network Controller")
    parser.add_argument(
        "--version", action="version", version="%(prog)s " + __version__
    )
    parser.add_argument(
        "--socket-path",
        type=str,
        default="/tmp/contcfg.sock",
        help="Path to the Unix socket",
    )
    parser.add_argument(
        "--run-with-sudo",
        action="store_true",
        help="Run all commands with sudo",
    )

    subparsers = parser.add_subparsers(dest="command", help="Sub-command help")

    # Start server sub-command
    server_parser = subparsers.add_parser(
        "start-server", help="Start the server"
    )
    server_parser.add_argument(
        "min_rate", type=int, help="Minimum rate in mbit"
    )
    server_parser.add_argument(
        "max_rate", type=int, help="Maximum rate in mbit"
    )
    server_parser.add_argument("interval", type=int, help="Interval in seconds")

    # Control server sub-command
    ctrl_parser = subparsers.add_parser("ctrl", help="Control the server")
    ctrl_subparsers = ctrl_parser.add_subparsers(
        dest="ctrl_command", help="Control sub-command help"
    )
    # Add and delete container sub-commands
    for action in ["add", "del"]:
        sub_parser = ctrl_subparsers.add_parser(
            action, help=f"{action.capitalize()} container"
        )
        sub_parser.add_argument(
            "container", type=str, help="Container name or id"
        )
    # Add all containers sub-command
    sub_parser = ctrl_subparsers.add_parser(
        "add-all", help="Add all containers"
    )
    sub_parser.add_argument("prefix", type=str, help="Container name prefix")

    # Stop server sub-command
    subparsers.add_parser("stop-server", help="Stop the server")

    return parser


def main():
    parser = create_parser()
    args = parser.parse_args()

    if args.command == "start-server":
        start_server(args)
    elif args.command == "ctrl":
        ctrl(args)
    elif args.command == "stop-server":
        stop_server(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
