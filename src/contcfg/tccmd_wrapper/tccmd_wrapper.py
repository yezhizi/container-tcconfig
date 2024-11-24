# -*- coding: utf-8 -*-

import subprocess

from .base import check_scripts, get_script


class ContainerNotFoundError(Exception):
    pass


class TCCmdWrapper:
    """tc command wrapper for setting bandwidth limits between docker containers.
    This class is a singleton, so only one instance will be created.
    Args:
        - run_with_sudo (bool, optional) : run all commands with sudo. Default is False.
    """

    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(TCCmdWrapper, cls).__new__(cls)
        return cls._instance

    def __init__(self, run_with_sudo: bool = False):
        if not hasattr(self, "_initialized"):
            check_scripts()  # check if all scripts are present
            self._exec_script = get_script("docker_tcconfig.sh")
            self._initialized = True
            self._rate_units = [
                "bit",
                "kbit",
                "mbit",
                "gbit",
                "tbit",
                "bps",
                "kbps",
                "mbps",
                "gbps",
                "tbps",
            ]
        self._run_with_sudo = run_with_sudo

    def set_bandwidth(
        self,
        container1: str,
        container2: str,
        bandwidth: int,
        bandwidth_unit: str = "mbit",
        _run_with_sudo: bool = None,
    ):
        """Set bandwidth limit between two containers.
        Args:
            - container1 (str) : container name or id
            - container2 (str) : container name or id
            - bandwidth (int) : bandwidth limit
            - bandwidth_unit (str, optional) : bandwidth unit. Default is "mbit".
            - _run_with_sudo (bool, optional) : run command with sudo. Default is None.
        """

        self._check_container(container1)
        self._check_container(container2)
        self._check_bandwidth(bandwidth, bandwidth_unit)
        cmd = (
            f"{self._exec_script} {container1} {container2} {bandwidth}{bandwidth_unit}"
        )
        self._exec(cmd, _run_with_sudo)

    def _exec(self, cmd: str, _run_with_sudo: bool = None, _bash: bool = True):
        """Execute a command.

        Args:
            cmd (str): command to execute
            _run_with_sudo (bool, optional): run command with sudo. Defaults to None.
            _bash (bool, optional): run command with bash. Defaults to True.
        """

        if _bash and not cmd.strip().startswith("bash"):
            cmd = f"bash {cmd}"
        if _run_with_sudo or self._run_with_sudo:
            cmd = f"sudo {cmd}"
        subprocess.run(
            cmd,
            shell=True,
            check=True,
            stdout=subprocess.DEVNULL,
        )

    def _check_container(self, container: str, _run_with_sudo: bool = None):
        """Check if container exists.

        Args:
            container (str): container name or id
            _run_with_sudo (bool, optional): run command with sudo. Defaults to None.

        Raises:
            e: subprocess.CalledProcessError if container not found
        """

        cmd = f"docker inspect {container}"
        try:
            self._exec(cmd, _run_with_sudo, _bash=False)
        except subprocess.CalledProcessError as e:
            if not _run_with_sudo and not self._run_with_sudo:
                raise ContainerNotFoundError(
                    f"Container {container} not found. "
                    f"Try to set _run_with_sudo=True."
                ) from e
            raise e

    def _check_bandwidth(self, bandwidth: int, bandwidth_unit: str):
        if bandwidth_unit not in self._rate_units:
            raise ValueError(f"Invalid bandwidth unit {bandwidth_unit}")
        if bandwidth < 0:
            raise ValueError(f"Invalid bandwidth {bandwidth}")
