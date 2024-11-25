import threading
import asyncio
from asyncio import Queue

from contcfg.container_net_ctrl.comm import NetCtrlCommServer, NetCtrlCommClient
from contcfg.container_net_ctrl import CtrlMsg, CtrlAction


q = Queue()
socket_path = "/tmp/net_ctrl_socket.sock"


def server():
    server = NetCtrlCommServer(socket_path)
    asyncio.run(server.start(q))


def test_net_ctrl_comm():
    import time

    server_thread = threading.Thread(target=server)
    server_thread.start()

    time.sleep(0.2)

    client = NetCtrlCommClient(socket_path)

    for i in range(19):
        msg = CtrlMsg(action=CtrlAction.SET_BANDWIDTH, container="container1")
        client.send(msg)
        time.sleep(0.1)

    client.stop()

    server_thread.join()


if __name__ == "__main__":
    test_net_ctrl_comm()
    assert q.qsize() == 20
