# -*- coding: utf-8 -*-

from enum import Enum
from dataclasses import dataclass


class CtrlAction(Enum):
    SET_BANDWIDTH = 1  # set bandwidth limit between two containers
    ADD_CONTAINER = 2  # add a new container to monitor
    DEL_CONTAINER = 3  # remove a container from monitoring
    STOP = 4  # stop monitoring and adjusting network


@dataclass
class CtrlMsg:
    action: CtrlAction
    container: str = None
