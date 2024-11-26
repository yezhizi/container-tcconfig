import random
import asyncio
from asyncio import Queue
import logging
from typing import Optional, List, Tuple, Dict


from ..cmd_wrapper import (
    TCCmdWrapper,
    DockerCmdWrapper,
    RateValueError,
    ContainerNotFoundError,
)
from .msg import CtrlMsg, CtrlAction
from .comm import NetCtrlCommServer

__all__ = ["ConNetServer"]

logging.basicConfig(
    level=logging.INFO, format="[%(asctime)s][%(levelname)s]%(message)s"
)


def all_pairs_iter(lst: list, paticular=None):
    """Generate all pairs from a list. If paticular is given,
    generate pairs including paticular."""
    if paticular:
        for i in range(len(lst)):
            if lst[i] != paticular:
                yield lst[i], paticular
    else:
        for i in range(len(lst)):
            for j in range(i + 1, len(lst)):
                yield lst[i], lst[j]


class ConNetServer:
    """Container network controller class.
    This class is used to control network bandwidth
    between docker containers.
    Args:
        - min_rate (int) : minimum rate in mbit
        - max_rate (int) : maximum rate in mbit
        - interval (int) : interval in seconds
        - prefix (str, optional) : container name prefix.
        - _server_socket_path (str, optional) : path to the Unix socket.
        - _run_with_sudo (bool, optional) : run all commands with sudo.
    Kwargs:
        - rate_unit (str, optional) : rate unit. Default is "mbit".
        - interval_unit (str, optional) : interval unit. Default is "min".
        Default is None.
        - _run_with_sudo (bool, optional) : run all commands with sudo.
        Default is False.
    """

    def __init__(
        self,
        min_rate: int,
        max_rate: int,
        interval: int,
        *,
        prefix: str = "",
        _server_socket_path: str = "/tmp/contcfg.sock",
        _run_with_sudo: bool = False,
        **kwargs,
    ):
        self.min_rate = min_rate
        self.max_rate = max_rate
        self.rate_unit = kwargs.get("rate_unit", "mbit")
        self.interval_unit = kwargs.get("interval_unit", "min")
        self.prefix = prefix
        self._run_with_sudo = _run_with_sudo
        # convert interval to seconds
        if self.interval_unit.startswith("s"):
            self.interval_sec = interval
        elif self.interval_unit.startswith("m"):
            self.interval_sec = interval * 60
        elif self.interval_unit.startswith("h"):
            self.interval_sec = interval * 3600

        self._container_list: List[str] = []
        self._msg_queue: Queue = asyncio.Queue()
        self._is_running = False
        self._limit_dict: Dict[Tuple[str, str], int] = {}
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._socket_path = _server_socket_path

    async def _monitor_and_adjust_network(self):
        """Monitor and adjust network bandwidth between containers."""
        while True:
            msg = await self._msg_queue.get()
            logging.debug(f"Received message: {msg}")
            if msg.action == CtrlAction.STOP:
                self._is_running = False
                # clear all bandwidth limits
                for container in self._container_list:
                    self._clear_one(container)
                break
            elif msg.action == CtrlAction.SET_BANDWIDTH:
                # for each container pair, set bandwidth limit
                for container1, container2 in all_pairs_iter(
                    self._container_list
                ):
                    self._set_bandwidth_limit(container1, container2)
            elif msg.action == CtrlAction.ADD_CONTAINER:
                if msg.container in self._container_list:
                    logging.warning(
                        f"Recv ADD_CONTAINER. the container {msg.container} "
                        + "is already in the list"
                    )
                    continue
                # adjust network for new container
                for container1, container2 in all_pairs_iter(
                    self._container_list, msg.container
                ):
                    self._set_bandwidth_limit(container1, container2)
                self._container_list.append(msg.container)
            elif msg.action == CtrlAction.DEL_CONTAINER:
                if msg.container not in self._container_list:
                    logging.warning(
                        f"Recv DEL_CONTAINER. the container {msg.container} "
                        + "is not in the list"
                    )
                    continue
                self._container_list.remove(msg.container)
                # clear bandwidth limit for the container
                if DockerCmdWrapper(self._run_with_sudo).is_container_exist(
                    msg.container
                ):
                    self._clear_one(msg.container)
            # show bandwidth limits
            self._show_bandwidth_limits()

    async def _periodic_clock(self):
        """Periodic clock to trigger network adjustment."""
        while self._is_running:
            await asyncio.sleep(self.interval_sec)
            await self._msg_queue.put(CtrlMsg(CtrlAction.SET_BANDWIDTH))
        # stop the loop
        self._loop.stop()

    def start(self):
        """start monitoring and adjusting network."""
        server = NetCtrlCommServer(self._socket_path)
        self._is_running = True
        loop = asyncio.get_event_loop()
        self._loop = loop
        loop.create_task(self._monitor_and_adjust_network())
        loop.create_task(self._periodic_clock())
        loop.create_task(server.start(self._msg_queue))
        loop.run_forever()

    def _show_bandwidth_limits(self):
        """Show bandwidth limits between containers."""
        s = ""
        for (container1, container2), bandwidth in self._limit_dict.items():
            s += (
                f"{container1} <--> {container2} : {bandwidth} {self.rate_unit}"
            )
            s += "\n"
        if s:
            logging.info(f"Bandwidth limits:\n{s}")

    def _set_bandwidth_limit(
        self, container1: str, container2: str, bandwidth: Optional[int] = None
    ):
        """Set bandwidth limit between two containers.
        Args:
            - container1 (str) : container name or id
            - container2 (str) : container name or id
            - bandwidth (int, optional) : bandwidth limit. Default is None.
        """
        if bandwidth is None:
            bandwidth = random.randint(self.min_rate, self.max_rate)

        try:
            container1, container2 = sorted([container1, container2])
            TCCmdWrapper(self._run_with_sudo).set_bandwidth(
                container1, container2, bandwidth, self.rate_unit
            )
            self._limit_dict[(container1, container2)] = bandwidth
        except ContainerNotFoundError:
            logging.error(f"Container {container1} or {container2} not found")
        except RateValueError as e:
            logging.error(f"Rate value error: {e}")
        except Exception as e:
            logging.error(
                "Error setting bandwidth. Please check if tc is installed"
                + f" or run with sudo: {e}"
            )

    def _clear_one(self, container1: str):
        """Clear tc rules for one container."""
        try:
            TCCmdWrapper(self._run_with_sudo).clear_one_container(container1)
        except ContainerNotFoundError:
            logging.error(f"Container {container1} not found")
        except Exception as e:
            logging.error(f"Error clearing bandwidth limit: {e}")
