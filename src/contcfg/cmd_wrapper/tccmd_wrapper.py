# -*- coding: utf-8 -*-

from .base import check_scripts, get_script, singleton, exec_cmd
from .dockercmd_wrapper import DockerCmdWrapper
from .exception import RateValueError


@singleton
class TCCmdWrapper:
    """tc command wrapper for setting bandwidth limits between docker containers.
    This class is a singleton, so only one instance will be created.
    Args:
        - run_with_sudo (bool, optional) : run all commands with sudo. Default is False.
    """

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
        run_with_sudo = self._run_with_sudo or _run_with_sudo
        _check_container = DockerCmdWrapper(
            run_with_sudo
        ).check_container  # function call to check if container exists

        _check_container(container1)
        _check_container(container2)
        self._check_bandwidth(bandwidth, bandwidth_unit)
        cmd = (
            f"{self._exec_script} {container1} {container2} {bandwidth}{bandwidth_unit}"
        )
        exec_cmd(cmd, run_with_sudo)

    def _check_bandwidth(self, bandwidth: int, bandwidth_unit: str):
        if bandwidth_unit not in self._rate_units:
            raise RateValueError(f"Invalid bandwidth unit {bandwidth_unit}")
        if bandwidth < 0:
            raise RateValueError(f"Invalid bandwidth {bandwidth}")
