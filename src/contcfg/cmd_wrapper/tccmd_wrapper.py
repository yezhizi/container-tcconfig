from .base import check_scripts, get_script, singleton, exec_cmd
from .tc_base import TC_BANDWIDTH_UNITS, split_raw_str_rate
from .dockercmd_wrapper import DockerCmdWrapper
from .exception import RateValueError

from typing import Union


@singleton
class TCCmdWrapper:
    """tc command wrapper for setting bandwidth
    limits between docker containers.
    This class is a singleton,
    so only one instance will be created.
    Args:
        - run_with_sudo (bool, optional) : run all commands with sudo.
        Default is False.
    """

    def __init__(self, run_with_sudo: bool = False):
        if not hasattr(self, "_initialized"):
            check_scripts()  # check if all scripts are present
            self._exec_script = get_script("docker_tcconfig.sh")
            self._initialized = True

        self._run_with_sudo = run_with_sudo

    def set_bandwidth(
        self,
        container1: str,
        container2: str,
        bandwidth: Union[int, str],
        bandwidth_unit: str = "mbit",
        _run_with_sudo: bool = False,
    ):
        """Set bandwidth limit between two containers.
        Args:
            - container1 (str) : container name or id
            - container2 (str) : container name or id
            - bandwidth (int) : bandwidth limit
            - bandwidth_unit (str, optional) : bandwidth unit.
            Default is "mbit".
            - _run_with_sudo (bool, optional) : run command with sudo.
            Default is None.
        """
        if isinstance(bandwidth, str):
            bandwidth, bandwidth_unit = split_raw_str_rate(bandwidth)
        run_with_sudo = self._run_with_sudo or _run_with_sudo
        _check_container = DockerCmdWrapper(
            run_with_sudo
        ).check_container  # function call to check if container exists

        _check_container(container1)
        _check_container(container2)
        self._check_bandwidth(bandwidth, bandwidth_unit)
        cmd = (
            f"{self._exec_script} {container1} {container2} "
            + f"{bandwidth}{bandwidth_unit}"
        )
        exec_cmd(cmd, run_with_sudo)

    def init_htb(self, container: str, _run_with_sudo: bool = False):
        """Initialize htb qdisc for container.
        Args:
            - container (str) : container name or id
            - _run_with_sudo (bool, optional) : run command with sudo.
            Default is None.
        """
        run_with_sudo = self._run_with_sudo or _run_with_sudo
        DockerCmdWrapper(run_with_sudo).check_container(container)
        cmd = f"{self._exec_script} -init {container}"
        exec_cmd(cmd, run_with_sudo)

    def clear_one_container(self, container: str, _run_with_sudo: bool = False):
        """Clear bandwidth limit for one container.
        Args:
            - container (str) : container name or id
            - _run_with_sudo (bool, optional) : run command with sudo.
            Default is None.
        """
        run_with_sudo = self._run_with_sudo or _run_with_sudo
        if DockerCmdWrapper(run_with_sudo).is_container_exist(container):
            cmd = f"{self._exec_script} -c {container}"
            exec_cmd(cmd, run_with_sudo)

    def _check_bandwidth(self, bandwidth: int, bandwidth_unit: str):
        if bandwidth_unit not in TC_BANDWIDTH_UNITS:
            raise RateValueError(f"Invalid bandwidth unit {bandwidth_unit}")
        if bandwidth < 0:
            raise RateValueError(f"Invalid bandwidth {bandwidth}")
