# msfconsole

`msfconsole` 是 Metasploit Framework 的主要交互式控制台，用于检索、配置和运行模块，并管理任务、数据库记录与会话。它适合在渗透测试、漏洞验证和安全实验中统一组织工作流，但工具本身不会替使用者判断目标是否在授权范围内。

> 本文中的命令只用于本机、靶场或书面授权的测试环境。示例使用 `lab-*.local` 主机名和 RFC 5737 文档地址；执行前应替换为实验环境的真实配置，并确认测试范围、时间窗口、允许的测试手段以及数据保留要求。

## 目录

- [定位与授权边界](#定位与授权边界)
- [核心术语](#核心术语)
- [启动与帮助](#启动与帮助)
- [模块基本流程](#模块基本流程)
- [目标、载荷与网络选项](#目标载荷与网络选项)
- [数据库与 Workspace](#数据库与-workspace)
- [作业与会话管理](#作业与会话管理)
- [Resource 脚本](#resource-脚本)
- [常见诊断](#常见诊断)
- [退出与清理](#退出与清理)
- [命令速查](#命令速查)
- [参考资料](#参考资料)

## 定位与授权边界

Metasploit Framework 是一个模块化安全测试框架，`msfconsole` 是其中负责交互、配置和编排的前端。典型用途包括：

- 查询模块的适用平台、参考漏洞编号、目标类型和选项。
- 在授权环境中运行信息收集、服务识别、漏洞检查或漏洞验证模块。
- 为模块选择兼容的 payload，并管理由模块创建的作业和会话。
- 将主机、服务、漏洞、凭据元数据等测试结果按 workspace 分类保存。
- 通过 Resource 脚本复现经过审核的实验步骤。

使用前至少应明确以下边界：

1. **目标边界**：允许测试的主机、网段、域名、云资源和第三方依赖。
2. **行为边界**：是否允许扫描、身份验证尝试、漏洞利用、上传文件或造成服务重启。
3. **时间与流量边界**：允许测试的时间段、并发数和速率上限。
4. **数据边界**：日志、凭据、会话输出和 `loot` 文件的保存位置、访问权限与销毁时间。
5. **停止条件**：出现服务异常、超出范围、取得非预期敏感数据时应立即停止并通知负责人。

`msfconsole` 与 `msfvenom` 不应混淆：前者是 Framework 控制台；后者是独立的命令行工具，主要用于生成和检查 payload。不能把 `msfvenom` 参数当作 `msfconsole` 内部命令使用。

## 核心术语

| 术语 | 含义 | 注意事项 |
| --- | --- | --- |
| `exploit` | 利用特定缺陷或错误配置以触发预期行为的模块 | 可能影响目标稳定性；必须先阅读 `info`、核对目标和授权范围 |
| `payload` | 模块成功执行后交付或运行的功能组件 | 必须与模块、目标平台和架构兼容；并非所有模块都需要 payload |
| `auxiliary` | 扫描、枚举、协议交互、模糊测试等不以 exploit/payload 组合为核心的模块 | “辅助模块”不等于无副作用，仍需控制范围与并发 |
| `post` | 依赖已有会话运行的后续模块 | 通常需要设置 `SESSION`；运行前仍需确认授权内容 |
| `encoder` | 为满足坏字符、传输格式等约束而转换 payload 字节的组件 | 不是加密机制，也不保证绕过安全产品 |
| `nop` | 为部分平台和利用场景生成 no-operation 指令序列的组件 | 只在特定模块和架构中有意义，现代模块未必使用 |
| `target` | exploit 模块为特定系统版本、架构或触发方式定义的目标配置 | 它是模块内的目标编号，不是远程主机地址 |
| `job` | 在后台运行的模块实例或监听器 | job 不等于已经建立的 session |
| `session` | 模块与授权目标之间已建立的交互通道 | 类型可能是 shell、Meterpreter 等；能力和可用命令并不相同 |

## 启动与帮助

### 启动控制台

在已安装 Metasploit Framework 的终端中运行：

```bash
msfconsole
```

常见启动方式：

```bash
# 减少启动横幅输出
msfconsole -q

# 启动后执行经过审核的 Resource 脚本
msfconsole -r ./lab.rc
```

命令行参数可能随版本变化，可在系统终端执行 `msfconsole --help` 查看当前版本支持的选项。

### 控制台内获取帮助

```text
help
help search
search -h
version
```

- `help` 或 `?`：列出当前上下文可用命令。
- `help <命令>`：查看某个控制台命令的说明。
- `<命令> -h`：许多命令和模块支持自己的参数帮助。
- `version`：确认 Framework 和控制台版本，排查文档与本机行为差异。
- Tab 补全：用于补全命令、模块路径和部分选项，减少拼写错误。

进入模块、会话或其他上下文后，可用命令会发生变化。遇到不确定的命令时，应在当前提示符下重新执行 `help`。

## 模块基本流程

推荐遵循“搜索 -> 阅读 -> 选择 -> 检查选项 -> 设置 -> 验证 -> 运行 -> 记录”的顺序。

### 搜索与阅读模块信息

```text
search type:auxiliary name:http version
info auxiliary/scanner/http/http_version
use auxiliary/scanner/http/http_version
```

`search` 支持组合 `type:`、`name:`、`platform:`、`cve:`、`rank:` 等条件，实际可用过滤条件以 `help search` 为准。虽然可以使用搜索结果的序号选择模块，但完整模块路径更适合文档和脚本复现。

`show` 用于按类别列出模块或显示当前模块的信息。例如在主控制台中可执行 `show auxiliary`、`show exploits`，进入模块后则常用 `show options`、`show advanced`、`show targets` 和 `show payloads`。不同上下文支持的类别不同，可先执行 `show -h`。

`info` 应重点检查：

- 模块说明、作者、参考资料和披露日期。
- 支持的平台、架构、targets 与 payloads。
- 是否具有破坏性提示、可靠性说明或特殊前置条件。
- Basic、Advanced 以及其他模块特定选项；并非每个模块都包含全部类别。

### 查看和设置选项

以下示例只识别授权实验站点的 HTTP 服务版本：

```text
use auxiliary/scanner/http/http_version
show options
set RHOSTS lab-web.local
run
back
```

| 命令 | 作用 |
| --- | --- |
| `show options` | 显示当前模块的常规选项、当前值及是否必填 |
| `show advanced` | 显示高级选项；修改前应理解副作用 |
| `set NAME value` | 在当前模块中设置选项 |
| `setg NAME value` | 设置跨模块可用的全局值 |
| `unset NAME` | 清除当前模块中的选项值 |
| `unsetg NAME` | 清除全局选项值 |
| `back` | 离开当前模块，返回上一级控制台上下文 |

局部设置通常优先于同名全局设置。`setg` 便于同一实验中复用配置，但也容易把旧目标带入新模块；切换项目或 workspace 时，应检查并清除不再适用的全局值。其是否跨重启保存还与 `save`、用户配置和版本有关，不应假定永久有效。

### 检查与运行

```text
show options
check
run
```

需要注意：

- 只有实现了检查逻辑的模块才能使用 `check`；否则会提示不支持。
- `check` 的 `Safe`、`Detected`、`Appears`、`Vulnerable` 或 `Unknown` 等结果只是模块根据有限证据作出的判断，可能存在误报、漏报或环境差异。
- `check` 仍会向目标发送请求，不能视为完全无副作用；执行前同样需要授权。
- `run` 用于执行当前模块；部分 exploit 模块也常使用 `exploit`。支持的参数应通过当前上下文中的 `run -h` 或 `exploit -h` 确认。

不要因为 `check` 不支持或返回不确定结果就直接运行 exploit。应结合服务版本、补丁状态、模块说明、独立证据和变更窗口进行判断。

## 目标、载荷与网络选项

### `TARGET` 与 `PAYLOAD`

在支持多个 target 的 exploit 模块中，可使用：

```text
show targets
set TARGET <编号>
show payloads
set PAYLOAD <兼容的完整模块名>
show options
```

- `TARGET` 选择模块预定义的系统版本、架构或利用方式。编号来自 `show targets`，不能填写 IP 地址。
- `PAYLOAD` 选择模块执行后使用的功能组件。先选定 target，再执行 `show payloads`，有助于只查看兼容项。
- 某些模块可以自动选择 target 或 payload，但仍应通过 `show options` 和 `info` 核对结果。

### 常见网络选项

| 选项 | 含义 | 使用要点 |
| --- | --- | --- |
| `RHOSTS` | 一个或多个授权远程目标 | 可能接受主机名、地址、CIDR 或文件输入，具体格式由模块和版本决定 |
| `RHOST` | 单个远程目标 | 只在定义该选项的模块中使用 |
| `RPORT` | 远程目标服务端口 | 默认值不一定与实验环境实际服务端口一致 |
| `LHOST` | 本地监听或回连所使用的地址 | 对 reverse 类 payload，应是实验目标能够路由到的测试机地址，而不只是测试机任意网卡地址 |
| `LPORT` | 本地监听端口 | 确认未被占用，并符合实验网络和防火墙策略 |

下面只是选项关系示意，不对应任何具体 exploit：

```text
set RHOSTS lab-target.local
set RPORT 443
set LHOST 192.0.2.10
set LPORT 4444
show options
```

`192.0.2.10` 属于 RFC 5737 文档地址，不能直接用于实际网络。并非所有模块或 payload 都需要上述全部选项，例如 bind 类与 reverse 类 payload 的网络方向不同，应以模块的 `show options` 为准。

## 数据库与 Workspace

### 数据库的作用

Metasploit 可连接 PostgreSQL 保存主机、服务、漏洞、凭据元数据、备注和 loot 等项目数据。数据库断开时，许多模块仍可运行，但跨会话查询、导入和项目分类能力会受到影响。

在 `msfconsole` 中检查连接：

```text
db_status
```

Kali 等打包发行版通常提供 `msfdb` 管理脚本，可在系统终端中检查并初始化数据库：

```bash
sudo msfdb status
sudo msfdb init
```

`msfdb` 不是所有安装方式都提供，服务名称、权限和初始化流程也会因发行版与 Framework 版本不同而变化。不要在已有数据的环境中随意执行 `reinit` 一类重建操作；应先确认本机帮助、备份需求和数据保留策略。

连接成功后，可按当前版本的 `help` 查看 `hosts`、`services`、`vulns`、`notes`、`loot`、`creds`、`db_import` 等数据库命令。导入扫描结果不会自动证明目标存在漏洞，仍需核对来源、时间和证据。

### 使用 Workspace 隔离项目

```text
workspace
workspace -a lab-training
workspace lab-training
workspace default
```

- `workspace`：列出 workspace，并标示当前项。
- `workspace -a <名称>`：创建 workspace。
- `workspace <名称>`：切换到已有 workspace。
- `workspace -d <名称>`：部分版本用于删除 workspace；删除前应确认当前版本帮助和数据保留要求。

Workspace 是数据库记录的逻辑分组，不是网络访问控制，也不会自动限制模块只能访问某个网段。即使已经切换 workspace，仍必须逐次检查 `RHOSTS` 和全局选项。命令参数存在版本差异时，以 `help workspace` 为准。

## 作业与会话管理

### 后台作业

模块支持后台执行时，可根据当前模块帮助使用 `run -j` 或 `exploit -j`。常用管理命令如下：

```text
jobs
jobs -v
jobs -k <job_id>
jobs -K
```

- `jobs`：列出后台作业。
- `jobs -v`：显示更详细的信息。
- `jobs -k <job_id>`：终止指定作业。
- `jobs -K`：终止全部作业，执行前应确认没有其他获准任务仍在运行。

后台监听器通常显示为 job；成功建立的交互连接则显示为 session。停止监听 job 不一定自动终止已经建立的 session。

### 会话

```text
sessions
sessions -i <session_id>
sessions -k <session_id>
sessions -K
```

- `sessions`：列出当前会话及其类型、连接信息和描述。
- `sessions -i <session_id>`：进入指定会话。
- `sessions -k <session_id>`：终止指定会话。
- `sessions -K`：终止全部会话，使用前应确认影响范围。

进入会话后先执行该上下文的 `help`。若需要暂时返回 `msfconsole` 而保留会话，可在支持该命令的会话中使用 `background`；不同 shell 或 session 类型的后台方式可能不同。不要把会话内的 `exit` 与主控制台的 `exit` 混用，因为前者通常会终止当前会话。

`post` 模块通常通过 `set SESSION <session_id>` 指定已有会话。运行前应阅读 `info` 并检查授权范围，本文不展开会话后的控制、持久化或规避检测操作。

## Resource 脚本

Resource 脚本是按行保存的 `msfconsole` 命令文件，适合复现实验初始化、模块选择和审计记录。它不会替代人工审核；脚本中的每条命令仍以当前用户权限执行。

一个仅面向授权实验 Web 服务识别的示例：

```text
# lab-http-version.rc
version
db_status
workspace lab-training
use auxiliary/scanner/http/http_version
set RHOSTS lab-web.local
show options
run
back
```

在控制台内执行：

```text
resource ./lab-http-version.rc
```

也可以在系统终端启动时加载：

```bash
msfconsole -r ./lab-http-version.rc
```

使用脚本时应注意：

- 将 workspace 预先创建好，避免脚本因环境状态不同而失败。
- 不要把密码、令牌或真实目标清单提交到版本库；敏感配置应按项目的秘密管理规范处理。
- Resource 脚本默认会连续执行命令。高影响步骤前宜拆分脚本并人工确认，避免旧配置被直接复用。
- 某些版本提供 `makerc` 将当前控制台历史写为脚本；生成结果可能包含敏感值，必须逐行审查后再保存或运行。
- 通过 `help resource`、`help makerc` 核对当前版本支持的语法。

## 常见诊断

| 现象 | 检查方法 | 常见原因与处理 |
| --- | --- | --- |
| 找不到模块或模块路径失效 | `search`、`version`、`help search` | 文档对应其他版本、模块改名或安装不完整；按当前安装方式更新索引/软件包，不要盲用旧路径 |
| 提示缺少必填选项 | `show options`、`show advanced` | `RHOSTS`、端口、凭据或模块专有选项未设置；核对局部值与 `setg` 遗留值 |
| payload 不兼容 | 先选 `TARGET`，再执行 `show payloads` | 平台、架构、连接方向或空间约束不匹配；不要强行复用其他模块的 payload |
| `check` 不可用或返回 `Unknown` | `info`、`help check` | 模块未实现检查、服务响应不足或网络中间设备改变了结果；不能据此断言安全或可利用 |
| reverse 类连接无法建立 | 核对 `LHOST`、`LPORT`、路由、防火墙、VPN/NAT 和端口占用 | `LHOST` 对目标不可达、回程路由错误、监听端口被占用或被网络策略阻断 |
| 数据库断开 | `db_status`；系统终端执行 `msfdb status`（若存在） | PostgreSQL 未运行、连接配置错误、初始化用户不同或安装方式不提供 `msfdb` |
| 结果出现在 job 而没有 session | `jobs -v`、`sessions` | 监听器仍在等待，模块只创建了后台任务，或目标没有建立会话；job 与 session 是不同对象 |
| 命令在当前提示符不可用 | `help`，必要时使用 `back` 或 `background` | 当前位于模块、session 或其他子上下文，支持的命令集不同 |

需要保留控制台输出时，可在支持该命令的版本中使用：

```text
spool ./logs/lab-session.log
# 执行已授权的实验步骤
spool off
```

日志可能包含目标信息、用户名、凭据或会话输出，应存放在受控目录，并纳入项目的数据保留与销毁流程。模块级详细日志或 `VERBOSE` 等选项并非所有模块都相同，应从 `show advanced` 确认，而不是全局套用。

## 退出与清理

结束测试前建议按以下顺序检查：

1. 使用 `jobs` 和 `sessions` 盘点仍在运行的任务与会话。
2. 按授权计划终止不再需要的指定 session 和 job；避免在多人共用环境中直接使用全部终止选项。
3. 如果启用了 `spool`，执行 `spool off`，确认日志已写入受控位置。
4. 使用 `workspace`、`hosts`、`services` 等命令核对记录归属，避免数据留在错误项目中。
5. 检查项目目录及 Metasploit 数据目录中的日志、loot、导出文件和 Resource 脚本，按约定加密、移交或删除敏感内容。
6. 在主控制台执行 `exit` 或 `quit`。若控制台提示仍有活动会话，应先确认影响，不要无条件强制退出。

退出 `msfconsole` 不会自动删除数据库记录、loot 或日志，也不代表目标侧变更已恢复。若测试模块可能修改目标，应依据模块说明和测试方案完成回滚，并由系统负责人验证服务状态。仅当这台测试机不再需要数据库服务时，再按发行版提供的方法停止相关服务。

## 命令速查

| 阶段 | 命令 | 作用 |
| --- | --- | --- |
| 帮助 | `help [command]` | 查看当前上下文或指定命令帮助 |
| 搜索 | `search <条件>` | 查找模块 |
| 阅读 | `info [module]` | 查看模块说明、选项和参考资料 |
| 选择 | `use <module>` | 进入模块上下文 |
| 返回 | `back` | 离开当前模块 |
| 查看 | `show options` | 查看模块选项和必填状态 |
| 查看 | `show targets` | 查看 exploit 模块支持的目标配置 |
| 查看 | `show payloads` | 查看当前模块/target 的兼容 payload |
| 配置 | `set` / `unset` | 设置或清除当前模块选项 |
| 配置 | `setg` / `unsetg` | 设置或清除全局选项 |
| 判断 | `check` | 在模块支持时执行漏洞检查，不保证结论确定 |
| 执行 | `run` | 执行当前模块；参数以 `run -h` 为准 |
| 作业 | `jobs` | 列出和管理后台作业 |
| 会话 | `sessions` | 列出和管理会话 |
| 数据库 | `db_status` | 查看数据库连接状态 |
| 项目 | `workspace` | 列出、创建或切换数据工作区 |
| 自动化 | `resource <file>` | 执行审核过的 Resource 脚本 |
| 记录 | `spool <file>` / `spool off` | 开始或停止记录控制台输出 |
| 退出 | `exit` / `quit` | 退出主控制台 |

## 参考资料

### 官方资料

- [Metasploit Framework 官方文档](https://docs.metasploit.com/)
- [Running modules：模块检索、配置与运行](https://docs.metasploit.com/docs/using-metasploit/basics/using-metasploit.html)
- [Managing Sessions：会话管理](https://docs.metasploit.com/docs/using-metasploit/basics/managing-sessions.html)
- [Database Support：数据库支持](https://docs.metasploit.com/docs/using-metasploit/intermediate/metasploit-database-support.html)
- [Metasploit Framework GitHub 仓库](https://github.com/rapid7/metasploit-framework)

### 延伸阅读

- [OffSec Metasploit Unleashed：msfconsole](https://www.offsec.com/metasploit-unleashed/msfconsole/)
- [CSDN：msfconsole 相关文章](https://blog.csdn.net/chengxuyuanyy/article/details/143788780)
- [博客园：Metasploit 相关文章](https://www.cnblogs.com/Junglezt/p/16009926.html)
- [华为云社区：Metasploit 相关文章](https://bbs.huaweicloud.com/blogs/392003)
- [Airunfive：msfconsole 命令集](https://airunfive.github.io/2024/07/22/msfconsole%E5%91%BD%E4%BB%A4%E9%9B%86/)

第三方资料可能对应较旧版本，命令行为和参数应以当前安装版本的 `help`、模块 `info` 及官方文档为准。
