# contcfg

这是一个简单的用于控制 Docker 容器之间网络的工具。目前只支持设置网络链路的带宽。

## 特性

- 设置容器之间的带宽限制
- 支持动态添加和删除容器
- 定期调整网络带宽
- 支持通过 Unix Socket 接收控制消息

## 安装

```bash
pip install contcfg
```

## 原理

`contcfg` 通过在 docker 容器内部执行 `tc` 命令来设置网络带宽。[`tc`](https://man7.org/linux/man-pages/man8/tc.8.html)

在桥接模式下，容器之间的网络通信是通过`veth pair`来实现的。`veth pair`是一对虚拟网络设备，一端连接到容器内部，另一端连接到宿主机的网桥上。`tc`命令可以通过`veth pair`来设置网络带宽。
![docker network](https://miro.medium.com/v2/resize:fit:828/format:webp/1*v5c5nl2BoA0BqwqWoj5Y1w.jpeg)

`contcfg`通过设置容器内部`peer`的`egress`带宽来限制容器的网络带宽。`peer`是`veth pair`的一端，`egress`分别表示出口的方向。

## 使用

```bash
contcfg --help

usage: contcfg [-h] [--version] [--socket-path SOCKET_PATH] {start-server,ctrl,stop-server,cli} ...

Container Network Controller

positional arguments:
  {start-server,ctrl,stop-server,cli}
                        Sub-command help
    start-server        Start the server
    ctrl                Control the server
    stop-server         Stop the server
    cli                 Run the CLI

options:
  -h, --help            show this help message and exit
  --version             show program's version number and exit
  --socket-path SOCKET_PATH
                        Path to the Unix socket
```

### 关于带宽单位
`tc`命令采用的带宽单位与常规的使用不太一致，如`10mbit`表示10m bit/s，实际上习惯表示为10mbps ;`10mbps`表示10m bytes/s， 而习惯上表示为10mBps。 在`contcfg`中，我们与`tc`保持一致。
  > 以下来自`tc`的使用说明 

  >              bit or a bare number
  >                     Bits per second
  >              kbit   Kilobits per second
  >              mbit   Megabits per second
  >              gbit   Gigabits per second
  >              tbit   Terabits per second
  >              bps    Bytes per second
  >              kbps   Kilobytes per second
  >              mbps   Megabytes per second
  >              gbps   Gigabytes per second
  >              tbps   Terabytes per second
  >              To specify in IEC units, replace the SI prefix (k-, m-,
  >              g-, t-) with IEC prefix (ki-, mi-, gi- and ti-)
  >              respectively.
  >
  >              TC store rates as a 32-bit unsigned integer in bps
  >              internally, so we can specify a max rate of 4294967295
  >              bps.


### CLI

```bash
contcfg cli set c1 c2 100mbit # 设置 c1 和 c2 的带宽为 100mbit
contcfg cli clear c1 c2 # 清除 c1 和 c2 的带宽限制
```

## 注意
- docker 容器需要在桥接模式下才能使用 `contcfg`
- `contcfg` 需要在 root 权限下运行
- `contcfg` 要求容器内部安装有 `tc` 命令，且启动时需要指定`--cap-add=NET_ADMIN` 权限
- `contcfg` 会在容器内部执行 `tc` 命令，可能会影响容器内部的网络性能。 仅在测试环境下使用
