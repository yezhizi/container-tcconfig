import subprocess
from typing import Optional

from .base import singleton, exec_cmd
from .exception import ContainerNotFoundError


@singleton
class DockerCmdWrapper:
    """docker command wrapper for managing docker containers.
    This class is a singleton, so only one instance will be created.
    Args:
        - run_with_sudo (bool, optional) : run all commands with sudo.
        Default is False.
    """

    def __init__(self, run_with_sudo: bool = True):
        if not hasattr(self, "_initialized"):
            self._initialized = True
        self._run_with_sudo = run_with_sudo

    def run_cmd(self, cmd: str):
        """Run docker command.
        Args:
            - cmd (str) : docker command to run
        """
        if self._run_with_sudo:
            cmd = f"sudo {cmd}"
        return subprocess.run(cmd, shell=True, check=True)

    def check_container(self, container: str):
        """Check if container exists.

        Args:
            container (str): container name or id
            _run_with_sudo (bool, optional): run command with sudo.
            Defaults to None.

        Raises:
            e: subprocess.CalledProcessError if container not found
        """

        cmd = f"docker inspect {container}"
        try:
            exec_cmd(cmd, self._run_with_sudo, bash=False)
        except subprocess.CalledProcessError as e:
            if not self._run_with_sudo:
                raise ContainerNotFoundError(
                    f"Container {container} not found. "
                    f"Try to set _run_with_sudo=True."
                ) from e
            raise ContainerNotFoundError(
                f"Container {container} not found."
            ) from e

    def is_container_exist(self, container: str) -> bool:
        """Check if container exists.

        Args:
            container (str): container name or id

        Returns:
            bool: True if container exists, False otherwise
        """
        cmd = f"docker inspect {container}"
        try:
            exec_cmd(cmd, self._run_with_sudo, bash=False)
        except subprocess.CalledProcessError:
            return False
        return True

    def get_container(self, prefix: Optional[str] = None) -> list[str]:
        """Get all containers with given prefix.

        Args:
            - prefix (str, optional): container name prefix. Default is None.
        """
        cmd = "docker ps --format '{{.Names}}'"
        if prefix:
            cmd += f" | grep {prefix}"
        return (
            exec_cmd(cmd, self._run_with_sudo, bash=False, stdout=True)
            .stdout.decode()
            .splitlines()
        )
