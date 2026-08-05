# <center>Kali + Ubuntu 靶机 Docker 实验环境部署说明</center>

“双网络”结构：Kali 同时连接实验网和外网，Ubuntu 靶机只连接隔离实验网。
这样 Kali 能更新软件和访问互联网，靶机默认不能主动访问外网。

网络拓扑
--------

Internet
   |
wan_net（Docker NAT）
   |
 Kali
   |
lab_net（internal）
   |
Ubuntu Target
   |
宿主机端口映射：127.0.0.1:8008 -> Ubuntu:80


一、目录结构
------------

在 ..\Lab 下创建：

Lab\
├─ compose.yaml
├─ Kali\
│  └─ Dockerfile
├─ Target\
│  └─ Dockerfile
└─ Share\


二、compose.yaml
---------------

说明：

1. gw_priority 需要较新的 Docker Compose。
2. 如果提示不认识该字段，可以升级 Docker Desktop。
3. 也可以先删除 gw_priority，然后进入 Kali 执行 ip route 检查默认路由。
4. 如果 172.30.50.0/24 与现有 VPN 或局域网冲突，请替换成其他私有子网。


三、Kali Dockerfile
-------------------

建议把需要的工具写进 Dockerfile，不要每次进入容器后再手工安装，
否则重新构建或创建容器后容易丢失。


四、Ubuntu 靶机 Dockerfile
--------------------------


这里先用 Apache 演示网络连通性，并不是故意存在漏洞的靶机。


五、启动和测试
--------------

在 PowerShell 中执行：

cd ..\Lab
docker compose up -d --build
docker compose ps
docker compose exec kali bash

进入 Kali 后测试：

ip route
getent hosts target
ping -c 2 target
curl http://target
nmap -sV target
curl -I https://www.kali.org

说明：

- target 是 Docker 内置 DNS 提供的服务名，通常比硬编码 IP 更方便。
- 172.30.50.10 是实验网内部地址。
- Kali 通过 wan_net 访问互联网。
- Ubuntu 只有 lab_net，运行时不能主动访问互联网。
- 镜像构建阶段仍然可以下载 Ubuntu 软件包。

Windows 宿主机访问 Ubuntu：

curl http://127.0.0.1:8008


六、让局域网其他电脑访问 Ubuntu
--------------------------------

方法一：绑定宿主机所有网络接口

将 compose.yaml 中的端口映射改为：

ports:
  - "0.0.0.0:8008:80"

方法二：只绑定 Windows 的某个局域网地址，安全性更好

ports:
  - "192.168.1.23:8008:80"

请把 192.168.1.23 替换为 Windows 宿主机实际的局域网 IPv4 地址。

重新创建容器：

docker compose up -d

局域网其他电脑访问：

http://192.168.1.23:8008

必要时在管理员 PowerShell 中，仅对“专用网络”开放 TCP 8008：

New-NetFirewallRule `
  -DisplayName "Docker Ubuntu Target 8008" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8008 `
  -Action Allow `
  -Profile Private

端口映射对照：

1. 仅宿主机访问
   映射：127.0.0.1:8008:80
   地址：http://127.0.0.1:8008

2. 局域网访问
   映射：0.0.0.0:8008:80
   地址：http://Windows局域网IP:8008

3. 只绑定指定网卡地址
   映射：192.168.1.23:8008:80
   地址：http://192.168.1.23:8008

Docker Desktop/WSL2 下，局域网设备通常不能直接访问容器的 172.30.50.10；
正常做法是访问“Windows 主机 IP + 映射端口”。

如果必须让 Ubuntu 直接拥有类似 192.168.1.50 的独立局域网 IP，通常需要 Linux
Docker 主机上的 macvlan 或 ipvlan。Docker Desktop on Windows 不太适合这种模式，
可以考虑在 Linux 虚拟机或物理 Linux 主机中运行 Docker。


七、安全建议
------------

如果 Ubuntu 是 DVWA、Juice Shop 或其他故意脆弱的靶机，建议：

- 最安全的方式是不设置 ports，只允许 Kali 从 lab_net 访问。
- 需要宿主机访问时，优先绑定 127.0.0.1。
- 不要直接将脆弱靶机映射到公网。
- 不要给容器挂载 Docker Socket、宿主机根目录或随意使用 privileged: true。
- 远程访问实验环境时，优先通过 WireGuard、Tailscale 等 VPN，避免公网端口转发。
- 只测试自己拥有或明确获得授权的目标。


八、Docker Kali 的限制
----------------------

Docker 中的 Kali 不是完整虚拟机，它共享 Docker Linux 内核。

适合的场景：

- Web 安全实验
- 网络服务实验
- 常规端口扫描和流量分析
- 命令行安全工具

不太适合的场景：

- 无线网卡监听模式
- 内核漏洞实验
- 完整 systemd 环境
- 驱动或复杂底层网络实验

如果需要这些功能，建议使用 Kali 虚拟机，并让虚拟机连接 Docker 靶机网络，
或者将 Kali 和靶机都部署为虚拟机。


九、停止环境
------------

停止并删除容器及 Compose 网络：

docker compose down

重新构建并启动：

docker compose up -d --build

