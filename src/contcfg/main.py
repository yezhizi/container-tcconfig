import argparse
import sys
import os
import contcfg
from contcfg import ConNetServer, ConNetController, TCCmdWrapper
from contcfg.cmd_wrapper import split_raw_str_rate

__version__ = contcfg.__version__


def is_running_as_root():
    return os.geteuid() == 0


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
def start_server(args, run_with_sudo):
    min_rate, min_unit = split_raw_str_rate(args.min_rate)
    max_rate, max_unit = split_raw_str_rate(args.max_rate)
    if min_unit != max_unit:
        raise ValueError("Rate units do not match. Please provide same units.")
    server = ConNetServer(
        min_rate,
        max_rate,
        args.interval,
        rate_unit=min_unit,
        interval_unit="min",
        _server_socket_path=args.socket_path,
        _run_with_sudo=run_with_sudo,
    )
    server.start()


@handle_exception
def ctrl(args, run_with_sudo):
    sender = ConNetController(
        _socket_path=args.socket_path, _run_with_sudo=run_with_sudo
    )
    if args.ctrl_command == "add":
        sender.add_container(args.container)
    elif args.ctrl_command == "del":
        sender.del_container(args.container)
    elif args.ctrl_command == "add-all":
        sender.add_all_containers(args.prefix)
    sender.stop()


@handle_exception
def stop_server(args, run_with_sudo):
    sender = ConNetController(
        _socket_path=args.socket_path, _run_with_sudo=run_with_sudo
    )
    sender.stop_server()


@handle_exception
def run_cli(args, run_with_sudo):
    if args.cli_command == "set":
        TCCmdWrapper(run_with_sudo).set_bandwidth(
            args.container1, args.container2, args.bandwidth
        )
    elif args.cli_command == "clear":
        for c in args.containers:
            TCCmdWrapper(run_with_sudo).clear_one_container(c)


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

    subparsers = parser.add_subparsers(dest="command", help="Sub-command help")

    # Start server sub-command
    server_parser = subparsers.add_parser(
        "start-server", help="Start the server"
    )
    server_parser.add_argument("min_rate", type=str, help="Minimum rate")
    server_parser.add_argument("max_rate", type=str, help="Maximum rate")
    server_parser.add_argument("interval", type=int, help="Interval in minutes")

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

    # Cli of wrapper
    cli_parser = subparsers.add_parser("cli", help="Run the CLI")

    cli_subparsers = cli_parser.add_subparsers(
        dest="cli_command", help="CLI sub-command help"
    )
    # Set bandwidth sub-command
    sub_parser = cli_subparsers.add_parser("set", help="Set bandwidth")

    sub_parser.add_argument("container1", type=str, help="Container name or id")
    sub_parser.add_argument("container2", type=str, help="Container name or id")
    sub_parser.add_argument("bandwidth", type=str, help="Bandwidth limit")

    # Clear bandwidth sub-command
    sub_parser = cli_subparsers.add_parser("clear", help="Clear bandwidth")
    sub_parser.add_argument(
        "containers", type=str, nargs="+", help="Container name(s) or id(s)"
    )

    return parser


def main():
    parser = create_parser()
    args = parser.parse_args()
    run_with_sudo = is_running_as_root()
    if args.command == "start-server":
        start_server(args, run_with_sudo)
    elif args.command == "ctrl":
        ctrl(args, run_with_sudo)
    elif args.command == "stop-server":
        stop_server(args, run_with_sudo)
    elif args.command == "cli":
        run_cli(args, run_with_sudo)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
