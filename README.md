<h1 align="center">SkillTree</h1>

<p align="center">
  面向软件开发者的结构化技术知识库：从计算机科学基础到生产系统工程。
</p>

<p align="center">
  <a href="https://dreamwalkerjk.github.io/SkillTree/"><strong>在线文档</strong></a>
  ·
  <a href="https://github.com/DreamWalkerJK/SkillTree">GitHub 仓库</a>
  ·
  <a href="https://github.com/DreamWalkerJK">作者主页</a>
</p>

> [!TIP]
> 推荐通过 [SkillTree 在线文档](https://dreamwalkerjk.github.io/SkillTree/) 阅读：支持侧边栏导航、全文搜索、深浅主题、代码高亮、数学公式以及上一篇/下一篇。

## 项目定位

SkillTree 用于沉淀开发过程中的系统化知识、问题分析和可运行示例。内容强调概念边界、工程取舍、实现细节与参考资料，而不是只记录零散的 API 用法。

当前内容主要覆盖：

- C#、.NET、ASP.NET Core、EF Core、并发与性能
- 软件架构、领域驱动设计、状态机、设计原则与设计模式
- 算法、数学、计算机网络、Linux/Windows 与系统运维
- 密码学原理、开放设计、哈希函数、碰撞安全与攻击模型
- MySQL、PostgreSQL、SQL Server 与查询优化
- Kubernetes、Helm、Kafka 等云原生与工程组件
- Kali、Metasploit 与可复现的网络安全实验环境

## 知识领域

| 领域 | 代表内容 |
| --- | --- |
| .NET / C# | [C# 与 .NET LTS 中高阶指南](DotNet/CSharp和NET-LTS中高阶指南.md) · [.NET 10 技术学习指南](DotNet/NET10技术学习指南.md) · [async Task 与 Task.FromResult](DotNet/AsyncTask与Task.FromResult.md) · [Roslyn](DotNet/Roslyn.md) |
| 架构与设计 | [领域驱动设计 DDD](Architecture/DDD.md) · [状态机](Architecture/状态机.md) · [SOLID](DesignPrinciples/SOLID.md) · [设计模式](DesignPattern/设计模式.md) |
| 算法与数学 | [哈希碰撞](Algorithm/哈希碰撞.md) · [旅行商问题 TSP](Algorithm/图与网络/旅行商问题TSP.md) · [非对称旅行商问题 ATSP](Algorithm/图与网络/非对称旅行商问题ATSP.md) · [生日悖论](Mathematics/生日悖论.md) |
| 密码学 | [Kerckhoffs 原则：开放设计、密钥保密与现代安全工程](Cryptography/Kerckhoffs原则.md) · [SHA-256：标准流程、压缩函数、安全性质与工程实践](Cryptography/SHA-256.md) · [生日攻击](Cryptography/生日攻击.md) · [生日悖论与密码学中的生日界](Mathematics/生日悖论.md) |
| 数据库 | [MySQL](DataBase/MySql/MySQL.md) · [SQL Server 执行计划](<DataBase/SQL Server/SQL Server执行计划.md>) · [CTE 与 View](DataBase/CTE和View.md) |
| 云原生与组件 | [Helm Chart](<Component/Helm Chart.md>) · [Kafka 外部地址配置](Component/kafka配置外部地址.md) |
| 网络安全 | [Kali Linux](Cybersecurity/Tools/Kali.md) · [msfconsole](Cybersecurity/Tools/msfconsole.md) · [Docker 实验环境](Cybersecurity/Lab/notice.md) |
| 计算机基础 | [网络模型](Network/网络模型.md) · [Linux 常用命令与运维手册](OperatingSystem/Linux/操作命令.md) · [Windows 基础命令](OperatingSystem/Windows/基础命令.md) · [正则表达式](GeneralCodingSkills/正则表达式.md) |

## 推荐阅读

1. [C# 和 .NET LTS 中高阶语法与用法指南（.NET 10 → .NET 8）](DotNet/CSharp和NET-LTS中高阶指南.md)
2. [领域驱动设计（Domain-Driven Design, DDD）](Architecture/DDD.md)
3. [状态机：形式化模型、执行语义与工程实践](Architecture/状态机.md)
4. [旅行商问题（Traveling Salesman Problem, TSP）](Algorithm/图与网络/旅行商问题TSP.md)
5. [Kerckhoffs 原则：开放设计、密钥保密与现代安全工程](Cryptography/Kerckhoffs原则.md)
6. [SHA-256：标准流程、压缩函数、安全性质与工程实践](Cryptography/SHA-256.md)
7. [生日悖论与密码学中的生日界](Mathematics/生日悖论.md)
8. [生日攻击：模型、复杂度与工程防御](Cryptography/生日攻击.md)
9. [Linux 常用命令与运维手册](OperatingSystem/Linux/操作命令.md)
10. [Kali + Ubuntu 靶机 Docker 实验环境](Cybersecurity/Lab/notice.md)

## 仓库结构

```text
SkillTree/
├── Algorithm/             # 算法、数据结构与组合优化
├── Architecture/          # 软件架构、DDD 与状态机
├── Component/             # Helm、Kafka 等组件
├── Cryptography/          # 密码学原理、算法、攻击模型与工程安全
├── Cybersecurity/         # 安全工具与实验环境
├── DataBase/              # MySQL、PostgreSQL、SQL Server
├── DesignPattern/         # 设计模式
├── DesignPrinciples/      # 设计原则
├── DotNet/                # C#、.NET、ASP.NET Core、EF Core
├── GeneralCodingSkills/   # 通用编码能力
├── Mathematics/           # 数学与概率
├── Network/               # 计算机网络
├── OperatingSystem/       # Linux、Windows 与系统运维
└── docs/                  # GitHub Pages 网站外壳与导航
```

## 在线文档与本地预览

GitHub Pages 发布源为 `main` 分支的 `/docs` 目录：

- 在线地址：<https://dreamwalkerjk.github.io/SkillTree/>
- Pages 外壳位于 `docs/`
- 文章仍保留在原有知识目录中，网站会从 `main` 分支读取 Markdown

本地预览无需安装依赖：

```powershell
python -m http.server 8000
```

然后访问 <http://localhost:8000/docs/>。本地模式会直接读取当前工作区中的文章，便于在推送前检查导航和排版。

## 内容维护

新增文章时：

1. 将 Markdown 放入对应的知识领域目录。
2. 在 `docs/_sidebar.md` 中添加导航项。
3. 如属于核心主题，可同步更新本 README 的“知识领域”或“推荐阅读”。
4. 推送到 `main` 后等待 GitHub Pages 完成部署。

SQL、文本和项目文件可以加入侧边栏，并通过 GitHub 源码视图打开；Markdown 文章则直接在文档站内阅读。
