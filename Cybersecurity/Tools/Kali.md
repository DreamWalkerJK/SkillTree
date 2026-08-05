# Kali Linux

> Kali Linux 是面向渗透测试、安全评估、数字取证和安全研究的滚动发行版。它提供的是工具与工作环境，不会自动赋予测试权限。本文中的命令仅用于自己拥有或已获得明确书面授权的系统，执行前应确认目标、时间窗口、允许的测试类型和流量上限。

## 目录

- [1. 定位与版本选择](#1-定位与版本选择)
- [2. 安装方式与场景取舍](#2-安装方式与场景取舍)
- [3. 官方 Docker 镜像快速开始](#3-官方-docker-镜像快速开始)
- [4. 数据持久化与可复现环境](#4-数据持久化与可复现环境)
- [5. 包管理与元包](#5-包管理与元包)
- [6. 基础配置](#6-基础配置)
- [7. 授权安全测试工作流](#7-授权安全测试工作流)
- [8. Docker 容器的能力边界](#8-docker-容器的能力边界)
- [9. 常见问题排查](#9-常见问题排查)
- [10. 安全建议](#10-安全建议)
- [11. 参考资料](#11-参考资料)

## 1. 定位与版本选择

Kali 基于 Debian，但采用 `kali-rolling` 滚动仓库。官网发布的编号版本主要是某个时间点的
安装介质和预构建镜像快照，并不是相互独立的长期支持分支。系统持续更新后会进入当前的
rolling 状态。

Kali 适合以下用途：

- 在隔离实验室中学习网络协议、Web 安全和主机安全；
- 对已授权资产进行发现、验证、证据留存和复测；
- 分析数据包、磁盘镜像、日志和可疑文件；
- 为安全工具准备一致、可丢弃或可复现的运行环境。

它通常不适合作为日常办公系统、互联网服务器或生产工作负载的基础镜像。Kali 默认强调工具可用性，不能替代系统加固、资产授权、变更管理和审计流程。

### 1.1 Rolling、安装镜像与容器标签

| 名称 | 含义 | 选择建议 |
| --- | --- | --- |
| `kali-rolling` | 持续更新的软件仓库，也是官方 Docker 镜像常用标签 | 日常实验和持续维护使用 |
| Installer | 包含安装器和常用离线软件集合，不能作为 Live 系统直接使用 | 不确定如何选择时，优先使用标准 Installer |
| NetInstaller | 体积小，安装时从网络下载软件包 | 网络稳定且确实需要小型介质时使用 |
| Live | 不安装即可从 USB 等介质启动 | 临时使用、硬件兼容性检查或取证场景 |
| Everything | 包含接近完整的工具集合，体积很大 | 离线环境且明确需要大量工具时使用 |
| 预构建 VM | 官方为常见虚拟化平台准备的虚拟机 | 希望快速获得完整桌面和内核环境时使用 |

`docker.io/kalilinux/kali-rolling` 是可变标签。同一个标签在不同日期可能对应不同镜像。普通学习环境可以定期拉取最新镜像；需要复现实验时，应记录镜像摘要：

```powershell
docker pull docker.io/kalilinux/kali-rolling
docker image inspect docker.io/kalilinux/kali-rolling `
  --format '{{index .RepoDigests 0}}'
```

严格复现时，可以在 `Dockerfile` 的 `FROM` 中使用记录下来的 `@sha256:...` 摘要，并通过
受控变更定期更新。摘要通常与 CPU 架构有关，跨架构运行前应重新确认。

### 1.2 下载介质的校验

ISO 和预构建 VM 只应从 Kali 官方下载页获取。下载后，将文件哈希与官网发布并签名的 `SHA256SUMS` 对照；不要仅凭文件名或第三方网盘来源判断真伪。

```bash
sha256sum kali-linux-*.iso
gpg --verify SHA256SUMS.gpg SHA256SUMS
```

Windows 可以计算同样的 SHA-256：

```powershell
Get-FileHash -Algorithm SHA256 .\kali-linux-*.iso
```

Kali 官方签名密钥的获取和指纹核对应遵循[安全下载 Kali 镜像](https://www.kali.org/docs/introduction/download-images-securely/)中的当前步骤，不要为了让校验通过而关闭签名检查。

## 2. 安装方式与场景取舍

| 方式 | 优点 | 局限 | 典型场景 |
| --- | --- | --- | --- |
| Docker | 启动快、轻量、易重建 | 共享宿主机内核，无完整 `systemd` 和硬件能力 | 命令行实验 |
| 虚拟机 | 有独立内核、完整桌面和快照，网络拓扑容易隔离 | 资源占用高于容器；硬件直通需要额外配置 | 综合课程、完整实验室、需要服务管理的工具 |
| 实体机安装 | 原生硬件、GPU、USB 和无线网卡支持最好 | 分区和驱动风险更高；隔离、恢复不如 VM 方便 | 无线研究、硬件研究、长期专用工作站 |
| Live USB | 不修改磁盘即可临时启动，可选持久化分区 | 性能和可靠性受 USB 介质影响 | 临时环境、兼容性检查、取证启动 |
| WSL | 与 Windows 集成方便 | 网络、内核和设备行为不同于标准 VM | 命令行学习 |

选择建议：

- 只需要命令行工具、希望随时重建：从官方 Docker 镜像开始；
- 需要桌面代理、完整服务管理、复杂路由或实验快照：使用官方预构建 VM；
- 需要无线监听模式、特定驱动、USB 或 GPU 直通：优先考虑 VM 直通，仍不满足时再使用专用实体机；
- 实体机安装前先备份数据，确认磁盘目标，并考虑全盘加密；不要把故意脆弱的实验服务直接暴露到办公网或公网。

## 3. 官方 Docker 镜像快速开始

### 3.1 前置检查

先确认 Docker Engine 或 Docker Desktop 正常工作：

```powershell
docker version
docker info
```

镜像的官方名称是 `docker.io/kalilinux/kali-rolling`。明确写出注册表可以减少拉取同名非官方镜像的风险。

### 3.2 临时容器

以下方式适合快速确认工具或命令。退出后容器会因 `--rm` 被删除，容器内安装的软件包和未挂载的数据也会一并丢失：

```powershell
docker pull docker.io/kalilinux/kali-rolling
docker run --rm --interactive --tty `
  --name kali-ephemeral `
  docker.io/kalilinux/kali-rolling
```

进入容器后可以检查环境并按需安装少量工具：

```bash
cat /etc/os-release
uname -m
apt update
apt install -y curl nmap
```

官方基础镜像刻意保持精简，并不包含桌面版的默认工具集合。不要因为镜像名是 Kali 就假设 `nmap`、`metasploit-framework` 或其他工具已经安装。

### 3.3 可恢复的命名容器

不使用 `--rm` 时，停止的容器仍保留可写层：

```powershell
docker run --interactive --tty `
  --name kali-lab `
  docker.io/kalilinux/kali-rolling
```

退出后可再次启动并进入：

```powershell
docker container ls --all
docker start --attach --interactive kali-lab
```

容器正在后台运行时，使用 `exec` 开一个新 Shell：

```powershell
docker exec --interactive --tty kali-lab bash
```

这类容器适合短期探索，但不是可靠的环境定义。执行 `docker rm kali-lab` 后，可写层中的包和
配置都会消失。需要长期保留的成果应挂载到宿主机；需要长期保留的工具版本应写进
`Dockerfile`。

### 3.4 网络与端口

默认 bridge 网络通常足以访问互联网和同一 Docker 网络中的实验靶机。应为实验环境创建专用
网络，利用 Docker DNS 通过服务名访问目标，避免依赖会变化的容器 IP。

```powershell
docker network create authorized-lab
docker run --rm --interactive --tty `
  --network authorized-lab `
  docker.io/kalilinux/kali-rolling
```

将服务发布给宿主机时，优先只绑定回环地址：

```powershell
docker run --rm --publish 127.0.0.1:8080:8080 your-authorized-lab-image
```

`127.0.0.1` 在容器内指容器自身，不是宿主机。Docker Desktop 通常可通过
`host.docker.internal` 访问宿主机服务。不要为了省事使用 `--network host` 或把端口绑定到
`0.0.0.0`，除非已经理解平台差异和暴露范围。

## 4. 数据持久化与可复现环境

### 4.1 三类状态

| 对象 | 保存内容 | 删除后的结果 | 建议用途 |
| --- | --- | --- | --- |
| 镜像 | 只读基础文件系统和预装工具 | 可重新拉取或构建 | 固化工具和依赖 |
| 容器可写层 | 容器内临时安装的包和配置 | 删除容器后丢失 | 临时探索 |
| Bind Mount | 宿主机目录中的笔记、报告和样本 | 删除容器后仍在宿主机 | 项目成果和证据 |
| Named Volume | 由 Docker 管理的数据 | 删除容器后默认保留，删除卷后丢失 | Shell 历史、缓存和工具用户配置 |

不要使用 `docker commit` 代替环境定义。它难以审查和复现，也容易把历史记录、凭据或样本一起写入镜像。

### 4.2 使用 Bind Mount 保存工作目录

PowerShell 示例：

```powershell
New-Item -ItemType Directory -Force .\workspace | Out-Null
$kaliWorkspace = (Resolve-Path .\workspace).Path

docker run --rm --interactive --tty `
  --mount "type=bind,source=$kaliWorkspace,target=/workspace" `
  --workdir /workspace `
  docker.io/kalilinux/kali-rolling
```

样本和证据不需要被工具修改时，将挂载设为只读：

```powershell
--mount "type=bind,source=$kaliWorkspace,target=/evidence,readonly"
```

在 Linux 宿主机上，应注意容器 UID/GID 与宿主机目录权限的对应关系。Docker Desktop 的文件
共享还可能带来大小写、符号链接和 I/O 性能差异。

### 4.3 用 Dockerfile 固化工具

下面的示例只安装常见的发现、协议验证和数据包分析工具，并创建非 root 用户。根据实际任务增减包，不要默认安装 `kali-linux-everything`：

```dockerfile
FROM docker.io/kalilinux/kali-rolling

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get -y full-upgrade \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dnsutils \
        file \
        git \
        iproute2 \
        jq \
        nmap \
        openssl \
        tcpdump \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 --shell /bin/bash analyst \
    && mkdir -p /workspace \
    && chown analyst:analyst /workspace

USER analyst
WORKDIR /workspace
CMD ["sleep", "infinity"]
```

若明确需要 Kali 官方的无桌面工具集合，可以把逐包安装替换为 `apt-get install -y kali-linux-headless`，但镜像会明显增大。

### 4.4 Docker Compose 示例

将上面的内容保存为 `Dockerfile`，再在同一目录使用以下 `compose.yaml`：

```yaml
services:
  kali:
    build:
      context: .
    image: local/kali-lab:latest
    init: true
    stdin_open: true
    tty: true
    working_dir: /workspace
    command: ["sleep", "infinity"]
    volumes:
      - type: bind
        source: ./workspace
        target: /workspace
      - type: volume
        source: kali-home
        target: /home/analyst
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL

volumes:
  kali-home:
```

常用命令：

```powershell
New-Item -ItemType Directory -Force .\workspace | Out-Null
docker compose build --pull
docker compose up --detach
docker compose exec kali bash
docker compose down
```

`docker compose down` 会删除容器和 Compose 网络，但默认保留 `kali-home`。
`docker compose down --volumes` 会连同该卷及其中数据一起删除，执行前必须确认不再需要。

每次需要升级工具时重新执行 `docker compose build --pull` 并创建新容器。重要实验还应记录
构建日期、基础镜像摘要和 `dpkg-query` 输出：

```bash
dpkg-query -W -f='${Package}\t${Version}\n' | sort > /workspace/package-versions.tsv
```

## 5. 包管理与元包

### 5.1 软件源

标准 rolling 软件源的核心配置通常为：

```text
deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
```

先检查现有配置，不要机械追加重复条目：

```bash
cat /etc/apt/sources.list
grep -R --no-filename --extended-regexp '^[[:space:]]*deb ' \
  /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
```

不要把 Ubuntu、普通 Debian 或来源不明的仓库混入 Kali。混用仓库可能造成依赖冲突或供应链
风险。第三方仓库必须经过评估，并使用独立的签名密钥和 `signed-by` 配置。

### 5.2 更新与查询

Kali 是滚动发行版，官方推荐使用 `full-upgrade` 处理依赖变化：

```bash
sudo apt update
apt list --upgradable
sudo apt full-upgrade
```

容器默认通常以 root 身份运行，因此没有 `sudo` 时可直接执行 `apt`；完整系统和非 root 容器应使用 `sudo` 或在镜像构建阶段安装软件。不要在工具运行到一半时更新依赖，先保存工作，再完成升级和验证。

常用包管理命令：

```bash
apt search nmap
apt show nmap
apt-cache policy nmap
dpkg -L nmap
dpkg-query -W nmap
sudo apt install nmap
sudo apt remove nmap
sudo apt autoremove
```

### 5.3 元包选择

元包本身几乎不包含工具，而是通过依赖安装一组软件。应按任务选择，避免无差别安装全部工具。

| 元包 | 用途 | 说明 |
| --- | --- | --- |
| `kali-linux-core` | 最小 Kali 基础系统 | 工具最少，适合自定义镜像起点 |
| `kali-linux-headless` | 无桌面的常用安全工具集合 | 官方 Docker 文档推荐的通用容器集合，体积较大 |
| `kali-linux-default` | 标准 Kali 软件集合 | 更接近默认安装体验 |
| `kali-linux-large` | 比默认集合更广的工具 | 需要更多磁盘和更新时间 |
| `kali-linux-everything` | 接近完整的软件集合 | 极大，通常不适合容器和日常环境 |
| `kali-tools-top10` | 常用工具子集 | 快速实验，但仍应核对实际依赖 |
| `kali-tools-web` | Web 评估工具分类 | 按任务安装的分类元包 |
| `kali-tools-forensics` | 数字取证工具分类 | 适合离线分析工作站或 VM |
| `kali-tools-information-gathering` | 信息收集工具分类 | 使用时仍需受授权范围和速率限制 |

查看当前仓库中可用的元包：

```bash
apt-cache search '^kali-(linux|tools)-' | less
apt show kali-linux-headless
```

## 6. 基础配置

### 6.1 记录系统基线

开始实验前先记录系统和工具版本，便于复现结果：

```bash
cat /etc/os-release
uname -a
dpkg --print-architecture
date --utc --iso-8601=seconds
ip -brief address
ip route
cat /etc/resolv.conf
```

### 6.2 时间、时区与区域设置

证据时间线优先使用 UTC。完整系统可以交互式配置时区和 Locale：

```bash
sudo apt install locales tzdata
sudo dpkg-reconfigure locales
sudo dpkg-reconfigure tzdata
```

容器通常直接使用 UTC 更容易复现；不要只改显示时区而忽略宿主机时钟是否准确。签名校验和 TLS 错误也可能由系统时间偏差引起。

### 6.3 用户与权限

完整 Kali 系统默认应使用普通用户，只在安装软件或执行明确需要特权的操作时使用 `sudo`。
官方 Docker 基础镜像通常以 root 运行，生产式用法应像前面的 `Dockerfile` 一样创建普通用户。

只有在任务确实需要时才增加单项 Linux capability。例如，抓包或修改接口可能需要
`NET_RAW`、`NET_ADMIN`；不要直接使用 `--privileged`。不要把宿主机的 Docker Socket、
根目录、SSH 私钥目录或云凭据目录挂进 Kali 容器。

### 6.4 DNS、代理与证书

- `getent hosts example.test` 可同时检查系统解析链路，不要只依赖 `ping`；
- Docker Desktop 通常继承宿主机的 DNS 和代理设置，VPN 切换后可能需要重启容器；
- 企业 TLS 代理环境应把受信任的内部 CA 作为受控配置加入镜像，不要使用 `curl -k` 或关闭 APT 证书校验作为长期方案；
- 不要把代理密码、API Token 或 Cookie 写入 `Dockerfile`、镜像层、Shell 历史和报告。

## 7. 授权安全测试工作流

### 7.1 测试前确认

至少明确以下内容后再发起网络请求：

- 书面授权方、目标域名/IP/CIDR 和明确排除项；
- 允许的技术类型、最大并发或速率、测试时段；
- 紧急联系人、停止条件和数据保留期限；
- 是否允许账号测试、数据包捕获、漏洞验证和第三方 SaaS；
- 证据中敏感数据的加密、脱敏和交付方式。

### 7.2 建立工作目录与审计记录

以下示例中的 `target.lab` 必须替换成隔离实验室或授权清单内的目标：

```bash
CASE_ID='authorized-lab-001'
TARGET='target.lab'

mkdir -p "/workspace/${CASE_ID}"/{notes,evidence,pcap,reports}
date --utc --iso-8601=seconds | tee "/workspace/${CASE_ID}/notes/start-time.txt"
```

需要保留交互式命令记录时，可以使用 `script`，但应先确认输出不会包含密码和 Token：

```bash
script --append --timing="/workspace/${CASE_ID}/notes/session.time" \
  "/workspace/${CASE_ID}/notes/session.log"
```

### 7.3 低影响发现与协议验证

先确认解析和路由，再从低速 TCP Connect 扫描开始。下面的参数避免依赖原始套接字，并设置了保守速率；仍需服从授权文件中的限制：

```bash
getent ahosts "$TARGET" | tee "/workspace/${CASE_ID}/evidence/dns.txt"

nmap -sT -sV --version-light -T3 --max-rate 50 --reason \
  -oA "/workspace/${CASE_ID}/evidence/nmap-services" \
  "$TARGET"
```

对已确认开放的 HTTP/TLS 服务做人工可解释的验证：

```bash
curl --silent --show-error --location \
  --dump-header "/workspace/${CASE_ID}/evidence/http-headers.txt" \
  --output "/workspace/${CASE_ID}/evidence/http-body.html" \
  "https://${TARGET}/"

openssl s_client -connect "${TARGET}:443" -servername "$TARGET" \
  -showcerts </dev/null \
  > "/workspace/${CASE_ID}/evidence/tls.txt" 2>&1
```

常用工具的职责边界：

| 阶段 | 工具示例 | 目标产物 |
| --- | --- | --- |
| 主机与服务发现 | `getent`、`ip`、`nmap -sT` | 可追溯的资产和端口清单 |
| HTTP/TLS 验证 | `curl`、`openssl s_client` | 响应头、证书链和人工观察 |
| Web 代理验证 | Burp Suite、OWASP ZAP | 已授权请求、响应和复现步骤 |
| 流量分析 | `tcpdump`、Wireshark、TShark | PCAP、过滤条件和时间范围 |
| 离线文件检查 | `file`、`sha256sum`、`strings` | 类型、哈希和静态特征 |
| 报告与复测 | Markdown、截图、原始输出 | 影响、证据、修复建议和复测结论 |

不要把“工具返回疑似漏洞”直接当成结论。应手工确认目标归属、版本证据、前置条件、影响和误报可能，并采用授权范围内影响最小的验证方法。

### 7.4 抓包与离线证据

抓包可能包含凭据和个人数据，必须得到授权并限制过滤范围。前面的 Compose 服务默认丢弃了全部 capability；确需在隔离实验网络中抓包时，可为一次性命令临时增加所需能力：

```powershell
docker compose run --rm --user root `
  --cap-add NET_RAW --cap-add NET_ADMIN `
  kali tcpdump -i any -nn -s 0 `
  -w /workspace/authorized-lab-001/pcap/capture.pcap
```

结束捕获后对证据计算哈希，并尽量在副本上分析：

```bash
sha256sum /workspace/authorized-lab-001/pcap/capture.pcap \
  | tee /workspace/authorized-lab-001/pcap/SHA256SUMS
```

对未知文件只做离线静态检查，不要在日常宿主机或共享办公网络中直接执行：

```bash
sha256sum suspicious-file.bin
file suspicious-file.bin
strings -a -n 8 suspicious-file.bin | less
```

需要动态恶意软件分析时，应改用专门的隔离沙箱、快照和网络控制方案，而不是普通 Kali Docker 容器。

### 7.5 报告与复测

每个发现至少记录：

- 目标标识、UTC 时间、工具及精确版本；
- 可重复的最小步骤和原始证据文件路径；
- 实际观察、影响、误报排除过程和严重度依据；
- 不包含明文凭据的修复建议；
- 修复后的复测日期、方法和结果。

## 8. Docker 容器的能力边界

Docker 中的 Kali 不是完整虚拟机。它使用宿主机提供的 Linux 内核，因此即使容器内用户空间显示为 Kali，也不能代表 Kali 自己的内核、驱动和启动系统。

| 需求 | 容器中的情况 | 更合适的方案 |
| --- | --- | --- |
| 命令行网络工具 | 通常可用，部分扫描模式需要 capability | 低权限容器或 VM |
| `systemctl` / 完整 `systemd` | 官方基础镜像默认不支持 | VM 或实体机 |
| 无线监听模式与注入 | 依赖网卡、驱动、内核和 USB 直通，容器体验差 | VM USB 直通或专用实体机 |
| 内核漏洞与内核模块 | 实际作用于共享的宿主机内核，风险高 | 隔离 VM 或专用实验主机 |
| USB、蓝牙、SDR | 需要设备映射和额外权限 | VM 直通或实体机 |
| GUI 工具 | 需要显示服务器转发，配置复杂且隔离边界易被削弱 | 官方桌面 VM |
| GPU 加速 | 依赖宿主驱动、设备映射和运行时 | 受控 VM 或专用主机 |
| 同网段二层实验 | Docker Desktop、NAT 和 bridge 会改变网络行为 | 专用 Linux 实验主机或 VM 网络 |
| 数字取证 | 只读挂载可做部分分析，但链路保全需额外流程 | 专用取证工作站和写保护设备 |

遇到工具要求 `systemd`、自定义内核、广泛设备访问或 `--privileged` 时，应优先重新评估运行方式，而不是不断放宽容器权限。

## 9. 常见问题排查

| 现象 | 检查方法 | 处理方向 |
| --- | --- | --- |
| `Unable to locate package` | `apt update`、检查软件源 | 修复仓库和 DNS；确认包名 |
| APT 签名或 Release 文件错误 | `date -u`、检查源和代理 | 校准时间；恢复官方源和密钥，不要关闭签名验证 |
| 容器启动后立即退出 | `docker logs`、`docker inspect` | 前台命令已结束；使用长期前台进程 |
| `systemctl: command not found` 或无法连接总线 | 确认是否在官方容器中 | 直接以前台进程运行工具，或改用 VM |
| Raw socket 权限不足 | `id`、`getcap`、检查 capability | 使用无特权模式或增加单项 capability |
| 无法访问宿主机 | `ip route`、平台文档 | Docker Desktop 使用 `host.docker.internal` |
| 容器间无法解析名称 | `docker network inspect <network>` | 确认容器连接同一用户定义网络，并使用容器/服务名 |
| VPN 后 DNS 或路由异常 | 检查 DNS 和路由 | 排查子网冲突，调整 Docker/VPN 网段 |
| Bind Mount 无法写入 | `id`、`ls -ln /workspace` | 对齐 UID/GID 和目录权限；不要使用全局可写权限规避问题 |
| 磁盘空间不足 | `docker system df`、`df -h`、`du -sh` | 找出明确不用的容器、镜像或卷后逐项删除，先备份证据 |
| `exec format error` | `uname -m`、检查镜像 | 选择匹配 CPU 架构的镜像 |
| 工具版本与资料不同 | 查看版本与包策略 | 以本机帮助和官方文档为准 |

进一步诊断容器状态：

```powershell
docker container ls --all
docker logs kali-lab
docker inspect kali-lab
docker network ls
docker system df
```

进一步诊断容器内网络：

```bash
ip -brief address
ip route
getent hosts http.kali.org
curl -I https://http.kali.org/
```

## 10. 安全建议

- 只测试自己拥有或已获得明确授权的目标；发现超出范围的资产时立即停止并联系授权方；
- 将故意脆弱的靶机放入隔离网络，默认不发布端口，不直接接入公网或办公局域网；
- 以普通用户运行工具，默认丢弃 capability，只为单次明确任务增加所需权限；
- 不使用 `--privileged`，不挂载 Docker Socket、宿主机根目录、用户主目录或云凭据；
- 只从官方来源拉取 Kali 镜像和安装介质，记录摘要并定期重建；
- 把证据目录和配置目录分开，证据尽量只读挂载，交付前计算哈希并加密；
- 不把密码、Token、私钥和真实客户数据提交到 Git、镜像层、命令历史或公开报告；
- 端口发布优先绑定 `127.0.0.1`，远程访问实验室优先使用受控 VPN；
- 对扫描设置速率、并发和停止条件，避免造成拒绝服务或触发无关系统；
- 结束项目后按数据保留策略清理容器、卷、PCAP、缓存和临时凭据，并保留必要审计记录。

## 11. 参考资料

### 官方资料

1. [Kali Linux 官方下载](https://www.kali.org/get-kali/)
2. [Kali Linux：如何选择安装镜像](https://www.kali.org/docs/introduction/what-image-to-download/)
3. [Kali Linux：安全下载与校验镜像](https://www.kali.org/docs/introduction/download-images-securely/)
4. [Kali Linux：官方 Docker 镜像说明](https://www.kali.org/docs/containers/official-kalilinux-docker-images/)
5. [Kali Linux：使用官方 Docker 镜像](https://www.kali.org/docs/containers/using-kali-docker-images/)
6. [Kali Linux：元包说明](https://www.kali.org/docs/general-use/metapackages/)
7. [Kali Linux：软件源配置](https://www.kali.org/docs/general-use/kali-linux-sources-list-repositories/)
8. [Kali Linux：更新系统](https://www.kali.org/docs/general-use/updating-kali/)
9. [Kali Linux 工具文档](https://www.kali.org/tools/)
10. [Docker Hub：Kali Linux 官方镜像组织](https://hub.docker.com/u/kalilinux)
11. [Docker 文档：Bind Mount](https://docs.docker.com/engine/storage/bind-mounts/)
12. [Docker 文档：运行时权限与 Linux Capability](https://docs.docker.com/engine/containers/run/#runtime-privilege-and-linux-capabilities)

### 延伸阅读

1. [Geek Blogs：在 Docker 中使用 Kali Linux](https://geek-blogs.com/blog/kali-linux-docker/)
2. [51CTO：Kali Linux Docker 相关文章](https://blog.51cto.com/u_92655/14562859)
