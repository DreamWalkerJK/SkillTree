# .NET 10 技术学习指南

> 本文以 [Monica](https://github.com/Tairitsua/Monica) 最新 `dev` 分支为样本，记录其中已经落地的 .NET 10 技术、架构实现和工程约束。本地审计目录为 `D:\Documents\Code\FIPS\MoLibrary`；目录名保留 `MoLibrary`，项目、框架和 NuGet 品牌统一称为 Monica。
>
> 审计基线为提交 `e709de09cf40628a1e3f5468687ae3d709201c76`，提交时间 2026-08-08，项目版本 `1.0.0-rc.12`。审计时，该提交与 GitHub 默认分支 `dev` 一致，本地对应的远程跟踪引用为 `origin/dev`。

## 目录

- [1. 文档目标与使用方式](#1-文档目标与使用方式)
- [2. Monica 技术全景](#2-monica-技术全景)
- [3. .NET 10、C# 14、ASP.NET Core 10 与 EF Core 10 新能力](#3-net-10c-14aspnet-core-10-与-ef-core-10-新能力)
- [4. SDK、项目系统与 NuGet 工程化](#4-sdk项目系统与-nuget-工程化)
- [5. C# 与 .NET 运行时基础](#5-c-与-net-运行时基础)
- [6. Generic Host、依赖注入、配置与 Options](#6-generic-host依赖注入配置与-options)
- [7. ASP.NET Core Web API](#7-aspnet-core-web-api)
- [8. 模块化架构与可组合基础设施](#8-模块化架构与可组合基础设施)
- [9. DDD、模块化单体、CQRS 与执行管道](#9-ddd模块化单体cqrs-与执行管道)
- [10. EF Core 10、Repository 与 Unit of Work](#10-ef-core-10repository-与-unit-of-work)
- [11. 事件驱动、后台任务、韧性与并发控制](#11-事件驱动后台任务韧性与并发控制)
- [12. 日志、指标、链路追踪与运行时诊断](#12-日志指标链路追踪与运行时诊断)
- [13. 认证、授权与应用安全](#13-认证授权与应用安全)
- [14. Blazor、MudBlazor 与运维工作台](#14-blazormudblazor-与运维工作台)
- [15. Roslyn、源生成器与架构分析](#15-roslyn源生成器与架构分析)
- [16. 测试、性能分析与质量保障](#16-测试性能分析与质量保障)
- [17. 分布式集成与 AI 能力](#17-分布式集成与-ai-能力)
- [18. 参考资料](#18-参考资料)

## 1. 文档目标与使用方式

### 1.1 适用范围

本文面向能够独立编写普通 C# 和 ASP.NET Core 应用的读者，讨论范围包括：

- .NET 10 Web API 的宿主、配置、依赖注入和运行生命周期。
- 模块化单体、DDD、CQRS、事件和后台任务的边界设计。
- EF Core、OpenTelemetry、Blazor、Roslyn 及常用分布式组件的组合方式。
- 基础设施的替换边界、诊断能力和测试隔离。
- 运行时 Agent Skills、仓库级 Skill 发布索引和受限文件工具的治理方式。

后文假定读者熟悉以下基础：

- 能使用类、接口、泛型、委托、LINQ、`async`/`await` 和异常处理。
- 能创建并运行 ASP.NET Core 项目。
- 理解 HTTP、JSON、关系型数据库和 Git 的基本概念。

### 1.2 技术来源与边界

Monica 由平台 API、第三方包和自定义框架共同组成。三者的兼容范围和替换成本不同，后文按这一边界标注各项技术。

| 类别 | 示例 | 关注点 |
| --- | --- | --- |
| .NET 10 平台原生能力 | C# 14、Generic Host、依赖注入、配置、`System.Text.Json`、ASP.NET Core、EF Core | 标准 API、生命周期和跨项目通用的运行机制。 |
| 第三方生态 | MudBlazor、Mapster、Serilog、OpenTelemetry、Kafka、Dapr、Redis、Cronos、Qdrant | 组件边界、升级兼容性、运行成本和替换方式。 |
| Monica 自定义设计 | `MonicaModule<TOptions>`、`ModuleRegistration`、ProjectUnit、`Res<T>`、自动控制器、模块诊断 | 项目内部的设计约定及适用条件；这些类型不属于 .NET 标准库。 |

### 1.3 文档组织与源码路径

各章依次说明相关机制、Monica 中的代码位置和独立验证场景。源码分析围绕四条线索展开：

1. 组件的创建方和释放方。
2. 配置在启动期冻结还是在运行期重载。
3. 失败边界，以及错误进入日志、指标或 API 响应的路径。
4. 实现中依赖 Monica 约定的部分，以及可直接迁移到普通 .NET 项目的部分。

本文中的本地目录引用继续使用 `MoLibrary/...`，均相对于 `D:\Documents\Code\FIPS\MoLibrary` 根目录；相同文件可在 [GitHub 源码仓库](https://github.com/Tairitsua/Monica) 中按仓库相对路径定位。

## 2. Monica 技术全景

### 2.1 项目基线

本节统计基于 2026-08-09 对本地仓库和 GitHub 默认分支的交叉检查。公共构建配置位于 `Directory.Build.props`：

- 当前分支为 `dev`，提交为 `e709de09`，包版本为 `1.0.0-rc.12`。
- 目标框架为 `net10.0`。
- 默认使用随 .NET 10 SDK 提供的 C# 14。
- 开启 nullable reference types：`<Nullable>enable</Nullable>`。
- 开启 implicit global usings：`<ImplicitUsings>enable</ImplicitUsings>`。
- 生成 XML 文档文件。
- 使用 `.slnx` 解决方案格式：`Monica.slnx`。
- NuGet 包启用 Source Link、符号包和包级 README。

`1.0.0-rc.12` 仍是 release candidate，在 `1.0.0` 稳定版之前允许出现破坏性调整。当前 `dev` 相比 `v1.0.0-rc.12` 标签后的额外提交只更新 Agent Skill 索引投影，产品项目源码仍对应 rc.12 基线。

仓库共有 78 个受 Git 跟踪的 `.csproj`：47 个产品、模板或生成器项目，23 个测试项目，7 个示例项目和 1 个 Benchmark 项目。其中 17 个使用 Razor SDK，3 个使用 Web SDK，其余以普通类库为主。

`eng/package-tiers.json` 将发布包分为 31 个 Stable、7 个 Integrations 和 6 个 Labs，另有 2 个不发布的 Labs 项目。这套分层直接约束包依赖方向，也决定了测试和发布流程如何组织。

已发布的 Labs 包是 `Monica.AI`、`Monica.AI.UI`、`Monica.DataChannel`、`Monica.DevOps`、`Monica.Office` 和 `Monica.Profiling`。`Monica.Experimental` 与 `Monica.ProjectUnits.CodeAnalysis` 同样按 Labs 管理，但不作为 NuGet 包发布。

仓库当前没有 `global.json`，开发机使用哪个 .NET 10 SDK feature band 取决于本机安装情况。要求构建结果一致时，项目根目录还需明确 SDK 版本和 roll-forward 策略。

`.NET 10` 是长期支持版本，对应 C# 14、ASP.NET Core 10、EF Core 10 和同代 SDK 工具链。

### 2.2 分层视图

```text
C# 14 + .NET 10 Runtime / BCL
                |
                v
Generic Host + DI + Configuration + Logging + Options
                |
                v
ASP.NET Core 10 + EF Core 10 + Blazor + BackgroundService
                |
                v
模块系统 + DDD ProjectUnit + 执行管道 + Repository + EventBus
                |
                v
OpenTelemetry + Serilog + 测试 + Roslyn + 运行时诊断
                |
                v
Kafka / Dapr / Redis / SignalR / 分布式锁 / AI / MCP / RAG / Agent Skills
```

图中的下层是上层的运行基础：Host、DI、异步、HTTP 和数据访问提供生命周期与错误处理约定，模块系统、消息组件和 AI 扩展建立在这些约定之上。

### 2.3 主要技术映射

| 领域 | Monica 代表项目或文件 | 可迁移的 .NET 技术 |
| --- | --- | --- |
| 模块组合 | `Monica.Core/Modularity` | DI 扩展、Options、依赖图、拓扑排序、启动生命周期、反射发现 |
| Web API | `Monica.WebApi`、`Monica.Core/Results` | Minimal API、MVC、Endpoint Filter、OpenAPI、异常处理、统一响应 |
| 领域架构 | `Monica.ProjectUnits`、`examples/Monica.ReferenceApplication` | 模块化单体、DDD、CQRS、Mediator、富领域模型 |
| 数据访问 | `Monica.Repository` | EF Core 10、Repository、Unit of Work、审计、软删除、并发控制 |
| 配置 | `Monica.Configuration` | `IConfiguration`、自定义 Provider、Options、热重载、验证、版本与回滚 |
| 事件与消息 | `Monica.EventBus`、`Monica.EventBus.Kafka`、`Monica.DataChannel` | 进程内事件、分布式消息、发布订阅、消费者生命周期 |
| 后台任务 | `Monica.JobScheduler` | `IHostedService`、`BackgroundService`、Cron、取消、重试、并发限制 |
| 可观测性 | `Monica.OpenTelemetry`、`Monica.Logging`、`Monica.Profiling` | `ILogger`、`ActivitySource`、`Meter`、OTLP、Prometheus、EventPipe |
| UI | `Monica.UI` 及各 `*.UI` 项目 | Blazor Interactive Server、Razor Class Library、MudBlazor、本地化 |
| 编译器平台 | `Monica.Generators.AutoController`、`Monica.ProjectUnits.CodeAnalysis` | Roslyn incremental generator、analyzer、Workspace、MSBuild |
| 测试 | `Monica.Testing`、`tests/Test.Monica.*` | xUnit v3、TestHost、NSubstitute、bUnit、覆盖率、测试隔离 |
| 分布式系统 | `Monica.Dapr`、`Monica.StateStore.*`、`Monica.ServiceDiscovery`、`Monica.Locker` | 状态存储、服务调用、服务发现、分布式锁、最终一致性 |
| AI | `Monica.AI`、`Monica.AI.UI` | `Microsoft.Extensions.AI`、Agent Framework、MCP、RAG、向量数据库、流式输出 |
| Agent 工程 | `skills/`、`.monica/agent-skill-index.json`、`Monica.AI/Modules/ModuleSkillSystem.cs` | Agent Skills、不可变发布索引、摘要校验、文件访问边界、脚本执行策略 |

### 2.4 主要依赖版本快照

版本快照来自同一次本地扫描，用于说明当前组合，不代表兼容性承诺。迁移到其他项目时仍需核对包的兼容范围、变更日志和安全公告。

| 技术 | 扫描到的主要版本 |
| --- | --- |
| Monica | `1.0.0-rc.12`，审计提交 `e709de09` |
| .NET / ASP.NET Core / EF Core | `net10.0`，主要 Microsoft 包为 `10.0.2`；测试工具包中部分为 `10.0.9` |
| Mapster | `7.4.0`，DI adapter `1.0.1` |
| Microsoft.Extensions.Resilience | `10.2.0` |
| OpenTelemetry | SDK/OTLP `1.15.3`，Prometheus ASP.NET Core exporter `1.15.3-beta.1` |
| Serilog.AspNetCore | `10.0.0` |
| MudBlazor | `9.0.0` |
| Dapr .NET SDK | `1.18.4` |
| Confluent.Kafka | `2.13.0` |
| StackExchange.Redis | `2.10.1` |
| Microsoft.Extensions.AI | `10.6.0` |
| Microsoft.Agents.AI | `1.13.0` |
| ModelContextProtocol | `1.2.0` |
| Qdrant.Client | `1.17.0` |
| Roslyn | `Microsoft.CodeAnalysis.* 5.0.0` |
| 测试 | Microsoft.NET.Test.Sdk `18.4.0`、xUnit v3 `3.2.2`、runner `3.1.5`、bUnit `2.7.2`、NSubstitute `5.3.0` |
| BenchmarkDotNet | `0.15.8` |

仓库同时存在 `10.0.2` 和 `10.0.9` 等不同 patch 版本。这可能来自刻意的兼容性覆盖，也可能是尚未统一的版本漂移，需要结合各项目用途确认；相同目标框架不会自动统一 NuGet 版本。

### 2.5 阅读顺序

| 层级 | 内容 | 说明 |
| --- | --- | --- |
| 第一层 | C#、异步、Host、DI、配置、ASP.NET Core、EF Core、测试、日志 | 后续模块直接依赖这些基础。 |
| 第二层 | 模块化、DDD、事件、后台任务、韧性、OpenTelemetry、安全、Blazor 运维页 | 对应项目的 Stable 主路径。 |
| 第三层 | Kafka、Dapr、Redis、SignalR、Roslyn、Profiling、AI、MCP、RAG、Agent Skills | 根据部署形态、业务场景和 Agent 工作流选用。 |

Stable 包不反向依赖 Labs；数据库、Broker、缓存等外部适配器也通过 Integrations 单独引入。这种分层限制了升级影响，也避免 Stable 基础包被可选组件拖入额外依赖。

## 3. .NET 10、C# 14、ASP.NET Core 10 与 EF Core 10 新能力

### 3.1 C# 14

#### Extension members

C# 14 引入 `extension` 块。它不仅能组织扩展方法，还能定义扩展属性和静态扩展成员。Monica 的模块注册入口大量使用了这一语法，例如 `Monica.Authority/Modules/ModuleAuthentication.cs`：

```csharp
public static class ModuleAuthenticationBuilderExtensions
{
    extension(IMonicaBuilder builder)
    {
        public ModuleRegistration<ModuleAuthentication, ModuleAuthenticationOption>
            AddAuthentication(Action<ModuleAuthenticationOption>? configure = null)
        {
            return builder.AddModule<ModuleAuthentication, ModuleAuthenticationOption>(configure);
        }
    }
}
```

与传统 `this` 扩展方法相比，`extension` 块把同一接收类型的扩展成员集中在一起，并支持扩展属性和静态扩展成员。在 Monica 中，这种组织方式正好对应 fluent builder、模块注册和小型领域 DSL。

它的边界包括：

- 扩展成员不会修改目标类型，也不能访问目标类型的私有成员。
- 当实例成员与扩展成员同名时，实例成员优先。
- 与接收类型关系较弱的工具函数放在普通静态类中，调用关系更直观。

#### 其他 C# 14 变化

| 功能 | 含义 | 验证场景 |
| --- | --- | --- |
| `field` backed property | 在属性访问器中访问编译器生成的后备字段，不必手写 `_field`。 | Options 属性中的非空与范围校验。 |
| Null-conditional assignment | `customer?.Order = order` 仅在对象非空时计算并赋值右值。 | 与显式 `if` 的可读性和调试体验对比。 |
| `nameof(List<>)` | `nameof` 支持开放泛型类型。 | 泛型注册诊断中的稳定类型名。 |
| 一等 `Span<T>` 转换 | 数组、`Span<T>`、`ReadOnlySpan<T>` 的组合和类型推断更自然。 | 无额外分配的文本解析及 BenchmarkDotNet 对比。 |
| 简单 Lambda 参数修饰符 | Lambda 可在省略类型时使用 `ref`、`in`、`out` 等修饰符。 | `TryParse<T>` 委托。 |
| partial 构造函数和事件 | 生成代码与手写代码可以共同完成构造或事件实现。 | 源生成器实验中分离声明端和实现端。 |
| 自定义复合赋值运算符 | 类型可以更精确地控制 `+=`、`-=` 等操作。 | 语义明确的值对象。 |

项目源码更频繁地使用 primary constructor、record、collection expression、pattern matching 和 nullable reference types。它们并非都由 C# 14 引入，却构成了当前代码的主要写法。

### 3.2 ASP.NET Core 10

项目代码直接涉及的变化如下：

| 能力 | 行为变化 | 在 Monica 中的落点 |
| --- | --- | --- |
| Minimal API 内置验证 | 调用 `AddValidation()` 后，框架使用源生成器发现端点参数上的 DataAnnotations，并通过端点过滤器执行验证；失败时返回 400。 | `Monica.WebApi` 自带验证和端点生成体系，形成了与平台实现对照的现成样本。 |
| OpenAPI 3.1 | 默认文档版本升级为 3.1，并采用 JSON Schema 2020-12；nullable schema 和 transformer API 与旧版本存在差异。 | 项目同时引用 `Microsoft.AspNetCore.OpenApi` 和 Swashbuckle，升级会涉及 transformer 兼容性。 |
| Server-Sent Events | `TypedResults.ServerSentEvents(...)` 可直接输出 `IAsyncEnumerable<SseItem<T>>`。 | 用于 AI token、任务进度和单向监控流；双向通信仍由 SignalR 承担。 |
| JSON + `PipeReader` | MVC、Minimal API 和 `ReadFromJsonAsync` 默认使用新的 `PipeReader` JSON 路径，减少中间复制。 | 自定义 `JsonConverter` 若未处理 `Utf8JsonReader.HasValueSequence`，跨缓冲区值可能解析失败。 |
| API Cookie 认证行为 | 已知 API 端点在未认证或无权限时默认返回 401/403，而不是重定向登录页。 | 这种变化会影响同时服务浏览器和 API 的认证契约。 |
| Exception Handler diagnostics | 被 `IExceptionHandler` 成功处理的异常默认不再写出异常诊断；可用 `SuppressDiagnosticsCallback` 自定义。 | 该配置决定哪些异常继续进入日志和 telemetry，直接影响重复告警与信号缺失。 |
| Blazor 增强 | 增加指标与追踪、嵌套对象验证、WebAssembly 预加载、circuit state persistence、passkey 模板等。 | `Monica.UI` 使用 Interactive Server 和运维工作台，这些能力直接影响诊断、表单和断线恢复。 |

Minimal API 验证的最小示例：

```csharp
using System.ComponentModel.DataAnnotations;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddValidation();

var app = builder.Build();

app.MapPost("/orders", (CreateOrderRequest request) =>
    TypedResults.Created($"/orders/{Guid.NewGuid()}", request));

app.Run();

public sealed record CreateOrderRequest(
    [property: Required, StringLength(64)] string OrderNumber,
    [property: Range(typeof(decimal), "0.01", "999999999")] decimal Total);
```

DataAnnotations 负责输入形状和简单范围校验。“订单只能审批一次”这类依赖当前状态的规则属于领域对象或应用服务的职责。

`AddValidation()` 使用源生成器，只发现调用所在程序集中的有效验证类型。Minimal API endpoint 位于其他程序集时，注册扩展也要由该程序集提供，并在那里调用 `AddValidation()`。

### 3.3 EF Core 10

EF Core 10 中对本项目影响较大的变化包括：

- **Named query filters**：一个实体可以同时配置软删除、租户等多个有名称的全局过滤器，并按名称只关闭其中一个。
- **`LeftJoin` / `RightJoin`**：.NET 10 增加一等 LINQ 操作符，EF Core 10 可以翻译成对应 SQL，避免过去复杂的 `GroupJoin + DefaultIfEmpty` 写法。
- **更灵活的 `ExecuteUpdateAsync`**：setter 可以使用普通语句 Lambda，便于按条件动态组合批量更新。
- **关系型 JSON 列批量更新**：映射为 complex type 的 JSON 属性可以参与 `ExecuteUpdateAsync`。
- **参数集合翻译改进**：在 SQL 计划缓存和集合基数信息之间采用更合理的默认策略。
- **安全改进**：日志默认遮盖被内联的敏感常量，并对 raw SQL 字符串拼接给出分析器警告。

Named query filters 示例：

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<Order>()
        .HasQueryFilter("SoftDeletionFilter", order => !order.IsDeleted)
        .HasQueryFilter("TenantFilter", order => order.TenantId == _tenantId);
}

var includingDeleted = await dbContext.Orders
    .IgnoreQueryFilters(["SoftDeletionFilter"])
    .ToListAsync(cancellationToken);
```

全局过滤器会隐式进入所有查询，因此测试范围还要覆盖管理端、跨租户任务、数据迁移以及 `IgnoreQueryFilters` 的授权路径。

### 3.4 Runtime、BCL 与 SDK

| 方向 | .NET 10 能力 | 实际影响 |
| --- | --- | --- |
| Runtime | JIT 内联、去虚拟化、栈分配、循环优化和 NativeAOT 持续增强 | 热路径是否受益，以 BenchmarkDotNet 和 profiler 数据为准。 |
| `System.Text.Json` | 严格序列化选项、拒绝重复属性、`PipeReader` 支持等 | 适合安全边界、高吞吐 API 和 AOT 场景，也要求自定义 converter 更严谨。 |
| SDK 测试 | `dotnet test` 支持 Microsoft.Testing.Platform | 理解测试宿主、测试框架与命令行平台是不同层次。 |
| 容器发布 | Console 应用也可原生创建容器镜像，并可显式控制镜像格式 | 简单发布无需 Dockerfile；复杂系统仍涉及镜像层、用户权限和运行时配置。 |
| File-based apps | 单文件 C# 应用的运行、发布和 NativeAOT 能力增强 | 定位于运维脚本、实验和小工具，不替代结构化的大型解决方案。 |
| CLI 工具 | `dotnet tool exec`、`dnx`、CLI schema、原生补全脚本 | 用于仓库级工具和可重复的开发流程。 |

## 4. SDK、项目系统与 NuGet 工程化

### 4.1 项目系统为什么重要

大型 .NET 项目的行为不只由 `.cs` 文件决定。目标框架、编译选项、包引用、分析器、生成器、静态资源、打包元数据和测试平台都由 MSBuild 项目系统驱动。

Monica 将工程行为集中在以下文件中：

- 在 `Directory.Build.props` 统一设置 `net10.0`、nullable、XML 文档和包元数据。
- 使用 `Directory.Build.targets` 补充构建行为。
- 测试目录通过 `tests/Directory.Packages.props` 集中管理测试包版本。
- 源生成器项目以 `netstandard2.0` 为目标，并把 DLL 打包到 `analyzers/dotnet/cs`，因为生成器运行在编译器宿主中，不等同于业务运行时库。
- `Monica.Templates` 使用 `PackageType=Template` 交付 `dotnet new` 模板。
- 所有可打包项目启用 Source Link 和符号包，便于消费者调试 NuGet 源码。

### 4.2 关键项目属性

当前根级 `Directory.Build.props` 的公共编译部分如下：

```xml
<Project>
  <PropertyGroup>
    <SatelliteResourceLanguages>en;zh-Hans</SatelliteResourceLanguages>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <NoWarn>$(NoWarn);1591;CS9107</NoWarn>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
  </PropertyGroup>
</Project>
```

这些属性控制的内容包括：

- `TargetFramework` 决定可用 reference assemblies 和运行时契约，不只是一个标签。
- `Nullable` 是编译期静态分析，不会自动阻止运行时出现 `null`。
- `NoWarn` 当前全局忽略 XML 文档告警 `1591` 和 primary-constructor 捕获告警 `CS9107`；这属于仓库现状，不等同于全局零告警策略。
- 根配置没有统一开启 `TreatWarningsAsErrors`，只有 Benchmark 项目显式开启。学习项目如果需要严格门禁，应单独设置并记录必要的抑制原因。
- `PrivateAssets="all"` 常用于只在开发或构建时需要、不能传递给消费者的包。
- `FrameworkReference` 引用共享框架；`PackageReference` 引用 NuGet 资产，两者生命周期不同。

固定 SDK 选择策略时，项目根目录使用 `global.json`：

```json
{
  "sdk": {
    "version": "10.0.102",
    "rollForward": "latestPatch",
    "allowPrerelease": false
  }
}
```

`global.json` 只控制 SDK 选择策略，不会锁定 NuGet 包或运行时镜像。可重复构建还依赖 CI、开发机和容器解析到同一套预期 SDK。

参考仓库只在 `tests` 子树使用 Central Package Management，产品包版本仍分散在各 `.csproj`。这种组织方式允许项目独立升级，但也更容易出现 patch 漂移。是否把 `Directory.Packages.props` 提升到根目录，取决于发布包之间的版本耦合程度。

可打包项目从根配置继承 `Version=1.0.0-rc.12`、MIT license、Source Link、`snupkg` 和仓库地址。当前 `<PackageReleaseNotes>` 文本仍写着“release candidate 9”，与 rc.12 版本字段不一致；这是构建元数据可以独立漂移的实例，发布检查不能只比较 `<Version>`。

rc.12 的 release workflow 同时产出两类制品：NuGet 的 `nupkg`/`snupkg`，以及 Agent Skill 的 catalog、index、manifest 和 ZIP。工作流会检查 tag、根版本、模板 `MonicaVersion`、包成熟度以及 Skill 摘要，再执行 build、串行项目测试、pack 和发布。

### 4.3 常用命令

```powershell
dotnet --info
dotnet restore
dotnet build MySolution.slnx -m
dotnet test MySolution.slnx
dotnet list package --outdated
dotnet pack -c Release
dotnet publish -c Release
```

`-m` 表示让 MSBuild 在一次构建中调度并行任务。多个独立构建进程同时写入相同 `bin/obj` 时会产生文件竞争。

### 4.4 工程基线验证

一个覆盖本节工程设置的最小 `.slnx` 包含 `AppHost`、`Domain`、`Infrastructure`、`Contracts` 和 `Tests`：

1. 用 `Directory.Build.props` 统一目标框架和 nullable。
2. 用 `Directory.Packages.props` 集中管理第三方包版本。
3. 生成一个带 Source Link 的本地 NuGet 包。
4. 在另一个临时项目中引用该包并进入包源码调试。

验证时检查三点：解决方案零告警构建并通过测试；生成的包带有 README、符号包和正确的依赖元数据；另一个项目引用该包后能够进入源码调试。

## 5. C# 与 .NET 运行时基础

### 5.1 项目中常见的语言特性

源码大量使用以下语言特性：

- 泛型、泛型约束、协变和逆变。
- delegate、event、Lambda 与 expression tree 的区别。
- record、init-only property、required member 和不可变快照。
- pattern matching、switch expression、property pattern。
- primary constructor 与普通构造函数的取舍。
- collection expression、spread element 和不可变集合。
- nullable reference types 与 `ArgumentNullException.ThrowIfNull`。
- attribute、reflection、assembly 与 type metadata。
- `IDisposable`、`IAsyncDisposable` 和资源所有权。

参考应用用 record 表达请求，把业务状态留在实体中：

```csharp
public sealed record CreateOrderCommand(
    string OrderNumber,
    string CustomerName,
    decimal Total);

public sealed class Order
{
    public string OrderNumber { get; }
    public decimal Total { get; }
    public OrderStatus Status { get; private set; }

    public void Approve()
    {
        if (Status != OrderStatus.Draft)
        {
            throw new InvalidOperationException("Only draft orders can be approved.");
        }

        Status = OrderStatus.Approved;
    }
}
```

record 用于表达值和消息；Entity 维护身份和生命周期，状态变化通常由行为方法控制。两者在同一模型中承担不同职责。

### 5.2 异步与取消

取消信号沿完整 I/O 路径传播：

```text
HTTP RequestAborted
    -> Application Service
    -> Repository / HttpClient / EventBus
    -> Database or remote I/O
```

从 HTTP 入口到最终 I/O，每一层都接收并透传 `CancellationToken`。相关边界如下：

- `Task.Run` 不会把同步 I/O 变成真正的异步 I/O，这条路径直接使用异步 API。
- `.Result` 和 `.Wait()` 会同步阻塞异步任务。
- 取消通常不是业务失败；在适当边界让 `OperationCanceledException` 继续传播。
- `ValueTask` 主要服务于高频且经常同步完成的底层 API；普通业务方法使用 `Task` 更直接。
- `IAsyncEnumerable<T>` 适合逐项产生数据，但要处理取消、枚举器释放和部分失败。

### 5.3 并发、线程安全和上下文

Monica 同时使用 `lock`、`Interlocked`、`AsyncLocal`、Channel、后台服务和不可变快照。这些工具的作用范围不同：

| 工具 | 适用问题 | 不适用问题 |
| --- | --- | --- |
| `lock` / `Monitor` | 同一进程内保护一段同步临界区 | 跨进程协调、在锁内等待慢 I/O |
| `SemaphoreSlim` | 异步并发限流或异步互斥 | 分布式锁 |
| `Interlocked` | 单个数值或引用的原子更新 | 多字段不变量 |
| `ConcurrentDictionary` | 并发键值访问 | 多步组合操作自动具备事务性 |
| Channel | 生产者—消费者和背压 | 需要持久化、跨进程可靠消息 |
| `AsyncLocal<T>` | 随异步执行流传播请求上下文 | 普通业务数据存储、后台任务自动继承所有上下文 |
| 分布式锁 | 多实例争抢同一外部资源 | 替代数据库唯一约束或幂等设计 |

相关专题：

- [ExecutionContext 和 SynchronizationContext](ExecutionContext和SynchronizationContext.md)
- [Interlocked](Interlocked.md)
- [多线程并发访问 HashSet](Question/多线程并发访问Hashset.md)

### 5.4 现代 BCL 数据结构与可测试时间

项目还使用了 `System.Threading.Lock`、`TimeProvider`、`FrozenDictionary`、`FrozenSet`、`PriorityQueue`、`PeriodicTimer`、`Task.WaitAsync` 和 keyed DI：

| API | 适用场景 | 关键边界 |
| --- | --- | --- |
| `System.Threading.Lock` | 新代码中的进程内同步临界区 | 不跨进程；锁内慢 I/O 会拉长临界区。 |
| `FrozenDictionary` / `FrozenSet` | 启动时构造、运行时高频只读的目录 | 冻结成本较高，不适合频繁更新。 |
| `TimeProvider` | 可替换当前时间和定时器，便于测试超时、过期、调度 | 应用统一注入后，局部调用 `DateTime.UtcNow` 会绕过测试时钟。 |
| `PriorityQueue<TElement,TPriority>` | 调度器、延迟队列、按优先级处理 | 默认不是线程安全集合，也不是持久队列。 |
| `Task.WaitAsync` | 为现有 Task 增加取消或等待超时 | 等待超时不一定能停止底层操作。 |
| Keyed DI | 同一 abstraction 注册多个有名称的 provider | key 属于契约，集中定义后更容易发现缺失和重复。 |

这些 API 减少了自建基础工具的数量，但不会自动处理生命周期、资源所有权和失败恢复。

### 5.5 Channel 工作队列验证

本节的验证对象是一条有界 Channel 工作队列：

- HTTP 端点提交任务。
- 单个 `BackgroundService` 消费任务。
- 支持 `CancellationToken`、容量限制和优雅停止。
- 用 `Interlocked` 维护已接收、已完成、失败数量。
- 并发测试覆盖进程内任务的丢失和重复情况。

再通过故障注入记录进程崩溃时队列数据的行为，由此确定何时要换成 Kafka、RabbitMQ 或 Dapr pub/sub。Channel 只提供进程内协调，不提供持久化消息语义。

## 6. Generic Host、依赖注入、配置与 Options

### 6.1 Generic Host 是应用骨架

ASP.NET Core 应用运行在 Generic Host 之上。Host 统一管理：

- 配置源和环境。
- DI 容器。
- 日志系统。
- `IHostedService` 启停。
- 应用生命周期和优雅关闭。

典型生命周期如下：

```text
CreateBuilder
  -> 收集 Configuration 与 ServiceDescriptor
  -> Build：生成不可变的根服务图
  -> Start：启动 HostedService 和 Web Server
  -> Run：处理请求与后台工作
  -> Stop：发出取消并等待优雅退出
  -> Dispose：释放根容器拥有的资源
```

`AddMonica(...)` 建立在 `IHostApplicationBuilder` 之上。它在 `Build()` 前记录并验证模块图，最终仍把服务写入标准 DI 容器。

### 6.2 DI 生命周期

| 生命周期 | 创建频率 | 典型对象 | 主要风险 |
| --- | --- | --- | --- |
| Singleton | 每个根容器一个 | 无状态目录、线程安全缓存、注册表 | 捕获 Scoped 服务；共享可变状态无同步；长期持有大对象 |
| Scoped | 每个 HTTP 请求或手工 scope 一个 | `DbContext`、Unit of Work、请求用户上下文 | 在并行任务间共享非线程安全实例；scope 泄漏 |
| Transient | 每次解析一个 | 轻量策略、短期转换器 | 高频创建成本；被 Singleton 捕获后实际寿命被延长 |

长生命周期服务直接持有短生命周期服务会形成 captive dependency。后台 Singleton 使用 `DbContext` 时，通过 `IServiceScopeFactory` 创建作用域，或者改用 `IDbContextFactory<TContext>`。

关于 `DbContext` 并发问题，参见 [多线程并发访问 DbContext](Question/多线程并发访问DbContext.md)。

### 6.3 Configuration 与 Options

配置系统把多个 Provider 按顺序叠加成键值视图；后加入的 Provider 通常覆盖先加入的值。常见来源包括 JSON、环境变量、命令行、内存和自定义远端存储。

Options 的三种消费方式：

| 接口 | 行为 | 适用场景 |
| --- | --- | --- |
| `IOptions<T>` | Singleton 缓存，不随配置重载更新 | 启动后固定的配置 |
| `IOptionsSnapshot<T>` | 每个 scope 重新计算一次 | Web 请求希望看到新配置 |
| `IOptionsMonitor<T>` | Singleton，可读取当前值并订阅变化 | 长生命周期服务和热重载 |

标准注册示例：

```csharp
builder.Services
    .AddOptions<OrderingOptions>()
    .Bind(builder.Configuration.GetSection("Ordering"))
    .ValidateDataAnnotations()
    .Validate(
        options => options.BacklogWarningThreshold > 0,
        "BacklogWarningThreshold must be greater than zero.")
    .ValidateOnStart();

public sealed class OrderingOptions
{
    public int BacklogWarningThreshold { get; init; } = 100;
}
```

`MoLibrary/Monica.Configuration` 在标准配置系统之上增加了自定义 `ConfigurationProvider`、schema-first 定义、有效值存储、历史、回滚、运行时验证和分布式重载通知。这套实现从基础能力逐层扩展：

1. 标准 Provider 和强类型 Options。
2. 只读自定义 Provider。
3. reload token、写入一致性和并发冲突。
4. 历史、审批、回滚和多实例广播。

rc.12 将配置输入统一为不可变的 `MonicaConfigurationInputPlan`。Host 原有 Provider、受管 JSON 源、section path 约定和 store 组合只声明一次，随后由 bootstrap configuration、启动期有效 Options 加载以及运行期 `AddConfiguration(inputPlan)` 共同使用。这样可以避免“启动验证读取一组配置，运行时 Provider 又读取另一组配置”的双轨问题。

`MonicaConfigurationProvider` 把持久化的有效值文档投影回扁平配置键，并在完整或局部替换后调用 `OnReload()`。File Store 和 EF Core Store 都维护 definition version；统一版本快照用于跨多个配置定义的历史与回滚。File Store 的互斥仍由进程内 `SemaphoreSlim` 提供，因此共享目录的多进程并发不能按数据库事务语义理解。

模块系统的 `ModuleOptions<T>` 在启动组合时冻结，用来决定当前 Host 具备哪些能力；`Monica.Configuration` 管理的是可在运行期发布和重载的业务 Options。两者不能互换，运行期配置更新也不会重新编译模块图。

`Monica.Configuration.EventBus` 只广播版本和失效通知等 metadata，不传输配置值。接收实例收到信号后，再从事实存储读取、校验并替换本地投影。该模式减少了敏感数据经过消息系统的机会，代价是处理丢通知、去重、防抖、jitter 和版本比较。

### 6.4 配置边界

- 业务代码直接注入 `IConfiguration` 并拼接字符串键，会把配置契约分散到各处；强类型 Options 将绑定和验证集中在入口。
- `reloadOnChange` 只表示配置源会发出变更信号，消费者何时看到新值取决于所用的 Options 接口。
- 配置重载不是事务。多个相关键分批变化时，消费者可能看到中间状态，通常以快照、版本或原子发布隔离。
- 密钥放入 `appsettings.json` 会进入普通配置和源码分发链路；Secret Manager、环境变量、Key Vault 等来源用于承载敏感值。
- 配置 schema 上的 `IsSensitive` 通常只控制管理面脱敏，不自动代表值已加密存储或进入 secret vault。
- 进程内 `SemaphoreSlim` 只能串行化当前进程的文件写入；多实例共享配置事实存储时，跨实例并发控制由数据库或 provider 提供。
- DI 容器能够解析服务，只说明当前服务图可构造，不能替代模块边界和依赖方向检查。

### 6.5 Options 重载验证

验证对象是一份可重载的 `OrderingOptions`：

- 值来自 JSON 和环境变量。
- 启动时验证阈值范围。
- 后台服务使用 `IOptionsMonitor<T>` 感知变化。
- 每次变更输出配置版本，但不记录敏感值。
- 测试覆盖非法更新，并确认上一份有效快照不被替换。

## 7. ASP.NET Core Web API

### 7.1 请求执行模型

```text
Kestrel
  -> Middleware：异常、转发头、HTTPS、静态文件、路由、CORS、认证、授权
  -> Endpoint：Minimal API / Controller / SignalR / Razor Component
  -> Endpoint Filter 或 MVC Filter
  -> Application Service
  -> HTTP Result + JSON Serialization
```

中间件顺序直接决定请求行为。认证在授权之前运行，后者才能读取已建立的 `HttpContext.User`；CORS、路由和端点映射也各有固定阶段。Monica 的模块系统专门定义了 Web stage，用来确定不同模块写入管道的相对顺序。

### 7.2 主要接口和机制

- Routing、route group、endpoint metadata 和 link generation。
- 参数绑定：route、query、header、body、form 和 DI 参数。
- `TypedResults`、HTTP 状态码和 Problem Details。
- Minimal API 与 Controller 的取舍。
- Middleware、Endpoint Filter、MVC Filter 的作用层级。
- DataAnnotations、FluentValidation 或自定义验证的边界。
- `System.Text.Json` 配置、converter 和 source generation。
- OpenAPI document、schema/operation transformer 和 API 版本策略。
- 全局异常处理、日志关联和敏感信息清理。

### 7.3 Minimal API、Controller 和自动生成端点

| 方式 | 优点 | 代价 | 适合场景 |
| --- | --- | --- | --- |
| Minimal API | 低样板、route group 组合自然、适合垂直切片 | 大量端点若无约束容易散乱 | 小中型 API、内部服务、明确的 feature folder |
| Controller | MVC 生态成熟、约定清晰、Filter 和模型绑定完整 | 类型和 attribute 样板更多 | 大型公开 API、已有 MVC 规范 |
| 源生成端点 | 契约可作为唯一事实来源，减少重复代码 | 调试和错误诊断更难，生成器必须稳定 | 高度标准化、跨服务 RPC 契约 |

参考应用把 `[ApiEndpoint]` 放在 request record 上，再由 `Monica.Generators.AutoController` 生成 Controller 和 RPC Client。路由和 RPC 契约因此共用一个声明来源；具体 attribute 和生成器属于项目约定，并非平台要求。

### 7.4 序列化、对象映射与本地化

`Monica.Core` 还包含 JSON serialization、Mapster object mapping 和 localization 模块。这三类能力都位于系统边界：

- `System.Text.Json` 决定 wire format、日期、枚举、数字、null 和兼容策略。
- Object mapper 决定领域对象如何投影为 DTO，错误映射可能泄露内部字段。
- Localization 决定用户可见文本如何按 culture 解析，内部异常原文不属于翻译键。

项目采用以下映射策略：

- 简单且关键的领域映射采用手写代码，调用关系和调试路径最直接。
- 大量结构相似的 DTO 交给 Mapster 等工具，映射配置在启动期完成验证。
- 查询 DTO 直接在 EF LINQ 中投影，避免先加载完整实体再转到内存映射。
- 密钥、审计字段、内部状态和导航属性排除在 convention 自动映射之外。

Monica 没有使用 Mapster 的进程级 `TypeAdapterConfig.GlobalSettings`，而是让每个 Host 拥有独立配置。profile 统一发现后，先冻结并编译候选配置，再通过 `Interlocked.Exchange` 原子发布新快照。同进程的多个测试 Host 因此不会共享映射状态，读取方也不会拿到尚未完成编译的配置。

`CompilationBarrier` 默认是 `ModuleStartupWorkBarrier.NoBarrier`。Host 可以先进入 ready 状态，映射验证继续在后台运行；如果编译失败，错误进入模块诊断，未预编译的映射仍可沿用 Mapster 的惰性路径。

设置为 `BeforeHostLifecycle` 时，所有映射必须在 Generic Host 生命周期参与者启动前通过编译。对象映射模块只接受这两种策略。`ProjectToType` 仍受 EF provider 表达式翻译能力的限制，所以投影查询需要使用真实 provider 做集成测试。

自定义 `JsonConverter` 的测试面包括跨缓冲区读取、null、异常输入和 AOT/source generation。ASP.NET Core 10 切换到 JSON + `PipeReader` 后，converter 还要处理 `Utf8JsonReader.HasValueSequence`。

`Monica.AutoModel` 使用 Dynamic LINQ 提供动态查询能力。客户端传入的字段名、排序和表达式在进入 Dynamic LINQ 前经过 allowlist、复杂度限制和权限检查；“能够解析”并不代表“允许执行”。

### 7.5 统一响应与错误边界

项目使用 `Res`、`Res<T>` 和 Result Envelope 统一 Facade/API 边界。这种设计的关键不是统一外形，而是保持以下契约清晰：

- HTTP 状态码是否仍然准确表达结果？
- 业务失败、输入错误、认证失败、并发冲突和系统异常是否能区分？
- 是否会把已经是 `IResult` 的响应再次包成 200？
- 客户端能否使用标准 Problem Details？
- 错误信息中是否泄露堆栈、连接串或内部类型？

公开 REST API 通常使用标准状态码和 Problem Details；内部 RPC 或 UI Facade 更依赖稳定 envelope。是否统一包装取决于客户端契约。

Endpoint Filter 的详细执行顺序、短路和使用方式参见 [EndpointFilter](EndpointFilter.md)。

### 7.6 .NET 10 流式 API 选择

| 技术 | 通信方向 | 适合场景 |
| --- | --- | --- |
| SSE | 服务端到客户端单向流 | AI token、任务进度、日志尾部、状态推送 |
| SignalR | 双向实时通信 | 聊天、协作、客户端命令、Hub 分组 |
| WebSocket | 双向底层通道 | 需要自定义协议和极细控制 |
| 普通流式 JSON/NDJSON | 单向响应流 | 大结果集逐项返回、服务间处理 |

SSE 的部署边界还包括断线重连、事件 ID、代理超时、缓冲和认证过期。

### 7.7 订单 API 验证

验证用订单 API 包含以下能力：

- route group：`/api/v1/orders`。
- 创建、查询、审批三个端点。
- .NET 10 内置验证。
- 标准 Problem Details。
- 一个 Endpoint Filter 记录业务操作名和耗时。
- OpenAPI 3.1 文档。
- 一个 SSE 端点推送审批进度。

集成测试固定状态码、响应 schema、验证错误和取消行为；Swagger 只承担交互式检查。

## 8. 模块化架构与可组合基础设施

### 8.1 模块系统解决什么问题

当基础设施增多后，直接在 `Program.cs` 中连续调用几十个 `AddXxx` 和 `UseXxx` 会出现：

- 隐式依赖：A 模块只有在 B 模块先注册时才能工作。
- 顺序脆弱：移动一行中间件就产生运行时故障。
- 配置分散：服务、Options、端点和后台任务不在一个所有权边界。
- 无法诊断：运行时很难回答启用了什么、为何启用、耗时多少。
- 不同宿主相互污染：静态全局注册表会让测试和多 Host 进程不可靠。

`MoLibrary/Monica.Core/Modularity` 为每个 Host 维护独立的模块图。`AddMonica(...)` 回调返回后，模块图随即封闭；后续注册按依赖优先级和确定的生命周期阶段执行。

### 8.2 核心概念映射

| Monica 概念 | 一般架构含义 |
| --- | --- |
| `MonicaModule<TOptions>` | 一个模块的生命周期策略和配置所有者 |
| `ModuleDescriptor.Require` | 硬依赖边；缺少时自动包含 |
| `AfterIfPresent` | 可选排序边；不自动引入对方 |
| `ModuleRegistration<TModule,TOptions>` | 当前 Host 绑定的 fluent registration handle |
| `RequireFeature` / `SatisfyFeature` | 强制调用方显式选择 provider，避免默认行为含糊 |
| `DeclareTypeDiscovery` | 预声明结构化类型查询，统一扫描后再串行提交注册 |
| `ConfigureServices` / `ConfigureEndpoints` | 确定性生命周期阶段 |
| diagnostics snapshot | 模块图、耗时、错误和拓扑的不可变运行时投影 |

依赖图必须是有向无环图：

```text
WebApi ------> Core
Repository --> Core
JobScheduler -> Core
    |
    +-------> Repository provider（可选）

UI module ---> 对应基础设施 module
```

如果出现环，通常说明职责划分错误，或者把跨模块协作放进了具体实现而不是抽象契约。

当前 `CompiledModuleGraph` 不只是调用一次普通排序：它构建冻结图，使用稳定的拓扑顺序保证相同声明得到相同结果，并通过强连通分量分析给出具体循环集合。其实现涉及 DAG、Kahn/DFS 类拓扑处理、Tarjan SCC、稳定排序和可操作的错误信息。采用这些算法，是为了在 Host 被修改之前发现组合失败，并准确指出循环所在。

### 8.3 冻结配置和注册图的作用

组合边界封闭后不再允许修改，主要带来以下结果：

- 启动行为可重复。
- 测试能确定每个 Host 的真实依赖图。
- Options 验证发生在服务容器被修改之前。
- 运行时诊断快照不会与仍在变化的注册状态竞争。
- 不会保留一个 registration handle，在应用启动后偷偷增加服务。

这与不可变对象以及编译阶段、执行阶段分离的机制一致：先收集声明，再完成验证和编译，最后执行副作用。相比边声明边修改 Host，这种流程更容易保持一致性。

### 8.4 类型发现的性能取舍

许多框架会让每个模块独立扫描全部程序集。假设有 `M` 个模块和 `N` 个类型，最坏情况下会重复做约 `M × N` 的分析。

Monica 让模块先声明 `TypeQuery`，合并非空查询后只分析一次类型全集，再按模块拓扑顺序串行执行注册回调。这个设计包含以下取舍：

- 分离只读分析与有副作用的服务注册。
- 对结构化查询做合并和缓存。
- 注册提交保持确定顺序。
- 无条件扫描所有已加载程序集会扩大成本和不确定性；assembly boundary 应显式限制。
- 对反射和类型图使用 BenchmarkDotNet 验证，而不是猜测性能。

`TypeQuery` 本身是可比较的结构化查询 AST，支持 assignable、subclass、attribute、open generic 以及 AND/OR/NOT。与接收任意 predicate Lambda 相比，结构化 AST 可以做等价判断、去重、诊断和缓存；代价是查询语言必须显式建模，不能无限开放自定义代码。

rc.12 的类型发现不只返回匹配结果，还记录 assembly resolution、shape construction、query evaluation 和 commit 等阶段指标。程序集清单按需生成，避免每次读取基础诊断快照时重复展开程序集路径和加载状态。

### 8.5 启动工作与 barrier

模块可以通过 `ScheduleStartupWork(...)` 提交可并发的启动工作。barrier 表示“最迟在哪个边界等待完成”，不是 timeout：

| `ModuleStartupWorkBarrier` | 完成边界 |
| --- | --- |
| `BeforeTypeDiscovery` | 开始结构化类型发现之前 |
| `BeforePostConfigureServices` | 进入 post-service configuration 之前 |
| `BeforeServiceRegistrationCompletion` | `AddMonica(...)` 返回、Host 可以构建 ServiceProvider 之前 |
| `BeforeHostLifecycle` | 任何 Generic Host lifecycle participant 启动之前 |
| `NoBarrier` | 不阻塞组合和 Host 启动；失败只进入诊断 |

`MaxConcurrentStartupWorkItems` 默认取处理器数量。调度器会为 barrier-bound 工作保留执行容量，避免 `NoBarrier` 任务占满全部 lane。`ModuleStartupPerformanceBudgets` 可以为组合总耗时、服务注册、类型发现、barrier 等待、最长模块回调和最长排队设置预算；所有预算默认未设置，因此诊断先报告测量事实，不自动生成性能评分。

### 8.6 标准 DI 下的简化模块

以下代码不使用 Monica API，只用标准 DI 表达相同的组合边界：

```csharp
public sealed class OrdersModuleOptions
{
    public int MaximumPageSize { get; set; } = 100;
}

public static class OrdersModuleExtensions
{
    extension(IServiceCollection services)
    {
        public IServiceCollection AddOrders(
            Action<OrdersModuleOptions>? configure = null)
        {
            services.AddOptions<OrdersModuleOptions>()
                .Configure(options => configure?.Invoke(options))
                .Validate(options => options.MaximumPageSize is > 0 and <= 1000)
                .ValidateOnStart();

            services.AddScoped<IOrderService, OrderService>();
            return services;
        }
    }
}
```

加入依赖图、provider selection、生命周期阶段、诊断和 type discovery 后，框架复杂度会迅速增加。只有多个独立模块持续需要这些约束时，完整模块框架的维护成本才合理。

### 8.7 模块编译器的实现边界

实现模块系统时需要防范以下问题：

- 用 assembly scanning 隐藏所有注册，导致读代码时无法知道服务来自哪里。
- 依赖静态全局模块表，使多个测试 Host 相互污染。
- 模块直接解析另一个模块的内部服务，而不是依赖公开 abstraction。
- provider 没有显式选择，直到运行时第一次调用才报错。
- 为了“解耦”创建大量只有一个实现、没有稳定边界的接口。

可以先实现一个小型模块编译器，支持硬依赖、可选排序、循环检测、Options 验证和诊断输出。初始版本只生成排序后的模块清单，不必立即加入复杂的反射扫描。测试范围包括缺少 provider、重复注册、循环依赖，以及两个独立 Host 的隔离。

## 9. DDD、模块化单体、CQRS 与执行管道

### 9.1 适用目标与边界

DDD 不是把文件夹命名为 `Domain`，CQRS 也不等于每个操作都引入消息中间件。它们解决的是业务复杂度、语言一致性和变更边界问题。

`MoLibrary/examples/Monica.ReferenceApplication` 展示了一个订单模块化单体：

```text
AppHost
  -> Domains.Ordering
      -> Platform.Infrastructure
          -> Platform.Protocol
              -> Platform.BuildingBlocks
```

一个部署单元仍然可以拥有清晰的 bounded context 和单向项目引用。与过早拆分微服务相比，模块化单体保留进程内调用和事务的简单性，同时通过模块边界控制耦合。

### 9.2 参考应用中的角色

| 角色 | 参考代码 | 职责 |
| --- | --- | --- |
| Composition Root | `src/AppHost/Monica.Reference.Api/Program.cs` | 只组合模块、Provider、端点和宿主能力，不承载订单规则。 |
| Entity | `Domains/Ordering/Entities/Order.cs` | 维护订单身份、状态转换和业务不变量。 |
| Command | `Platform.Protocol/.../Requests/CommandCreateOrder.cs` | 表达改变系统状态的意图和稳定契约。 |
| Query | `Platform.Protocol/.../Requests/QueryGetOrders.cs` | 表达读取意图，不隐藏写副作用。 |
| Application Service / Handler | `Domains/Ordering/Application/Handlers*` | 编排 Repository、Entity、Unit of Work 和 EventBus。 |
| Repository abstraction | `Domains/Ordering/Interfaces/IRepositoryOrder.cs` | 定义领域所需的数据访问语义。 |
| Domain/Integration Event | `Platform.Protocol/.../Events/EventOrderApproved.cs` | 表达已经发生的业务事实。 |
| Background Worker | `WorkerOrderBacklogReport.cs` | 执行与 HTTP 请求无关的周期性用例。 |
| Configuration ProjectUnit | `Configurations/OrderingOptions.cs` | 提供强类型、可发现的业务配置。 |

### 9.3 富领域模型

富领域模型把规则放在拥有状态的对象中。例如订单审批应由 `Order.Approve(...)` 控制，而不是由 Controller 直接设置 `Status`：

```csharp
public void Approve(DateTimeOffset approvedAtUtc)
{
    if (Status == OrderStatus.Approved)
    {
        throw new InvalidOperationException("The order is already approved.");
    }

    if (approvedAtUtc < CreatedAtUtc)
    {
        throw new ArgumentOutOfRangeException(nameof(approvedAtUtc));
    }

    Status = OrderStatus.Approved;
    ApprovedAtUtc = approvedAtUtc;
}
```

这种封装带来以下直接效果：

- 任何调用路径都不能绕过不变量。
- 规则和状态位于同一高内聚对象中。
- 单元测试不需要启动 Web Host 或数据库。
- Application Service 专注编排，不会逐渐变成包含全部业务规则的“大服务”。

但并非所有项目都需要复杂聚合。只有 CRUD 规则时，简单模型通常更合适；没有行为的聚合根、值对象和领域服务只会增加建模与维护成本。

### 9.4 CQRS 与 Mediator

CQRS 的最小含义是分离写意图和读意图：

- Command 可以改变状态，应明确事务、幂等和授权要求。
- Query 不应产生业务写副作用，可以针对读取优化。
- 两者可以共用同一个数据库，不要求一开始就采用读写分库。

`Monica.Core/Mediator` 提供内置 Mediator，`Monica.Core/Execution` 在 Mediator、MVC 和后台服务等入口之上建立 execution behavior pipeline。通用的管道模型如下：

```text
Request
  -> Validation Behavior
  -> Authorization Behavior
  -> UnitOfWork Behavior
  -> Logging / Tracing Behavior
  -> Handler
  -> Reverse unwind
```

行为管道适合承载横切逻辑，同时需要防范以下问题：

- 顺序依赖没有被声明。
- 同一事务被 MVC Filter、Mediator behavior 和 Repository 重复创建。
- 所有异常都被捕获并转换，取消和系统故障失去语义。
- Handler 之间互相调用形成隐蔽调用图。

### 9.5 边界结果与内部异常

参考项目约定 Facade 使用 `Res<T>`，内部 Service 使用普通返回值和异常。错误转换只发生在应用边界：

- **内部代码**可用异常表达无法继续执行的错误，保持签名自然。
- **应用/API 边界**把已知业务失败翻译成稳定、可序列化的结果。
- **未知异常**交给全局异常处理和可观测系统，不应伪装成普通业务失败。

`Res<T>` 是 Monica 的自定义选择，不是 DDD 或 CQRS 的必要组成。其他项目可以使用 discriminated union、Problem Details、异常映射或 typed result union，只要边界语义一致。

项目中还存在一个需要特别检查的 overload 陷阱：当返回类型是 `Res<string>` 时，`Res.Ok(content)` 可能绑定到把字符串当作提示信息的非泛型 overload，导致 `Data` 丢失。应显式写成 `Res.Ok<string>(content)`。因此，fluent result API 的 overload 设计必须通过编译测试和边界测试验证，不能只依据调用代码的表面可读性判断。

### 9.6 ProjectUnit 的架构作用

`Monica.ProjectUnits` 会发现 ApplicationService、Entity、Repository、DomainEvent、Handler、Configuration、RecurringJob 等类型，并生成运行时目录和诊断。它把“架构约定”转化为可查询数据，使开发者和编码 Agent 能够基于同一份结构化信息维护大型项目。

运行时目录与 `Monica.ProjectUnits.CodeAnalysis` 的源码目录通过 `ProjectUnitSourceAnalysisContract` 对齐。rc.12 使用 `monica-project-units-source/v3`，由 `DiscoverableUnitTypes` 固定源码分析器允许产出的角色集合。

直接标记的 `ExcludeFromBusinessTypeDiscovery` 与非继承的 `[Configuration]` 也和运行时发现保持相同语义。这个契约解决的是目录漂移：同一个类不应出现“运行时能发现，静态分析却遗漏”或相反的结果。

类似项目可以采用以下做法：

- 用 attribute 或命名约定补充负责人、标签和需求编号。
- 分析项目中应存在但缺失的关系，例如事件无处理器、Repository 无实现。
- 提供只读架构目录，而不是把 `System.Type` 和反射对象直接暴露给 UI。
- 将架构验证加入 CI，而不是只写在团队 Wiki 中。

### 9.7 订单领域边界验证

以订单模块为范围实现：

1. `Order` 聚合和审批不变量。
2. Create、Approve Command 与 List Query。
3. 独立的 Handler 和 Repository abstraction。
4. Validation、UnitOfWork、Tracing 三个 pipeline behavior。
5. 架构测试：Domain 不引用 ASP.NET Core，Contracts 不引用 Infrastructure。

检查实现时，需要能够说明“规则属于哪一层、依赖为什么朝这个方向、事务在哪开始和结束”，而不能只展示文件夹树。

更多 DDD 背景参见 [DDD](../Architecture/DDD.md)。

## 10. EF Core 10、Repository 与 Unit of Work

### 10.1 EF Core 本身已经提供的能力

`DbContext` 本身同时承担多项职责：

- Unit of Work：跟踪一组变更并在 `SaveChanges` 时提交。
- Identity Map：同一 Context 内同一主键通常对应同一实体实例。
- Change Tracker：记录实体状态和属性变化。
- Repository-like access：`DbSet<T>` 提供查询和写入入口。
- Transaction coordination：协调数据库连接与事务。

因此，Repository 和额外的 Unit of Work 不是必选模式。只有在需要稳定领域接口、多数据源适配、统一审计/事件、查询隔离或框架约束时，额外抽象才可能抵消其维护成本。

### 10.2 Monica 的数据能力

`Monica.Repository` 包含：

- `RepositoryDbContext<TContext>` 和 `EfRepository`。
- `IDbContextProvider<TContext>` 与自适应 Context 获取。
- Unit of Work manager 和 execution behavior。
- 审计字段、软删除、额外属性、并发标记。
- sequential GUID 与 Snowflake ID。
- DbContext、连接和活动查询诊断。
- Entity change event 与事务完成后的事件协调。

这是一套框架级能力。评估这些封装时，应将其还原到 EF Core 原生机制，确认它减少了哪些重复代码，又隐藏了哪些成本。

### 10.3 DbContext 生命周期和线程安全

`DbContext` 默认应是 Scoped，并且不是线程安全的。下面的代码存在风险：

```csharp
await Task.WhenAll(
    dbContext.Orders.ToListAsync(cancellationToken),
    dbContext.Customers.ToListAsync(cancellationToken));
```

即使两个查询只读，也不能在同一个 Context 上并行执行。可选择：

- 顺序执行。
- 每个并行分支创建独立 scope/Context。
- 注入 `IDbContextFactory<TContext>`，显式创建和释放 Context。

详细说明参见 [多线程并发访问 DbContext](Question/多线程并发访问DbContext.md)。

### 10.4 查询与跟踪

查询层需要明确以下行为：

- `AsNoTracking()` 适合只读查询，减少跟踪开销。
- 投影到 DTO 通常比加载完整实体再映射更高效。
- `Include` 过多会造成笛卡尔膨胀；必要时使用 split query，并检查生成 SQL。
- 避免查询循环中的 N+1。
- 分页必须有稳定排序；大偏移量场景考虑 keyset pagination。
- 在内存中编译或执行本可翻译到 SQL 的过滤，会失去数据库侧筛选和索引优化。
- 通过 `ToQueryString()`、日志和真实执行计划验证，而不是只看 LINQ。

已有专题：

- [ChangeTracker.TrackGraph](ChangeTracker.TrackGraph.md)
- [DistinctBy 性能](DistinctBy性能.md)

### 10.5 事务、事件和一致性

参考订单应用在审批成功后通过 Unit of Work 的 `OnCompleted` 发布本地事件。这保证处理器只观察到已成功完成的请求边界。

当前 `UnitOfWork.CompleteAsync` 的内部顺序是：`SaveChangesAsync`、刷新 `AsyncEventBuffer`、提交数据库事务、执行 `OnCompleted` handler。两类回调的时点不同：buffered event 在 commit 前刷新，显式 `OnCompleted` handler 在 commit 成功后执行。需要外部副作用时，不能把两者视为同一种一致性保证。

`UnitOfWorkManager` 在业务操作失败后使用 `CancellationToken.None` 执行 rollback，避免请求取消令牌已经触发时跳过清理。如果 rollback 自身也失败，框架保留原始业务异常，并把 rollback 异常挂到 `Exception.Data["Monica.Repository.UnitOfWork.RollbackException"]`，防止清理错误覆盖第一现场。

但需要区分两种情况：

1. **进程内本地事件**：事务完成后发布通常足够，但进程在提交后、发布前崩溃仍可能丢失事件。
2. **分布式事件**：数据库提交和消息发送无法天然形成一个原子操作，通常需要 transactional outbox、CDC 或消息中间件事务能力。

生产级 Outbox 的基本流程：

```text
业务事务：写业务数据 + 写 Outbox 记录
                 |
                 v
后台发布器读取未发布记录
  -> 发送 Broker
  -> 标记已发布
  -> 失败重试
```

消费者仍必须幂等，因为“至少一次”投递可能产生重复消息。

### 10.6 EF Core 10 验证范围

可以用以下场景验证相关功能：

- 为 `Order` 同时添加 Tenant 与 SoftDelete named query filter。
- 使用 `IgnoreQueryFilters(["SoftDeletionFilter"])` 构建受权限保护的回收站查询。
- 用 `LeftJoin` 编写订单与可选审批人的查询，并查看 SQL。
- 用语句 Lambda 的 `ExecuteUpdateAsync` 批量更新超时订单。
- 为 JSON complex type 做局部批量更新。
- 检查敏感日志遮盖和 raw SQL analyzer。

### 10.7 抽象与使用风险

- Generic Repository 只暴露 `GetAll/Insert/Update/Delete`，反而丢失领域语义和 EF Core 能力。
- 一个请求里创建多个互不协调的 Context，导致事务和实体身份不一致。
- 在 Singleton 或静态字段中缓存 Entity/DbContext。
- 对所有查询无脑 `Include`，或在 Repository 内部悄悄执行 `ToList()`。
- 用 InMemory Provider 证明关系型查询一定正确；它不能完整模拟 SQL 翻译、约束和事务。
- 开启 `EnableSensitiveDataLogging` 后把生产 SQL 参数上传到集中日志。

### 10.8 关系型持久化验证

将订单模块从内存 Repository 替换为 SQLite 或 PostgreSQL：

- 编写 migration。
- 实现乐观并发标记。
- 添加软删除和租户过滤器。
- 在同一事务写入 Outbox。
- 使用真实关系型 Provider 做集成测试。
- 用 `ToQueryString()` 和执行计划检查列表查询。

验证范围至少覆盖并发审批、事务回滚、重复消息和跨租户数据隔离。

## 11. 事件驱动、后台任务、韧性与并发控制

### 11.1 本地事件与分布式事件

| 维度 | 本地事件总线 | 分布式消息系统 |
| --- | --- | --- |
| 边界 | 同一进程 | 跨进程、跨服务 |
| 延迟 | 很低 | 有网络与 Broker 延迟 |
| 可靠性 | 通常随进程 | 可持久化，但仍需投递语义设计 |
| 事务 | 可与当前流程紧密协调 | 通常需要 Outbox/幂等/最终一致性 |
| 序列化 | 可直接传对象 | 必须定义稳定消息契约 |
| 典型用途 | 模块内解耦、提交后反应 | 服务集成、异步削峰、数据管道 |

`Monica.EventBus` 提供本地实现、自动发现 handler 和分布式 provider abstraction；`Monica.EventBus.Kafka` 提供 Kafka 适配；`Monica.Dapr` 也能提供 pub/sub。

事件系统的设计需要明确以下内容：

- event name 和 schema version。
- 至少一次、至多一次和近似恰好一次语义。
- 消费者幂等。
- 分区键与顺序。
- retry、dead-letter、poison message。
- trace context 和 correlation ID 传播。
- handler scope、取消和优雅停机。

### 11.2 Hosted Service 与 Job Scheduler

`IHostedService` 适合随 Host 启停的后台组件；`BackgroundService` 提供基于 `ExecuteAsync` 的常用实现。`MoLibrary/Monica.JobScheduler` 又在其上增加：

- recurring job 与 triggered job。
- Cronos cron 表达式。
- 最大并发、执行超时和重试。
- in-memory 或 EF Core metadata repository。
- 分布式和进程内 provider。
- 执行日志、状态、僵尸检测和 UI。

标准后台服务示例：

```csharp
public sealed class OutboxPublisher(
    IServiceScopeFactory scopeFactory,
    ILogger<OutboxPublisher> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(5));

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var dispatcher = scope.ServiceProvider
                .GetRequiredService<IOutboxDispatcher>();

            await dispatcher.DispatchPendingAsync(stoppingToken);
            logger.LogDebug("Outbox dispatch cycle completed.");
        }
    }
}
```

每轮工作都创建独立的 Scoped 服务范围，并持续传递停止令牌；`PeriodicTimer` 也需要在服务结束时正确释放。

参考项目当前部分 scheduler 使用 Timer 的 `async void` callback。这类写法难以由调用方等待，异常、重入和优雅停机也更难协调，因此更适合作为代码审查案例，不适合作为实现模板。新实现优先使用 `BackgroundService + PeriodicTimer`，或者让 Timer callback 只负责把工作放入 Channel，再由可等待的 Task 消费。

### 11.3 韧性策略

`Monica.Core/Modules/ModuleResilience.cs` 使用 `Microsoft.Extensions.Resilience` 和 Polly resilience pipeline。常见策略：

| 策略 | 作用 | 关键风险 |
| --- | --- | --- |
| Timeout | 限制单次等待 | 超时不一定会取消远端操作，必须传播 CancellationToken。 |
| Retry | 处理短暂故障 | 非幂等写操作可能被重复执行；指数退避仍需 jitter。 |
| Circuit Breaker | 持续失败时快速拒绝 | 阈值过小会放大抖动，过大则失去保护。 |
| Rate Limiter | 控制吞吐和并发 | 应决定排队还是拒绝，并观测排队时间。 |
| Hedging | 并行或延迟发出多个尝试 | 增加下游负载，只适合安全、幂等的操作。 |
| Fallback | 返回替代结果 | 容易掩盖真实故障和数据过期。 |

无限重试缺少可控的故障边界。重试策略应设置总时间预算、可观测指标和明确的异常分类。

### 11.4 锁、状态存储与任务进度

`Monica.Locker` 同时提供进程内 keyed lock 和 distributed lock abstraction；`Monica.StateStore` 提供状态、任务进度和取消协调，`Monica.StateStore.StackExchange` 使用 Redis。

选型边界如下：

- 单进程临界区优先 `lock`、`SemaphoreSlim` 或 keyed lock。
- 多实例协调才使用分布式锁。
- 数据唯一性最终仍应由数据库约束保护。
- 分布式锁必须考虑 lease 到期、续租、进程暂停和 fencing token。
- 任务状态需要持久化时，内存 Singleton 不能作为唯一存储。

### 11.5 超时订单作业验证

实现一个订单超时取消作业，并验证以下行为：

1. 每分钟扫描超过 30 分钟仍为 Draft 的订单。
2. 使用数据库批量更新和乐观并发，不逐条加载全部实体。
3. 多实例运行时保证同一订单的副作用幂等。
4. 外部通知使用带 timeout、retry、circuit breaker 的 HttpClient。
5. 输出成功、失败、重试、跳过和耗时指标。
6. 支持优雅停止，并验证停止时不会接收新批次。

## 12. 日志、指标、链路追踪与运行时诊断

### 12.1 可观测性的三根支柱

| 信号 | 回答的问题 | .NET API |
| --- | --- | --- |
| Logs | 发生了什么，包含哪些上下文？ | `ILogger<T>`、Serilog |
| Metrics | 系统整体趋势和当前健康度如何？ | `Meter`、Counter、Histogram、ObservableGauge |
| Traces | 一次请求跨组件经历了什么？ | `ActivitySource`、`Activity`、OpenTelemetry |

Health Check 回答的是“当前是否可服务”，profiling 回答的是“CPU、内存和分配花在哪里”，它们与三大信号相关但不等同。

### 12.2 OpenTelemetry 数据流

```text
Instrumentation
  -> Activity / Metric instruments
  -> OpenTelemetry SDK processors/readers
  -> OTLP / Prometheus / Console exporter
  -> Collector / APM / Dashboard
```

`MoLibrary/Monica.OpenTelemetry` 默认订阅 `Monica.*` Meter，并支持：

- ASP.NET Core、HttpClient 和 Runtime **metrics** instrumentation。
- OTLP exporter。
- Prometheus `/metrics` endpoint。
- Console exporter。
- 有界的 in-process metrics collector 和 Blazor dashboard。

项目 README 明确指出：in-process collector 适合本地诊断，不应用作生产长期保留或多实例分析。这一限制明确了进程内诊断与生产观测后端之间的边界。

需要区分当前实现与本章扩展示例。本次源码审计直接找到的是 `WithMetrics(...)`，没有找到 `WithTracing(...)` 或项目级 `ActivitySource` 接入。`Monica.Framework/ChainTracing` 是项目自定义的调用链上下文，也不能直接等同于 OpenTelemetry distributed tracing。

下面的注册代码是标准 tracing 组合的补充示例，不代表 Monica 当前已经完整实现 logs、metrics 和 traces。

包含 tracing 的补充注册示例：

```csharp
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("Ordering.Api"))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddSource("Ordering"))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddMeter("Ordering"));
```

Exporter 可以按环境另行选择，避免业务模块直接依赖具体后端。

### 12.3 自定义指标和链路

```csharp
using System.Diagnostics;
using System.Diagnostics.Metrics;

public sealed class OrderTelemetry : IDisposable
{
    public const string SOURCE_NAME = "Ordering";
    private readonly ActivitySource _activitySource = new(SOURCE_NAME);
    private readonly Counter<long> _approvedOrders;
    private readonly Histogram<double> _approvalDuration;

    public OrderTelemetry(IMeterFactory meterFactory)
    {
        var meter = meterFactory.Create(SOURCE_NAME);
        _approvedOrders = meter.CreateCounter<long>("ordering.orders.approved");
        _approvalDuration = meter.CreateHistogram<double>(
            "ordering.order.approval.duration",
            unit: "s");
    }

    public Activity? StartApproval(Guid orderId) =>
        _activitySource.StartActivity("Approve order")?
            .AddTag("order.id", orderId);

    public void Dispose() => _activitySource.Dispose();
}
```

示例用于说明 API；真实系统要谨慎选择 tag。把用户 ID、订单 ID 或 URL 原文作为 metric tag，可能制造无限 cardinality。高基数标识通常更适合 trace/log，而 metric 应使用状态、类型、区域等有界维度。

### 12.4 结构化日志

保留结构化字段的写法：

```csharp
logger.LogInformation(
    "Approved order {OrderId} for tenant {TenantId}",
    order.Id,
    tenantId);
```

避免插值字符串提前丢失结构化字段：

```csharp
logger.LogInformation($"Approved order {order.Id}");
```

`Monica.Logging` 使用 Serilog 和 async sink。异步日志可以降低请求线程阻塞，但要理解缓冲区满、进程崩溃、flush 和关机等待策略。

### 12.5 框架诊断

Monica 不只采集通用 telemetry，还为模块、HostedService、Repository、ProjectUnit、Configuration 和 DI 建立专用诊断快照。这类诊断回答的是领域化问题：

- 哪些模块被组合，依赖拓扑是什么？
- 哪个初始化阶段最慢？
- 哪个后台服务处于异常状态？
- 哪些 DbContext 被注册，当前活动连接如何？
- 哪些 ProjectUnit 缺少元数据或依赖关系？

Core 模块诊断需要显式注册 `monica.AddModuleSystem()`；`monica.AddModuleSystemUI()` 会自动引入它。`ModuleDiagnosticsFacade` 当前提供四类边界：

- `GetSnapshot()`：不可变、带 revision 的组合快照，包含模块拓扑、回调、启动工作、类型发现阶段和耗时。
- `GetAssemblyInventory()`：按需构建并缓存程序集解析和类型扫描清单，避免基础快照总是携带程序集路径。
- `GetModuleOptions(...)`：为最终模块 Options 生成完整的公开属性目录，并只投影有界值。
- `CreateExport()`：生成可移植 baseline，不包含配置值、程序集路径、堆栈或原始异常详情。

模块 Options 的每个 public、非 indexer 属性都会进入目录。`[ModuleOptionDiagnosticsSensitive]`、内置敏感名称判断或 Host policy 可以把字段标为敏感；默认模式为 `Redacted`。`RevealSensitive` 只允许在 Development 环境使用，计算值和运行时形状的值始终只保留 metadata，portable export 永远不包含 Options。

设计专用诊断时应遵循：

- 对外暴露不可变 DTO，不暴露反射对象或可变内部状态。
- 限制记录条数、tag set 和正文大小。
- 默认清理密钥、连接串、文件绝对路径、堆栈和原始异常。
- Development 与 Production 采用不同揭示策略，并配置授权。
- 诊断本身也要有性能预算。

### 12.6 Profiling 与 Benchmark

`Monica.Profiling` 使用 `Microsoft.Diagnostics.Runtime` 和 TraceEvent 分析 EventPipe/ETW、分配与堆快照；`benchmarks/Benchmark.Monica.Core` 使用 BenchmarkDotNet 测量模块组合、类型发现和诊断投影。

排查通常按以下顺序进行：

1. 用 metrics/traces 定位异常区域。
2. 用 profiler 找 CPU、分配、锁竞争或 GC 原因。
3. 建立可重复 microbenchmark。
4. 优化并比较统计结果。
5. 回到端到端负载验证实际收益。

microbenchmark 快不代表整个应用更快，尤其不能忽略数据库、网络和序列化。

### 12.7 可观测性基线

为订单系统建立以下可观测基线：

- 每个请求具有 trace，并向数据库和外部 HTTP 传播。
- 指标包含吞吐、错误、延迟、后台积压和 Outbox 未发布数。
- 日志可通过 trace ID 关联。
- `/health/live` 只检查进程存活，`/health/ready` 检查必要依赖。
- Prometheus 或 OTLP 导出可配置。
- 构建一个本地诊断页，但限制样本和敏感数据。

## 13. 认证、授权与应用安全

### 13.1 Authentication 与 Authorization

- Authentication 回答“你是谁”。
- Authorization 回答“你能做什么”。

`MoLibrary/Monica.Authority` 使用 JWT bearer、claims、permission bit、CORS 和当前用户 abstraction。参考模块还展示了 C# 14 extension block、模块顺序和受限 query-string access token。

标准 JWT bearer 注册通常包括：

```csharp
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = builder.Configuration["Authentication:Authority"];
        options.Audience = "ordering-api";
        options.RequireHttpsMetadata = true;
    });

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("orders.approve", policy =>
        policy.RequireClaim("permission", "orders.approve"));
```

优先使用成熟身份提供商和标准 OIDC/OAuth 2.0 流程。自行签发 token 时必须理解密钥轮换、issuer、audience、clock skew、refresh token 重放和撤销。

### 13.2 Query-string token 的风险

SignalR、SSE 或受限传输有时需要从 query string 读取 access token。必须限制到明确路径，因为 URL 可能进入：

- 代理和服务器访问日志。
- 浏览器历史。
- 监控与分析系统。
- Referer header。

参考模块要求显式配置 path prefix，并拒绝为整个应用根路径开启。这形成了一个较安全的默认边界。

### 13.3 .NET 10 相关变化

- Cookie authentication 对已知 API endpoint 默认返回 401/403，而不是 HTML redirect。
- ASP.NET Core Identity 增加 passkey/WebAuthn 支持，适合抗钓鱼登录。
- Identity 提供新的 meter，可观察用户管理、登录、登出和双因素认证行为。
- EF Core 10 对 SQL 日志敏感常量遮盖和 raw SQL 拼接分析更严格。

升级时要写契约测试，尤其检查 SPA、Blazor、传统网页和 API 是否依赖旧重定向行为。

### 13.4 安全边界与控制项

- HTTPS、HSTS、反向代理与 forwarded headers。
- CORS 不是认证机制，`AllowAnyOrigin` 不会保护 API。
- CSRF 与 cookie authentication；bearer token 的威胁模型不同。
- XSS、输出编码和 Blazor/Markdown 富文本清理。
- SSRF：AI 工具、MCP、Webhook、文件下载尤其要限制目标地址。
- SQL injection：优先参数化 API，严格审查 `FromSqlRaw`。
- Secret management 和 key rotation。
- 最小权限、策略授权和资源级授权。
- 审计日志与普通诊断日志的不同保留要求。
- 软件供应链：锁定依赖、漏洞扫描、NuGet 来源和签名。

### 13.5 授权与运维端点风险

认证与运维端点中需要防范以下问题：

- 只验证 token 签名，不验证 issuer、audience 和 lifetime。
- 把角色名硬编码到所有业务方法，而没有稳定 permission/policy。
- 在日志记录 token、cookie、API key 或完整认证 header。
- 用 CORS 代替授权。
- Blazor 运维页面只隐藏菜单，没有在服务端 endpoint 再授权。
- Development 诊断能力在 Production 默认开放。

为订单审批建立 policy-based authorization，分别测试未认证、无权限、有权限、token 过期和 issuer 错误。运维诊断端点使用独立 policy，并增加直接调用 endpoint 的测试，用来确认菜单隐藏不能替代服务端授权。

## 14. Blazor、MudBlazor 与运维工作台

### 14.1 项目采用的 UI 模式

`Monica.UI` 是 Razor Class Library，使用：

- Blazor Interactive Server Components。
- MudBlazor 9 和 MudBlazor.Markdown。
- static web assets。
- JSON embedded localization resources。
- Scoped circuit state，例如主题和用户上下文。
- 一个 UI Shell，再由 JobScheduler、Configuration、Repository、OpenTelemetry、AI 等模块贡献页面。

`ModuleShellUI` 中的关键注册是：

```csharp
services.AddRazorComponents()
    .AddInteractiveServerComponents();

webApp.MapRazorComponents<AppShell>()
    .AddInteractiveServerRenderMode()
    .AddAdditionalAssemblies(componentAssemblies);
```

Razor Class Library 的组件、路由和静态资源来自 NuGet 包或额外程序集，因此 `AddAdditionalAssemblies`、`MapStaticAssets` 和静态资源清单非常重要。

### 14.2 Blazor Server 执行模型

Interactive Server 的 UI 逻辑运行在服务器，浏览器通过 SignalR circuit 发送事件和接收渲染差异。

优点：

- 浏览器下载体积小。
- 可以直接使用服务器端 .NET 能力。
- 适合内部运维后台和低延迟网络。

代价：

- 每个活动用户占用服务器 circuit 状态。
- 网络断开影响交互。
- Scoped 服务通常是“每个 circuit”，不等于“每个 HTTP 请求”。
- 不能在组件中长期保留大对象、非线程安全数据库上下文或未释放订阅。

### 14.3 组件生命周期与状态边界

- 参数用 `[Parameter]`，跨层级共享状态谨慎使用 cascading value。
- I/O 放在合适的生命周期方法，避免每次 render 重复请求。
- `OnAfterRenderAsync(firstRender)` 适合需要 DOM/JS 的初始化。
- 订阅 event、timer、`IOptionsMonitor.OnChange` 后必须释放。
- 组件中的异步回调要处理取消和 component disposal。
- `@key` 用于稳定列表项身份，不是性能装饰。
- CSS isolation 配合第三方组件时要理解 `::deep` 和最终 DOM。

### 14.4 .NET 10 Blazor 相关机制

| 能力 | 机制与影响 |
| --- | --- |
| Metrics 与 tracing | 可以观测 component lifecycle、navigation、event handling 和 circuit。 |
| 改进的表单验证 | 支持嵌套对象和集合，并使用源生成器提高 AOT 兼容性。 |
| Circuit state persistence | 网络中断、标签页节流或主动暂停后可恢复部分会话状态。 |
| Persistent state 增强 | enhanced navigation 中可以更精细控制恢复和更新。 |
| WebAssembly resource preload | 模板用 `ResourcePreloader` 更可靠地预加载资源。 |
| Passkey 模板 | Identity + Blazor 可提供现代无密码登录体验。 |

源生成验证要求顶层模型位于 `.cs` 文件并标记 `[ValidatableType]`。这是因为 Razor 编译器和验证功能都使用源生成器，而一个生成器的输出目前不能作为另一个生成器的输入。

### 14.5 运维 UI 的边界

Monica 的 UI 主要是运行时工作台，而不是业务前台。这类页面尤其要注意：

- 服务端授权必须独立存在，不能只靠菜单隐藏。
- Module System 工作台默认只在 Development 开放。设置 `ModuleSystemUIOption.EnableOutsideDevelopment=true` 时，`AuthorizationPolicy` 不能为空；同一 policy 会同时约束导航显示和 Core diagnostics 调用。
- 默认只展示清理后的配置和诊断。
- 大型列表要分页、虚拟化或使用有界快照。
- 不允许一次加载完整堆快照、日志或高基数指标到 circuit。
- Production 中的重启、配置修改、任务触发等操作应有二次确认、审计和策略授权。
- UI 模块不应反向成为基础设施模块的依赖。

### 14.6 运维工作台验证

创建一个订单运维工作台，并覆盖以下场景：

- 展示请求吞吐、审批延迟、后台积压和 Outbox 数量。
- 支持深色模式和中英文切换。
- 表单使用 .NET 10 嵌套验证。
- 页面刷新或 circuit 恢复后保留筛选条件。
- 所有管理操作调用受授权的 API/Facade。
- 使用 bUnit 测试加载、错误、无权限和空状态。

## 15. Roslyn、源生成器与架构分析

### 15.1 Monica 中的两类 Roslyn 用法

| 类型 | 项目 | 运行时机 | 主要用途 |
| --- | --- | --- | --- |
| Incremental source generator | `Monica.Generators.AutoController`、`Monica.Framework.Generators` | 编译期间 | 从 request contract 生成 Controller/RPC client，生成 change-tracking 辅助代码 |
| Workspace semantic analysis | `Monica.ProjectUnits.CodeAnalysis` | 工具运行期间 | 用 MSBuildWorkspace 分析整个解决方案，而不加载业务程序集 |

两类工具的执行边界不同。Generator 参与当前 compilation，只能添加新源码，不能修改用户已有文件；Workspace 工具可以跨项目读取和修改 Solution，但不会自动进入编译过程。

### 15.2 Incremental Generator 的适用场景

运行时反射只能在应用启动后发现部分问题，对 NativeAOT 也不友好。Incremental Generator 可用于：

- 在编译期读取 syntax、symbol 和 attribute。
- 生成强类型、可调试的源码。
- 对未变化输入复用中间结果，降低 IDE 编辑成本。
- 在编译期报告精确到源码位置的 diagnostic。

`Monica.Generators.AutoController/Monica.Generators.AutoController.csproj` 目标为 `netstandard2.0`，并以 analyzer asset 打包：

```xml
<PropertyGroup>
  <TargetFramework>netstandard2.0</TargetFramework>
  <IncludeBuildOutput>false</IncludeBuildOutput>
  <DevelopmentDependency>true</DevelopmentDependency>
</PropertyGroup>

<ItemGroup>
  <None Include="$(OutputPath)\$(AssemblyName).dll"
        Pack="true"
        PackagePath="analyzers/dotnet/cs" />
</ItemGroup>
```

生成器由编译器进程加载，因此目标框架需要兼容编译器宿主。业务项目使用 `net10.0`，不表示 analyzer 也适合只面向 `net10.0`。

### 15.3 生成器实现约束

- 输入和输出需要保持确定性，不依赖当前时间、网络或任意外部进程。
- 用 `ForAttributeWithMetadataName` 等精确入口，避免每次扫描全部语法节点。
- 尽早把 Roslyn 大对象转换为小型不可变模型，便于缓存和测试。
- 每个 `AddSource` hint name 应稳定且唯一。
- 对非法输入报告 diagnostic，避免静默生成错误代码。
- 生成代码应可读，便于开发者查看和调试。
- 分析器/生成器包版本要兼容目标 SDK 和 IDE 中的 compiler host。

### 15.4 Runtime reflection、Generator 与 Analyzer 的选择

| 需求 | 更合适的技术 |
| --- | --- |
| 运行时加载真正未知的插件 | Reflection / AssemblyLoadContext |
| 从编译期已知契约生成样板代码 | Incremental Generator |
| 阻止违反编码或架构规则的代码 | Diagnostic Analyzer |
| 自动提供 IDE 修复 | CodeFixProvider |
| 跨项目查询依赖和 symbol | MSBuildWorkspace |
| 简单静态映射且代码很少 | 直接手写，通常最清楚 |

### 15.5 Incremental Generator 验证

可以编写一个 generator，查找标记 `[ApiContract]` 的 request record，生成 endpoint mapping extension，并报告下列诊断：

- route 重复。
- request 不是 partial/record 或不满足约定。
- 返回类型不可序列化。
- route parameter 与属性不匹配。

同时编写 snapshot/golden-file 测试，检查输入未变化时输出是否稳定；再用 Benchmark 或 generator timing 观察大型项目中的增量性能。

Roslyn API、Syntax/Semantic Model、Workspace、Analyzer 和 Generator 的详细说明参见 [Roslyn](Roslyn.md)。

## 16. 测试、性能分析与质量保障

### 16.1 项目测试栈

本次扫描到的主要工具包括：

- xUnit v3：测试框架。
- Microsoft.NET.Test.Sdk 与 .NET 10 `dotnet test`。
- AwesomeAssertions：可读断言。
- NSubstitute 与 analyzer：test double。
- ASP.NET Core TestHost：宿主和 HTTP 集成测试。
- bUnit + AngleSharp：Blazor component test。
- EF Core SQLite/InMemory：数据测试 provider。
- coverlet collector：覆盖率。
- BenchmarkDotNet：microbenchmark。

`Monica.Testing` 还提供完整 Host factory、scope、service seam replacement、数据库隔离和 ProjectUnit 快速 fixture。

### 16.2 测试分层

| 层次 | 验证内容 | 典型工具 | 不应承担的任务 |
| --- | --- | --- | --- |
| 纯单元测试 | Entity、值对象、纯策略和转换 | xUnit、AwesomeAssertions | 验证真实 DI、SQL 或 HTTP |
| Collaboration test | Handler 与明确的几个协作者 | NSubstitute 或轻量 fixture | 模拟整个框架 |
| Integration test | DI、Options、EF SQL、模块组合、外部适配器 | TestHost、SQLite、容器 | 覆盖所有排列组合 |
| Component test | Razor 渲染、事件、状态、权限分支 | bUnit、AngleSharp | 证明浏览器 JS 和真实网络完全正确 |
| End-to-end test | 关键用户旅程和部署集成 | 浏览器/真实服务 | 代替大量快速测试 |
| Benchmark | 热路径吞吐、延迟、分配 | BenchmarkDotNet | 业务正确性 |

### 16.3 完整 Host 测试覆盖的运行时行为

框架行为往往依赖：

- 模块图和 type discovery。
- Options binding/validation。
- scoped 生命周期。
- HostedService 启动。
- middleware 和 endpoint mapping。
- EF provider、transaction 和 serializer 配置。

只执行 `new Handler(mock1, mock2)` 无法覆盖这些行为。`MonicaTestApplicationFactory<T>` 为每个测试场景创建完整且独立的 Host，并通过明确的 seam 替换外部边界，而不是复制已构建容器中的 service descriptor。

### 16.4 EF Core 测试选择

- 领域规则用纯单元测试。
- LINQ 翻译、约束、事务和 migration 使用真实关系型 provider。
- SQLite in-memory 可做快速关系型测试，但与 SQL Server/PostgreSQL 仍有语法和行为差异。
- EF InMemory 适合很少数不关心关系语义的场景，不应证明生产 SQL 正确。
- 不建议模拟 `DbSet<T>` 来测试复杂查询；它无法复制 EF query provider。

### 16.5 测试并发与隔离

- 每个场景使用独立数据库名称、schema、容器或事务边界。
- 不共享可变 Singleton double。
- dispose scope 后再 dispose Host。
- 仅对共享外部资源的测试进行串行化，其他测试可保持并行。
- 测试 cancellation、timeout 和关机，而不只测成功路径。
- 时间相关逻辑使用 `TimeProvider` 或抽象时钟，避免真实等待。

当前 CI 把编译和测试并发分开处理。`dotnet build Monica.slnx -m` 允许 MSBuild 并行编译；`dotnet test Monica.slnx -m:1` 则串行调度测试项目，用于降低多个测试宿主和输出目录之间的竞争。

`tests/xunit.runner.json` 仍开启 assembly/collection parallelization，因此项目级串行不等于每个测试方法都串行。分析测试卡死或资源争用时，需要分别检查 MSBuild project parallelism、test assembly parallelism 和 collection parallelism。

### 16.6 Benchmark 与性能基线

`benchmarks/Benchmark.Monica.Core` 测试 100～10,000 个类型、不同查询数、10～200 个模块和诊断快照规模。其实现方式包括：

- correctness test 与 benchmark 分开。
- expensive stress case 不进入普通 CI。
- 动态生成或编译放在 iteration setup，避免污染被测量路径。
- 对 collectibility 等结果失败时直接让 benchmark 失败，而不是返回一个容易忽略的布尔值。

分析性能结果时通常需要同时观察均值、分位数、误差、分配量、GC 次数和基线比值。单次 Stopwatch 结果不足以作为可靠结论。

### 16.7 综合测试矩阵

综合项目的测试范围可包括：

1. Entity 审批不变量单元测试。
2. Handler collaboration test。
3. SQLite/PostgreSQL transaction、filter、Outbox 集成测试。
4. TestHost HTTP 合同测试。
5. bUnit 运维组件测试。
6. Source generator golden test。
7. 类型发现或序列化 Benchmark。
8. 覆盖取消、重复事件、并发审批、无权限和配置非法更新。

覆盖率只能显示哪些行执行过，不能反映断言质量。可将 mutation-prone 的规则、失败路径和边界条件单独列入测试清单。

## 17. 分布式集成与 AI 能力

### 17.1 Integrations 技术矩阵

| 能力 | 项目/依赖 | 适用条件 |
| --- | --- | --- |
| Kafka | `Monica.EventBus.Kafka`、Confluent.Kafka | 需要高吞吐持久事件流、分区顺序、消费组时。 |
| ActiveMQ | `Monica.DataChannel`、Apache.NMS.ActiveMQ | 既有 JMS/ActiveMQ 生态或传统消息集成时。 |
| Dapr | `Monica.Dapr` | 希望用 sidecar 统一 pub/sub、state、lock、service invocation、actor 时。 |
| Redis | `Monica.StateStore.StackExchange` | 需要共享缓存、状态、任务进度或协调时。 |
| SignalR | `Monica.SignalR` | 需要服务端与客户端双向实时交互时。 |
| Service Discovery | `Monica.ServiceDiscovery` | 动态实例、健康检查、负载选择或自建注册中心确有需要时。 |
| Distributed Lock | `Monica.Locker` | 多实例对不可原子化外部资源进行短期协调时。 |
| Excel/Markdown/DevOps | `Monica.Office`、`Monica.Markdown`、`Monica.DevOps` | 由明确产品功能驱动，不应进入所有服务的基础依赖。 |

`Monica.SignalR` 还展示了 `Hub<TContract>`、`IHubContext<THub,TContract>`、连接目录和发送指标代理。当前连接 registry 是进程内 `ConcurrentDictionary`，只能表示单实例 presence；多副本系统需要 backplane 或外部 presence store。

源码中 `EnableDetailedErrors` 的默认值为 `true`。这个默认值便于开发诊断，但可能向客户端暴露过多异常细节；Production Host 应明确覆盖为关闭。

### 17.2 微服务拆分的适用边界

引入分布式边界后会新增：

- 网络部分失败和超时。
- 跨服务 schema 演进。
- 最终一致性。
- trace context 传播。
- 服务发现、证书和 secret 分发。
- 独立部署、回滚和容量规划。
- 本地开发与集成测试复杂度。

当一个模块化单体尚不能保持清晰边界时，拆成网络服务通常只会把代码耦合变成运行时耦合。先用项目引用、模块 API 和架构测试建立边界，再根据独立扩缩容、团队自治、隔离或部署节奏决定是否拆分。

### 17.3 AI 抽象层

`Monica.AI` 使用的主要组件包括：

- `Microsoft.Extensions.AI` 与 `IChatClient`。
- Microsoft Agent Framework。
- OpenAI、Anthropic provider。
- MCP server/client。
- class-based 与 file-based Agent Skills、受限只读文件工具。
- Chat history、tool calling 和 streaming coordinator。
- Knowledge Base、chunker、embedding、vector store。
- In-memory vector store 与 Qdrant。

业务代码可通过 provider abstraction 依赖 `IChatClient` 或应用自有的窄接口，避免在各处暴露具体 SDK 类型。这样便于：

- 替换供应商和模型。
- 在测试中使用 fake client。
- 统一超时、重试、配额、审计和 token 统计。
- 控制工具调用和敏感数据。

### 17.4 MCP

Model Context Protocol 用统一协议向 Agent 暴露 tool、resource 和 prompt。项目支持本地 MCP server、stdio hosted service、外部 HTTP MCP client 和 capability catalog。

`ModuleMcpOption.McpHttpEndpointPath` 默认是 `/mcp`，实际 HTTP endpoint 统一投影为 `/mcp/{serverName}`。`CreateHttpEndpointPath(serverName)`、运行时 route pattern 和管理 UI 共用同一套规范化逻辑，并对 server name 做 URL escaping。

宿主可以通过 `RequireHttpAuthorization(policyName)` 为 Monica 托管的 HTTP MCP endpoint 指定统一授权策略。它约束的是 endpoint 执行边界，不能由管理 UI 隐藏或工具目录过滤代替。

接入 MCP 时需要关注以下安全边界：

- 工具列表本身不构成授权，执行前仍需检查当前用户和资源权限。
- 外部 MCP endpoint 可能形成 SSRF 或数据外泄通道。
- 文件工具需要限制允许的根目录，并处理符号链接和路径规范化。
- subprocess tool 应限定命令、参数 schema、超时、输出上限和沙箱。
- Tool description 和返回数据都可能携带 prompt injection。
- 高风险工具应配置确认、审计和最小权限。

### 17.5 RAG 执行链

```text
Document
  -> Parse / Normalize
  -> Chunk
  -> Generate Embedding
  -> Store vector + metadata
  -> User query embedding
  -> Top-K retrieval / filter / rerank
  -> Build grounded prompt
  -> Model answer + citation
```

`Monica.AI/Modules/ModuleRAG.cs` 支持内存或 Qdrant vector store、多种 chunker、知识库级 embedding binding、索引状态和搜索 Facade。

各环节需要分别评估：

- Chunk 大小和 overlap 影响上下文完整性与噪声。
- Embedding model 变化可能要求重建索引。
- Top-K 不是越大越好。
- 相似度分数不能直接等同于事实正确性。
- 文档更新、删除和权限变化需要同步传播到索引。
- 检索阶段需要应用租户与 ACL 过滤，不能检索后才尝试隐藏。
- 回答应保留 citation，并允许明确返回“资料不足”。

### 17.6 Streaming、SSE 与 Channel

项目的 Agent streaming coordinator 使用异步流/Channel 类型的生产者—消费者思想。.NET 10 的 SSE 可以作为浏览器输出边界：

```text
Model provider stream
  -> normalize updates
  -> bounded Channel
  -> cancellation / backpressure
  -> SSE endpoint
  -> browser
```

实现前需要确定：客户端断开时是否取消模型调用、Channel 满时阻塞还是丢弃、工具调用事件是否对用户可见，以及最终消息如何持久化。

### 17.7 只读运维 Agent 验证

可以在订单系统主路径稳定后增加一个只读运维 Agent：

1. 用 `IChatClient` 抽象 provider，并提供 fake implementation。
2. 只暴露读取订单统计和查询文档的工具。
3. 使用 RAG 检索运维手册，回答需带引用。
4. 用 SSE 输出流式结果。
5. 对 tenant、document ACL 和 tool policy 做服务端检查。
6. 记录 token、延迟、tool error 和取消指标，但不记录敏感 prompt 全文。
7. 编写 prompt injection、越权工具调用和 provider timeout 测试。
8. 注册一个 file-based Skill，只允许读取测试目录，并覆盖越界路径、结果上限和未配置 script runner 的失败行为。

AI、MCP 和 RAG 在项目中属于 Labs。引入这些能力时，仍需沿用既有的配置、安全、可观测、测试和数据边界。

### 17.8 Agent Skill 系统与发布治理

Monica 中有两套相关但生命周期不同的 Skill：

1. **应用运行时 Skill**：`Monica.AI/Modules/ModuleSkillSystem.cs` 通过 `ModuleSkillSystem` 发现继承 `Skill` 的 class，也可以加载以 `SKILL.md` 为入口的文件型 Agent Framework Skill，并把能力贡献给 Chat Agent。
2. **仓库开发 Skill**：根目录 `skills/` 是 Monica 自有开发指导的唯一源码，当前包含 20 个 `monica-*` Skill；`.agents/skills/` 与 `.claude/skills/` 是面向不同 Agent Host 的生成投影，不是编辑源。

运行时文件访问能力采用显式 root allowlist。默认配置还限制 `rg` 子进程超时、读取行数、token 数、搜索结果数、上下文行和单行字符数；例如默认最长运行 20 秒，单次读取上限 400 行/12,000 tokens，结果上限 200 条。文件型 Skill 的脚本只有在提供 runner 时才能执行，内置 subprocess runner 仍需单独评估命令、工作目录、超时和输出边界。

仓库级 `.monica/agent-skill-index.json` 使用 schema v2，记录 stable/preview channel、不可变 release tag、commit、catalog/manifest/tree digest、每个 Skill 的 digest、revision 和 `lastChangedIn`。rc.12 release workflow 同时发布 catalog、index、manifest 和 ZIP，并在切换版本前验证摘要。

这可以看作一套内容供应链设计：版本标签面向人，digest 用于机器校验完整性，revision 和 `lastChangedIn` 用于解释某个 Skill 从哪个发布开始变化。

这两套机制不能混为一谈。`ModuleSkillSystem` 决定运行中 Agent 可以调用什么；`skills/` 和 release index 决定开发 Agent 获取哪一版工程约束。前者关注授权与工具执行，后者关注来源、完整性、版本切换和投影一致性。

### 17.9 参考代码的适用边界

阅读大型项目时，需要同时识别可复用的设计和现有实现的运行风险。本次审计中有以下几个适合进一步评审的例子：

- `Monica.DataChannel` 的一个同步入口使用 `.Wait()` 调用异步发送，存在 sync-over-async 阻塞风险；新 API 应尽量 async all the way。
- JobScheduler 的部分 Timer callback 使用 `async void`，应重点分析异常、重入和停止等待问题。
- `Monica.DevOps` 能执行终端、Git、SSH 和文件操作，属于高权限能力，需要配置根路径、allowlist、超时、进程树终止、审计和独立授权。
- Excel 导入导出要考虑 EPPlus 许可、公式注入、不可信文档和内存上限。
- heap snapshot、dump、terminal output 和 AI chat history 都可能含有 secret 或 PII，诊断和运维功能同样属于安全边界。

此外，根 README 把 FluentValidation 列入技术栈，但正式项目文件中未扫描到对应依赖或使用证据。因此本文只把它作为可选验证方案，而不把它写成“项目已经采用”的事实。技术盘点宜以源码和构建依赖为依据，并单独记录 README 与实现之间的差异。

## 18. 参考资料

### 18.1 Microsoft 官方资料

1. [.NET 10 新增功能](https://learn.microsoft.com/dotnet/core/whats-new/dotnet-10/overview)
2. [C# 14 新增功能](https://learn.microsoft.com/dotnet/csharp/whats-new/csharp-14)
3. [ASP.NET Core 10 新增功能](https://learn.microsoft.com/aspnet/core/release-notes/aspnetcore-10.0)
4. [EF Core 10 新增功能](https://learn.microsoft.com/ef/core/what-is-new/ef-core-10.0/whatsnew)
5. [.NET Generic Host](https://learn.microsoft.com/dotnet/core/extensions/generic-host)
6. [.NET 依赖注入](https://learn.microsoft.com/dotnet/core/extensions/dependency-injection)
7. [.NET 配置](https://learn.microsoft.com/dotnet/core/extensions/configuration)
8. [.NET Options pattern](https://learn.microsoft.com/dotnet/core/extensions/options)
9. [ASP.NET Core Minimal API](https://learn.microsoft.com/aspnet/core/fundamentals/minimal-apis)
10. [ASP.NET Core 错误处理](https://learn.microsoft.com/aspnet/core/fundamentals/error-handling)
11. [ASP.NET Core OpenAPI](https://learn.microsoft.com/aspnet/core/fundamentals/openapi/overview)
12. [EF Core DbContext lifetime](https://learn.microsoft.com/ef/core/dbcontext-configuration/)
13. [EF Core 高效查询](https://learn.microsoft.com/ef/core/performance/efficient-querying)
14. [.NET OpenTelemetry](https://learn.microsoft.com/dotnet/core/diagnostics/observability-with-otel)
15. [ASP.NET Core Blazor](https://learn.microsoft.com/aspnet/core/blazor/)
16. [Roslyn SDK](https://learn.microsoft.com/dotnet/csharp/roslyn-sdk/)
17. [ASP.NET Core Security](https://learn.microsoft.com/aspnet/core/security/)
18. [Microsoft Testing Platform](https://learn.microsoft.com/dotnet/core/testing/microsoft-testing-platform-intro)

### 18.2 生态组件官方资料

1. [OpenTelemetry .NET](https://opentelemetry.io/docs/languages/dotnet/)
2. [Polly](https://www.pollydocs.org/)
3. [MudBlazor](https://mudblazor.com/)
4. [Mapster](https://github.com/MapsterMapper/Mapster/wiki)
5. [Dapr .NET SDK](https://docs.dapr.io/developing-applications/sdks/dotnet/)
6. [Confluent.Kafka .NET Client](https://docs.confluent.io/kafka-clients/dotnet/current/overview.html)
7. [StackExchange.Redis](https://stackexchange.github.io/StackExchange.Redis/)
8. [Microsoft.Extensions.AI](https://learn.microsoft.com/dotnet/ai/microsoft-extensions-ai)
9. [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
10. [Model Context Protocol](https://modelcontextprotocol.io/)
11. [Qdrant](https://qdrant.tech/documentation/)
12. [BenchmarkDotNet](https://benchmarkdotnet.org/)
13. [bUnit](https://bunit.dev/)

### 18.3 Monica 重点阅读路径

源码入口：[https://github.com/Tairitsua/Monica](https://github.com/Tairitsua/Monica)。可按以下顺序建立主路径，再进入具体实现：

1. `README.zh_CN.md` 与 `CHANGELOG.md`：项目定位、rc.12 变更和当前实现边界。
2. `Directory.Build.props`、`Directory.Build.targets` 与 `eng/package-tiers.json`：构建、打包和成熟度基线。
3. `examples/Monica.ReferenceApplication/README.md` 与 `examples/Monica.ReferenceApplication/src/AppHost/Monica.Reference.Api/Program.cs`：Stable 主路径。
4. `Monica.Core/Modularity/Abstractions`：模块、Options、注册句柄、启动工作和类型发现计划。
5. `Monica.Core/Modularity/Services` 与 `Monica.Core/Modularity/Diagnostics`：模块图编译、barrier、性能预算和诊断投影。
6. `Monica.ProjectUnits` 与 `Monica.ProjectUnits.CodeAnalysis`：运行时目录和源码分析 contract。
7. `Monica.Configuration`：不可变 input plan、Provider 投影、版本和回滚。
8. `Monica.Repository` 与 `Monica.EventBus`：数据、事务和事件边界。
9. `Monica.JobScheduler` 与 `Monica.OpenTelemetry`：后台运行和可观测性。
10. `Monica.UI/Modules/ModuleShellUI.cs` 与 `Monica.UI/Modules/ModuleSystemUI.cs`：Blazor Shell、诊断工作台和授权边界。
11. `Monica.Generators.AutoController`：incremental generator。
12. `Monica.Testing/README.md`、`tests/Test.Monica.*` 与 `.github/workflows/unit-tests.yml`：完整 Host 测试及 CI 并发策略。
13. `Monica.AI/Modules`：AI、MCP、RAG 和运行时 Skill system。
14. `skills/monica-guide` 与 `.monica/agent-skill-index.json`：开发 Agent Skill 的安装、版本、摘要和发布治理。

### 18.4 本仓库相关专题

- [EndpointFilter](EndpointFilter.md)
- [Roslyn](Roslyn.md)
- [ChangeTracker.TrackGraph](ChangeTracker.TrackGraph.md)
- [ExecutionContext 和 SynchronizationContext](ExecutionContext和SynchronizationContext.md)
- [Interlocked](Interlocked.md)
- [多线程并发访问 DbContext](Question/多线程并发访问DbContext.md)
- [多线程并发访问 HashSet](Question/多线程并发访问Hashset.md)
- [DDD](../Architecture/DDD.md)

本文的顺序不表示每个项目都需要使用全部技术。选型时可结合问题、约束、生命周期、失败模式、运维成本和团队能力，采用复杂度足够低且可以验证的方案。
