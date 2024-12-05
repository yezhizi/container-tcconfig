from .comm import NetCtrlCommClient
from .msg import CtrlMsg, CtrlAction
from ..cmd_wrapper import DockerCmdWrapper


class ConNetController:
    """Container network controller message sender.
    This class is used to send control messages
    to the network controller.
    Args:
        - socket_path (str) : path to the unix socket
    """

    def __init__(
        self,
        prefix: str = "",
        *,
        _socket_path: str = "/tmp/contcfg.sock",
        _run_with_sudo: bool = False,
    ):
        self._socket_path = _socket_path
        self._client = NetCtrlCommClient(self._socket_path)
        self._run_with_sudo = _run_with_sudo
        self._prefix = prefix
        self._containers: list[str] = []

    def add_container(self, container: str):
        """Add container to the network controller.
        Args:
            - container (str) : container name or id
        """
        if container in self._containers:
            raise ValueError(f"Container {container} already exists.")
        try:
            DockerCmdWrapper(self._run_with_sudo).check_container(container)
        except Exception as e:
            raise e
        self._client.send(CtrlMsg(CtrlAction.ADD_CONTAINER, container))
        self._containers.append(container)

    def del_container(self, container: str):
        """Delete container from the network controller.
        Args:
            - container (str) : container name or id
        """
        if container not in self._containers:
            raise ValueError(f"Container {container} not found.")
        self._client.send(CtrlMsg(CtrlAction.DEL_CONTAINER, container))
        self._containers.remove(container)

    def find_all_containers(self, prefix: str = ""):
        """Find all containers with given prefix."""
        prefix = prefix if prefix else self._prefix
        if not prefix:
            raise ValueError("Prefix is not set.")

        containers = DockerCmdWrapper(self._run_with_sudo).get_container(prefix)
        return containers

    def add_all_containers(self, prefix: str):
        """Add all containers with given prefix."""
        containers = self.find_all_containers(prefix)
        for container in containers:
            if container not in self._containers:
                self.add_container(container)

    def stop_server(self):
        """Stop the server."""
        self._client.stop_server()

    def stop(self):
        """Stop the client."""
        self._client.stop()
