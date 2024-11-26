import multiprocessing as mp
import time

from contcfg.container_net_ctrl import ConNetServer, ConNetController
from contcfg.container_net_ctrl import CtrlMsg, CtrlAction


def test_net_ctrl_comm():
    # 1. Create a server
    server = ConNetServer(
        min_rate=1,
        max_rate=10,
        interval=5,
        prefix="test",
        rate_unit="mbit",
        interval_unit="s",
        _run_with_sudo=True,
    )
    task = mp.Process(target=server.start)
    task.start()

    time.sleep(1)
    # 2. Create a client
    sender = ConNetController(_run_with_sudo=True)

    for c in sender.find_all_containers("constellation-test-worker-"):
        sender.add_container(c)
        time.sleep(0.1)

    # 4. Stop
    sender.stop_server()
    task.join()
    print("Test finished.")


if __name__ == "__main__":
    test_net_ctrl_comm()
