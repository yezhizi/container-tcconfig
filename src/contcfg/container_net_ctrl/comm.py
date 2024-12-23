import socket
import os
import struct
import pickle
import time
import fcntl
import errno
import asyncio
from asyncio import Queue
from typing import Optional

from .msg import CtrlMsg, CtrlAction


class NetCtrlCommServer:
    """Network control communication server.
    This class is used to create a unix socket server
    to receive control messages from clients.
    Typically, only one client will connect to the server.
    Args:
        - socket_path (str) : path to the unix socket
    """

    def __init__(self, socket_path: str):
        self.socket_path = socket_path
        self._lock_file = None
        self._check_path()
        self._server: Optional[asyncio.AbstractServer] = None
        self._stop_event = asyncio.Event()

    async def start(self, q: Queue):
        """Start the server. This method will start the server
        and wait for incoming messages, and put
        them in the queue.
        Args:
            - q (Queue) : asyncio.Queue object to put incoming messages
        """
        try:
            self._server = await asyncio.start_unix_server(
                lambda reader, writer: self._handle_client(reader, writer, q),
                path=self.socket_path,
            )
        except OSError as e:
            if e.errno in (errno.EADDRINUSE, errno.EACCES):
                raise OSError(
                    f"Failed to bind to socket: {self.socket_path}"
                ) from e
            else:
                raise
        try:
            serve_task = asyncio.create_task(self._server.serve_forever())
            await self._stop_event.wait()  # stop event
            serve_task.cancel()  # cancel the serve task
            try:
                await serve_task
            except asyncio.CancelledError:
                pass
        finally:
            await self.stop()

    async def _recvall(self, reader, n):
        """Receive n bytes from the reader.
        Args:
            - reader : asyncio.StreamReader object
            - n (int) : number of bytes to receive
        """
        data = bytearray()
        while len(data) < n:
            packet = await reader.read(n - len(data))
            if not packet:
                return None
            data.extend(packet)
        return data

    def _check_path(self):
        """Check if the socket path exists and is in use."""
        lock_file = self.socket_path + ".lock"
        self._lock_file = open(lock_file, "w")

        try:
            fcntl.flock(self._lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise OSError(
                "Another instance is holding the lock. "
                f"Socket path: {self.socket_path}"
            )

        if os.path.exists(self.socket_path):
            try:
                # Attempt to connect to the existing socket
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                    s.settimeout(1)  # set timeout to 1 second
                    s.connect(self.socket_path)
                # If the connection is successful, the socket is in use
                raise OSError(
                    f"Socket is already in use. Socket path: {self.socket_path}"
                )
            except OSError as e:
                if e.errno == errno.ECONNREFUSED:
                    # If the connection is refused, the socket is not in use
                    os.remove(self.socket_path)
                elif e.errno == errno.ENOENT:
                    # If the socket does not exist, it is not in use
                    pass
                else:
                    raise

    async def _handle_client(self, reader, writer, q: Queue):
        """Handle the client connection."""
        try:
            while True:
                raw_msglen = await self._recvall(reader, 4)
                if not raw_msglen:
                    break
                msglen = struct.unpack(">I", raw_msglen)[0]
                data = await self._recvall(reader, msglen)
                if not data:
                    break
                data_obj = pickle.loads(data)
                # put the data in the queue
                await q.put(data_obj)
                if data_obj.action == CtrlAction.STOP:
                    asyncio.create_task(self._initiate_stop())
                    break
        finally:
            # close the writer
            writer.close()
            await writer.wait_closed()

    async def _initiate_stop(self):
        """Initiate the stop event."""

        self._stop_event.set()

    async def stop(self):
        """Stop the server."""
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        self._stop_event.set()


class NetCtrlCommClient:
    def __init__(
        self, socket_path: str, _conn_retry: int = 5, _retry_interval: int = 1
    ):
        self.socket_path = socket_path
        self.conn: Optional[socket.socket] = None
        self._conn_retry = _conn_retry
        self._retry_interval = _retry_interval
        self._connected = False
        self._connect()

    def _connect(self):
        self._check_path()
        for _ in range(self._conn_retry):
            try:
                self.conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.conn.connect(self.socket_path)
                break
            except ConnectionRefusedError:
                print(
                    f"Connection refused. Retrying \
                    in {self._retry_interval} seconds."
                )
                time.sleep(self._retry_interval)
        else:
            raise ConnectionRefusedError(
                f"Cound not connect to {self.socket_path}"
            )
        self._connected = True

    def send(self, data: CtrlMsg):
        """Send data to the server."""
        if not self._connected:
            raise ConnectionError("Connection has been closed.")

        serialized_data = pickle.dumps(data)
        data_len = struct.pack(">I", len(serialized_data))
        if self.conn is not None:
            self.conn.sendall(data_len + serialized_data)
        else:
            raise ConnectionError("Connection is not established.")

    def stop_server(self):
        """Stop the server. This method will send a stop message
        to the server and close the connection.
        """
        self.send(CtrlMsg(action=CtrlAction.STOP))  # send stop message
        self.stop()

    def stop(self):
        """Stop the client."""
        self.conn.close()
        self._connected = False

    def _check_path(self):
        """Check if the socket path exists, and remove it if it does."""
        if not os.path.exists(self.socket_path):
            raise FileNotFoundError(
                f"Socket file not found: {self.socket_path}"
            )
