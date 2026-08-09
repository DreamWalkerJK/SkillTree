# 领域驱动设计（Domain-Driven Design, DDD）

领域驱动设计是一套处理复杂业务软件的方法体系。它要求团队从领域问题出发，通过业务人员与技术人员共同维护的统一语言建立领域模型，再让代码、模块边界、接口契约和团队协作方式持续反映该模型。

DDD 的核心不是目录命名、基类、框架或设计模式，而是两个相互约束的过程：

1. 领域问题驱动模型设计。
2. 领域模型驱动软件设计与实现。

如果模型只存在于文档中而没有进入代码，或者代码套用了实体、仓储、领域服务等形式却没有表达真实业务规则，都不属于有效的 DDD 实践。

## 目录

1. [DDD 解决的问题](#1-ddd-解决的问题)
2. [DDD 与相关架构和模式的关系](#2-ddd-与相关架构和模式的关系)
3. [战略设计与战术设计](#3-战略设计与战术设计)
4. [领域、模型与统一语言](#4-领域模型与统一语言)
5. [战略设计](#5-战略设计)
6. [领域建模方法](#6-领域建模方法)
7. [战术设计](#7-战术设计)
8. [C# 示例：订单聚合](#8-c-示例订单聚合)
9. [应用架构与依赖方向](#9-应用架构与依赖方向)
10. [事务、一致性与并发](#10-事务一致性与并发)
11. [CQRS、事件驱动与事件溯源](#11-cqrs事件驱动与事件溯源)
12. [查询与跨上下文集成](#12-查询与跨上下文集成)
13. [测试策略](#13-测试策略)
14. [落地流程](#14-落地流程)
15. [常见错误](#15-常见错误)
16. [设计评审清单](#16-设计评审清单)
17. [术语速查](#17-术语速查)
18. [参考资料](#18-参考资料)

## 1. DDD 解决的问题

### 1.1 本质复杂性与偶然复杂性

业务系统的复杂性可以粗略分为两类：

- **本质复杂性**：来自业务规则本身，例如订单状态转换、授信条件、定价规则、库存占用、结算周期和监管约束。
- **偶然复杂性**：来自技术实现，例如框架配置、数据库映射、消息中间件、序列化、网络重试和部署环境。

DDD 的主要目标是控制本质复杂性，同时通过清晰边界防止技术细节污染领域模型。它不能消除业务复杂性，但可以使复杂性具有明确的名称、归属和变化边界。

### 1.2 典型症状

出现以下情况时，应考虑引入 DDD 的战略设计或战术设计方法：

- 同一业务术语在产品、运营、开发和数据库中含义不同。
- 业务规则散落在 Controller、Application Service、SQL、定时任务和前端代码中。
- 修改一个业务概念需要同时改动多个无明确边界的模块。
- 多个团队共享同一套模型，但各自对模型的解释不同。
- 数据表结构被直接当作业务模型，代码只能表达 CRUD，无法表达状态转换和业务意图。
- 服务已经拆分，但服务之间仍共享数据库、共享实体或形成大量同步调用。
- 核心业务频繁变化，而通用技术能力与核心模型紧密耦合。

### 1.3 适用边界

DDD 不是所有系统的默认实现方式。是否采用以及采用到什么程度，应由业务复杂度和长期收益决定。

| 场景 | 建议 |
| --- | --- |
| 核心业务规则复杂、变化频繁、需要长期维护 | 采用战略设计，并在核心子域使用富领域模型 |
| 多团队协作、术语冲突明显、模块边界不清 | 优先建立统一语言、子域和限界上下文 |
| 业务简单但需要长期演进 | 可使用轻量 DDD：明确边界、统一命名、封装关键不变量 |
| 纯 CRUD、短生命周期后台、无显著业务规则 | 事务脚本或简单分层通常更经济 |
| 数据搬运、ETL、报表聚合 | 以数据管道或查询模型为主，不必强行建立复杂聚合 |
| 技术验证、一次性脚本 | 不应引入完整的 DDD 战术模式 |

DDD 可以局部使用。核心子域采用富领域模型，支撑子域使用事务脚本，通用子域购买成熟产品，是常见且合理的组合。

## 2. DDD 与相关架构和模式的关系

分层架构、六边形架构、SOA、微服务、CQRS、事件驱动架构、事件溯源和 Saga 不是一条线性的“架构演进路线”。它们解决的问题不同，可以与 DDD 组合，也可以独立使用。

| 架构或模式 | 主要问题 | 与 DDD 的关系 |
| --- | --- | --- |
| 分层架构（Layered Architecture） | 按职责组织代码与依赖 | 可用于隔离领域层、应用层、基础设施层和接口层 |
| 六边形架构（Ports and Adapters） | 隔离核心逻辑与外部技术 | 通过端口和适配器保护领域模型，适合 DDD 落地 |
| 洋葱架构、整洁架构 | 约束依赖方向 | 与六边形架构目标相近，强调依赖指向业务核心 |
| 模块化单体 | 在单一部署单元内建立强模块边界 | 限界上下文可以先映射为模块，不要求立即拆为微服务 |
| SOA、微服务 | 划分可独立部署和治理的服务 | 限界上下文是服务边界的重要候选，但二者不是一一对应关系 |
| REST、gRPC、消息通信 | 定义跨进程交互方式 | 属于上下文之间的集成机制，不属于领域模型本身 |
| CQRS | 分离改变状态的模型与读取数据的模型 | 当写模型与查询需求差异明显时使用，不要求读写分库 |
| 事件驱动架构（EDA） | 通过事件实现异步协作和解耦 | 领域事件可作为事件来源，但领域事件不等同于集成事件 |
| 事件溯源（Event Sourcing） | 以事件序列作为状态事实来源 | 可实现聚合持久化，但不是 DDD 的必要条件 |
| Saga / Process Manager | 协调跨聚合或跨服务的长业务流程 | 通过本地事务、补偿或前向恢复实现最终一致性 |
| Outbox | 保证业务数据与待发布消息的原子写入 | 常用于可靠发布集成事件 |
| Fabric / Grid | 分布式计算 | 书中讨论的可组合技术，不等同于现代 Data Mesh |

需要明确以下边界：

- DDD 是设计方法，不是微服务框架。
- 限界上下文是模型的语义边界，不天然等于进程、服务、程序集或数据库。
- CQRS 是职责与模型分离，不只是“读写分库”，也不只用于解决页面展示复杂性。
- 事件驱动架构与管道—过滤器（Pipes and Filters）是不同的架构风格。
- Saga 是本地事务序列的协调模式，不是必然并行的任务处理模式。
- 微服务会引入网络、数据一致性、部署和可观测性成本，不应作为实施 DDD 的前置条件。

## 3. 战略设计与战术设计

DDD 包含两个相互关联的层次。

| 层次 | 关注点 | 主要产物 |
| --- | --- | --- |
| 战略设计（Strategic Design） | 业务范围如何拆分，不同模型如何协作 | 统一语言、子域、限界上下文、上下文映射 |
| 战术设计（Tactical Design） | 单个限界上下文内部如何表达和实现业务规则 | 实体、值对象、聚合、领域服务、领域事件、仓储、工厂 |

战略设计先回答“模型在哪个边界内成立”，战术设计再回答“这个边界内部如何实现”。如果跳过战略设计，直接在整个系统中建立一套共享实体和仓储，战术模式会放大耦合，而不是降低复杂度。

DDD 的工作过程不是瀑布式阶段。随着团队对业务理解加深，统一语言、上下文边界和代码模型都需要持续调整。

## 4. 领域、模型与统一语言

### 4.1 领域和领域模型

**领域（Domain）**是软件要解决的问题范围。电商、保险理赔、证券交易和物流履约都可以是领域；在具体组织中，领域应按实际业务目标和责任范围定义。

**领域模型（Domain Model）**是对领域中关键概念、规则、状态和关系的选择性抽象。模型不是现实世界的完整复制，也不是数据库 ER 图。一个有效模型应满足：

- 能解释关键业务决策。
- 能表达必须始终成立的不变量。
- 能区分不同概念的边界和生命周期。
- 能映射到可执行代码。
- 能随着业务认知变化而演进。

同一个现实对象在不同限界上下文中可以具有不同模型。例如：

- 在“销售”上下文中，`Customer` 关注购买资格、折扣等级和收货偏好。
- 在“结算”上下文中，`Account` 关注应收余额、账期和信用额度。
- 在“配送”上下文中，`Recipient` 关注姓名、电话和交付地址。

强行共享一个包含所有字段的 `Customer` 实体，会让不同上下文相互污染。

### 4.2 统一语言

**统一语言（Ubiquitous Language）**是业务专家和开发团队在特定限界上下文中共同使用的语言。它应进入：

- 需求、验收标准和业务规则。
- 事件风暴、流程图和模型图。
- 类、方法、命令、事件和接口名称。
- 日志、指标、告警和审计信息。
- API 契约及必要的数据库命名。

统一语言不是一次性术语表，而是模型的一部分。出现歧义时，应明确术语所属上下文和精确定义。

示例：

| 术语 | 所属上下文 | 定义 | 不应混用的概念 |
| --- | --- | --- | --- |
| 提交订单 | 销售 | 买方确认订单内容，订单从草稿进入待处理状态 | 创建购物车、支付 |
| 授权支付 | 支付 | 支付机构批准冻结指定金额 | 扣款、结算 |
| 占用库存 | 库存 | 为指定订单预留可用数量 | 实际出库 |
| 发运 | 履约 | 包裹交给承运方并获得运单信息 | 拣货、签收 |

如果业务人员说“订单已完成”，开发人员必须追问它在当前上下文中表示已支付、已发货、已签收还是已结算。模糊动词通常意味着模型仍不充分。

## 5. 战略设计

### 5.1 子域

领域可以拆分为多个子域（Subdomain）。子域属于问题空间，用于描述组织面对的业务问题。

| 子域类型 | 定义 | 投资策略 |
| --- | --- | --- |
| 核心子域（Core Subdomain） | 形成业务差异化和竞争优势的能力 | 投入最强团队，持续建模，避免被通用方案限制 |
| 支撑子域（Supporting Subdomain） | 支持核心业务，但通常不是竞争优势来源 | 自建简单实现，控制复杂度和维护成本 |
| 通用子域（Generic Subdomain） | 多个组织都需要且已有成熟方案的能力 | 优先采购、复用或采用标准产品 |

子域分类不是永久结论。随着商业策略变化，原来的支撑子域可能成为核心子域，核心能力也可能商品化。

### 5.2 限界上下文

**限界上下文（Bounded Context）**是某个领域模型和统一语言成立的明确边界。它属于解决方案空间，定义了：

- 哪些术语在边界内具有唯一含义。
- 哪些规则和数据由该上下文负责。
- 哪个团队对模型拥有决策权。
- 对外公开什么契约。
- 如何翻译外部模型。

子域与限界上下文不是严格一一对应：

- 一个子域可以由多个限界上下文实现。
- 一个较小的限界上下文可以承担一个完整子域。
- 遗留系统中，一个限界上下文可能错误地混合多个子域。

识别上下文边界时，可观察以下信号：

- 同一术语出现不同定义。
- 业务规则、变化频率或数据一致性要求不同。
- 不同团队拥有不同发布节奏。
- 某部分需要独立扩展、合规或安全隔离。
- 两组功能很少在同一事务中修改。
- 模型之间需要大量条件判断才能兼容。

边界过大会形成模型混杂和发布耦合；边界过小会造成频繁远程调用、分布式事务和重复翻译。边界应以业务能力和模型内聚为主，而不是按数据库表、技术层或页面菜单机械拆分。

### 5.3 上下文映射

上下文映射（Context Map）描述限界上下文之间的依赖方向、模型翻译和协作方式。常见关系如下。

| 模式 | 含义 | 适用说明 |
| --- | --- | --- |
| 合作关系（Partnership） | 两个团队共同规划接口和交付节奏 | 双方目标一致且能够紧密协作 |
| 共享内核（Shared Kernel） | 上下文共享一小部分模型或代码 | 共享范围必须小，变更需共同批准 |
| 客户—供应商（Customer/Supplier） | 上游提供能力，下游对需求有正式影响力 | 应明确优先级、版本和验收契约 |
| 遵奉者（Conformist） | 下游直接接受上游模型 | 上游稳定且下游缺乏谈判能力时使用 |
| 防腐层（Anti-Corruption Layer, ACL） | 下游建立翻译层隔离外部模型 | 集成遗留系统或第三方平台时优先考虑 |
| 开放主机服务（Open Host Service） | 上下文提供稳定、公开的集成协议 | 多个下游需要接入时使用 |
| 发布语言（Published Language） | 使用明确版本化的公共契约 | 可采用 OpenAPI、Protobuf、消息 Schema 等 |
| 各行其道（Separate Ways） | 上下文不集成，各自实现所需能力 | 集成收益低于耦合成本时使用 |
| 大泥球（Big Ball of Mud） | 现有系统缺乏稳定边界 | 应隔离而不是让其模型扩散到新上下文 |

上下文映射必须标明上游和下游。技术调用方向不一定等于业务依赖方向：下游可以通过 HTTP 调用上游，也可以订阅上游事件，但其模型仍受上游契约影响。

### 5.4 边界与部署单元

限界上下文首先是逻辑和模型边界，部署方式是后续决策。

```text
一个限界上下文 -> 一个模块 -> 同一进程内调用
一个限界上下文 -> 一个或多个服务 -> 远程调用或消息
多个小型限界上下文 -> 一个部署单元 -> 模块间保持显式边界
```

对于多数新系统，先构建模块化单体通常更稳妥：它保留本地事务、调试和部署的简单性，同时允许以后根据团队自治、发布频率、扩展需求和故障隔离要求拆分服务。

## 6. 领域建模方法

### 6.1 事件风暴

事件风暴（Event Storming）通过已经发生的业务事实梳理流程，适合业务专家和技术人员共同建模。典型步骤如下：

1. 明确业务范围和研讨目标。
2. 按时间顺序列出领域事件，例如“订单已提交”“支付已授权”“库存已占用”。
3. 找出触发事件的命令，例如“提交订单”“授权支付”。
4. 标记发出命令的参与者或外部系统。
5. 补充决策所需的读模型、业务规则和策略。
6. 标记冲突、异常、等待和认知不一致等热点。
7. 按业务能力和语言边界对事件聚类，识别候选子域与限界上下文。
8. 通过具体业务场景回放模型，验证正常路径和失败路径。

事件风暴的产物不是最终架构。它提供业务事实、命令、规则和边界假设，仍需通过代码、测试和实际业务反馈验证。

### 6.2 其他建模方式

- **领域故事讲述（Domain Storytelling）**：通过参与者、工作对象和活动描述业务协作，适合澄清人员与系统之间的职责。
- **四色建模**：围绕时标对象、角色、地点/物品和描述对象识别业务模型，适合业务凭证和流程密集的领域。
- **示例映射（Example Mapping）**：用规则、示例和问题细化验收标准，适合把模型连接到可执行测试。
- **状态机建模**：适合生命周期和状态转换严格的实体，例如订单、合同和理赔案件。

建模方法服务于理解业务，不应形成与实现脱节的大量图表。模型中的关键名词、动词和约束应能在代码中找到对应表达。

## 7. 战术设计

### 7.1 实体

实体（Entity）由身份和生命周期定义，而不是由全部属性值定义。两个订单即使内容完全相同，只要订单标识不同，就仍是不同实体。

实体应：

- 使用稳定身份。
- 封装状态变化，不公开任意 Setter。
- 通过业务方法表达意图。
- 在方法内部维护自身不变量。
- 避免依赖数据库、Web 框架和消息中间件。

### 7.2 值对象

值对象（Value Object）由属性值定义，没有需要独立跟踪的身份。金额、货币、地址、时间范围和坐标通常适合建模为值对象。

值对象应：

- 不可变。
- 使用结构相等性。
- 在构造时完成校验。
- 封装与该值相关的运算。
- 整体替换，而不是逐字段修改。

值对象并非“没有主键的数据表”。是否需要身份取决于领域语义，而不是持久化方式。

### 7.3 聚合与聚合根

聚合（Aggregate）是一组作为数据修改和一致性单元的领域对象。聚合根（Aggregate Root）是外部访问聚合的唯一入口。

聚合承担两项核心职责：

1. 保护必须在事务提交时成立的不变量。
2. 限制对象图和事务边界，防止任意跨对象修改。

聚合设计原则：

- 聚合应尽量小，只包含需要强一致维护的状态。
- 外部只能通过聚合根修改聚合内部对象。
- 仓储以聚合根为单位加载和保存。
- 聚合之间优先通过标识引用，而不是持有可修改对象引用。
- 一个应用事务通常只修改一个聚合实例。
- 跨对象计算可以由领域服务表达；跨聚合状态协作通常通过领域事件或流程管理器完成。
- 跨聚合一致性默认采用最终一致性；只有业务确实要求时才扩大事务范围。
- 聚合边界由业务不变量决定，不由页面一次提交的字段数量决定。

“订单及其明细必须一起满足金额和状态规则”可以形成一个聚合；“订单提交后需要占用库存”通常涉及订单和库存两个聚合，不应把整个库存对象图放入订单聚合。

### 7.4 领域服务、应用服务与基础设施服务

| 类型 | 职责 | 可以包含的内容 | 不应包含的内容 |
| --- | --- | --- | --- |
| 领域服务 | 表达不自然属于单个实体或值对象的领域操作 | 跨对象计算、领域策略、业务判断 | HTTP、事务提交、DTO 转换、消息中间件调用 |
| 应用服务 | 编排一个用例 | 加载聚合、调用领域行为、权限协调、提交事务、发布结果 | 核心业务规则和复杂状态判断 |
| 基础设施服务 | 实现外部技术能力 | 邮件、存储、第三方 API、消息和时钟适配器 | 决定领域状态是否合法的规则 |

优先把行为放入拥有相关状态的实体或值对象。只有当操作确实不属于任何单个对象时，才使用领域服务。把所有逻辑放入 `OrderDomainService` 会重新产生贫血模型。

领域服务所需的外部能力应通过接口表达。接口放在领域层还是应用层取决于
使用者和语义所有权，技术实现仍位于基础设施层。

### 7.5 领域事件

领域事件（Domain Event）表示领域中已经发生且业务关心的事实，名称通常使用过去式，例如：

- `OrderSubmitted`
- `PaymentAuthorized`
- `InventoryReserved`

领域事件应是不可变事实，通常包含事件标识、发生时间、聚合标识和消费者需要的最小业务信息。不要把可修改实体对象直接放入事件。

领域事件与集成事件需要区分：

| 类型 | 边界 | 主要用途 | 稳定性要求 |
| --- | --- | --- | --- |
| 领域事件 | 限界上下文内部 | 解耦领域行为、触发内部策略 | 可随内部模型重构 |
| 集成事件 | 限界上下文之间 | 通知其他服务或模块 | 属于版本化公共契约 |

领域事件只有在相关事务成功后才能被视为对外成立。常见做法是先在聚合中暂存事件，提交业务数据与 Outbox 消息，再异步发布集成事件。

### 7.6 命令、策略与流程管理器

- **命令（Command）**表示调用方希望系统执行的动作，可以被拒绝，例如 `SubmitOrder`。
- **领域事件**表示已经发生的事实，不应被“撤销发布”。
- **策略（Policy）**描述“当某事件发生时，根据规则发出后续命令”。
- **流程管理器（Process Manager）**维护长业务流程状态，根据多个参与者的结果决定下一步。
- **Saga**由一系列本地事务构成，失败时执行补偿动作或采用前向恢复。补偿是新的业务行为，不是跨服务数据库回滚。

### 7.7 仓储

仓储（Repository）为聚合提供类似集合的访问语义，隐藏持久化细节。仓储接口通常围绕用例设计：

- 按标识加载聚合。
- 添加新聚合。
- 删除聚合（仅在领域允许时）。
- 必要的业务查找或存在性判断。

不建议为每张表建立仓储，也不建议默认引入包含大量 CRUD 方法的
`IGenericRepository<TEntity>`。泛型仓储容易泄露 `IQueryable`、
绕过聚合边界，并重复 ORM 已提供的能力。

查询报表、列表和搜索不必通过聚合仓储。它们可以使用专用 Query Service、只读数据库访问或 CQRS 读模型。

### 7.8 工厂与规格

- **工厂（Factory）**封装复杂对象或聚合的创建过程，确保新对象从一开始就有效。简单构造不需要额外工厂。
- **规格（Specification）**把可组合的业务判断表达为对象，适合需要复用和组合的领域规则。不要把 ORM 查询条件全部包装成规格后误认为完成了领域建模。

### 7.9 模块

模块（Module）也是领域模型的一部分。模块应围绕业务概念组织，并使用统一语言
命名，而不是只按 `Entities`、`Services`、`Repositories` 等技术类型分组。

模块设计应满足：

- 模块内部概念高度内聚。
- 模块之间依赖少且方向明确。
- 公开接口小于内部实现。
- 聚合内部类型尽可能保持 `internal` 或私有。
- 模块名称能向业务人员解释其职责。
- 循环依赖通常意味着职责或边界仍需调整。

解决方案可以在项目级按层隔离依赖，同时在每个项目内部按业务能力组织。例如，
`Sales.Domain/Orders`、`Sales.Application/Orders` 比把所有实体集中到一个巨大
`Entities` 目录更容易维护模型边界。

### 7.10 模型表达质量

可执行模型不仅要正确，还要便于阅读和修改。

| 原则 | 含义 | 在订单示例中的体现 |
| --- | --- | --- |
| 意图揭示接口 | 方法名称直接表达业务动作 | `Submit`、`AddLine`、`ChangeLineQuantity` |
| 显式不变量 | 规则在负责对象中集中校验 | 空订单不能提交、提交后不能修改 |
| 无副作用函数 | 计算返回新值，不修改输入 | `Money.Add`、`Money.Multiply` |
| 概念轮廓 | 代码边界贴合领域中的稳定概念 | `Money`、`Order`、`OrderLine` |
| 最小知识 | 对象只了解完成职责所需的信息 | 订单只保存客户和商品标识 |
| 闭合运算 | 运算结果仍属于同一概念类型 | 金额相加后仍返回 `Money` |

当一个方法需要大量布尔参数、技术枚举或无含义的 `string` 才能调用时，通常说明
统一语言尚未进入接口，或者缺少值对象与明确的业务操作。

## 8. C# 示例：订单聚合

以下示例位于“销售”限界上下文，业务规则为：

- 订单创建后处于草稿状态。
- 只有草稿订单可以添加明细。
- 数量必须大于零，单价不能为负数。
- 一个订单只允许使用一种货币。
- 没有明细的订单不能提交。
- 提交后的订单不能再次修改或提交。

示例只展示领域模型的核心结构，生产代码还应补充授权、持久化映射、并发控制、日志和集成事件发布。

为控制示例篇幅，`Money` 统一保留两位小数。生产系统应根据币种最小单位、计价精度和舍入策略建模，不能假设所有货币都使用两位小数。

代码采用现代 C# 语法，其中 `[]` 集合表达式需要 C# 12。使用旧版本语言时，
可改为 `new List<T>()`，不影响领域模型本身。

### 8.1 值对象和强类型标识

```csharp
using System;
using System.Linq;

namespace Sales.Domain.Orders;

public sealed class DomainRuleViolationException : Exception
{
    public DomainRuleViolationException(string message)
        : base(message)
    {
    }
}

public readonly record struct OrderId(Guid Value)
{
    public static OrderId New() => new(Guid.NewGuid());
}

public readonly record struct CustomerId(Guid Value);

public readonly record struct ProductId(Guid Value);

public readonly record struct OrderLineId(Guid Value)
{
    public static OrderLineId New() => new(Guid.NewGuid());
}

public sealed record Money
{
    public decimal Amount { get; }

    public string Currency { get; }

    public Money(decimal amount, string currency)
    {
        if (amount < 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(amount),
                "Amount cannot be negative.");
        }

        if (string.IsNullOrWhiteSpace(currency))
        {
            throw new ArgumentException(
                "Currency is required.",
                nameof(currency));
        }

        var normalizedCurrency =
            currency.Trim().ToUpperInvariant();

        if (normalizedCurrency.Length != 3 ||
            normalizedCurrency.Any(
                static character =>
                    character is < 'A' or > 'Z'))
        {
            throw new ArgumentException(
                "Currency must be a three-letter code.",
                nameof(currency));
        }

        Amount = decimal.Round(amount, 2, MidpointRounding.ToEven);
        Currency = normalizedCurrency;
    }

    public Money Add(Money other)
    {
        ArgumentNullException.ThrowIfNull(other);

        if (!StringComparer.Ordinal.Equals(Currency, other.Currency))
        {
            throw new DomainRuleViolationException(
                $"Cannot add {Currency} and {other.Currency}.");
        }

        return new Money(Amount + other.Amount, Currency);
    }

    public Money Multiply(int quantity)
    {
        if (quantity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(quantity));
        }

        return new Money(Amount * quantity, Currency);
    }

    public static Money Zero(string currency) => new(0m, currency);
}
```

`Money` 使用值相等性且不可变。货币校验和金额运算位于值对象内部，调用方不能绕过规则直接拼接数值。

### 8.2 领域事件基础类型

```csharp
using System;
using System.Collections.Generic;

namespace Sales.Domain.Abstractions;

public interface IDomainEvent
{
    Guid EventId { get; }

    DateTimeOffset OccurredAtUtc { get; }
}

public abstract class AggregateRoot
{
    private readonly List<IDomainEvent> _domainEvents = [];

    public IReadOnlyCollection<IDomainEvent> DomainEvents =>
        _domainEvents.AsReadOnly();

    protected void Raise(IDomainEvent domainEvent)
    {
        ArgumentNullException.ThrowIfNull(domainEvent);
        _domainEvents.Add(domainEvent);
    }

    public void ClearDomainEvents() => _domainEvents.Clear();
}
```

领域事件暂存列表是实现选择，不是 DDD 的强制规定。它的作用是让事务边界在保存聚合后统一处理事件，避免领域对象直接依赖消息总线。

### 8.3 实体、聚合根和不变量

```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using Sales.Domain.Abstractions;

namespace Sales.Domain.Orders;

public enum OrderStatus
{
    Draft = 0,
    Submitted = 1,
    Cancelled = 2
}

public sealed class OrderLine
{
    private OrderLine()
    {
    }

    internal OrderLine(
        OrderLineId id,
        ProductId productId,
        int quantity,
        Money unitPrice)
    {
        if (quantity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(quantity));
        }

        Id = id;
        ProductId = productId;
        Quantity = quantity;
        UnitPrice = unitPrice
            ?? throw new ArgumentNullException(nameof(unitPrice));
    }

    public OrderLineId Id { get; private set; }

    public ProductId ProductId { get; private set; }

    public int Quantity { get; private set; }

    public Money UnitPrice { get; private set; } = null!;

    public Money Subtotal => UnitPrice.Multiply(Quantity);

    internal void ChangeQuantity(int quantity)
    {
        if (quantity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(quantity));
        }

        Quantity = quantity;
    }
}

public sealed record OrderSubmittedDomainEvent(
    Guid EventId,
    DateTimeOffset OccurredAtUtc,
    OrderId OrderId,
    CustomerId CustomerId,
    Money Total) : IDomainEvent;

public sealed class Order : AggregateRoot
{
    private readonly List<OrderLine> _lines = [];

    private Order()
    {
    }

    private Order(
        OrderId id,
        CustomerId customerId,
        string currency,
        DateTimeOffset createdAtUtc)
    {
        if (string.IsNullOrWhiteSpace(currency))
        {
            throw new ArgumentException(
                "Currency is required.",
                nameof(currency));
        }

        var normalizedCurrency =
            currency.Trim().ToUpperInvariant();

        if (normalizedCurrency.Length != 3 ||
            normalizedCurrency.Any(
                static character =>
                    character is < 'A' or > 'Z'))
        {
            throw new ArgumentException(
                "Currency must be a three-letter code.",
                nameof(currency));
        }

        Id = id;
        CustomerId = customerId;
        Currency = normalizedCurrency;
        CreatedAtUtc = createdAtUtc;
        Status = OrderStatus.Draft;
    }

    public OrderId Id { get; private set; }

    public CustomerId CustomerId { get; private set; }

    public string Currency { get; private set; } = string.Empty;

    public OrderStatus Status { get; private set; }

    public DateTimeOffset CreatedAtUtc { get; private set; }

    public DateTimeOffset? SubmittedAtUtc { get; private set; }

    public IReadOnlyCollection<OrderLine> Lines => _lines.AsReadOnly();

    public Money Total => _lines.Aggregate(
        Money.Zero(Currency),
        static (total, line) => total.Add(line.Subtotal));

    public static Order Create(
        CustomerId customerId,
        string currency,
        DateTimeOffset createdAtUtc)
    {
        return new Order(
            OrderId.New(),
            customerId,
            currency,
            createdAtUtc);
    }

    public void AddLine(
        ProductId productId,
        int quantity,
        Money unitPrice)
    {
        EnsureDraft();
        ArgumentNullException.ThrowIfNull(unitPrice);

        if (!StringComparer.Ordinal.Equals(Currency, unitPrice.Currency))
        {
            throw new DomainRuleViolationException(
                $"Order currency is {Currency}, " +
                $"but line currency is {unitPrice.Currency}.");
        }

        _lines.Add(
            new OrderLine(
                OrderLineId.New(),
                productId,
                quantity,
                unitPrice));
    }

    public void ChangeLineQuantity(
        OrderLineId lineId,
        int quantity)
    {
        EnsureDraft();

        var line = _lines.SingleOrDefault(x => x.Id == lineId)
            ?? throw new DomainRuleViolationException(
                $"Order line {lineId.Value} was not found.");

        line.ChangeQuantity(quantity);
    }

    public void Submit(DateTimeOffset submittedAtUtc)
    {
        EnsureDraft();

        if (_lines.Count == 0)
        {
            throw new DomainRuleViolationException(
                "An empty order cannot be submitted.");
        }

        if (submittedAtUtc < CreatedAtUtc)
        {
            throw new DomainRuleViolationException(
                "Submission time cannot be earlier than creation time.");
        }

        Status = OrderStatus.Submitted;
        SubmittedAtUtc = submittedAtUtc;

        Raise(
            new OrderSubmittedDomainEvent(
                Guid.NewGuid(),
                submittedAtUtc,
                Id,
                CustomerId,
                Total));
    }

    private void EnsureDraft()
    {
        if (Status != OrderStatus.Draft)
        {
            throw new DomainRuleViolationException(
                $"Order in {Status} status cannot be modified.");
        }
    }
}
```

该模型具有以下特征：

- `Order` 是聚合根，外部不能直接创建或修改 `OrderLine`。
- 状态属性没有公共 Setter。
- `AddLine`、`ChangeLineQuantity` 和 `Submit` 使用统一语言表达业务意图。
- 不变量位于聚合和值对象内部，而不是放在 Controller 中。
- 聚合只保存 `CustomerId` 和 `ProductId`，不持有客户与商品聚合。
- 领域事件记录已经发生的业务事实，但不直接发送消息。

### 8.4 仓储和应用服务

```csharp
using System.Threading;
using System.Threading.Tasks;
using Sales.Domain.Orders;

namespace Sales.Application.Abstractions;

public interface IOrderRepository
{
    Task<Order?> GetAsync(
        OrderId orderId,
        CancellationToken cancellationToken);

    Task AddAsync(
        Order order,
        CancellationToken cancellationToken);
}

public interface IUnitOfWork
{
    Task<int> SaveChangesAsync(
        CancellationToken cancellationToken);
}
```

仓储接口放在领域层还是应用层取决于团队约定。关键约束是接口表达领域或用例需要，基础设施实现该接口，领域模型不依赖具体 ORM。

```csharp
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Sales.Application.Abstractions;
using Sales.Domain.Orders;

namespace Sales.Application.Orders.SubmitOrder;

public sealed record SubmitOrderCommand(
    Guid OrderId,
    DateTimeOffset SubmittedAtUtc);

public sealed class SubmitOrderHandler
{
    private readonly IOrderRepository _orders;
    private readonly IUnitOfWork _unitOfWork;

    public SubmitOrderHandler(
        IOrderRepository orders,
        IUnitOfWork unitOfWork)
    {
        _orders = orders;
        _unitOfWork = unitOfWork;
    }

    public async Task Handle(
        SubmitOrderCommand command,
        CancellationToken cancellationToken)
    {
        var orderId = new OrderId(command.OrderId);

        var order = await _orders.GetAsync(
            orderId,
            cancellationToken);

        if (order is null)
        {
            throw new KeyNotFoundException(
                $"Order {command.OrderId} was not found.");
        }

        order.Submit(command.SubmittedAtUtc);

        await _unitOfWork.SaveChangesAsync(cancellationToken);
    }
}
```

Application Handler 只负责编排：加载聚合、调用领域行为并提交工作单元。能决定订单是否允许提交的规则仍位于 `Order`。

### 8.5 EF Core 映射

持久化映射属于基础设施层。以下配置以 EF Core 关系数据库提供程序为例。领域对象可以为 ORM 保留私有无参构造函数，但不应暴露公共 Setter 破坏不变量。

```csharp
using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Sales.Domain.Orders;

namespace Sales.Infrastructure.Persistence.Configurations;

public sealed class OrderConfiguration
    : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> builder)
    {
        builder.ToTable("Orders");

        builder.HasKey(x => x.Id);

        builder.Property(x => x.Id)
            .HasConversion(
                id => id.Value,
                value => new OrderId(value));

        builder.Property(x => x.CustomerId)
            .HasConversion(
                id => id.Value,
                value => new CustomerId(value));

        builder.Property(x => x.Currency)
            .HasMaxLength(3)
            .IsRequired();

        builder.Property(x => x.Status)
            .HasConversion<string>()
            .HasMaxLength(32);

        builder.Ignore(x => x.DomainEvents);
        builder.Ignore(x => x.Total);

        builder.OwnsMany(
            x => x.Lines,
            line =>
            {
                line.ToTable("OrderLines");
                line.WithOwner().HasForeignKey("OrderId");

                line.HasKey("OrderId", nameof(OrderLine.Id));

                line.Property(x => x.Id)
                    .HasConversion(
                        id => id.Value,
                        value => new OrderLineId(value));

                line.Property(x => x.ProductId)
                    .HasConversion(
                        id => id.Value,
                        value => new ProductId(value));

                line.OwnsOne(
                    x => x.UnitPrice,
                    money =>
                    {
                        money.Property(x => x.Amount)
                            .HasColumnName("UnitPriceAmount")
                            .HasPrecision(18, 2);

                        money.Property(x => x.Currency)
                            .HasColumnName("UnitPriceCurrency")
                            .HasMaxLength(3)
                            .IsRequired();
                    });
            });

        builder.Navigation(x => x.Lines)
            .UsePropertyAccessMode(PropertyAccessMode.Field);
    }
}
```

映射策略应服务于聚合边界。为了方便 ORM 而把内部集合改成公共可写集合，等于让持久化技术反向控制领域模型。

### 8.6 聚合单元测试

聚合测试应直接验证业务行为和不变量，不需要启动 Web Host 或连接数据库。

```csharp
using System;
using Sales.Domain.Orders;
using Xunit;

namespace Sales.Domain.Tests.Orders;

public sealed class OrderTests
{
    [Fact]
    public void Submit_without_lines_is_rejected()
    {
        var order = Order.Create(
            new CustomerId(Guid.NewGuid()),
            "CNY",
            new DateTimeOffset(
                2026,
                8,
                9,
                10,
                0,
                0,
                TimeSpan.Zero));

        Action act = () => order.Submit(
            new DateTimeOffset(
                2026,
                8,
                9,
                10,
                1,
                0,
                TimeSpan.Zero));

        Assert.Throws<DomainRuleViolationException>(act);
    }

    [Fact]
    public void Submit_valid_order_changes_status_and_records_event()
    {
        var createdAt = DateTimeOffset.UtcNow;
        var order = Order.Create(
            new CustomerId(Guid.NewGuid()),
            "CNY",
            createdAt);

        order.AddLine(
            new ProductId(Guid.NewGuid()),
            2,
            new Money(50m, "CNY"));

        order.Submit(createdAt.AddMinutes(1));

        Assert.Equal(OrderStatus.Submitted, order.Status);
        Assert.Equal(new Money(100m, "CNY"), order.Total);

        var domainEvent =
            Assert.Single(order.DomainEvents);

        var submitted =
            Assert.IsType<OrderSubmittedDomainEvent>(domainEvent);

        Assert.Equal(order.Id, submitted.OrderId);
        Assert.Equal(order.Total, submitted.Total);
    }

    [Fact]
    public void Add_line_with_different_currency_is_rejected()
    {
        var order = Order.Create(
            new CustomerId(Guid.NewGuid()),
            "CNY",
            DateTimeOffset.UtcNow);

        Action act = () => order.AddLine(
            new ProductId(Guid.NewGuid()),
            1,
            new Money(10m, "USD"));

        Assert.Throws<DomainRuleViolationException>(act);
    }
}
```

测试名称应使用领域语言描述业务规则，而不是只验证属性 Setter 或 ORM 行为。

## 9. 应用架构与依赖方向

经典四层架构可以按以下职责组织：

| 层 | 职责 | 典型内容 |
| --- | --- | --- |
| 接口层（Presentation） | 转换外部协议 | ASP.NET Core Endpoint、消息消费者 |
| 应用层（Application） | 编排用例和事务 | Command/Query Handler、Application Service、端口接口 |
| 领域层（Domain） | 表达业务模型和规则 | 聚合、实体、值对象、领域服务、领域事件 |
| 基础设施层（Infrastructure） | 实现技术能力 | EF Core、消息总线、文件、缓存、第三方客户端 |

推荐的依赖方向：

```text
Presentation / Composition Root
  +---> Application ------> Domain
  +---> Infrastructure ---> Application
                       +---> Domain

Domain -X-> Application / Infrastructure / Presentation
```

在实际 .NET 解决方案中，通常由 Composition Root 引用各实现并完成依赖注入。
领域层不引用 ASP.NET Core、EF Core、消息中间件 SDK 或具体数据库驱动。

示例目录：

```text
src/
  Sales.Domain/
    Orders/
      Order.cs
      Money.cs
      OrderSubmittedDomainEvent.cs
  Sales.Application/
    Abstractions/
    Orders/
      SubmitOrder/
  Sales.Infrastructure/
    Persistence/
    Messaging/
  Sales.Api/
    Endpoints/
tests/
  Sales.Domain.Tests/
  Sales.Application.Tests/
  Sales.Infrastructure.Tests/
```

目录结构只是边界的可视化。真正的架构约束来自项目引用、公开类型范围、事务边界和自动化架构测试。

### 9.1 六边形架构

六边形架构将应用核心视为六边形内部，将外部交互分为端口和适配器：

- **输入端口**：应用提供的用例，例如 Command Handler。
- **输入适配器**：HTTP Endpoint、CLI、消息消费者、定时任务。
- **输出端口**：应用需要的能力，例如仓储、时钟、支付网关接口。
- **输出适配器**：EF Core 仓储、第三方支付客户端、消息发布器。

同一个用例可以由 HTTP、消息或测试代码调用；更换数据库或第三方 SDK 不应改变领域规则。

## 10. 事务、一致性与并发

### 10.1 聚合内强一致

聚合方法执行结束时，应满足聚合内部不变量。一个数据库事务通常对应一次应用用例：

1. 加载聚合。
2. 调用领域行为。
3. 保存聚合。
4. 提交事务。
5. 处理提交后动作。

不要在聚合方法内部调用 `SaveChanges`。事务由应用层或工作单元控制，领域对象只负责业务决策。

### 10.2 跨聚合最终一致

订单提交、支付授权和库存占用分别属于不同聚合或上下文时，不应通过一个巨大对象图伪造强一致。常见流程如下：

```text
提交订单
  -> 销售事务：订单变为 Submitted
  -> 发布 OrderSubmitted 集成事件
  -> 库存事务：创建库存预留
  -> 发布 InventoryReserved 或 InventoryReservationFailed
  -> 流程管理器推进订单，或触发补偿
```

设计最终一致性时必须明确：

- 业务允许的中间状态。
- 超时和重试策略。
- 重复消息的幂等处理。
- 消息乱序处理。
- 失败后的补偿或人工介入。
- 状态查询和运维可见性。

### 10.3 乐观并发

同一个聚合可能被并发修改。可使用版本号或数据库行版本进行乐观并发控制：

1. 加载聚合及版本。
2. 修改聚合。
3. 更新时带上原版本条件。
4. 更新行数为零时抛出并发冲突。
5. 根据用例决定重新加载、重试或返回冲突。

自动重试并不总是安全。例如两个操作分别提交和取消同一订单时，重放命令必须重新经过业务规则，而不能简单覆盖状态。

### 10.4 Outbox

业务数据写入成功而消息发布失败，会造成其他上下文永远收不到事件；消息先发布而事务回滚，则会发布一个未成立的事实。Outbox 通过同一数据库事务写入业务数据和待发送消息来解决该问题。

典型流程：

1. 聚合产生领域事件。
2. 应用将需要跨边界传播的事件转换为集成事件。
3. 在同一事务中保存聚合和 Outbox 记录。
4. 后台发布器读取未发送记录并发送到消息系统。
5. 发布成功后标记记录；失败则重试。

Outbox 通常提供“至少一次”投递，而不是“恰好一次”。消费者仍需使用事件标识、业务键或 Inbox 表实现幂等。

## 11. CQRS、事件驱动与事件溯源

### 11.1 CQRS

CQRS 的最小形式是分离命令和查询：

- Command 表达改变状态的意图，经过领域模型和事务。
- Query 不产生业务写副作用，直接返回面向调用方的读模型。

CQRS 不要求：

- 不同数据库。
- 消息中间件。
- 事件溯源。
- 每个查询都异步。
- 每个 CRUD 操作都建立复杂 Handler 管道。

可按复杂度逐步采用：

| 级别 | 写侧 | 读侧 | 一致性 |
| --- | --- | --- | --- |
| 逻辑分离 | Command Handler | Query Handler | 同一数据库、即时一致 |
| 模型分离 | 领域聚合 | 专用 SQL/DTO | 同一数据库、即时或近即时 |
| 存储分离 | 写库 | 读库或搜索引擎 | 事件同步、最终一致 |

当读写模型差异不大时，简单查询服务通常足够。

### 11.2 事件驱动架构

事件驱动可以降低发送方对消费者的直接依赖，但会引入：

- 最终一致性。
- 重复、丢失和乱序处理。
- Schema 演进。
- 分布式追踪。
- 消费积压与故障恢复。

事件名称应表达业务事实，而不是数据库变化。`OrderSubmitted` 比 `OrderRowUpdated` 更稳定，也更符合统一语言。

### 11.3 事件溯源

事件溯源以不可变事件序列作为聚合状态的事实来源，当前状态通过重放事件得到。

适用场景：

- 业务必须保留完整决策历史。
- 状态变化过程本身具有业务价值。
- 需要基于历史事件构建多种投影。
- 领域天然以事件表达，例如账务流水或交易撮合。

主要代价：

- 事件版本和兼容性管理。
- 投影重建与快照策略。
- 调试方式改变。
- 删除、隐私和合规处理更复杂。
- 最终一致性的读模型。

普通状态持久化加 Outbox 已能满足很多系统，不应因为采用 DDD 就默认使用事件溯源。

## 12. 查询与跨上下文集成

### 12.1 查询不应破坏聚合边界

聚合用于业务决策和状态变更，不适合承担所有展示查询。列表、统计和跨聚合搜索可以使用：

- 专用 SQL 或只读 DbContext。
- 数据库视图。
- 搜索索引。
- CQRS 投影。
- API Composition。

查询模型可以针对页面或客户端设计，不必与领域实体一一对应。查询路径绕过聚合是允许的，前提是它不借此修改领域状态。

### 12.2 防腐层

防腐层负责将外部模型翻译为当前上下文的语言。它可以包含：

- 外部 API Client。
- 外部 DTO。
- 当前上下文的端口接口。
- DTO 与领域概念之间的转换器。
- 错误码、枚举和状态语义映射。

防腐层的目的不是隐藏所有技术细节，而是防止外部模型成为当前领域模型的事实标准。

### 12.3 契约设计

跨上下文契约应：

- 只暴露消费者需要的信息。
- 明确版本和兼容策略。
- 使用稳定业务语义。
- 区分命令、查询和事件。
- 明确幂等键、相关标识和时间语义。
- 避免直接序列化内部领域实体。

## 13. 测试策略

DDD 项目的测试重点是模型规则和边界，而不是追求每层都有相同形式的测试。

| 测试类型 | 验证内容 |
| --- | --- |
| 值对象单元测试 | 构造约束、相等性、运算 |
| 聚合单元测试 | 状态转换、不变量、领域事件 |
| 领域服务单元测试 | 跨对象业务计算和策略 |
| 应用服务测试 | 用例编排、事务调用、错误映射 |
| 仓储集成测试 | 聚合完整保存与重新加载、并发版本 |
| 消息集成测试 | Outbox、序列化、重复消费和失败重试 |
| 契约测试 | 上下文之间 API 或消息 Schema 的兼容性 |
| 架构测试 | 项目引用和命名空间依赖是否符合约束 |
| 端到端测试 | 少量关键业务链路 |

测试应覆盖失败路径和边界条件，例如：

- 重复提交订单。
- 空订单提交。
- 不同货币混用。
- 并发更新冲突。
- 事件重复消费。
- Saga 某一步超时后恢复。

## 14. 落地流程

### 14.1 发现与建模

1. 选择一个有明确业务价值和边界的场景。
2. 邀请真正掌握规则的业务专家参与。
3. 使用事件风暴或领域故事梳理事件、命令、规则和异常。
4. 建立初始统一语言，记录歧义和待确认问题。
5. 识别子域、限界上下文及上下游关系。
6. 选择核心子域中的一个垂直切片作为试点。

### 14.2 实现

1. 从必须保护的不变量识别聚合边界。
2. 使用实体和值对象表达状态和规则。
3. 用应用服务编排用例。
4. 定义最小仓储和外部端口。
5. 在基础设施层实现持久化和集成。
6. 优先完成聚合单元测试和仓储集成测试。
7. 根据真实查询需求决定是否引入 CQRS。
8. 根据跨边界可靠性要求决定是否引入 Outbox、Saga。

### 14.3 持续演进

- 在需求评审、代码评审和验收中使用统一语言。
- 新业务规则出现时，先确定其所属上下文和责任对象。
- 定期检查上下文之间的同步调用、共享表和共享模型。
- 记录重要模型决策及替代方案。
- 使用架构测试防止依赖方向退化。
- 通过生产事件、错误和运营反馈修正模型。

DDD 的模型不是“设计完成后冻结”的产物，而是团队对业务认知的可执行版本。

## 15. 常见错误

### 15.1 只复制目录和基类

创建 `Domain`、`Application`、`Infrastructure` 目录，以及 `EntityBase`、`RepositoryBase`，不代表完成了领域建模。判断标准应是代码能否表达统一语言、业务行为和不变量。

### 15.2 贫血领域模型

实体只包含 Getter/Setter，所有规则都在 Application Service 或 Domain Service 中，会导致：

- 任意调用方都能制造非法状态。
- 规则与数据分离。
- 服务类不断膨胀。
- 聚合边界失去意义。

### 15.3 一个数据库表对应一个聚合

聚合是业务一致性边界，不是表关系的包装。一个聚合可以映射多张表；一张表也可能只是查询模型或基础设施细节。

### 15.4 巨型聚合

为了使用一个事务，把订单、客户、商品、库存和支付放入同一聚合，会造成：

- 加载对象图过大。
- 并发冲突频繁。
- 模块无法独立演进。
- 业务边界被持久化便利性取代。

### 15.5 跨上下文共享实体

共享同一个 NuGet 模型包看似减少重复，实际会把不同上下文绑定到同一语义和发布周期。应共享稳定契约或标识格式，而不是共享可修改领域实体。

### 15.6 仓储泄露 IQueryable

如果仓储返回 `IQueryable<TEntity>`，调用方可以任意拼接查询、加载导航属性并绕过聚合意图。写侧仓储应提供有限、业务化的操作；复杂查询使用专用读路径。

### 15.7 领域事件直接等同于消息

内部领域事件与外部消息具有不同的兼容性、可靠性和安全要求。直接把内部事件发布到消息总线，会让内部重构破坏消费者，并可能在事务回滚前传播无效事实。

### 15.8 过早引入分布式复杂度

DDD 不要求微服务、事件溯源、读写分库或消息中间件。先证明边界和模型有效，再根据独立部署、扩展、自治和一致性需求增加技术机制。

### 15.9 把所有规则放入领域服务

属于实体自身的状态转换应由实体负责。领域服务只处理不自然属于单个对象的业务操作，否则会退化为带 DDD 命名的事务脚本。

### 15.10 忽略失败和时间

分布式业务流程如果只建模成功路径，没有超时、取消、重复、乱序、补偿和人工处理状态，就不是完整模型。

## 16. 设计评审清单

### 16.1 战略设计

- [ ] 核心、支撑和通用子域是否已区分？
- [ ] 每个限界上下文是否有清晰职责和负责人？
- [ ] 同一术语在不同上下文中的含义是否已明确？
- [ ] 上下文映射是否标明上游、下游和翻译策略？
- [ ] 是否存在共享数据库、共享实体或未版本化契约？
- [ ] 服务拆分是否有独立部署或治理方面的真实理由？

### 16.2 战术设计

- [ ] 实体身份和生命周期是否明确？
- [ ] 值对象是否不可变并在构造时保持有效？
- [ ] 聚合边界是否由不变量和事务要求决定？
- [ ] 外部是否只能通过聚合根修改内部状态？
- [ ] 聚合之间是否优先使用标识引用？
- [ ] 核心规则是否位于领域模型而非 Controller？
- [ ] 领域服务是否确实无法归属于实体或值对象？
- [ ] 仓储是否以聚合根为单位并避免泄露 ORM？

### 16.3 一致性与集成

- [ ] 事务边界在哪里开始和结束？
- [ ] 跨聚合流程是否明确允许的中间状态？
- [ ] 领域事件和集成事件是否分离？
- [ ] 业务数据与消息发布是否使用 Outbox 等可靠机制？
- [ ] 消费者是否幂等？
- [ ] 是否处理并发冲突、重复、乱序、超时和补偿？
- [ ] 公共契约是否可版本化并具备兼容策略？

### 16.4 可维护性

- [ ] 代码命名是否与统一语言一致？
- [ ] 领域层是否独立于 Web、ORM 和消息 SDK？
- [ ] 聚合规则是否有快速单元测试？
- [ ] 仓储是否有真实数据库集成测试？
- [ ] 项目引用和边界是否有自动化验证？
- [ ] 模型决策是否能由业务规则解释，而非仅由框架约定解释？

## 17. 术语速查

| 术语 | 定义 |
| --- | --- |
| 领域 | 软件要解决的问题范围 |
| 领域模型 | 对领域关键概念、规则、状态和关系的抽象 |
| 统一语言 | 特定上下文内由业务与技术共同维护的精确语言 |
| 子域 | 问题空间中的业务能力划分 |
| 限界上下文 | 某套模型和语言成立的边界 |
| 上下文映射 | 上下文之间依赖、协作和翻译关系的描述 |
| 实体 | 由身份和生命周期定义的对象 |
| 值对象 | 由属性值定义、通常不可变的对象 |
| 聚合 | 数据修改和一致性边界 |
| 聚合根 | 聚合对外的唯一修改入口 |
| 领域服务 | 不适合归属于单个实体或值对象的领域操作 |
| 应用服务 | 编排用例、事务和外部端口的服务 |
| 领域事件 | 上下文内部已经发生的业务事实 |
| 集成事件 | 跨上下文传播的版本化业务事实 |
| 仓储 | 以聚合为单位提供持久化访问语义的抽象 |
| 防腐层 | 隔离并翻译外部模型的边界层 |
| CQRS | 命令与查询职责及模型的分离 |
| Saga | 由本地事务及补偿或前向恢复组成的长流程 |
| Outbox | 原子保存业务数据和待发布消息的模式 |

## 18. 参考资料

### 18.1 书籍

1. Eric Evans：《领域驱动设计：软件核心复杂性应对之道》
   （*Domain-Driven Design: Tackling Complexity in the Heart of Software*）。
2. Vaughn Vernon：《实现领域驱动设计》（*Implementing Domain-Driven Design*）。

### 18.2 在线资料

1. [领域驱动设计指南](https://ddd-fans.github.io/ddd-guideline/main.html)
2. [领域驱动设计（DDD）架构全解析](https://www.cnblogs.com/wxg1990/articles/19564764)
3. [领域驱动设计（DDD）入门](https://x-gen-lab.github.io/knowledge-os/02-technologies/embedded/10-cross-cutting-concerns/02-software-architecture-design-patterns/intermediate/06-domain-driven-design/)
4. [一文读懂：领域驱动设计 DDD](https://www.zhihu.com/tardis/bd/art/641295531?source_id=1001)
5. [DDD 相关资料（知乎专栏）](https://zhuanlan.zhihu.com/p/1921246706936292234)
6. [【DDD】全网最详细 2 万字讲解 DDD，从理论到实战（代码示例）](https://blog.csdn.net/bookssea/article/details/127248954)
7. [DDD 概念理解——理论篇](https://abelyang.blog.csdn.net/article/details/155675658)

### 18.3 仓库内相关文档

- [.NET 10 技术学习指南：DDD、模块化单体、CQRS 与执行管道](../DotNet/NET10技术学习指南.md#9-ddd模块化单体cqrs-与执行管道)
