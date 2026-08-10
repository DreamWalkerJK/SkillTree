# C# 和 .NET LTS 中高阶语法与用法指南（.NET 10 → .NET 8）

> 最后核对：2026-08-10。本文只讨论当前相邻的两个 LTS 基线：`.NET 10 / C# 14` 与 `.NET 8 / C# 12`，按版本倒序组织。`.NET 9 / C# 13` 属于 STS，不单独成章。
>
> 从 .NET 5 开始，产品正式名称是“.NET”，不再叫“.NET Core”。因此准确说法是“.NET 10”和“.NET 8”；“ASP.NET Core”与“EF Core”仍保留 Core 名称。

本文面向已经掌握类、接口、委托、LINQ、异常和基本 `async`/`await` 的开发者。目标不是罗列语法糖，而是回答四个问题：

1. 新语法解决什么问题，编译器实际做了什么。
2. API 在什么边界内安全，什么时候会产生分配、阻塞或生命周期错误。
3. 如何在 ASP.NET Core、EF Core、Native AOT 和生产诊断中落地。
4. 去哪里阅读 Microsoft 官方文档、语言提案和框架源码。

仓库提供四个经过构建验证的伴随项目：

- [Net10Features](Examples/CSharpNetLts/Net10Features/Program.cs)：C# 14 与 .NET 10。
- [Net8Features](Examples/CSharpNetLts/Net8Features/Program.cs)：C# 12 与 .NET 8。
- [AdvancedPatterns](Examples/CSharpNetLts/AdvancedPatterns/Program.cs)：泛型数学、可空契约、模式匹配、Span、异步流、Channel 和可观测性。
- [AdvancedWebApi](Examples/CSharpNetLts/AdvancedWebApi/Program.cs)：Typed Results、Problem Details、异常处理、Options、Keyed DI 与 JSON 源生成。

## 目录

- [1. 版本、SDK 与项目基线](#1-版本sdk-与项目基线)
- [2. .NET 10 与 C# 14](#2-net-10-与-c-14)
- [3. .NET 8 与 C# 12](#3-net-8-与-c-12)
- [4. 类型系统、可空性与泛型](#4-类型系统可空性与泛型)
- [5. 值、引用、Span 与内存](#5-值引用span-与内存)
- [6. 异步、取消与并发](#6-异步取消与并发)
- [7. 集合、LINQ 与性能](#7-集合linq-与性能)
- [8. JSON、源生成、裁剪与 Native AOT](#8-json源生成裁剪与-native-aot)
- [9. Generic Host、DI、Options 与后台服务](#9-generic-hostdioptions-与后台服务)
- [10. ASP.NET Core 中高阶用法](#10-aspnet-core-中高阶用法)
- [11. EF Core 中高阶用法](#11-ef-core-中高阶用法)
- [12. 日志、指标、链路与运行时诊断](#12-日志指标链路与运行时诊断)
- [13. 多目标、升级与兼容性](#13-多目标升级与兼容性)
- [14. 官方资料与源码阅读地图](#14-官方资料与源码阅读地图)
- [附录 A：运行完整示例](#附录-a运行完整示例)
- [附录 B：代码审查清单](#附录-b代码审查清单)

## 1. 版本、SDK 与项目基线

### 1.1 只选 LTS 的版本矩阵

以下支持状态来自 Microsoft 的 [.NET 支持策略](https://dotnet.microsoft.com/zh-cn/platform/support/policy/dotnet-core) 与官方 [release metadata](https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json)。日期是产品生命周期边界，不代表可以长期停留在任意旧 patch；获得支持通常要求安装当前服务分支的最新 patch。

| 平台 | 默认 C# | TFM | 发布类型 | 2026-08-10 状态 | 支持结束 | 建议 |
| --- | --- | --- | --- | --- | --- | --- |
| .NET 10 | C# 14 | `net10.0` | LTS | Active | 2028-11-14 | 新项目首选；优先使用最新 `10.0.x` patch。 |
| .NET 8 | C# 12 | `net8.0` | LTS | Maintenance | 2026-11-10 | 仅用于既有生产基线或依赖兼容；应制定迁移到 .NET 10 的计划。 |

`.NET 9 / C# 13` 是 STS，因此本文不按该版本组织内容。语言和 BCL 是累积演进的：面向 `net10.0` 时当然也能使用更早已经进入编译器和运行时的能力，但这里以两个 LTS 目标的“最终可用能力”作为边界。

### 1.2 SDK、TFM、运行时与语言版本不是一回事

| 名称 | 决定什么 | 示例 |
| --- | --- | --- |
| SDK | 编译、还原、发布和模板工具链 | `dotnet --version` 输出 `10.0.102`。 |
| TFM | 编译时可引用的 API 集合和运行时目标 | `<TargetFramework>net10.0</TargetFramework>`。 |
| Runtime | 程序实际加载的 CLR 与 BCL patch | `Microsoft.NETCore.App 10.0.x`。 |
| C# 版本 | 编译器接受哪些语言语法和规则 | `<LangVersion>14.0</LangVersion>`。 |

新 SDK 可以编译较旧 TFM，前提是机器拥有相应 targeting pack。反过来，`net8.0` 不会因为使用 .NET 10 SDK 就自动获得 .NET 10 API。语言版本也不能替代运行时 API：即使人为让 `net8.0` 使用更新语言，引用 `JsonSerializerOptions.Strict` 仍会失败，因为该 API 不存在于 .NET 8 引用程序集。Microsoft 也不支持“目标旧 TFM、强制使用高于该 TFM 默认值的 C#”作为正式组合；不要把 `net8.0 + LangVersion 14.0` 当兼容方案。

官方资料：

- [目标框架](https://learn.microsoft.com/zh-cn/dotnet/standard/frameworks)
- [配置 C# 语言版本](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/configure-language-version)
- [.NET SDK 版本选择规则](https://learn.microsoft.com/zh-cn/dotnet/core/versions/selection)

### 1.3 推荐项目文件

.NET 10 项目：

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <LangVersion>14.0</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>
</Project>
```

.NET 8 项目：

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <LangVersion>12.0</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>
</Project>
```

显式写出稳定语言版本有两个好处：代码审查者能看到语法基线，CI 也不会因为安装了更新 SDK 而悄悄启用未来语法。库项目通常不要使用 `latest` 或 `preview`；这会让构建结果依赖构建机，而不是依赖仓库声明。

### 1.4 同时支持两个 LTS

类库可多目标：

```xml
<PropertyGroup>
  <TargetFrameworks>net10.0;net8.0</TargetFrameworks>
  <Nullable>enable</Nullable>
  <ImplicitUsings>enable</ImplicitUsings>
</PropertyGroup>
```

只在 .NET 10 存在的 API 应隔离在小范围适配器中：

```csharp
public static class JsonPolicy
{
    public static JsonSerializerOptions Create()
    {
#if NET10_0_OR_GREATER
        return JsonSerializerOptions.Strict;
#else
        return new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = false,
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
        };
#endif
    }
}
```

.NET 8 没有与 `.NET 10` strict preset 完全等价的内置组合；尤其不能仅靠选项获得同等的 nullable/required 构造参数运行时检查。多目标库应把这类差异写入契约测试，而不是宣称两个分支行为完全一致。

条件编译适合解决“API 是否存在”，不适合把整个业务流程复制成两份。若分支开始扩散，应建立 `IPlatformFeature` 适配器，分别在 `net10.0` 与 `net8.0` 文件中实现。

## 2. .NET 10 与 C# 14

### 2.1 C# 14 能力总览

官方入口：[C# 14 新增功能](https://learn.microsoft.com/zh-cn/dotnet/csharp/whats-new/csharp-14)。语言设计原文位于 [dotnet/csharplang 的 C# 14 proposals](https://github.com/dotnet/csharplang/tree/main/proposals/csharp-14.0)。编译器实现可查看与本文验证 SDK 10.0.102 对应的 [dotnet/dotnet VMR Roslyn 快照](https://github.com/dotnet/dotnet/tree/44525024595742ebe09023abe709df51de65009b/src/roslyn/src/Compilers/CSharp)。

| 特性 | 主要价值 | 使用判断 |
| --- | --- | --- |
| Extension members | 扩展属性、扩展方法、静态扩展成员和扩展运算符统一进入 `extension` 块。 | 适合 fluent API、小型 DSL 和高内聚的扩展集合。 |
| `field` backed properties | 在访问器中使用编译器生成的后备字段。 | 适合轻量验证、规范化和通知；复杂状态仍用显式字段。 |
| Null-conditional assignment | `target?.Property = value`、`target?[i] += value`。 | 可消除简单空检查；不要隐藏“对象必须存在”的业务不变量。 |
| Unbound generic `nameof` | `nameof(Dictionary<,>)`。 | 日志、诊断、生成器和元数据代码更自然。 |
| First-class Span conversions | 改善数组、`Span<T>`、`ReadOnlySpan<T>` 的转换、扩展接收方和泛型推断。 | 编写低分配 API 时更易用，但生命周期规则没有放宽。 |
| Lambda 参数修饰符简化 | `(text, out result) => ...` 不必重复参数类型。 | 带 `ref`、`in`、`out`、`scoped` 的委托更简洁。 |
| Partial constructors/events | 生成器可声明构造函数或事件，由用户代码实现。 | 适合 source generator 与手写代码协作。 |
| User-defined compound assignment | 可声明实例 `operator +=` 等原地操作。 | 主要面向数值、缓冲区和领域值对象作者；需保持运算语义直观。 |
| File-based app directives | 单文件应用可在文件头声明 SDK、包和项目属性。 | 脚本、演示、运维工具；大型应用仍使用项目文件。 |

### 2.2 Extension members

传统扩展方法只能模拟实例方法。C# 14 的 `extension` 块还能声明扩展属性以及作用于类型本身的静态扩展成员：

```csharp
Console.WriteLine(JobState.Completed.IsTerminal); // True

public enum JobState
{
    Pending,
    Running,
    Completed,
    Failed
}

public static class JobStateExtensions
{
    extension(JobState state)
    {
        public bool IsTerminal =>
            state is JobState.Completed or JobState.Failed;
    }
}
```

需要理解的边界：

- 扩展成员仍是静态分派，不会修改接收类型，也不能访问其私有成员。
- 实例成员优先于同名扩展成员；不要用扩展成员“覆盖”真实成员。
- 扩展是否可见仍由命名空间导入决定，公开库应避免过于通用的成员名。
- 旧式 `this` 扩展方法依然有效；没有必要机械迁移所有代码。
- Extension member 是源码层便利。设计公共二进制 API 时仍要考虑调用方重新编译和工具链版本。
- 扩展属性不能为目标对象增加真实存储，也不能进入传统表达式树；需要 IQueryable provider 翻译时应使用其明确支持的方法形态。

选择顺序通常是：若拥有接收类型，且行为是该类型稳定、内在的能力，优先真实实例成员；若操作有多个平等输入、需要注入策略/依赖，或可能执行 I/O，优先普通函数或服务；只有在不能修改接收类型、且从接收者出发确实更自然时，才选扩展成员。扩展属性应廉价、确定且无副作用，不应把枚举远程查询、网络访问或大量计算隐藏在看似普通的属性读取中。

上例对 enum 添加一个纯粹、常量成本的分类属性，价值比为一个可自由修改的 class 添加同样属性更明确。

完整示例见 [Net10Features/Program.cs](Examples/CSharpNetLts/Net10Features/Program.cs)。规范与源码入口：

- [Extension members 语言提案](https://github.com/dotnet/csharplang/blob/main/proposals/csharp-14.0/extensions.md)
- [扩展方法与扩展成员](https://learn.microsoft.com/zh-cn/dotnet/csharp/programming-guide/classes-and-structs/extension-methods)
- [Roslyn C# 编译器快照](https://github.com/dotnet/dotnet/tree/44525024595742ebe09023abe709df51de65009b/src/roslyn/src/Compilers/CSharp/Portable)

### 2.3 `field` 属性与空条件赋值

`field` 只在属性访问器语境中代表编译器生成的后备字段：

```csharp
public sealed class UserProfile
{
    public UserProfile(string displayName)
    {
        // 通过 setter，确保构造阶段也执行相同规范化逻辑。
        DisplayName = displayName;
    }

    public string DisplayName
    {
        get => field;
        set => field = string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException("Display name is required.", nameof(value))
            : value.Trim();
    }

    public DateTimeOffset? LastSeenAt { get; set; }
}

UserProfile? profile = FindProfile();
profile?.LastSeenAt = DateTimeOffset.UtcNow;
```

这里有两个容易忽略的细节：

1. 属性初始化器直接初始化后备字段，不保证调用自定义 setter。若构造输入必须执行验证，应像示例一样在构造函数中赋给属性。
2. 空条件赋值右侧只在接收方非空时求值。它适合“对象可选”的场景；若找不到对象本身就是错误，显式抛出异常更能表达不变量。

如果类型中本来就有名为 `field` 的成员，可用 `@field` 或 `this.field` 消除歧义。复杂访问器需要多个字段、锁或缓存时，显式后备字段通常更清楚。

官方资料：

- [`field` keyword](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/keywords/field)
- [Null-conditional assignment 提案](https://github.com/dotnet/csharplang/blob/main/proposals/csharp-14.0/null-conditional-assignment.md)
- [成员访问与空条件运算符](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/operators/member-access-operators)

### 2.4 `nameof`、lambda 修饰符与 Span 转换

```csharp
public delegate bool TryParse<T>(string text, out T result);

TryParse<int> parse =
    (text, out result) => int.TryParse(text, out result);

Console.WriteLine(nameof(Dictionary<,>)); // Dictionary
```

C# 14 允许简单 lambda 参数携带 `ref`、`in`、`out`、`ref readonly` 或 `scoped` 修饰符，而不强迫所有参数重复类型。`params` 参数仍要求显式类型。

First-class Span 并没有让 `Span<T>` 变成可装箱、可跨 `await` 或可存入普通类字段的类型。它主要改善以下编译期体验：

- 数组、可写 Span 与只读 Span 之间的组合转换。
- Span 作为扩展方法接收方。
- 与泛型推断和重载解析的组合。

```csharp
static int Sum(ReadOnlySpan<int> values)
{
    int total = 0;
    foreach (int value in values)
    {
        total += value;
    }
    return total;
}

int[] values = [1, 2, 3];
Console.WriteLine(Sum(values));
```

这是一个需要回归测试的重载解析变化：升级到 C# 14 后，原本绑定到 `IEnumerable<T>` 的数组调用可能改为绑定 `Span<T>` / `ReadOnlySpan<T>` 重载；表达式树、测试断言和同时提供数组/span 重载的库尤其容易出现歧义或行为变化。必要时显式调用 `Enumerable` 方法或 `.AsSpan()` 固定意图。

- 语言提案：[First-class Span types](https://github.com/dotnet/csharplang/blob/main/proposals/csharp-14.0/first-class-span-types.md)
- 兼容性说明：[C# 14 overload resolution with Span](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/core-libraries/10.0/csharp-overload-resolution)

Span 的生命周期和使用准则见本文第 5 章。

### 2.5 Partial constructors、events 与原地运算符

Partial member 让生成器提供“声明面”，业务项目提供“实现面”。定义与实现必须同时存在且签名匹配。

```csharp
// AuditSink.Definition.cs
public sealed partial class AuditSink
{
    public partial AuditSink(string name);
    public partial event EventHandler<string>? Written;
}
```

```csharp
// AuditSink.Implementation.cs
public sealed partial class AuditSink
{
    private readonly string _name;
    private EventHandler<string>? _written;

    public partial AuditSink(string name)
    {
        _name = name;
    }

    public partial event EventHandler<string>? Written
    {
        add => _written += value;
        remove => _written -= value;
    }
}
```

用户定义复合赋值运算符是实例操作：

```csharp
var counter = new Counter();
counter += 3;

public struct Counter
{
    public int Value { get; private set; }

    public void operator +=(int amount)
    {
        Value = checked(Value + amount);
    }
}
```

只有当“原地修改”符合类型直觉时才应使用它。运算符是一项语义和成本承诺：调用方通常预期它本地、确定、较廉价，不会隐式访问数据库、网络、文件系统或消息代理。需要 `async`、`CancellationToken`、重试或事务的行为应使用名称明确的方法。

若类型同时提供 `+` 与 `+=`，两者应有一致的数学/领域语义。C# 14 的实例复合赋值运算符还可原地修改引用对象；如果使用 class，必须明确其他别名也会观察到同一次修改。服务对象、实体仓储或具有远程副作用的类型不适合重载运算符。规范：[User-defined compound assignment](https://github.com/dotnet/csharplang/blob/main/proposals/csharp-14.0/user-defined-compound-assignment.md)。

### 2.6 .NET 10 BCL：LINQ、严格 JSON、异步 ZIP 与 WebSocket

#### LeftJoin 与 RightJoin

过去的左连接通常需要 `GroupJoin`、`SelectMany` 和 `DefaultIfEmpty`。`.NET 10` 提供直接表达语义的 `LeftJoin` 与 `RightJoin`：

```csharp
var rows = orders.LeftJoin(
    customers,
    order => order.CustomerId,
    customer => customer.Id,
    (order, customer) => new
    {
        order.Id,
        Customer = customer?.Name ?? "<missing>",
        order.Total
    });
```

这不仅让 LINQ to Objects 更清楚，EF Core 10 也能识别并翻译对应操作。不要把连接后的 `customer` 当作一定非空；外连接的缺失侧仍应显式处理。

- API：[Enumerable.LeftJoin](https://learn.microsoft.com/zh-cn/dotnet/api/system.linq.enumerable.leftjoin?view=net-10.0)、[Enumerable.RightJoin](https://learn.microsoft.com/zh-cn/dotnet/api/system.linq.enumerable.rightjoin?view=net-10.0)
- 源码：[LeftJoin.cs](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Linq/src/System/Linq/LeftJoin.cs)、[RightJoin.cs](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Linq/src/System/Linq/RightJoin.cs)

#### `IAsyncEnumerable<T>` 原生 LINQ

.NET 10 在平台中提供 `System.Linq.AsyncEnumerable`，异步流可直接组合 `Where`、`Select` 等运算：

```csharp
await foreach (int value in Counter()
    .Where(value => value % 2 == 0)
    .Select(value => value * 10))
{
    Console.WriteLine(value);
}

static async IAsyncEnumerable<int> Counter()
{
    for (int value = 0; value < 5; value++)
    {
        await Task.Yield();
        yield return value;
    }
}
```

项目若直接引用旧 `System.Linq.Async`，升级后可能出现同名扩展方法歧义。单目标 `net10.0` 应评估移除旧包；多目标项目则把包引用和 using 边界写清楚。

- [AsyncEnumerable API](https://learn.microsoft.com/zh-cn/dotnet/api/system.linq.asyncenumerable?view=net-10.0)
- [兼容性说明](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/core-libraries/10.0/asyncenumerable)
- [源码](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Linq.AsyncEnumerable/src/System/Linq/AsyncEnumerable.cs)

#### `JsonSerializerOptions.Strict`

默认 JSON 选项为了兼容性相对宽松。`.NET 10` 新增严格预设，组合了未知成员拒绝、重复属性拒绝、大小写敏感、可空标注与 required 构造参数检查：

```csharp
const string json = """
    { "name": "first", "name": "second" }
    """;

_ = JsonSerializer.Deserialize<Payload>(
    json,
    JsonSerializerOptions.Strict); // 抛出 JsonException

public sealed record Payload(string Name);
```

严格反序列化适合命令、配置、安全敏感 DTO 和服务边界。事件回放或长期兼容的外部载荷可能需要更宽松、版本化的契约，不能一刀切。

`.NET 10` 还允许 `JsonSerializer` 直接从 `PipeReader` 反序列化。自定义 `JsonConverter<T>` 必须正确处理 `Utf8JsonReader.HasValueSequence`，不能假定值总在单个连续 `ValueSpan` 中。

- 官方：[.NET 10 库新增功能](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-10/libraries)
- 源码：[JsonSerializerOptions.cs](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Text.Json/src/System/Text/Json/Serialization/JsonSerializerOptions.cs)

#### 异步 ZIP

`.NET 10` 为创建、打开、提取和更新 ZIP 增加异步 API。I/O 密集型服务器不必再用 `Task.Run` 包装同步压缩调用：

```csharp
await using var destination = new MemoryStream();

using (ZipArchive archive = await ZipArchive.CreateAsync(
           destination,
           ZipArchiveMode.Create,
           leaveOpen: true,
           entryNameEncoding: null,
           cancellationToken))
{
    ZipArchiveEntry entry = archive.CreateEntry("hello.txt");
    await using Stream content = await entry.OpenAsync(cancellationToken);
    await content.WriteAsync("hello"u8.ToArray(), cancellationToken);
}
```

源码：[ZipArchive.cs](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.IO.Compression/src/System/IO/Compression/ZipArchive.cs)。对于小型内存数据，同步 API 可能更简单；异步的收益主要来自真实流式 I/O 和取消传播。

#### `WebSocketStream`

`WebSocketStream` 把 WebSocket 消息读写适配成 `Stream`，便于复用现有文本、二进制和序列化 API。它不会消除协议层设计：消息边界、背压、心跳、最大消息大小、关闭握手和认证仍由应用负责。

- 官方：[WebSocketStream API](https://learn.microsoft.com/zh-cn/dotnet/api/system.net.websockets.websocketstream?view=net-10.0)
- 源码：[WebSocketStream.cs](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Net.WebSockets/src/System/Net/WebSockets/WebSocketStream.cs)

### 2.7 .NET 10 Runtime 与 SDK

Runtime 的 JIT、PGO、循环、内联、逃逸分析、栈分配和 Native AOT 改进通常不要求修改业务代码。正确的做法是：升级 runtime 后重新运行代表性基准和生产画像，不要因为发布说明说“更快”就删除应用层容量验证。

官方入口：

- [.NET 10 Runtime 新增功能](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-10/runtime)
- [.NET 10 SDK 新增功能](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-10/sdk)
- [dotnet/runtime v10.0.0](https://github.com/dotnet/runtime/tree/v10.0.0)

.NET 10 的 file-based app 适合短工具和文档示例：

```csharp
#:sdk Microsoft.NET.Sdk.Web

var app = WebApplication.Create(args);
app.MapGet("/", () => new { Message = "Hello" });
app.Run();
```

```powershell
dotnet run app.cs
```

文件还可使用 `#:package`、`#:property` 和 `#:project`。一旦应用需要多个源文件、复杂条件、测试资源或发布配置，就应迁移回普通项目文件。

### 2.8 ASP.NET Core 10

官方入口：[ASP.NET Core 10 新增功能](https://learn.microsoft.com/zh-cn/aspnet/core/release-notes/aspnetcore-10.0?view=aspnetcore-10.0)，稳定源码基线：[dotnet/aspnetcore v10.0.0](https://github.com/dotnet/aspnetcore/tree/v10.0.0)。

#### Minimal API 内置验证

```csharp
using System.ComponentModel.DataAnnotations;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddValidation();

var app = builder.Build();
app.MapPost("/products", (ProductInput input) => TypedResults.Created(
    $"/products/{input.Code}",
    input));
app.Run();

public sealed record ProductInput(
    [property: Required, StringLength(20)] string Code,
    [property: Range(0.01, 1_000_000)] decimal Price);
```

验证覆盖路由、查询、请求头和请求体参数，失败时返回 400。它适合传输层约束，不能代替领域规则、数据库唯一约束或授权检查。端点分布在多个程序集时，要核对验证源生成器的发现边界。

- 完整官方示例：[MinimalValidationSample](https://github.com/dotnet/aspnetcore/blob/v10.0.0/src/Http/samples/MinimalValidationSample/Program.cs)
- 实现：[ValidationEndpointFilterFactory.cs](https://github.com/dotnet/aspnetcore/blob/v10.0.0/src/Http/Routing/src/ValidationEndpointFilterFactory.cs)

#### Server-Sent Events

```csharp
app.MapGet("/events", (CancellationToken cancellationToken) =>
    TypedResults.ServerSentEvents(ReadEvents(cancellationToken)));

static async IAsyncEnumerable<string> ReadEvents(
    [EnumeratorCancellation] CancellationToken cancellationToken)
{
    for (int index = 0; ; index++)
    {
        cancellationToken.ThrowIfCancellationRequested();
        yield return $"event-{index}";
        await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
    }
}
```

客户端断开后必须停止生产数据；不要吞掉传入的 `CancellationToken`。若需要双向低延迟通信，SignalR 或 WebSocket 更合适。

- 源码：[ServerSentEventsResult.cs](https://github.com/dotnet/aspnetcore/blob/v10.0.0/src/Http/Http.Results/src/ServerSentEventsResult.cs)
- 官方示例：[MinimalServerSentEvents](https://github.com/dotnet/AspNetCore.Docs/blob/main/aspnetcore/fundamentals/minimal-apis/10.0-samples/MinimalServerSentEvents/Program.cs)

#### OpenAPI 3.1 与升级边界

ASP.NET Core 10 默认面向 OpenAPI 3.1 / JSON Schema 2020-12，并支持 YAML、XML 注释、文档服务和更细粒度 transformer。底层 `Microsoft.OpenApi` 2.x 有重大 API 变化，旧 transformer 需要迁移；`WithOpenApi` 已弃用。

```csharp
builder.Services.AddOpenApi(options =>
{
    options.OpenApiVersion =
        Microsoft.OpenApi.OpenApiSpecVersion.OpenApi3_1;
});

app.MapOpenApi("/openapi/{documentName}.yaml");
```

- [自定义 OpenAPI](https://learn.microsoft.com/zh-cn/aspnet/core/fundamentals/openapi/customize-openapi?view=aspnetcore-10.0)
- [OpenApiOptions 源码](https://github.com/dotnet/aspnetcore/blob/v10.0.0/src/OpenApi/src/Services/OpenApiOptions.cs)

#### 升级时要检查的行为变化

##### Cookie Authentication：API 不再默认跳转

对框架识别为 API 的端点，Cookie Authentication 在未认证时默认返回 `401`，已认证但无权时返回 `403`，而不是把 API 客户端重定向到登录/拒绝访问页。普通浏览器页面仍可保留跳转语义。这避免 fetch/移动客户端把 `302 + HTML` 误当成 API 结果。

升级测试应同时断言状态码、`Location` header 和响应媒体类型。若某个 API 确实需要旧式跳转，通过 Cookie events 或端点级约定明确配置，不要为了一个特例无意全局恢复。

- [Cookie Authentication API 行为变化](https://learn.microsoft.com/zh-cn/aspnet/core/breaking-changes/10/cookie-authentication-api-endpoints?view=aspnetcore-10.0)

##### 已处理异常的诊断默认抑制

当 `IExceptionHandler.TryHandleAsync` 返回 `true` 时，.NET 10 的异常中间件默认抑制部分框架错误日志、EventSource 事件和 HTTP metric 错误标记。应用在自定义 handler 中主动写入的日志不会自动消失。因此升级后监控平台中的异常数下降，可能是诊断语义变化，不代表异常不再发生。

需要恢复旧诊断行为时：

```csharp
app.UseExceptionHandler(new ExceptionHandlerOptions
{
    SuppressDiagnosticsCallback = _ => false
});
```

如果 handler 已记录同一异常，恢复 middleware 诊断可能造成双重日志或计数。迁移回归应同时验证响应、日志、trace 和 metric，而不是只看 500 响应。

- [Exception handler diagnostics suppression](https://learn.microsoft.com/zh-cn/aspnet/core/breaking-changes/10/exception-handler-diagnostics-suppressed?view=aspnetcore-10.0)

##### OpenAPI 3.1 / OpenAPI.NET 2.x

除了核对生成的 OpenAPI 3.1 / JSON Schema 2020-12 契约，还要把旧 `.WithOpenApi(...)` 定制迁移到 operation/document transformer，并修改针对 OpenAPI.NET 1.x 具体类型的代码。对生成的 JSON/YAML 建立 snapshot/契约测试，CI 中还要实际运行所用的 client generator；文档能生成不代表下游工具已支持 3.1。

- [`WithOpenApi` 弃用](https://learn.microsoft.com/zh-cn/aspnet/core/breaking-changes/10/withopenapi-deprecated?view=aspnetcore-10.0)

##### JSON converter 与 `PipeReader`

MVC、Minimal API 与 `ReadFromJsonAsync` 使用 `PipeReader` JSON 路径后，`Utf8JsonReader` 的当前值可能跨多个 segment。只读 `ValueSpan` 的旧 converter 在小型单元测试中可能一直通过，却在真实分段输入下截断数据。测试要主动构造足够大或分段的输入，覆盖 `HasValueSequence == true`，长期修复方式见 [8.4 自定义 converter 的高级边界](#84-自定义-converter-的高级边界)。

第三方 converter 暂时无法修复时，可使用临时兼容开关：

```csharp
AppContext.SetSwitch(
    "Microsoft.AspNetCore.UseStreamBasedJsonParsing",
    true);
```

该开关只是迁移缓冲，不应取代升级/修复 converter。

##### 旧宿主 API

`IWebHost`、`WebHostBuilder` 等旧宿主 API 进入弃用路径。新代码应使用 Generic Host 与 `WebApplicationBuilder`，升级时同时回归启动顺序、配置源、日志、服务注册与优雅停止，不要只机械替换类名。

迁移入口：[ASP.NET Core 9 到 10](https://learn.microsoft.com/zh-cn/aspnet/core/migration/90-to-100?view=aspnetcore-10.0) 与 [ASP.NET Core 10 breaking changes](https://learn.microsoft.com/zh-cn/aspnet/core/breaking-changes/10/overview?view=aspnetcore-10.0)。

### 2.9 EF Core 10

官方入口：[EF Core 10 新增功能](https://learn.microsoft.com/zh-cn/ef/core/what-is-new/ef-core-10.0/whatsnew)，源码：[dotnet/efcore v10.0.0](https://github.com/dotnet/efcore/tree/v10.0.0)。高价值变化包括：

- 复杂类型支持 table splitting、JSON 映射和 `struct`。
- 翻译 .NET 10 的 `LeftJoin` 与 `RightJoin`。
- Named query filters 可单独禁用租户或软删除过滤器。
- 关系型 JSON 列支持 `ExecuteUpdate`。
- SQL Server/Azure SQL 支持原生 JSON 类型和向量搜索能力。
- 原始 SQL 字符串拼接警告、内联常量日志脱敏等安全改进。

Named query filters 示例：

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<Order>()
        .HasQueryFilter("TenantFilter", order => order.TenantId == _tenantId)
        .HasQueryFilter("SoftDeleteFilter", order => !order.IsDeleted);
}

IReadOnlyList<Order> includingDeleted = await context.Orders
    .IgnoreQueryFilters(["SoftDeleteFilter"])
    .ToListAsync(cancellationToken);
```

全局过滤器不是安全边界。租户 ID 必须来自可信上下文，管理端绕过过滤器要单独授权，并用集成测试验证生成 SQL。

### 2.10 .NET 10 采用清单

- 新项目以 `net10.0`、C# 14 和最新受支持 `10.0.x` patch 为基线。
- 先跑测试、基准和生产画像，再依赖 JIT/GC 性能改进。
- 边界 DTO 评估 `JsonSerializerOptions.Strict`，长期事件契约单独版本化。
- 自定义 `JsonConverter<T>` 检查 `HasValueSequence`。
- ASP.NET Core 升级时核对 Cookie 401/403、异常诊断抑制和 OpenAPI.NET 2.x。
- EF Core 升级必须审阅迁移脚本、生成 SQL、查询过滤器与 provider 兼容性。
- 公共库若仍支持 .NET 8，应多目标并把 .NET 10 API 封装在适配器内。

## 3. .NET 8 与 C# 12

### 3.1 C# 12 能力总览

官方入口：[C# 12 新增功能](https://learn.microsoft.com/zh-cn/dotnet/csharp/whats-new/csharp-12)，语言提案：[C# 12 proposals 的 .NET 8 GA 快照](https://github.com/dotnet/csharplang/tree/52763e3b581d1bc92ac90309c033a9f8a045c1e2/proposals/csharp-12.0)，对应 SDK 8.0.100 编译器源码快照：[Roslyn commit f43cd10](https://github.com/dotnet/roslyn/tree/f43cd10b737b6343956dee421cff8c50b602c788/src/Compilers/CSharp)。

| 特性 | 主要价值 | 关键边界 |
| --- | --- | --- |
| Primary constructors | 普通 class/struct 也能把构造参数放在类型声明上。 | 参数不是属性；捕获方式影响对象布局。 |
| Collection expressions | `[1, 2, 3]` 与 spread `[.. source]`。 | 必须有目标类型；不要假设底层一定是数组。 |
| `ref readonly` parameters | 表达“按只读引用传递”。 | 不写修饰符或传临时值在 C# 12 通常只是警告；主要面向底层 API。 |
| Default lambda parameters | lambda 可声明默认参数。 | 委托静态类型必须保留相应签名，动态调用仍要谨慎。 |
| Alias any type | 可为元组、数组、指针等类型起别名。 | 只是编译期别名，不创建新类型和额外类型安全。 |
| Inline arrays | 固定长度 struct 缓冲区，减少 unsafe fixed buffer 的需要。 | 长度编译期固定，适合底层库，不宜作为普通集合替代品。 |
| `ExperimentalAttribute` | 编译器对实验 API 发出诊断。 | 实验 API 可破坏性变化，公共稳定 API 不应依赖。 |
| Interceptors preview | 编译期替换指定调用点。 | C# 12 中是预览能力，本文不建议生产代码直接使用。 |

### 3.2 Primary constructors：参数不是属性

```csharp
public sealed class PriceCalculator(decimal taxRate)
{
    private readonly decimal _taxRate = taxRate is >= 0m and <= 1m
        ? taxRate
        : throw new ArgumentOutOfRangeException(nameof(taxRate));

    public decimal Gross(decimal net) => net * (1m + _taxRate);
}
```

普通 class 的 primary constructor 参数只在类型体中可见，不会像 `record` 参数那样自动生成公开属性。编译器只有在实例成员需要持续使用参数时才捕获存储；同时把参数复制到字段又直接在成员中使用参数，可能产生两份状态：

```csharp
// 不推荐：taxRate 既被复制到字段，又可能被其他成员直接捕获。
public sealed class Calculator(decimal taxRate)
{
    private decimal _taxRate = taxRate;
    public decimal Current => taxRate;
}
```

构造参数很多、验证复杂、继承关系明显时，普通构造函数往往更清楚。Primary constructor 的优势是减少样板，不是隐藏依赖。

- [Primary constructors 教程](https://learn.microsoft.com/zh-cn/dotnet/csharp/whats-new/tutorials/primary-constructors)
- [语言提案](https://github.com/dotnet/csharplang/blob/52763e3b581d1bc92ac90309c033a9f8a045c1e2/proposals/csharp-12.0/primary-constructors.md)

### 3.3 Collection expressions 与 spread

```csharp
string[] core = ["C#", ".NET"];
List<string> stack = [.. core, "ASP.NET Core", "EF Core"];
ReadOnlySpan<byte> magic = [0x50, 0x4B, 0x03, 0x04];
```

Collection expression 是目标类型驱动的。单独写 `var values = [1, 2, 3];` 没有足够目标类型，通常不能编译；应写出数组、Span、List 或 API 参数类型。

Spread 会枚举源序列。若源是数据库查询、网络流或带副作用迭代器，`[.. source]` 仍然会执行它；简短语法不会消除 I/O、延迟执行或分配成本。

```csharp
static int[] AppendChecksum(IEnumerable<int> source)
{
    int[] materialized = source.ToArray();
    int checksum = materialized.Sum();
    return [.. materialized, checksum];
}
```

这里先显式物化，避免为了求和和 spread 对单次序列重复枚举。

- [Collection expressions](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/operators/collection-expressions)
- [语言提案](https://github.com/dotnet/csharplang/blob/52763e3b581d1bc92ac90309c033a9f8a045c1e2/proposals/csharp-12.0/collection-expressions.md)

### 3.4 默认 lambda、任意类型别名与 `ref readonly`

```csharp
using Point = (int X, int Y);

Point point = (3, 4);
var greet = (string name = "world") => $"Hello, {name}!";
var sum = (params int[] values) => values.Sum();

Console.WriteLine(greet());
Console.WriteLine(sum(1, 2, 3));
Console.WriteLine(point.X * point.X + point.Y * point.Y);
```

别名 `Point` 仍然就是元组 `(int X, int Y)`，不能阻止把另一个相同形状的元组传入。需要领域类型安全时，应声明 `readonly record struct Point(int X, int Y)`。

C# 12 这里的 `params` 仍只支持传统数组形式，本文不展开后续非 LTS 基线的广义 params collections。带默认参数或 `params` 的 lambda 使用 `var` 时，编译器可能合成匿名 delegate 类型；不要假定它一定是 `Func<>` 或 `Action<>`。

`ref readonly` 参数适合向调用方表明“应提供稳定存储位置，被调方法不修改值”的底层 API：

```csharp
public readonly record struct LargeVector(double X, double Y, double Z, double W);

static double LengthSquared(ref readonly LargeVector vector) =>
    vector.X * vector.X + vector.Y * vector.Y +
    vector.Z * vector.Z + vector.W * vector.W;

LargeVector value = new(1, 2, 3, 4);
Console.WriteLine(LengthSquared(in value));     // 推荐：明确表达只读引用
// LengthSquared(value);                        // C# 12 警告，不是语法错误
```

普通小型 struct 按值传递通常已经足够快。不要为了“看起来高性能”把所有参数改成 `in` 或 `ref readonly`；应以基准和调用约束为依据。若需要把上述警告变成强约束，项目应启用 `TreatWarningsAsErrors`。

### 3.5 Inline arrays

```csharp
using System.Runtime.CompilerServices;

[InlineArray(8)]
public struct IntBuffer8
{
    private int _element0;
}

var buffer = new IntBuffer8();
for (int index = 0; index < 8; index++)
{
    buffer[index] = index * index;
}

Span<int> writable = buffer;
ReadOnlySpan<int> readable = buffer;
```

Inline array 的长度属于类型定义，适合协议头、密码学状态、SIMD 辅助结构和 runtime/library 内部实现。目标必须是 struct，只能有一个实例字段，长度必须大于 0；常量越界索引会在编译期报错，运行时索引仍走 Span 边界检查。它不是可增长集合，也不宜把大型 inline array 暴露为长期稳定的公共 ABI。

- [Inline arrays 文档](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/builtin-types/struct#inline-arrays)
- [语言提案](https://github.com/dotnet/csharplang/blob/52763e3b581d1bc92ac90309c033a9f8a045c1e2/proposals/csharp-12.0/inline-arrays.md)

完整 C# 12 示例见 [Net8Features/Program.cs](Examples/CSharpNetLts/Net8Features/Program.cs)。

### 3.6 .NET 8 BCL：Frozen collections、TimeProvider、SearchValues 与 Random

#### Frozen collections

`FrozenDictionary<TKey,TValue>` 与 `FrozenSet<T>` 为“一次构建、长期只读、频繁查询”优化：

```csharp
FrozenDictionary<string, int> statusCodes = new Dictionary<string, int>
{
    ["ok"] = 200,
    ["not-found"] = 404
}.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);
```

冻结有一次性构建成本。配置每次请求都变化、元素很少或只查一两次时，普通 Dictionary 更合适。Frozen 不等于 Immutable：Frozen 强调构建后读取性能；Immutable collections 强调通过结构共享创建新版本。

- [FrozenDictionary API](https://learn.microsoft.com/zh-cn/dotnet/api/system.collections.frozen.frozendictionary-2?view=net-8.0)
- [源码](https://github.com/dotnet/runtime/tree/v8.0.0/src/libraries/System.Collections.Immutable/src/System/Collections/Frozen)

#### TimeProvider

把“当前时间”和“定时器创建”抽象成依赖，可让过期、重试、缓存和调度逻辑确定性测试：

```csharp
public sealed class TokenService(TimeProvider timeProvider)
{
    public bool IsExpired(AccessToken token) =>
        timeProvider.GetUtcNow() >= token.ExpiresAt;
}

public sealed class ManualTimeProvider(DateTimeOffset initial) : TimeProvider
{
    private DateTimeOffset _utcNow = initial;
    public override DateTimeOffset GetUtcNow() => _utcNow;
    public void Advance(TimeSpan duration) => _utcNow += duration;
}
```

生产代码注入 `TimeProvider.System`。不要在领域逻辑深处直接调用 `DateTime.UtcNow`，否则测试只能等待真实时间或依赖脆弱的时间窗口。上面的简化实现只控制 `GetUtcNow()`；要确定性测试 `Task.Delay` 和计时器，使用 `Microsoft.Extensions.TimeProvider.Testing` 包中的 `FakeTimeProvider`。

- [TimeProvider 概述](https://learn.microsoft.com/zh-cn/dotnet/standard/datetime/timeprovider-overview)
- [源码](https://github.com/dotnet/runtime/blob/v8.0.0/src/libraries/Common/src/System/TimeProvider.cs)
- [FakeTimeProvider 源码](https://github.com/dotnet/extensions/blob/b31f7e964180e45b9b0855f24b91de024e0a438f/src/Libraries/Microsoft.Extensions.TimeProvider.Testing/FakeTimeProvider.cs)

#### SearchValues

重复调用 `IndexOfAny`、`ContainsAny` 等扫描 API 时，`SearchValues<T>` 会预计算并选择适合平台的搜索策略：

```csharp
SearchValues<char> separators = SearchValues.Create([',', ';', '|']);
ReadOnlySpan<char> input = "alpha;beta";
int separatorIndex = input.IndexOfAny(separators);
```

应复用 `SearchValues<T>`，不要在热循环中每次重新创建。.NET 8 的工厂能力面向 `byte` 和 `char`；不要把后续版本对更多类型的扩展倒写回 .NET 8。

- [SearchValues API](https://learn.microsoft.com/zh-cn/dotnet/api/system.buffers.searchvalues?view=net-8.0)
- [源码](https://github.com/dotnet/runtime/tree/v8.0.0/src/libraries/System.Private.CoreLib/src/System/SearchValues)

#### Random.GetItems 与 Shuffle

```csharp
string[] choices = ["red", "green", "blue"];
string[] picks = Random.Shared.GetItems(choices, 5);
Random.Shared.Shuffle(picks);
```

这些 API 用于普通随机抽样和洗牌，不适合密钥、令牌、验证码或其他安全随机场景；安全场景使用 `RandomNumberGenerator`。

- [Random 源码](https://github.com/dotnet/runtime/blob/v8.0.0/src/libraries/System.Private.CoreLib/src/System/Random.cs)
- [安全随机数](https://learn.microsoft.com/zh-cn/dotnet/api/system.security.cryptography.randomnumbergenerator)

### 3.7 .NET 8 System.Text.Json

.NET 8 的重要方向是更完整的源生成、Native AOT 兼容、接口层次结构处理以及已有对象的 Populate：

```csharp
public sealed class Customer
{
    [JsonObjectCreationHandling(JsonObjectCreationHandling.Populate)]
    public List<string> Tags { get; } = ["existing"];
}

Customer customer = JsonSerializer.Deserialize<Customer>(
    """{ "tags": ["new", "vip"] }""",
    new JsonSerializerOptions(JsonSerializerDefaults.Web))
    ?? throw new JsonException("Customer payload cannot be null.");

// existing, new, vip
```

Populate 会修改已有集合或对象。它适合只读集合属性和增量填充，但需要明确“合并”而不是“替换”的契约，尤其要防止默认值与输入重复。.NET 8 中它不支持带参数构造函数的目标类型；struct 属性会先修改副本再写回，因此必须有 setter。Native AOT 路径仍应使用 `JsonSerializerContext` 源生成，不要依赖未受控反射 fallback。

- [.NET 8 Runtime 与核心库新增功能](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-8/runtime)
- [System.Text.Json 源码](https://github.com/dotnet/runtime/tree/v8.0.0/src/libraries/System.Text.Json/src/System/Text/Json)

### 3.8 ASP.NET Core 8

官方入口：[ASP.NET Core 8 新增功能](https://learn.microsoft.com/zh-cn/aspnet/core/release-notes/aspnetcore-8.0?view=aspnetcore-8.0&preserve-view=true)，源码：[dotnet/aspnetcore v8.0.0](https://github.com/dotnet/aspnetcore/tree/v8.0.0)。

#### Keyed DI

```csharp
builder.Services.AddKeyedSingleton<ITimeFormatter, IsoTimeFormatter>("iso");

app.MapGet(
    "/time",
    ([FromKeyedServices("iso")] ITimeFormatter formatter) =>
        new { UtcNow = formatter.Format(DateTimeOffset.UtcNow) });
```

Keyed services 适合少量、稳定、同接口多实现的策略。若 key 来自任意用户输入或数量持续增长，通常应使用显式工厂、字典或策略注册表，避免把 DI 容器当运行时数据库。

- [Keyed services 文档](https://learn.microsoft.com/zh-cn/dotnet/core/extensions/dependency-injection#keyed-services)
- [DI 源码](https://github.com/dotnet/runtime/tree/v8.0.0/src/libraries/Microsoft.Extensions.DependencyInjection)

#### `IExceptionHandler` 与 Problem Details

```csharp
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

var app = builder.Build();
app.UseExceptionHandler();
```

异常处理器应把“意外异常”映射成稳定错误响应并记录诊断，不应把所有领域失败都先抛异常再捕获。预期失败可用 Result、验证错误或 Typed Results 表达。

`AddExceptionHandler<T>` 把 handler 注册为 singleton，不能直接注入 scoped `DbContext`；多个 handler 按注册顺序调用，第一个返回 `true` 的 handler 结束链路。.NET 8 中已处理异常仍会产生相关诊断；`SuppressDiagnosticsCallback` 是 .NET 10 行为，不能倒写到本节。

完整可运行代码见 [AdvancedWebApi/Program.cs](Examples/CSharpNetLts/AdvancedWebApi/Program.cs)。

- [ASP.NET Core 错误处理](https://learn.microsoft.com/zh-cn/aspnet/core/fundamentals/error-handling?view=aspnetcore-8.0&preserve-view=true)
- [Diagnostics 源码](https://github.com/dotnet/aspnetcore/tree/v8.0.0/src/Middleware/Diagnostics)

#### Native AOT 与 Request Delegate Generator

```powershell
dotnet new webapiaot -n AotApi -f net8.0
dotnet publish AotApi -c Release -r win-x64
```

Native AOT 可以降低启动时间和内存，但限制运行时反射、动态代码生成、部分序列化模式和某些第三方库。不要先把现有大型 MVC 应用切成 AOT 再逐个修警告；应先用兼容模板建立最小垂直切片，验证依赖链。

.NET 8 的主支持路线是 Minimal APIs、gRPC 和 Worker；传统 MVC controller 应用不会因为打开 `PublishAot` 就自动变得 AOT-compatible。Minimal API 的请求/响应 DTO 应全部注册到 `JsonSerializerContext`，并把 trim/AOT analyzer 警告当作真实兼容问题。EF Core 8 也不应被描述为已完整支持 Native AOT 的 ORM。

- [ASP.NET Core Native AOT](https://learn.microsoft.com/zh-cn/aspnet/core/fundamentals/native-aot?view=aspnetcore-8.0&preserve-view=true)
- [.NET Native AOT 部署](https://learn.microsoft.com/zh-cn/dotnet/core/deploying/native-aot/)

### 3.9 EF Core 8

官方入口：[EF Core 8 新增功能](https://learn.microsoft.com/zh-cn/ef/core/what-is-new/ef-core-8.0/whatsnew)，源码：[dotnet/efcore v8.0.0](https://github.com/dotnet/efcore/tree/v8.0.0)。核心能力：

- Complex types 表达无独立身份的值对象。
- Primitive collections 映射基本类型集合。
- JSON 列查询与更新增强，SQLite 也获得 JSON 列支持。
- 未映射类型的 raw SQL 查询。
- 更好的 `ExecuteUpdate` / `ExecuteDelete`。
- SQL Server 原生支持 `DateOnly` / `TimeOnly`。

复杂类型示例：

```csharp
[ComplexType]
public sealed record Address(string Line1, string City, string Country);

public sealed class Customer
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public required Address Address { get; set; }
}
```

Complex type 没有独立 key 和生命周期，适合值对象。若对象需要独立查询、关系、并发控制或单独生命周期，应建模为 entity，而不是为了少一张表强行使用 complex type。EF Core 8 不会按 convention 发现 complex type，必须用 attribute 或 Fluent API 配置；complex property 不能为 null，不支持 complex type collection，也不能映射到 JSON 列。共享可变 class 实例容易让多个 owner 一起被更新，因此优先使用 immutable record/struct。

Primitive collections 是 provider-dependent 映射：SQL Server 通常使用 JSON 文本，PostgreSQL 可能使用原生数组。它不等于规范化关联表；若需要元素级外键、索引、频繁单元素更新或复杂关联查询，应建模为子实体。

#### SQL Server `Contains` / `OPENJSON` 升级风险

EF Core 8 会把许多“参数集合 `Contains`”查询翻译为 `OPENJSON(@values)`，以减少因不同常量列表产生的 SQL 与查询计划缓存污染。这要求 SQL Server 2016+ 且 database compatibility level 至少为 130；少数数据分布还可能产生执行计划回退。升级时必须检查实际 SQL 与执行计划。无法升级数据库时，EF8 可用全局兼容开关：

```csharp
optionsBuilder.UseSqlServer(
    connectionString,
    sql => sql.UseCompatibilityLevel(120));
```

该开关也可能禁用其他新 SQL 翻译，只应在兼容性或基准数据证明有必要时使用；不要套用后续非 LTS 基线中才出现的查询翻译开关。

#### 未映射类型 raw SQL

```csharp
DateOnly start = new(2025, 1, 1);

IReadOnlyList<BlogSummary> rows = await context.Database
    .SqlQuery<BlogSummary>(
        $"SELECT Id, Title, PublishedOn FROM Posts WHERE PublishedOn >= {start}")
    .ToListAsync();

public sealed record BlogSummary(
    int Id,
    string Title,
    DateOnly PublishedOn);
```

`SqlQuery<T>` 会参数化 interpolated values，但表名、列名等 identifier 不能参数化，必须从白名单选择。不要把用户输入拼接进 `SqlQueryRaw<T>`。未映射 DTO 不进入 EF model，也不会作为实体被 change tracker 跟踪。

- [EF Core 8 breaking changes](https://learn.microsoft.com/zh-cn/ef/core/what-is-new/ef-core-8.0/breaking-changes)
- [`Contains` 兼容性变化](https://learn.microsoft.com/zh-cn/ef/core/what-is-new/ef-core-8.0/breaking-changes#sqlserver-contains-compatibility)
- [Raw SQL 查询](https://learn.microsoft.com/zh-cn/ef/core/querying/sql-queries)

### 3.10 .NET 8 采用清单

- 只把 .NET 8 当作仍在维护的既有 LTS 基线，不再作为长期新项目默认选择。
- 对外公共库可暂时多目标 `net10.0;net8.0`，应用项目优先迁移到 .NET 10。
- 使用 primary constructor 时检查参数是否被重复捕获或误认为属性。
- Collection expressions 保持目标类型明确，审查 spread 的枚举与分配成本。
- Frozen collections 只用于构建后高频读取的数据。
- 时间相关业务注入 `TimeProvider`。
- ASP.NET Core 统一 Problem Details、异常处理和 Options 启动验证。
- Native AOT 从最小切片验证兼容性，不忽略 trim/AOT 警告。
- EF Core 8 升级同样需要 provider、迁移和 SQL 集成测试。

## 4. 类型系统、可空性与泛型

### 4.1 Nullable reference types 是静态契约

启用：

```xml
<Nullable>enable</Nullable>
```

`string` 与 `string?` 的差异主要由编译器流分析执行，CLR 并不会自动阻止反射、旧程序集、JSON 或数据库把 null 放入 `string`。因此边界输入仍需运行时验证。

```csharp
public static bool TryNormalize(
    string? input,
    [NotNullWhen(true)] out string? normalized)
{
    normalized = input?.Trim();
    return !string.IsNullOrEmpty(normalized);
}

if (TryNormalize(raw, out string? text))
{
    Console.WriteLine(text.Length); // 编译器知道 text 非 null
}
```

常用流分析特性：

| 特性 | 用途 |
| --- | --- |
| `[NotNullWhen(true)]` | 返回指定布尔值时，参数/输出不为 null。 |
| `[MaybeNull]` | 返回类型表面非空，但某些路径可能为 null。 |
| `[NotNull]` | 方法返回后，参数保证非空。 |
| `[MemberNotNull]` | 方法返回后，指定成员已初始化。 |
| `[DoesNotReturn]` | 方法不会正常返回，帮助流分析收窄。 |

不要用 `!` 消音来替代契约：

```csharp
// 危险：只压制编译器，不改变运行时值。
Customer customer = repository.Find(id)!;
```

null-forgiving 运算符 `!` 只是向编译器声明“此处不会为 null”，不会插入任何运行时检查。只有当不变量已由相邻代码或框架生命周期强制建立、而编译器无法表达该事实时，才考虑使用 `!`。可接受的不变量来源包括构造函数验证、`?? throw`、启动期 Options 验证，或拥有正确 nullable flow attribute 的 API。若无法用一句话说明“谁建立了不变量，失败时在哪里终止”，就应保留可空类型并显式处理。

```csharp
string baseUrl = configuration["Catalog:BaseUrl"]
    ?? throw new InvalidOperationException(
        "Configuration value 'Catalog:BaseUrl' is required.");

Uri catalogUri = new(baseUrl, UriKind.Absolute);
```

应根据语义选择 `Customer?`、`TryGet`、Result 或明确异常，而不是用 `!` 隐藏未证明的假设。

- [Nullable reference types](https://learn.microsoft.com/zh-cn/dotnet/csharp/nullable-references)
- [可空静态分析特性](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/attributes/nullable-analysis)

### 4.2 `required`、`init` 与构造不变量

```csharp
public sealed class CreateOrderCommand
{
    public required string CustomerId { get; init; }
    public required IReadOnlyList<OrderLine> Lines { get; init; }
}
```

`required` 要求 C# 调用方在对象初始化阶段赋值，但反射、反序列化器和其他语言不一定执行相同检查；它也不检查空字符串、集合非空等业务规则。把它视为构造 API 契约，而不是完整验证框架。

对于必须始终有效的领域对象，构造函数或静态工厂更可靠：

```csharp
public sealed record Money
{
    private Money(decimal amount, string currency) =>
        (Amount, Currency) = (amount, currency);

    public decimal Amount { get; }
    public string Currency { get; }

    public static Money Create(decimal amount, string currency)
    {
        if (string.IsNullOrWhiteSpace(currency))
        {
            throw new ArgumentException("Currency is required.", nameof(currency));
        }

        return new Money(amount, currency.ToUpperInvariant());
    }
}
```

### 4.3 泛型约束要表达算法需求

```csharp
public static T MaxOrThrow<T>(IEnumerable<T> source)
    where T : IComparable<T>
{
    using IEnumerator<T> iterator = source.GetEnumerator();
    if (!iterator.MoveNext())
    {
        throw new InvalidOperationException("Sequence is empty.");
    }

    T best = iterator.Current;
    while (iterator.MoveNext())
    {
        if (iterator.Current.CompareTo(best) > 0)
        {
            best = iterator.Current;
        }
    }

    return best;
}
```

约束的价值不只是“让代码编译”，还包括：

- 为调用方声明类型必须提供的语义。
- 避免反射或 dynamic 的运行时失败。
- 让 JIT 对值类型泛型进行专门化。
- 让静态抽象接口成员表达运算能力。

常用约束顺序：基类/特殊约束、接口约束、`new()`。不要为了复用一个很小的函数引入五六个泛型参数；可读性和诊断质量同样重要。

### 4.4 Static abstract interface members 与泛型数学

该能力早于本文两个 LTS，但在 .NET 8 和 .NET 10 都是成熟的高级用法：

```csharp
using System.Numerics;

public static T Sum<T>(ReadOnlySpan<T> values)
    where T : INumber<T>
{
    T result = T.Zero;
    foreach (T value in values)
    {
        result += value;
    }
    return result;
}
```

与 `dynamic` 相比，泛型数学在编译期验证操作存在，通常也更易被 JIT 优化。代价是约束和错误信息更复杂；若算法只支持 `decimal`，直接写 `decimal` 通常比过度泛化更好。

- [Generic math](https://learn.microsoft.com/zh-cn/dotnet/standard/generics/math)
- [INumber<TSelf> API](https://learn.microsoft.com/zh-cn/dotnet/api/system.numerics.inumber-1)

### 4.5 协变、逆变与不变

```csharp
IEnumerable<string> strings = ["a", "b"];
IEnumerable<object> objects = strings; // out T：协变

Action<object> printObject = Console.WriteLine;
Action<string> printString = printObject; // in T：逆变
```

- 只生产 `T` 的接口适合 `out T`。
- 只消费 `T` 的接口适合 `in T`。
- 同时读写 `T` 的可变集合通常必须不变。

数组协变是 CLR 历史行为，会把部分类型错误推迟到运行时：

```csharp
object[] array = new string[1];
array[0] = new object(); // ArrayTypeMismatchException
```

公共 API 优先使用正确变体的泛型接口，不要依赖数组协变。

### 4.6 Records、模式匹配与封闭结果

Record 适合值语义消息、DTO 和不可变快照。用嵌套 sealed records 可以近似表达封闭结果集合：

```csharp
public abstract record OrderResult
{
    private OrderResult() { }

    public sealed record Accepted(Guid OrderId) : OrderResult;
    public sealed record Rejected(string Reason) : OrderResult;
}

string message = result switch
{
    OrderResult.Accepted(var id) => $"Accepted: {id}",
    OrderResult.Rejected(var reason) => $"Rejected: {reason}",
    _ => throw new UnreachableException()
};
```

Record 不会自动让内部可变集合变成不可变，浅拷贝的 `with` 也会共享引用成员：

```csharp
public sealed record Cart(List<string> Items);

Cart first = new(["A"]);
Cart second = first with { };
second.Items.Add("B"); // first.Items 也看到 B
```

需要深不可变时，使用 `ImmutableArray<T>`、只读值对象或显式复制策略。

## 5. 值、引用、Span 与内存

### 5.1 值类型不等于“永远在栈上”

值类型可作为局部变量、对象字段、数组元素、泛型实例或被装箱。它位于哪里取决于拥有它的存储，而不是只取决于 `struct` 关键字。相反，JIT 也可能通过逃逸分析把某些引用对象优化掉。

关注语义而不是口号：

- struct 复制的是整个值。
- class 复制的是对象引用。
- 大型可变 struct 容易产生隐式复制和行为困惑。
- 实现接口或转换为 `object` 可能装箱。
- `readonly struct` 能减少防御性复制并表达不可变意图。

### 5.2 `ref`、`in`、`out` 与 `scoped`

| 修饰符 | 调用目的 | 能否写入目标 | 典型用途 |
| --- | --- | --- | --- |
| `ref` | 按引用读写 | 是 | 原地修改、底层算法。 |
| `out` | 方法负责赋值 | 是，且返回前必须赋值 | Try 模式、多返回值兼容 API。 |
| `in` | 只读引用，可接受值表达式 | 否 | 避免复制较大只读 struct。 |
| `ref readonly` | 只读引用，强调稳定存储位置 | 否 | interop、低层库 API。 |
| `scoped` | 引用不能逃逸当前安全范围 | 取决于组合修饰符 | Span/ref 安全 API。 |

不要返回指向局部变量或 `stackalloc` 内存的引用。编译器的 ref safety 规则会阻止大多数逃逸，但 unsafe 和错误 interop 仍可能破坏安全。

### 5.3 `Span<T>`、`ReadOnlySpan<T>` 与 `Memory<T>`

| 类型 | 可否放到堆对象字段 | 可否跨 `await` | 适用场景 |
| --- | --- | --- | --- |
| `Span<T>` | 否 | 否 | 同步、短生命周期、可写切片。 |
| `ReadOnlySpan<T>` | 否 | 否 | 同步、短生命周期、只读解析。 |
| `Memory<T>` | 是 | 是 | 异步 I/O、跨方法保存的可写内存。 |
| `ReadOnlyMemory<T>` | 是 | 是 | 异步 I/O、跨方法保存的只读内存。 |

零分配 CSV 对解析示例：

```csharp
public static bool TryParsePair(
    ReadOnlySpan<char> input,
    out (int Left, int Right) pair)
{
    int separator = input.IndexOf(',');
    if (separator < 0
        || !int.TryParse(input[..separator], out int left)
        || !int.TryParse(input[(separator + 1)..], out int right))
    {
        pair = default;
        return false;
    }

    pair = (left, right);
    return true;
}
```

Span 避免了 `Substring`，但是否值得取决于热路径。业务编排代码优先可读性；协议解析、序列化、路由和高吞吐文本处理才更可能受益。

- [Memory 与 Span 使用准则](https://learn.microsoft.com/zh-cn/dotnet/standard/memory-and-spans/memory-t-usage-guidelines)
- [Span<T> API](https://learn.microsoft.com/zh-cn/dotnet/api/system.span-1)

### 5.4 `stackalloc` 与池化

```csharp
static int Encode(string input)
{
    const int MaxStackBytes = 256;
    const int MaxPayloadBytes = 1024 * 1024;

    int byteCount = Encoding.UTF8.GetByteCount(input);
    if (byteCount > MaxPayloadBytes)
    {
        throw new ArgumentException(
            "Encoded payload is too large.",
            nameof(input));
    }

    byte[]? rented = null;
    Span<byte> buffer = byteCount <= MaxStackBytes
        ? stackalloc byte[byteCount]
        : (rented = ArrayPool<byte>.Shared.Rent(byteCount))
            .AsSpan(0, byteCount);

    try
    {
        return Encoding.UTF8.GetBytes(input, buffer);
    }
    finally
    {
        if (rented is not null)
        {
            ArrayPool<byte>.Shared.Return(
                rented,
                clearArray: true);
        }
    }
}
```

`stackalloc` 适合尺寸小、上限明确、同步使用的临时缓冲区。“有上限”不等于“上限可信”：阈值应由代码控制，结合调用深度、目标平台的栈预算、方法是否递归和真实输入规模确定，并在部署环境验证。不要直接用外部输入作为 `stackalloc` 长度，也不要在循环中反复 `stackalloc`，因为这些栈空间通常要到当前方法返回时才释放。

超过栈阈值时转用 `ArrayPool<T>` 不等于可以取消业务层大小上限；否则攻击者仍可制造巨大租赁和计算。租出的数组可能比请求更大，只使用明确的有效切片，必须在 `finally` 归还，并且归还后不再保存任何引用。

包含密钥、令牌或个人数据时应清理。`clearArray: true` 会在归还时清理数组；密码学秘密还可在最后一次使用后对有效切片调用 `CryptographicOperations.ZeroMemory`，使清理时点和意图更明确。

### 5.5 `ref struct` 的设计边界

`Span<T>` 是 `ref struct`。这类类型受到限制，是为了保证内部引用不会逃逸到堆上：

- 不能装箱成 `object` 或普通接口引用。
- 不能作为普通 class 字段。
- 不能被 lambda 随意捕获。
- 不能跨越 `await` 或 `yield` 生存。

如果 API 要异步，应在 `await` 前完成 Span 处理，或改用 `Memory<T>`：

```csharp
static async Task<int> ReadHeaderAsync(
    Stream stream,
    Memory<byte> buffer,
    CancellationToken cancellationToken)
{
    int read = await stream.ReadAsync(buffer, cancellationToken);
    return ParseHeader(buffer[..read]);
}

// 同步 helper 内再获取 Span，兼容 net8.0 / C# 12。
static int ParseHeader(ReadOnlyMemory<byte> bytes)
{
    ReadOnlySpan<byte> header = bytes.Span;
    return header.Length;
}
```

C# 12 不允许在 `async` 方法体内声明 ref struct 局部变量，即使声明位于最后一个 `await` 之后也不行。后续语言版本放宽了部分“不跨挂起点”的使用，但同时支持本文两个 LTS 时，上述 `Memory<T>` → 同步 helper 的写法最稳妥。

## 6. 异步、取消与并发

### 6.1 `async` 不是自动并行

`async`/`await` 的核心是非阻塞地表示等待和继续执行。CPU 密集任务不会因为加上 `async` 就变快：

- I/O 密集：使用真正异步的数据库、网络、文件 API。
- CPU 密集：在确实需要并行且有资源预算时使用并行算法或受控工作队列。
- ASP.NET Core 请求中不要用 `Task.Run` 包装同步 I/O；它只是把阻塞转移到另一个线程池线程。

ASP.NET Core 请求本来就在线程池线程上执行。用 `Task.Run` 包装同步数据库、文件或网络调用，会再占用一个线程；在 I/O 完成前该线程仍被阻塞。高并发下会出现工作项排队、线程注入跟不上、延迟升高又引发更多超时的线程池饥饿放大回路。

```csharp
// 不推荐：同步 I/O 仍阻塞线程。
Product product = await Task.Run(
    () => legacyClient.LoadProduct(id),
    cancellationToken);

// 推荐：底层 API 真正异步，并接收取消。
Product asyncProduct = await client.LoadProductAsync(
    id,
    cancellationToken);
```

传给 `Task.Run` 的 token 可以取消尚未开始的工作，但不能强制终止一个已经运行、且底层不支持取消的同步 I/O。若暂时无法替换第三方同步 API，把它隔离到具有明确容量、并发上限和超时预算的适配层/后台队列，不要让每个 HTTP 请求无界创建 `Task.Run`。CPU 密集工作也必须按整个服务的 CPU 预算限流；`Task.Run` 本身不会增加计算能力。

### 6.2 Task 与 ValueTask

默认返回 `Task`。只有在以下条件同时较明确时才考虑 `ValueTask<T>`：

- 同步完成非常常见。
- 分配确实出现在热路径画像中。
- 调用方理解 ValueTask 通常只能消费一次，不能随意缓存或多次 await。

```csharp
public ValueTask<Product?> FindAsync(int id, CancellationToken cancellationToken)
{
    if (_cache.TryGetValue(id, out Product? cached))
    {
        return ValueTask.FromResult<Product?>(cached);
    }

    return new ValueTask<Product?>(LoadAsync(id, cancellationToken));
}
```

绝大多数应用服务返回 `Task<T>` 更简单。ValueTask 是性能工具，不是“更新的 Task”。

### 6.3 取消是协作协议

```csharp
public async Task<Order?> LoadOrderAsync(
    int id,
    CancellationToken cancellationToken)
{
    return await dbContext.Orders
        .AsNoTracking()
        .SingleOrDefaultAsync(order => order.Id == id, cancellationToken);
}
```

规则：

- 从最外层请求、后台服务或命令入口向下传递 token。
- 不要用 `CancellationToken.None` 截断本可取消的链路。
- 只由“拥有超时策略”的层创建 `CancellationTokenSource`。
- 区分用户取消、超时和真正故障；日志级别及重试策略不同。
- 一旦不可逆副作用已经提交，不能假装整个操作被取消；需要幂等、补偿或事务边界。

组合请求取消和本地超时：

```csharp
using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
using var linked = CancellationTokenSource.CreateLinkedTokenSource(
    requestAborted,
    timeout.Token);

await service.ExecuteAsync(linked.Token);
```

### 6.4 异步流

```csharp
static async IAsyncEnumerable<int> ReadSequenceAsync(
    int count,
    [EnumeratorCancellation] CancellationToken cancellationToken = default)
{
    for (int value = 0; value < count; value++)
    {
        await Task.Delay(100, cancellationToken);
        yield return value;
    }
}

await foreach (int value in ReadSequenceAsync(10, cancellationToken))
{
    Console.WriteLine(value);
}
```

异步流让消费者逐项处理，降低一次性物化内存，但不会自动提供背压给任意上游。若生产者和消费者解耦、速率不同或需要有界缓冲，应使用 Channel。

### 6.5 有界 Channel 与背压

```csharp
Channel<Job> channel = Channel.CreateBounded<Job>(new BoundedChannelOptions(100)
{
    FullMode = BoundedChannelFullMode.Wait,
    SingleWriter = false,
    SingleReader = false
});

await channel.Writer.WriteAsync(job, cancellationToken);

await foreach (Job next in channel.Reader.ReadAllAsync(cancellationToken))
{
    await handler.HandleAsync(next, cancellationToken);
}
```

有界容量把过载显式化。无界队列在峰值期间可能把吞吐问题变成内存问题。选择 `Wait`、`DropOldest`、`DropNewest` 或 `DropWrite` 必须基于业务语义，并为丢弃、等待时长和队列深度建立指标。

- [System.Threading.Channels](https://learn.microsoft.com/zh-cn/dotnet/core/extensions/channels)
- [Channel 源码](https://github.com/dotnet/runtime/tree/v8.0.0/src/libraries/System.Threading.Channels/src/System/Threading/Channels)

完整生产者/消费者示例见 [AdvancedPatterns/Program.cs](Examples/CSharpNetLts/AdvancedPatterns/Program.cs)。

### 6.6 `Task.WhenAll`、失败与限流

```csharp
Task<Result>[] tasks = ids
    .Select(id => client.LoadAsync(id, cancellationToken))
    .ToArray();

Result[] results = await Task.WhenAll(tasks);
```

`WhenAll` 并不限制并发。对几万个 ID 直接创建几万个网络请求会压垮连接池和下游。可用 `Parallel.ForEachAsync`、`SemaphoreSlim` 或 Channel 设定并发上限：

```csharp
await Parallel.ForEachAsync(
    ids,
    new ParallelOptions
    {
        MaxDegreeOfParallelism = 16,
        CancellationToken = cancellationToken
    },
    async (id, token) => await client.LoadAsync(id, token));
```

并发上限应由连接池、数据库容量、下游配额和延迟目标决定，而不是由 CPU 核数机械决定。

### 6.7 锁、原子操作与并发集合

| 需求 | 首选 |
| --- | --- |
| 保护多个相关字段和不变量 | `lock` / .NET 10 可用 `System.Threading.Lock`。 |
| 单个计数、交换、CAS | `Interlocked`。 |
| 多线程键值访问 | `ConcurrentDictionary<TKey,TValue>`。 |
| 生产者/消费者与背压 | `Channel<T>`。 |
| 构建后只读高频查询 | Frozen collections。 |
| 发布不可变快照 | Immutable collections 或原子替换引用。 |

C# 会直接拒绝在 `lock` 语句体中使用 `await`。代码审查还要检查等价问题：手工 `Monitor.Enter` 后跨异步挂起点、在 `ReaderWriterLockSlim` 临界区中执行 `.Result` / `.Wait()`，或从锁内启动未等待的异步操作。线程所有权锁不能安全跨越异步挂起点。若异步流程必须串行化，可使用 `SemaphoreSlim.WaitAsync`，并在成功获取后于 `finally` 中释放：

```csharp
await _gate.WaitAsync(cancellationToken);
try
{
    await UpdateStateAsync(cancellationToken);
}
finally
{
    _gate.Release();
}
```

`SemaphoreSlim` 不可重入，也不自动提供公平性或跨进程协调。若 `WaitAsync` 在成功前被取消/抛错，不能调用 `Release`；更复杂的读写或可重入语义应使用经过审核的 async-aware primitive。

锁只保护同一进程内共享内存，不能替代数据库并发令牌、唯一约束、消息幂等或分布式协调。

### 6.8 `ConfigureAwait`

ASP.NET Core 默认没有传统 UI `SynchronizationContext`，多数应用代码不需要到处写 `ConfigureAwait(false)`。通用库若不依赖调用方上下文，可使用它避免不必要的上下文恢复；UI 应用更新界面时则必须回到正确上下文。

更重要的规则是避免 sync-over-async：

```csharp
// 不推荐：可能死锁，也会阻塞线程。
Result result = LoadAsync().Result;
LoadAsync().GetAwaiter().GetResult();
```

异步应从入口一路传播到 I/O 边界。

### 6.9 重试、幂等与副作用边界

重试不是“再调一次”这么简单，而是允许同一个逻辑操作被执行多次。远程请求超时时，调用方并不知道服务端是“没收到”、“正在执行”还是“已提交但响应丢失”。因此：

- 只重试明确的短暂故障，例如部分超时、限流和暂时网络失败；验证失败、唯一约束冲突和权限失败不会因重试自愈。
- 重试必须有次数、总时间预算、退避和 jitter，并继续响应 `CancellationToken`；无限重试会放大下游故障。
- 读取、按确定 key 的 upsert 以及有幂等键的命令更容易安全重试。会扣款、发送邮件或追加消息的操作若没有去重设计，不应盲目重试。
- 幂等键必须绑定到用户/租户、操作类型和请求摘要，服务端应持久化首次结果；仅在内存字典中记录 key 无法跨重启和多实例去重。

例如订单接口可以要求客户端提供 `Idempotency-Key`，并在与订单相同的数据库事务中写入唯一键和结果。后续相同请求返回已保存结果，而不是再执行副作用。这与 HTTP resilience policy 配合时，才能让 POST 类操作可控重试。

- [HTTP resilience](https://learn.microsoft.com/zh-cn/dotnet/core/resilience/http-resilience)
- [Retry pattern](https://learn.microsoft.com/azure/architecture/patterns/retry)

## 7. 集合、LINQ 与性能

### 7.1 先按语义选择集合

| 需求 | 常用类型 | 注意 |
| --- | --- | --- |
| 连续索引、固定快照 | `T[]` / `ImmutableArray<T>` | 数组可变；ImmutableArray 适合发布不可变快照。 |
| 动态顺序集合 | `List<T>` | 预知规模时设置 capacity。 |
| 唯一性与成员测试 | `HashSet<T>` | comparer 是集合语义的一部分。 |
| 键值查找 | `Dictionary<TKey,TValue>` | 避免重复哈希；可用 `TryGetValue`。 |
| 构建后只读高频查找 | `FrozenDictionary` / `FrozenSet` | 冻结构建有成本。 |
| 多线程共享键值状态 | `ConcurrentDictionary` | 复合业务操作仍可能需要额外同步。 |
| 多生产者/消费者 | `Channel<T>` | 用有界容量表达背压。 |
| 优先级调度 | `PriorityQueue<TElement,TPriority>` | 相同优先级不保证稳定顺序。 |

集合的 comparer 必须与业务标识语义一致：

```csharp
var users = new Dictionary<string, User>(StringComparer.OrdinalIgnoreCase);
```

对机器标识、协议 key 和用户名规范化通常使用 ordinal 规则；面向用户的语言排序使用文化相关 comparer。不要依赖当前线程文化处理安全或协议标识。

### 7.2 延迟执行与重复枚举

```csharp
IEnumerable<Order> expensive = repository
    .StreamOrders()
    .Where(order => order.Total > 1000m);

int count = expensive.Count();
Order first = expensive.First(); // 可能再次访问数据源
```

LINQ to Objects 默认延迟执行。若数据源昂贵、只能枚举一次或必须保持一致快照，应显式物化：

```csharp
Order[] snapshot = expensive.ToArray();
int count = snapshot.Length;
Order first = snapshot[0];
```

物化不是永远正确：大结果集一次性 `ToListAsync` 会消耗内存。需要逐行处理时使用流式枚举、分页或异步流。

### 7.3 `IEnumerable<T>` 与 `IQueryable<T>`

`IEnumerable<T>` 后续运算在当前进程执行；`IQueryable<T>` 表达式树交给 provider 翻译。调用 `AsEnumerable()` 是明确的执行边界：

```csharp
// 过滤、投影和排序在数据库执行。
IQueryable<OrderSummary> query = context.Orders
    .Where(order => order.Status == OrderStatus.Paid)
    .OrderByDescending(order => order.CreatedAt)
    .Select(order => new OrderSummary(order.Id, order.Total));

List<OrderSummary> rows = await query
    .Take(100)
    .ToListAsync(cancellationToken);
```

危险写法：

```csharp
// 过早切到客户端，可能把整表拉入进程。
var rows = context.Orders
    .AsEnumerable()
    .Where(ExpensiveLocalPredicate)
    .ToList();
```

无法翻译的本地逻辑应先在数据库把候选集缩到明确上限，再切到客户端。始终观察生成 SQL，而不是仅凭 LINQ 外形推断成本。

### 7.4 Join、GroupBy 与聚合

在 .NET 10 中优先用 `LeftJoin` / `RightJoin` 表达外连接。对内连接仍可用 `Join` 或 query syntax。对数据库查询，能否翻译以及生成什么 SQL 由 EF provider 决定。

```csharp
var totalsByCustomer = orders
    .GroupBy(order => order.CustomerId)
    .Select(group => new
    {
        CustomerId = group.Key,
        Total = group.Sum(order => order.Total)
    });
```

LINQ to Objects 的 `GroupBy` 会持有分组元素；大数据流若只需要计数或累计，可用字典单遍聚合，减少中间对象。数据库端则通常应让 provider 翻译为 `GROUP BY`。

### 7.5 热路径中的分配

常见分配来源：

- 捕获局部变量的 lambda/闭包。
- `ToList`、`ToArray`、`GroupBy`、`OrderBy` 等物化或缓冲操作。
- 值类型装箱为接口或 `object`。
- `Substring`、插值字符串和临时格式化。
- 异步状态机与未同步完成的 Task。
- 反射、表达式编译和动态代理。

优化顺序应是：测量 → 找到占比 → 修改 → 再测量。不要仅凭“零分配”标签牺牲整个应用的可维护性。

```csharp
// 热日志路径使用 LoggerMessage 源生成，避免禁用级别下的装箱与模板解析。
public static partial class AppLog
{
    [LoggerMessage(
        EventId = 1001,
        Level = LogLevel.Information,
        Message = "Processed order {OrderId} in {ElapsedMs} ms")]
    public static partial void OrderProcessed(
        ILogger logger,
        int orderId,
        double elapsedMs);
}
```

### 7.6 Benchmark 的最低要求

微基准使用 BenchmarkDotNet，不要用单次 `Stopwatch` 得出结论。至少做到：

- Release 构建，不附加调试器。
- 消费返回值，防止死代码消除。
- 比较相同语义和相同输入。
- 区分吞吐、延迟、分配和 GC。
- 在目标 CPU、OS、runtime 和部署模式上运行。
- 用端到端负载验证微基准收益是否真实传递。

不同问题需要不同证据：

| 要回答的问题 | 首选证据 |
| --- | --- |
| 两个局部算法哪个更快、每次调用分配多少 | BenchmarkDotNet + `MemoryDiagnoser`。 |
| 真实请求的 CPU、GC、线程池等待或端到端延迟在哪里 | 代表性负载 + `dotnet-counters` / `dotnet-trace`。 |
| 哪些类型长期存活、托管堆为何增长 | `dotnet-gcdump`，必要时使用受控 dump。 |
| 改动是否只把成本转移到数据库、网络或下游 | 分布式 trace、下游指标和整体压测。 |

优化前后应保存相同 SDK、TFM、Release 配置、硬件、输入与工作负载下的基线。先用测试确认语义一致，再判断目标指标是否改善；只展示一次 `Stopwatch`、一张脱离负载的截图，或“理论上少分配”都不足以支撑生产优化。

- [BenchmarkDotNet 文档](https://benchmarkdotnet.org/articles/overview.html)
- [.NET 性能诊断工具](https://learn.microsoft.com/zh-cn/dotnet/core/diagnostics/)

## 8. JSON、源生成、裁剪与 Native AOT

### 8.1 先设计契约，再选择选项

JSON DTO 应与领域实体分离。这样可以独立控制：

- 属性名称、大小写、必填与可空。
- 枚举表示和版本演进。
- 对外可写字段，避免 over-posting。
- 多态白名单。
- 严格或宽松反序列化策略。
- 数据库实体的导航、代理和循环引用。

```csharp
public sealed record CreateOrderRequest(
    string CustomerId,
    IReadOnlyList<CreateOrderLineRequest> Lines);

public sealed record CreateOrderLineRequest(
    string Sku,
    int Quantity);
```

不要直接把 EF entity 当 API 请求模型。即使序列化成功，也会把持久化结构、跟踪行为和外部契约耦合起来。

### 8.2 System.Text.Json 源生成

```csharp
using System.Text.Json.Serialization;

[JsonSerializable(typeof(Product))]
[JsonSerializable(typeof(Product[]))]
[JsonSerializable(typeof(TimeResponse))]
internal sealed partial class AppJsonContext : JsonSerializerContext;
```

注册到 ASP.NET Core：

```csharp
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.TypeInfoResolverChain.Insert(
        0,
        AppJsonContext.Default));
```

源生成的收益：

- 启动时少做反射元数据发现。
- 更适合 trimming 与 Native AOT。
- 缺失类型元数据能在构建或测试阶段暴露。

代价是必须维护可达类型集合，运行时才出现的任意类型或开放插件模型更难处理。可以组合多个 resolver，但要明确优先级。

- [System.Text.Json 源生成](https://learn.microsoft.com/zh-cn/dotnet/standard/serialization/system-text-json/source-generation)
- [JsonSerializerContext 源码](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Text.Json/src/System/Text/Json/Serialization/JsonSerializerContext.cs)

完整用法见 [AdvancedWebApi/Program.cs](Examples/CSharpNetLts/AdvancedWebApi/Program.cs)。

### 8.3 多态必须白名单化

```csharp
[JsonPolymorphic(TypeDiscriminatorPropertyName = "$type")]
[JsonDerivedType(typeof(CardPayment), "card")]
[JsonDerivedType(typeof(BankTransfer), "bank")]
public abstract record Payment;

public sealed record CardPayment(string LastFour) : Payment;
public sealed record BankTransfer(string Reference) : Payment;
```

不要根据不可信输入任意加载 CLR 类型。显式 derived-type 白名单同时限定协议和安全边界。新增类型是契约变更，应有兼容测试。

### 8.4 自定义 converter 的高级边界

Converter 应：

- 验证 token 类型和数值范围。
- 正确推进 `Utf8JsonReader`，不多读也不少读。
- 在 .NET 10 PipeReader 路径处理 `HasValueSequence`。
- 避免递归调用相同 converter 导致栈溢出。
- 对不可信输入设置深度、大小和集合上限。

```csharp
ReadOnlySpan<byte> value = reader.HasValueSequence
    ? reader.ValueSequence.ToArray()
    : reader.ValueSpan;
```

`ToArray()` 是兼容写法，不一定是最终性能最优写法；热点 converter 可针对 `ReadOnlySequence<byte>` 分段解析。

### 8.5 Trimming 与 Native AOT

发布：

```powershell
dotnet publish -c Release -r linux-x64 -p:PublishAot=true
```

项目可先只启用分析：

```xml
<PropertyGroup>
  <PublishTrimmed>true</PublishTrimmed>
  <EnableTrimAnalyzer>true</EnableTrimAnalyzer>
  <IsAotCompatible>true</IsAotCompatible>
</PropertyGroup>
```

常见不兼容来源：

- 按字符串反射查找类型或成员。
- 运行时 `Expression.Compile`、Reflection.Emit、动态代理。
- 未声明的 JSON 反射序列化。
- 插件程序集在构建时不可知。
- 泛型参数上的运行时类型发现。

优先顺序：使用静态 API/源生成 → 为反射入口添加明确注解 → 最后才使用宽泛保留。随意加 `DynamicDependency` 或 linker descriptor 可能让警告消失，却隐藏真正不可达或错误契约。

`EnableTrimAnalyzer`、`IsAotCompatible` 和普通 `dotnet build` 只能提前发现部分问题。Linker 和 AOT 编译器只有在 `dotnet publish` 处理完整依赖闭包和具体 RID 时，才能暴露最终的 `IL2026`、`IL2070`、`IL3050` 等警告。CI 应对每个真实部署的 TFM/RID 执行 publish，并在不带开发 SDK 和源码的干净环境中启动制品，覆盖 JSON、DI、反射、错误处理以及确实使用的插件/动态路径。

“处理所有警告”不是把它们全局压制。应追踪到触发调用链：优先改用静态 API、源生成或 AOT-compatible 依赖；其次添加能真实描述反射需求的注解。只有行为已经验证、保留范围明确时才能局部 suppression，并写明原因和对应测试。第三方包产生的警告同样是应用的兼容风险，需要升级、替换或明确隔离。

- [Trim self-contained deployments](https://learn.microsoft.com/zh-cn/dotnet/core/deploying/trimming/trim-self-contained)
- [Prepare libraries for trimming](https://learn.microsoft.com/zh-cn/dotnet/core/deploying/trimming/prepare-libraries-for-trimming)
- [Native AOT](https://learn.microsoft.com/zh-cn/dotnet/core/deploying/native-aot/)

### 8.6 AOT 适用判断

适合：

- 冷启动敏感的 CLI、函数和轻量服务。
- 部署镜像和内存上限严格。
- 依赖链可静态分析，插件和动态代码很少。

不一定适合：

- 高度动态的插件平台。
- 强依赖运行时代理/反射的旧框架。
- 长期运行且启动并非瓶颈的大型服务。
- 团队尚未建立 AOT CI 和依赖兼容测试。

AOT 是部署模型选择，不是通用性能开关。吞吐可能受益、持平或在某些路径回退，必须实测。

## 9. Generic Host、DI、Options 与后台服务

### 9.1 Generic Host 是生命周期根

Host 统一管理：

- 配置与环境。
- 依赖注入容器。
- 日志。
- `IHostedService` / `BackgroundService`。
- 启动、优雅停止与取消。

```csharp
HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);
builder.Services.AddHostedService<Worker>();

using IHost host = builder.Build();
await host.RunAsync();
```

- [Generic Host](https://learn.microsoft.com/zh-cn/dotnet/core/extensions/generic-host)
- [Hosting 源码](https://github.com/dotnet/runtime/tree/v10.0.0/src/libraries/Microsoft.Extensions.Hosting)

### 9.2 DI 生命周期

| 生命周期 | 创建与释放 | 典型对象 |
| --- | --- | --- |
| Singleton | 容器生命周期一次 | 无状态线程安全服务、配置快照工厂、共享缓存协调器。 |
| Scoped | 每个 scope 一次；Web 中通常每请求一次 | `DbContext`、请求级 unit of work。 |
| Transient | 每次解析 | 轻量、无状态、无昂贵资源对象。 |

最常见错误是 singleton 捕获 scoped：

```csharp
// 错误设计：BackgroundService 是 singleton，不能直接长期持有 scoped DbContext。
public sealed class BadWorker(AppDbContext dbContext) : BackgroundService;
```

应为每轮工作创建 scope：

```csharp
public sealed class Worker(
    IServiceScopeFactory scopeFactory,
    ILogger<Worker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            await using (AsyncServiceScope scope =
                scopeFactory.CreateAsyncScope())
            {
                IJob job =
                    scope.ServiceProvider.GetRequiredService<IJob>();

                await job.RunAsync(stoppingToken);
            } // 工作单元结束后立即释放 scoped 服务。

            logger.LogInformation("Job completed");
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
    }
}
```

开发和测试启用 scope/build 验证：

```csharp
builder.Services.AddOptions();
// WebApplicationBuilder 在 Development 默认进行部分验证；
// 自定义 ServiceProvider 时显式设置 ValidateScopes/ValidateOnBuild。
```

“长寿命捕获短寿命”不只指 scoped。如果 singleton 在构造时解析并保存一个实现 `IDisposable` / `IAsyncDisposable` 的 transient，该实例就实际被提升到 singleton 寿命，通常要到根容器停止才释放。高频从根容器解析 disposable transient 还会让容器持有它们以便最终释放，形成内存和资源积压。

审查时要沿 singleton 的整条依赖链检查，而不是只看第一层构造参数。需要短寿命可释放资源时，在明确 scope 内解析，或使用一个定义所有权的 factory，由调用方在每次使用后释放。不要把任意 `IServiceProvider` 注入 singleton 后当作 Service Locator 绕过寿命设计。

- [Dependency injection guidelines](https://learn.microsoft.com/zh-cn/dotnet/core/extensions/dependency-injection-guidelines)

### 9.3 Options 模式与启动验证

```csharp
public sealed class CatalogOptions
{
    public const string SectionName = "Catalog";
    public int DefaultPageSize { get; init; } = 20;
    public int MaxPageSize { get; init; } = 100;
}

builder.Services
    .AddOptions<CatalogOptions>()
    .BindConfiguration(CatalogOptions.SectionName)
    .Validate(
        options => options.MaxPageSize is > 0 and <= 100,
        "MaxPageSize must be between 1 and 100.")
    .Validate(
        options => options.DefaultPageSize is > 0
            && options.DefaultPageSize <= options.MaxPageSize,
        "DefaultPageSize must be between 1 and MaxPageSize.")
    .ValidateOnStart();
```

配置绑定只负责把字符串转成对象，不会自动验证业务不变量。没有 `ValidateOnStart` 时，validator 往往在 options 第一次被解析时才运行，错误可能拖到第一个请求或后台任务开始后才暴露。`ValidateOnStart` 会在 Host 启动阶段运行已注册的验证器，失败时抛出 `OptionsValidationException`，阻止应用以错误配置进入服务状态。

`ValidateOnStart` 只会执行已声明的规则，不会自动证明配置节存在，也不会联机验证数据库、HTTP 服务或凭据真的可用。必选 section 可用 `GetRequiredSection`，必选字段和范围用 DataAnnotations、`.Validate(...)` 或 `IValidateOptions<T>`，跨字段关系必须显式写出。对 `IOptionsMonitor<T>`，启动验证只证明启动时的值；后续 reload 仍需经过验证，并定义新值无效时是保留旧值、拒绝重载还是停止服务。

| 接口 | 行为 | 使用场景 |
| --- | --- | --- |
| `IOptions<T>` | 单例值，不重载 | 不变配置。 |
| `IOptionsSnapshot<T>` | 每 scope 重算 | Web 请求级读取；不能注入 singleton。 |
| `IOptionsMonitor<T>` | singleton，可监听变化 | 后台服务、动态配置。 |

热重载不保证业务操作中途看到一致配置。对需要原子一致性的多个值，应把它们绑定为一个不可变 options 对象，每次读取同一快照。

- [Options pattern](https://learn.microsoft.com/zh-cn/dotnet/core/extensions/options)
- [Options validation source generator](https://learn.microsoft.com/zh-cn/dotnet/core/extensions/options-validation-generator)

### 9.4 `HttpClientFactory`

```csharp
builder.Services.AddHttpClient<CatalogClient>(client =>
{
    string baseUrl = builder.Configuration["Catalog:BaseUrl"]
        ?? throw new InvalidOperationException(
            "Configuration value 'Catalog:BaseUrl' is required.");

    client.BaseAddress = new Uri(baseUrl, UriKind.Absolute);
    client.Timeout = TimeSpan.FromSeconds(10);
});

public sealed class CatalogClient(HttpClient httpClient)
{
    public async Task<Product?> GetAsync(
        int id,
        string accessToken,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"products/{id}");

        request.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue(
                "Bearer",
                accessToken);

        using HttpResponseMessage response = await httpClient.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);

        response.EnsureSuccessStatusCode();

        return await response.Content.ReadFromJsonAsync<Product>(
            cancellationToken: cancellationToken);
    }
}
```

`IHttpClientFactory` 通常在每次解析时创建轻量 `HttpClient`，同时复用并轮换底层 `HttpMessageHandler` 和连接池。这既避免每个请求都新建连接池导致端口/连接压力，也能通过 handler lifetime 定期刷新 DNS。因此，禁止的是高频直接构造、销毁自己拥有 handler 的 `HttpClient`；通过 factory 或 typed client 获得短寿命 `HttpClient` 是正常用法。

`DefaultRequestHeaders` 只适合在客户端建立时设置对所有请求都相同的固定 header。认证令牌、用户、租户、条件请求和业务 correlation ID 属于单次请求状态；在共享客户端上反复修改会让并发请求串值。应像示例一样设置到各自的 `HttpRequestMessage`，或通过不缓存请求状态的 `DelegatingHandler` 注入。Factory 管理的 handler scope 可能比一个 Web 请求更长，handler 不应保存用户、租户或其他 scoped 状态。

超时、重试和断路器必须理解幂等性：GET 通常可重试；已产生副作用的 POST 若无幂等键，不应盲目自动重试。

- [IHttpClientFactory](https://learn.microsoft.com/zh-cn/dotnet/core/extensions/httpclient-factory)
- [HTTP resilience](https://learn.microsoft.com/zh-cn/dotnet/core/resilience/http-resilience)

### 9.5 BackgroundService 的停止与失败

后台服务必须：

- 使用 `stoppingToken`。
- 让宿主可观察致命异常。
- 在停止时结束读循环并释放资源。
- 为每个 scoped 工作单元创建 scope。
- 对永久失败、暂时失败和取消采用不同策略。
- 记录队列深度、处理时间、失败和重试次数。

“每轮创建 scope”更准确的说法是“每个需要 scoped 依赖的独立工作单元创建并释放 scope”。不应让 `DbContext`、事务或其他 scoped 资源在两轮之间的延迟中仍存活，也不必为完全不使用 scoped 依赖的轮询无条件建 scope。`stoppingToken` 要继续传给队列读取、计时等待、数据库、HTTP 与内部 handler；服务停止前还要等待已启动的子任务，不能 fire-and-forget 后直接返回。

不要写空 catch 后无限循环：

```csharp
catch (OperationCanceledException)
    when (stoppingToken.IsCancellationRequested)
{
    // 正常宿主停止，不按工作失败记录。
}
catch (Exception exception)
{
    logger.LogError(exception, "Work item failed");
    // 根据业务决定重试、死信或让服务失败；不能静默吞掉。
}
```

## 10. ASP.NET Core 中高阶用法

### 10.1 请求管道顺序是行为的一部分

典型顺序：

```csharp
app.UseExceptionHandler();
app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers(); // 或 app.MapGet/MapPost/MapGroup 等 Minimal API 端点
```

异常处理要包住后续可能失败的中间件。认证必须先建立 principal，授权再判断访问。CORS、静态文件、限流、输出缓存等都有自己的顺序约束；应按官方文档和集成测试验证，而不是只看能否启动。

### 10.2 Typed Results

```csharp
app.MapGet(
    "/products/{id:int}",
    Results<Ok<Product>, NotFound> (int id, ProductCatalog catalog) =>
        catalog.Find(id) is { } product
            ? TypedResults.Ok(product)
            : TypedResults.NotFound());
```

Typed Results 让返回集合进入方法签名，改善测试和 OpenAPI 元数据。端点分支很多时，显式 result union 可能变长；可以提取 application handler，端点只做传输层映射。

### 10.3 Problem Details 与异常边界

```csharp
public sealed class GlobalExceptionHandler(
    ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext context,
        Exception exception,
        CancellationToken cancellationToken)
    {
        logger.LogError(exception, "Unhandled request failure");

        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        await TypedResults.Problem(
                statusCode: 500,
                title: "Unexpected server error")
            .ExecuteAsync(context);

        return true;
    }
}
```

响应不要泄露堆栈、数据库语句、路径、密钥或内部类型名。可公开稳定错误 code 和 trace ID，详细诊断只进入受控日志。

### 10.4 端点取消与流式响应

Minimal API 可直接绑定请求取消：

```csharp
app.MapGet("/orders/{id:int}", async (
    int id,
    AppDbContext dbContext,
    CancellationToken cancellationToken) =>
{
    OrderDto? order = await dbContext.Orders
        .AsNoTracking()
        .Where(order => order.Id == id)
        .Select(order => new OrderDto(order.Id, order.Total))
        .SingleOrDefaultAsync(cancellationToken);

    return order is null
        ? Results.NotFound()
        : Results.Ok(order);
});
```

客户端断开不一定意味着下游数据库立即停止，但传播 token 能减少无意义工作。开始提交不可逆事务后，则应以一致性和幂等为优先，不能简单把取消当回滚保证。

### 10.5 模型绑定不是授权

即使请求模型验证通过，也必须继续检查：

- 当前用户能否操作目标资源。
- 租户 ID 是否来自可信身份，而不是请求 JSON。
- 服务端管理字段是否完全不在输入 DTO 中。
- 文件、集合、字符串和嵌套深度是否有限制。
- 重复请求是否有幂等策略。

避免 over-posting：

```csharp
// 输入 DTO 只包含允许客户端修改的字段。
public sealed record UpdateProfileRequest(string DisplayName);
```

模型绑定/验证只是把不可信 HTTP 数据转成类型并检查格式；认证和授权则判断 principal 是否可以执行操作，两者互不替代。`.RequireAuthorization()` 或 endpoint policy 可以限制“谁能进入端点”，但订单、文档等资源的所有权仍应在加载服务端资源后执行 resource-based authorization：

```csharp
Order? order = await dbContext.Orders
    .SingleOrDefaultAsync(
        order => order.Id == id,
        cancellationToken);

if (order is null)
{
    return Results.NotFound();
}

AuthorizationResult allowed = await authorizationService.AuthorizeAsync(
    httpContext.User,
    order,
    "CanEditOrder");

if (!allowed.Succeeded)
{
    return Results.Forbid();
}

order.Rename(request.DisplayName);
await dbContext.SaveChangesAsync(cancellationToken);
return Results.NoContent();
```

租户、owner、role、审批状态等安全字段必须来自 claims 或服务端数据，不能直接接受请求体中的同名值。不要把 EF entity 直接作为输入模型；应把允许修改的 DTO 字段显式映射到已授权的实体。

### 10.6 缓存、限流与一致性

- Output cache 缓存完整 HTTP 响应，必须考虑用户、租户、授权、语言和 header vary。
- Data cache 缓存业务数据，必须定义失效和陈旧容忍度。
- Rate limiter 保护系统容量，不替代认证和业务配额。
- 分布式缓存不提供自动强一致性，cache-aside 存在短暂旧值窗口。

敏感个性化响应默认不要共享缓存。缓存 key 中的租户与用户维度必须经过规范化，避免串租户数据泄漏。

### 10.7 完整 Web API 示例

[AdvancedWebApi](Examples/CSharpNetLts/AdvancedWebApi/Program.cs) 以 `net8.0` 为最低基线，包含：

- `IExceptionHandler` + Problem Details。
- Typed Results。
- Options 绑定和 `ValidateOnStart`。
- Keyed DI。
- `TimeProvider` 注入。
- FrozenDictionary 只读目录。
- System.Text.Json 源生成。
- 可直接执行的 [.http 请求](Examples/CSharpNetLts/AdvancedWebApi/AdvancedWebApi.http)。

该项目可把 TFM 改成 `net10.0`，再逐步加入 Minimal API validation、SSE 与 OpenAPI 3.1，而不需要重写应用层。

### 10.8 集成测试

ASP.NET Core 端点至少测试：

- 成功状态、媒体类型和响应契约。
- 绑定/验证失败。
- 未认证与无权限。
- 资源不存在与并发冲突。
- 异常映射不泄露细节。
- 取消、超时和流断开。
- 缓存与限流元数据。

使用 `WebApplicationFactory<TEntryPoint>` 启动真实管道，并用测试配置替换外部依赖。不要只单元测试 endpoint delegate 后就认为 middleware、路由、JSON 和授权已覆盖。

- [ASP.NET Core integration tests](https://learn.microsoft.com/zh-cn/aspnet/core/test/integration-tests)

## 11. EF Core 中高阶用法

### 11.1 DbContext 是短生命周期工作单元

`DbContext`：

- 不是线程安全的。
- 默认适合一个请求/命令一个 scope。
- 持有跟踪状态，长期使用会不断增长。
- 发生某些异常后可能不再适合继续使用。

不要并发使用同一个 context：

```csharp
// 错误：两个查询共享同一 DbContext 并发执行。
await Task.WhenAll(
    context.Orders.ToListAsync(cancellationToken),
    context.Customers.ToListAsync(cancellationToken));
```

需要并行独立工作单元时使用 `IDbContextFactory<TContext>` 创建不同实例，但先确认数据库连接池和服务器容量真的允许并行。

- [DbContext lifetime and configuration](https://learn.microsoft.com/zh-cn/ef/core/dbcontext-configuration/)

### 11.2 查询先投影，再物化

```csharp
List<OrderSummary> orders = await context.Orders
    .AsNoTracking()
    .Where(order => order.Status == OrderStatus.Paid)
    .OrderByDescending(order => order.CreatedAt)
    .Select(order => new OrderSummary(
        order.Id,
        order.Customer.Name,
        order.Total))
    .Take(100)
    .ToListAsync(cancellationToken);
```

优点：

- 只选择所需列。
- 不创建无用 entity 和跟踪条目。
- 导航投影通常翻译成 join/subquery，减少手工装载。
- DTO 契约和持久化 entity 解耦。

`Include` 适合确实要修改或遍历实体图的场景；只返回 API DTO 时通常直接 `Select` 更好。

对外查询必须有服务端上限，不能直接相信客户端传入的 `pageSize`。分页要有稳定且最终唯一的排序，否则并发插入时可能重复或遗漏行。深页面的 `Skip` 需要数据库扫描并丢弃前面的行，持续浏览场景通常更适合 keyset/seek pagination：

```csharp
int safePageSize = Math.Clamp(requestedPageSize, 1, 100);

List<OrderSummary> page = await context.Orders
    .AsNoTracking()
    .Where(order => order.Id > afterId)
    .OrderBy(order => order.Id)
    .Select(order => new OrderSummary(
        order.Id,
        order.Customer.Name,
        order.Total))
    .Take(safePageSize)
    .ToListAsync(cancellationToken);
```

若没有可靠的唯一游标，可用 `(CreatedAt, Id)` 等复合排序键。后台批处理也应分批读取并清理 change tracker，而不是无界 `ToListAsync()`。

### 11.3 Tracking、identity resolution 与只读查询

| 模式 | 使用场景 |
| --- | --- |
| 默认 tracking | 查询后要修改并 `SaveChanges`。 |
| `AsNoTracking()` | 只读投影/实体，不需要 identity resolution。 |
| `AsNoTrackingWithIdentityResolution()` | 只读实体图，希望同 key 复用同一对象实例。 |

不要全局关闭 tracking 后又期待修改自动保存。明确每个查询意图比“一套全局魔法默认值”更可靠。

### 11.4 N+1、split query 与笛卡尔膨胀

延迟加载很容易在循环中触发 N+1。多个 collection Include 又可能产生笛卡尔膨胀。应按场景选择：

- DTO projection。
- 显式 Include。
- `AsSplitQuery()` 分多个 SQL，避免单 SQL 巨大重复行。
- 分页和批量 key 查询。

Split query 减少行膨胀，但增加往返，并涉及多个查询间的一致性窗口。需要一致快照时结合事务隔离级别评估。

### 11.5 事务、SaveChanges 与外部消息

单次 `SaveChanges` 通常已在事务中。多个保存步骤需要原子性时显式事务：

```csharp
await using IDbContextTransaction transaction =
    await context.Database.BeginTransactionAsync(cancellationToken);

order.Confirm();
await context.SaveChangesAsync(cancellationToken);

context.OutboxMessages.Add(OutboxMessage.From(order.DomainEvents));
await context.SaveChangesAsync(cancellationToken);

await transaction.CommitAsync(cancellationToken);
```

数据库事务不能原子提交 Kafka、HTTP 或邮件。需要可靠发布时使用 transactional outbox：业务更改与带唯一 `MessageId` 的 outbox 记录在同一数据库事务中提交，独立 worker 再向 broker 发布。

Outbox 通常提供的是 at-least-once，不是 exactly-once。Worker 可能在 broker 已接收、但“已发送”状态尚未持久时崩溃，于是恢复后重复发布。消费方应以 `MessageId` 建立唯一约束或 inbox 记录，并把“去重记录 + 业务更改”放在同一本地事务中。邮件、支付等外部副作用仍需要它们自身的幂等键或去重机制。

### 11.6 乐观并发

```csharp
public sealed class Order
{
    public int Id { get; set; }

    [Timestamp]
    public byte[] Version { get; set; } = [];
}
```

`SaveChangesAsync` 影响 0 行时 EF 抛出 `DbUpdateConcurrencyException`。应用应选择：

- 返回 `409 Conflict`。
- 重新读取并让用户合并。
- 在明确可自动合并的字段上有限重试。

不要对所有并发冲突无脑重试；如果两个用户修改同一业务字段，最后写入覆盖前者可能违反业务预期。

- [Handling concurrency conflicts](https://learn.microsoft.com/zh-cn/ef/core/saving/concurrency)

### 11.7 ExecuteUpdate / ExecuteDelete

```csharp
int affected = await context.Orders
    .Where(order => order.Status == OrderStatus.Pending
                    && order.ExpiresAt < now)
    .ExecuteUpdateAsync(
        setters => setters
            .SetProperty(order => order.Status, OrderStatus.Expired),
        cancellationToken);
```

集合式删除使用同样的边界：

```csharp
int deleted = await context.Orders
    .Where(order => order.Status == OrderStatus.Cancelled
                    && order.CreatedAt < cutoff)
    .ExecuteDeleteAsync(cancellationToken);
```

批量更新绕过 change tracker：

- 已跟踪实体不会自动同步。
- 不执行实体 setter、领域事件或 SaveChanges interceptor 的同等路径。
- 需要自行添加租户、并发和业务条件。

`ExecuteUpdate` / `ExecuteDelete` 在调用时立即执行，不等待 `SaveChanges`。多次调用或与 `SaveChanges` 混用时，它们不会自动组成一个更大的事务；需要原子性就显式开启事务。若 context 已跟踪同一批实体，批量 SQL 后内存状态会过期，不应继续把它当作数据库真值。并发场景应把 token 放入 `Where` 并检查 `affected` / `deleted`。

它适合明确的集合式数据库操作，不适合偷偷绕过领域不变量。

### 11.8 原始 SQL 安全

优先参数化插值 API：

```csharp
string city = input.City;
List<Customer> customers = await context.Customers
    .FromSqlInterpolated($"SELECT * FROM Customers WHERE City = {city}")
    .ToListAsync(cancellationToken);
```

表名、列名和排序方向不能作为普通 SQL 参数。若必须动态选择，使用严格枚举/白名单映射，不能直接拼接用户输入。

### 11.9 .NET 10 与 .NET 8 的 EF 选择

| 领域 | EF Core 10 | EF Core 8 |
| --- | --- | --- |
| Complex types | table splitting、JSON、struct 等进一步增强 | 首次正式提供 complex types。 |
| Primitive collections | 延续并增强 provider 能力 | 重要新能力。 |
| 外连接 LINQ | 翻译 `LeftJoin` / `RightJoin` | 使用传统 GroupJoin/SelectMany 形态。 |
| Query filters | Named filters，可按名称禁用 | 多个条件通常组合成一个 filter。 |
| JSON 更新 | 关系型 JSON 列 ExecuteUpdate 增强 | JSON 查询/更新能力显著增强。 |
| 支持周期 | 跟随 .NET 10 LTS | 跟随 .NET 8 LTS，接近结束。 |

EF Core 主版本通常与目标 .NET 主版本配套。升级 provider 前核对其正式支持矩阵，不要只看 NuGet 能否还原。

### 11.10 数据库错误映射与迁移验证

不要把所有 `DbUpdateException` 都映射成同一个 `500`，也不要根据本地化的异常消息做字符串匹配。应在持久化边界按 provider 的稳定 error code / SQLSTATE 分类，再转成应用层错误：

| 数据库结果 | 典型语义 | 应用处理 |
| --- | --- | --- |
| 乐观并发 token 不匹配 | 资源已被他人修改 | `409 Conflict`、读取新版本后合并，或只对可自动合并字段有限重试。 |
| 唯一约束冲突 | 业务 key 已存在，也可能是幂等请求重放 | 根据约束名映射稳定领域错误；通常为 `409`，不要仅做“先查再插”。 |
| 外键/检查约束失败 | 关联不存在或数据违反数据库不变量 | 转换成领域或输入错误，同时保留内部诊断；不泄露表名和 SQL。 |
| 死锁、短暂连接故障、限流 | 可能是 transient | 只在整个事务可重放且副作用幂等时按 provider 策略有界重试。 |
| 提交期间断线 | 提交结果可能未知 | 不能盲目重放非幂等命令；用业务 key/幂等 key 重查最终状态。 |

唯一性的最终保证必须在数据库约束中；“插入前先查一次”在并发下仍有竞态。同时，对 provider 异常的翻译要保持在基础设施层，不让 SQL Server、PostgreSQL 等具体异常渗入领域逻辑。

迁移不能只在 InMemory 或 SQLite 替身上测试。至少建立以下门禁：

1. 使用与生产一致的 provider 主版本、数据库引擎版本和 compatibility level 生成、应用并回滚迁移。
2. 审查 `dotnet ef migrations script`、索引重建、表重写、默认值回填、锁持有时间与可能的数据丢失。
3. 用接近生产数量级的数据测量执行时间和阻塞，而不是只在空库上跑过。
4. 滚动发布使用 expand/contract：先添加兼容 schema，再发布新代码和回填，最后删除旧列/约束，确保新旧实例短时共存。
5. 上线前验证备份、恢复、失败后继续和人工回退手册；已破坏性转换的数据不一定能靠 down migration 完整恢复。

- [Applying migrations](https://learn.microsoft.com/zh-cn/ef/core/managing-schemas/migrations/applying)
- [Connection resiliency](https://learn.microsoft.com/zh-cn/ef/core/miscellaneous/connection-resiliency)

## 12. 日志、指标、链路与运行时诊断

### 12.1 结构化日志

```csharp
logger.LogInformation(
    "Order {OrderId} for tenant {TenantId} completed in {ElapsedMs} ms",
    orderId,
    tenantId,
    elapsed.TotalMilliseconds);
```

不要先插值：

```csharp
// 不推荐：丢失结构化字段，禁用日志时也已构造字符串。
logger.LogInformation($"Order {orderId} completed");
```

敏感数据默认不记录：密码、token、Cookie、完整身份证/银行卡、连接字符串和原始请求体。建立集中脱敏规则并对日志访问授权。

### 12.2 ActivitySource 与分布式链路

```csharp
public static readonly ActivitySource Activities =
    new("SkillTree.Orders", "1.0.0");

using Activity? activity = Activities.StartActivity("orders.confirm");
activity?.SetTag("order.id", orderId);
activity?.SetTag("tenant.id", tenantId);
```

只有注册了 listener 且采样时，`StartActivity` 才可能返回非 null。tag 的基数要受控；不要把用户 ID、订单 ID 全部作为 metric label，但它们可以在采样 trace 中作为属性，仍需遵守隐私规则。

- [Distributed tracing instrumentation](https://learn.microsoft.com/zh-cn/dotnet/core/diagnostics/distributed-tracing-instrumentation-walkthroughs)
- [ActivitySource 源码](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Diagnostics.DiagnosticSource/src/System/Diagnostics/ActivitySource.cs)

### 12.3 Meter 与指标基数

```csharp
public static readonly Meter Meter = new("SkillTree.Orders", "1.0.0");
public static readonly Counter<long> Completed =
    Meter.CreateCounter<long>("orders.completed");

Completed.Add(1, new KeyValuePair<string, object?>("status", "success"));
```

适合 label：状态、区域、固定 operation。危险 label：trace ID、用户 ID、URL 原始路径、异常消息。高基数会放大内存、网络和监控成本。

- [Metrics instrumentation](https://learn.microsoft.com/zh-cn/dotnet/core/diagnostics/metrics-instrumentation)

### 12.4 三类信号如何分工

| 信号 | 回答的问题 |
| --- | --- |
| Log | 某次具体事件发生了什么。 |
| Metric | 系统总体是否异常、趋势如何。 |
| Trace | 一次请求跨组件在哪里耗时或失败。 |

成熟诊断链路通常是：告警指标发现问题 → trace 定位慢在哪一跳 → 关联结构化日志查看细节。

### 12.5 dotnet 诊断工具

```powershell
dotnet-counters monitor --process-id <PID>
dotnet-trace collect --process-id <PID>
dotnet-gcdump collect --process-id <PID>
dotnet-dump collect --process-id <PID>
```

| 工具 | 适用 |
| --- | --- |
| `dotnet-counters` | 在线观察 GC、线程池、ASP.NET Core 和自定义 Meter。 |
| `dotnet-trace` | 收集 EventPipe trace，分析 CPU、等待、GC 和框架事件。 |
| `dotnet-gcdump` | 较低侵入地查看托管堆类型分布。 |
| `dotnet-dump` | 崩溃、死锁、异常和完整堆分析。 |
| `dotnet-monitor` | 容器/Kubernetes 中通过诊断端点采集。 |

Dump 和 trace 可能包含敏感内存、请求和路径。生产采集要有审批、加密、访问控制和保留期限。

Trace、dump、gcdump、崩溃转储和 profiler 输出都应按“生产敏感数据”而不是普通构建制品治理。采集前限定进程、时间窗口、事件类别和采样率；诊断端点使用最小权限并限制网络访问；文件在传输和静态存储时加密，只向故障处理人员临时授权，并建立自动过期、删除和审计记录。完整 dump 可能直接包含 token、连接字符串、用户数据和密钥，不应未经审查上传到公开 issue、聊天工具或长期共享目录。

- [.NET diagnostics](https://learn.microsoft.com/zh-cn/dotnet/core/diagnostics/)
- [dotnet/diagnostics 源码](https://github.com/dotnet/diagnostics)

## 13. 多目标、升级与兼容性

### 13.1 应用与库的策略不同

应用通常控制部署 runtime，应尽快统一到 .NET 10。公共库面对更多消费者，可暂时多目标：

```xml
<TargetFrameworks>net10.0;net8.0</TargetFrameworks>
```

若库只使用共同 API，可考虑 `netstandard2.0/2.1`，但会放弃很多现代 API、可空元数据细节和性能能力。不要为了“支持一切”默认选最低 TFM；先确认真实消费者。

### 13.2 条件编译、条件引用与文件拆分

少量差异：

```csharp
#if NET10_0_OR_GREATER
return source.LeftJoin(...);
#else
return source.GroupJoin(...).SelectMany(...);
#endif
```

较大差异用文件拆分：

```xml
<ItemGroup Condition="'$(TargetFramework)' == 'net10.0'">
  <Compile Include="Platform/JsonPolicy.Net10.cs" />
</ItemGroup>
```

不要让 `#if` 贯穿领域代码和控制流。平台差异应收敛在最外层适配器。

### 13.3 global.json

```json
{
  "sdk": {
    "version": "10.0.102",
    "rollForward": "latestPatch",
    "allowPrerelease": false
  }
}
```

`global.json` 固定 SDK feature band，而运行时和 NuGet 仍有自己的版本。安全 patch 策略需结合 CI 镜像更新，不能固定后就永不升级。

`global.json` 只会在机器已安装的 SDK 中执行选择，不会下载或更新 SDK。`rollForward: latestPatch` 也只在允许的 feature band 范围内选择较新 patch；陈旧 CI 镜像不会因为仓库中有 `global.json` 就自动获得安全更新。CI 应记录 `dotnet --info`、`--list-sdks` 与 `--list-runtimes`，并让镜像/runner 更新与 `global.json` 变更经过同一可审查的依赖更新流程。本文的 `10.0.102` 是示例验证基线，不是建议永久停留的生产安全版本。

SDK patch 与应用运行时 patch 需分开治理。Framework-dependent 部署使用目标主机/运行时镜像中的 .NET runtime；self-contained 和 Native AOT 发布把运行时实现带入制品，安全更新后必须重新 publish 和部署。开发机、CI SDK、构建容器与生产 runtime/base image 都应有明确的更新责任。

- [global.json overview](https://learn.microsoft.com/zh-cn/dotnet/core/tools/global-json)

### 13.4 从 .NET 8 升级到 .NET 10

建议顺序：

1. 把 .NET 8 应用升级到最新受支持 patch，先消除已有告警。
2. 更新 CI/容器/开发机 SDK，并用 `global.json` 固定。
3. 将 TFM 改为 `net10.0`，先不主动重写语法。
4. 更新 Microsoft.Extensions、ASP.NET Core、EF Core 和 provider 主版本。
5. 阅读 [.NET 9](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/9.0) 与 [.NET 10](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/10.0) 的全部 breaking changes；跨两代不能跳过中间兼容变化。
6. 构建并把新增 compiler/analyzer/trim 警告视为迁移任务。
7. 运行单元、集成、数据库迁移、契约、性能和部署测试。
8. 灰度发布，观察错误率、延迟、GC、线程池、数据库与资源用量。
9. 稳定后再逐步采用 C# 14 和 .NET 10 新 API。

“升级 TFM”和“现代化代码”应分成两个可回滚步骤，问题定位更清楚。

跨两代升级时尤其检查：

- C# 14 的 first-class Span 可能改变数组调用的重载绑定。
- `field`、`extension` 等上下文关键字可能与旧标识符产生新的绑定或诊断。
- 平台 `System.Linq.AsyncEnumerable` 可能与旧 `System.Linq.Async` 包产生扩展方法歧义。
- .NET 10 的 `BackgroundService.ExecuteAsync` 整体在后台 Task 上执行，不再依赖进入首个 `await` 前的同步阻塞阶段；需要阻塞启动的逻辑应迁到生命周期方法。
- Configuration 的 JSON `null` 处理发生变化，必须回归测试“缺失、null、空字符串”的区别。
- 单文件应用的 native library 搜索、默认 package pruning 和 `.deps.json` 可能变化。
- `dotnet new sln` 默认生成 `.slnx`，旧脚本若只匹配 `.sln` 要更新。
- ASP.NET Core 的 Cookie 401/403、异常诊断抑制、OpenAPI.NET 2.x 与 PipeReader converter 兼容性。

对应官方入口：[.NET 10 breaking changes](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/10.0) 与 [BackgroundService 行为变化](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/extensions/10.0/backgroundservice-executeasync-task)。

### 13.5 API 与包兼容检查

- 编译覆盖每个 TFM。
- 对公共库使用 API compatibility 工具检查二进制/源码变化。
- NuGet 包不要引用高于目标 TFM 支持范围的依赖。
- Source generator/analyzer 要在目标 SDK 和 IDE 中测试加载兼容性。
- EF provider、数据库服务器和迁移工具版本都要进入矩阵。
- Native AOT/trim 项目必须单独 publish，而不是只 `dotnet build`。

- [Package validation](https://learn.microsoft.com/zh-cn/dotnet/fundamentals/apicompat/package-validation/overview)
- [Breaking changes](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/)

### 13.6 建议 CI 矩阵

```yaml
strategy:
  matrix:
    include:
      - framework: net10.0
        runtime_sdk: 10.0.x
      - framework: net8.0
        runtime_sdk: 8.0.x

steps:
  - uses: actions/checkout@v4

  # 10.0.x 用于匹配 global.json 并构建；
  # net8.0 job 另装 8.0.x，使 .NET 8 runtime 真实存在。
  - uses: actions/setup-dotnet@v4
    with:
      dotnet-version: |
        10.0.x
        ${{ matrix.runtime_sdk }}

  - run: dotnet --info
  - run: dotnet --list-sdks
  - run: dotnet --list-runtimes
  - run: dotnet restore --locked-mode
  - run: dotnet build -c Release --no-restore -f ${{ matrix.framework }}
  - run: dotnet test -c Release --no-build -f ${{ matrix.framework }}
```

“SDK 10 能编译 `net8.0`”只验证引用程序集和条件编译分支，不等于“程序已在 .NET 8 runtime 运行”。类库应让测试项目同样 multi-target，并分别执行 `dotnet test -f net8.0` 与 `-f net10.0`；应用还应为每个 TFM publish，在只安装对应 LTS runtime 的干净容器/runner 中启动制品并跑关键路径 smoke test。CI 的版本矩阵必须真正驱动 SDK/runtime 安装，不能只声明一个未被 step 使用的变量。

### 13.7 发布门禁与制品验证

`dotnet build` 成功不代表最终部署制品可用。下列选项只在 publish 闭包中完整生效：

- trimming / Native AOT 和它们的完整依赖分析。
- self-contained 携带的 runtime patch。
- 具体 RID 的 native 依赖、单文件打包与平台资源。
- 容器 base image 中的 OS、ICU、OpenSSL、证书和 runtime。

对每个真实部署目标，CI 应执行与生产一致的 publish 命令，例如：

```powershell
dotnet publish .\src\App\App.csproj `
  -c Release `
  -f net10.0 `
  -r linux-x64 `
  --self-contained true `
  -p:PublishAot=true
```

随后在干净目标环境中运行输出文件，验证启动、配置、JSON、DI、数据库连接、TLS/证书、本地化、错误处理和优雅停止。Trim/AOT 警告要按 [8.5 节](#85-trimming-与-native-aot) 追踪到根因，不能通过全局 `NoWarn`、保留整个程序集或未验证的 linker descriptor 伪造“零警告”。

发布记录应保留 SDK/runtime 版本、TFM、RID、依赖锁文件、容器 digest、publish 参数与 smoke test 结果，这些才是能否重现和审计一个制品的依据。

## 14. 官方资料与源码阅读地图

### 14.1 版本总入口

| 主题 | .NET 10 | .NET 8 |
| --- | --- | --- |
| 平台概览 | [.NET 10](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-10/overview) | [.NET 8](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-8/overview) |
| C# | [C# 14](https://learn.microsoft.com/zh-cn/dotnet/csharp/whats-new/csharp-14) | [C# 12](https://learn.microsoft.com/zh-cn/dotnet/csharp/whats-new/csharp-12) |
| Runtime | [.NET 10 Runtime](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-10/runtime) | [.NET 8 Runtime](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-8/runtime) |
| SDK | [.NET 10 SDK](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-10/sdk) | [.NET 8 SDK](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-8/sdk) |
| ASP.NET Core | [10.0](https://learn.microsoft.com/zh-cn/aspnet/core/release-notes/aspnetcore-10.0?view=aspnetcore-10.0) | [8.0](https://learn.microsoft.com/zh-cn/aspnet/core/release-notes/aspnetcore-8.0?view=aspnetcore-8.0) |
| EF Core | [10.0](https://learn.microsoft.com/zh-cn/ef/core/what-is-new/ef-core-10.0/whatsnew) | [8.0](https://learn.microsoft.com/zh-cn/ef/core/what-is-new/ef-core-8.0/whatsnew) |
| Breaking changes | [.NET 10](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/10.0) | [.NET 8](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/8.0) |

### 14.2 官方源码仓库

| 仓库 | 内容 | 建议基线 |
| --- | --- | --- |
| [dotnet/runtime](https://github.com/dotnet/runtime) | CLR、JIT、GC、BCL、Microsoft.Extensions 的大量实现 | [`v10.0.0`](https://github.com/dotnet/runtime/tree/v10.0.0)、[`v8.0.0`](https://github.com/dotnet/runtime/tree/v8.0.0) |
| [dotnet/roslyn](https://github.com/dotnet/roslyn) / [dotnet/dotnet VMR](https://github.com/dotnet/dotnet) | C#/VB 编译器、语义模型、分析器、Workspace | [.NET 10 SDK 10.0.102 快照](https://github.com/dotnet/dotnet/tree/44525024595742ebe09023abe709df51de65009b/src/roslyn)、[.NET 8 Roslyn 快照](https://github.com/dotnet/roslyn/tree/f43cd10b737b6343956dee421cff8c50b602c788) |
| [dotnet/csharplang](https://github.com/dotnet/csharplang) | C# 提案、LDM 记录和规范草案 | [`csharp-14.0`](https://github.com/dotnet/csharplang/tree/main/proposals/csharp-14.0)、[`csharp-12.0` GA 快照](https://github.com/dotnet/csharplang/tree/52763e3b581d1bc92ac90309c033a9f8a045c1e2/proposals/csharp-12.0) |
| [dotnet/aspnetcore](https://github.com/dotnet/aspnetcore) | Kestrel、MVC、Minimal API、Blazor、Identity、SignalR | [`v10.0.0`](https://github.com/dotnet/aspnetcore/tree/v10.0.0)、[`v8.0.0`](https://github.com/dotnet/aspnetcore/tree/v8.0.0) |
| [dotnet/efcore](https://github.com/dotnet/efcore) | EF Core 查询、跟踪、更新和 provider 抽象 | [`v10.0.0`](https://github.com/dotnet/efcore/tree/v10.0.0)、[`v8.0.0`](https://github.com/dotnet/efcore/tree/v8.0.0) |
| [dotnet/sdk](https://github.com/dotnet/sdk) | CLI、MSBuild targets、publish 与项目系统 | 与使用的 SDK tag/commit 对齐 |
| [dotnet/docs](https://github.com/dotnet/docs) | .NET 与 C# 官方文档源文件 | `main`，结合页面 `ms.date` |
| [dotnet/AspNetCore.Docs](https://github.com/dotnet/AspNetCore.Docs) | ASP.NET Core 官方文档与示例 | `main`，示例包号需与稳定 runtime 核对 |
| [dotnet/EntityFramework.Docs](https://github.com/dotnet/EntityFramework.Docs) | EF Core 官方文档与示例 | `main` |

### 14.3 如何读源码

推荐顺序：

1. 先看公开 API 文档，确认契约和目标框架。
2. 看对应版本 tag，而不是直接看 `main`。
3. 从公开类型文件进入，再读同目录测试。
4. 搜索异常消息、EventSource/Meter 名称和 feature switch。
5. 区分 reference assembly 契约、实现程序集和平台专用 partial 文件。
6. 对 JIT intrinsic、source generator 或 analyzer，结合测试理解实际边界。

常用入口：

- [source.dot.net](https://source.dot.net/)：浏览当前 .NET 源码并跳转符号。
- [Source Link](https://learn.microsoft.com/zh-cn/dotnet/standard/library-guidance/sourcelink)：调试 NuGet 时进入准确源码。
- GitHub permalink：按 `y` 固定 commit，再在文档中引用，避免 `main` 漂移。

源码是实现证据，不是公共兼容承诺。应用代码只应依赖公开 API 和文档化行为；internal 类型随 patch 或主版本变化都不保证兼容。

### 14.4 精选源码入口

| 能力 | 源码 |
| --- | --- |
| .NET 10 LeftJoin | [LeftJoin.cs](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Linq/src/System/Linq/LeftJoin.cs) |
| .NET 10 Strict JSON | [JsonSerializerOptions.cs](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Text.Json/src/System/Text/Json/Serialization/JsonSerializerOptions.cs) |
| .NET 10 async ZIP | [ZipArchive.cs](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.IO.Compression/src/System/IO/Compression/ZipArchive.cs) |
| .NET 10 WebSocketStream | [WebSocketStream.cs](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Net.WebSockets/src/System/Net/WebSockets/WebSocketStream.cs) |
| ASP.NET Core 10 validation | [ValidationEndpointFilterFactory.cs](https://github.com/dotnet/aspnetcore/blob/v10.0.0/src/Http/Routing/src/ValidationEndpointFilterFactory.cs) |
| ASP.NET Core 10 SSE | [ServerSentEventsResult.cs](https://github.com/dotnet/aspnetcore/blob/v10.0.0/src/Http/Http.Results/src/ServerSentEventsResult.cs) |
| .NET 8 Frozen collections | [Frozen source](https://github.com/dotnet/runtime/tree/v8.0.0/src/libraries/System.Collections.Immutable/src/System/Collections/Frozen) |
| .NET 8 TimeProvider | [TimeProvider.cs](https://github.com/dotnet/runtime/blob/v8.0.0/src/libraries/Common/src/System/TimeProvider.cs) |
| .NET 8 SearchValues | [SearchValues source](https://github.com/dotnet/runtime/tree/v8.0.0/src/libraries/System.Private.CoreLib/src/System/SearchValues) |
| .NET 8 Keyed DI | [DependencyInjection source](https://github.com/dotnet/runtime/tree/v8.0.0/src/libraries/Microsoft.Extensions.DependencyInjection) |
| EF Core query pipeline | [Query source](https://github.com/dotnet/efcore/tree/v10.0.0/src/EFCore/Query) |
| EF Core change tracking | [ChangeTracking source](https://github.com/dotnet/efcore/tree/v10.0.0/src/EFCore/ChangeTracking) |

## 附录 A：运行完整示例

伴随示例根目录：[CSharpNetLts](Examples/CSharpNetLts/README.md)。

### A.1 构建全部项目

```powershell
cd DotNet\Examples\CSharpNetLts
dotnet build .\CSharpNetLts.slnx
```

### A.2 运行 .NET 10 / C# 14

```powershell
dotnet run --project .\Net10Features\Net10Features.csproj
```

覆盖：extension members、`field`、空条件赋值、lambda 参数修饰符、unbound generic `nameof`、`LeftJoin`、严格 JSON、异步 ZIP、partial constructor/event 与复合赋值运算符。

### A.3 运行 .NET 8 / C# 12

```powershell
dotnet run --project .\Net8Features\Net8Features.csproj
```

覆盖：primary constructor、collection expressions、任意类型别名、默认 lambda 参数、inline array、FrozenDictionary、SearchValues、Random、TimeProvider 与 JSON Populate。

### A.4 运行跨版本高级示例

```powershell
dotnet run --project .\AdvancedPatterns\AdvancedPatterns.csproj
```

覆盖：泛型数学、可空流分析属性、封闭结果模式、Span 解析、Activity/Meter、Bounded Channel 和异步流。

### A.5 运行 Web API

```powershell
dotnet run --project .\AdvancedWebApi\AdvancedWebApi.csproj --urls http://localhost:5000
```

然后执行 [AdvancedWebApi.http](Examples/CSharpNetLts/AdvancedWebApi/AdvancedWebApi.http) 中的请求，或使用：

```powershell
curl http://localhost:5000/products/1
curl "http://localhost:5000/products?take=2"
curl http://localhost:5000/time
curl http://localhost:5000/boom
```

## 附录 B：代码审查清单

本附录不再只给出“要问什么”，还说明“为什么要问”和“什么样才算通过”。审查结论应尽量附带代码位置、测试、生成 SQL、publish 日志、benchmark 或诊断记录，而不是只勾选“是/否”。

### 语言与类型

- **Nullable 是否开启，`!` 是否有真实不变量支撑。** Nullable 是编译期流分析，`!` 只压制警告，不会产生 null 检查。通过标准是所有项目启用 Nullable，每个 `!` 都能指出相邻的构造验证、`?? throw`、Options 启动验证或 flow attribute；无法证明时应保留可空类型并处理。详见 [§4.1](#4-类型系统可空性与泛型)。
- **`required` 是否被误当成运行时验证。** `required` 主要约束 C# 对象初始化器，反射、配置绑定、反序列化和其他语言不一定遵守，也不检查空字符串、范围或跨字段规则。通过标准是边界另有运行时验证，领域对象由构造函数/工厂建立不变量。详见 [§4.2](#4-类型系统可空性与泛型)。
- **Record 中是否藏有可变集合，`with` 是否造成共享。** Record 的值语义和 `with` 默认都是浅的；`List<T>` 等引用成员会被两个副本共享。通过标准是采用 `ImmutableArray<T>`/不可变值对象、显式深拷贝，或清楚声明共享可变状态就是契约，并有别名行为测试。详见 [§4.6](#4-类型系统可空性与泛型)。
- **Primary constructor 参数是否被重复捕获。** 参数既被复制到显式字段，又在实例成员中直接引用时，编译器可能再生成捕获存储，形成两份状态和不一致风险。通过标准是每个依赖/值只选一种持久表示，并审查编译器警告和类型布局。详见 [§3.2](#3-net-8-与-c-12)。
- **Extension member 是否比真实实例成员或普通函数更清楚。** 扩展成员是静态分派且受 using/命名空间影响，还容易隐藏成本。拥有类型并且行为是其内在能力时用实例成员；需要多个平等输入、依赖或 I/O 时用普通函数/服务。扩展属性通过标准是廉价、确定、无副作用。详见 [§2.2](#2-net-10-与-c-14)。
- **运算符重载是否符合直觉、无远程副作用。** 运算符被默认理解为本地、确定且较廉价的运算。通过标准是 `+` / `+=` 语义一致，溢出和别名行为明确，不包含数据库、网络、文件、消息、取消或事务；后者应使用名称明确的异步方法。详见 [§2.5](#2-net-10-与-c-14)。

### 内存与性能

- **Span 是否只用于明确热路径，是否错误跨 `await`。** Span 通过 ref safety 换取低分配，不适合普通业务编排。通过标准是有分配/延迟画像证明为热路径，跨异步边界保存 `Memory<T>` / `ReadOnlyMemory<T>`；C# 12 把 Span 操作移到同步 helper，C# 14 也不允许它跨任何挂起点存活。详见 [§5.3–5.5](#5-值引用span-与内存)。
- **`stackalloc` 是否有可信上限。** 外部输入长度、递归深度或循环中反复分配都可造成栈溢出。通过标准是代码控制的小阈值，在目标环境验证，超过阈值转池化/堆内存，且仍有业务输入总上限。详见 [§5.4](#5-值引用span-与内存)。
- **ArrayPool 是否在 finally 归还，敏感数据是否清理。** 漏还会增加持续分配，越界使用或归还后保存引用会污染其他租户。通过标准是 `try/finally`、只使用有效切片、归还后不再访问，敏感数据用 `clearArray: true` 或 `CryptographicOperations.ZeroMemory` 按时清理。详见 [§5.4](#5-值引用span-与内存)。
- **LINQ 是否重复枚举、意外物化或过早切客户端。** 重复枚举可以重复 I/O/副作用，`ToList`/`GroupBy`/`OrderBy` 可能大量缓冲，`AsEnumerable` 过早会把整表拉回应用。通过标准是明确执行边界，物化有理由和上限，数据库候选集先缩小，并审查生成 SQL。详见 [§7.2–7.5](#7-集合linq-与性能)。
- **优化是否有 Benchmark、trace 或 allocation 证据。** 不同问题需要不同工具：局部算法用 BenchmarkDotNet/MemoryDiagnoser，真实 CPU、GC、线程池和延迟用 counters/trace，堆存活用 gcdump/受控 dump。通过标准是优化前后语义相同、环境和输入可比，且目标指标与端到端效果都改善。详见 [§7.6](#7-集合linq-与性能) 与 [§12.5](#12-日志指标链路与运行时诊断)。

### 异步与并发

- **CancellationToken 是否贯穿到底层 I/O。** 只在方法签名接收 token 不算可取消，必须把原 token 或正确链接后的 token 传给最终数据库、HTTP、文件、流、Channel 和等待 API。通过标准是不用 `CancellationToken.None` 截断链路，正常 `OperationCanceledException` 不被当成故障吞掉/重试，已提交副作用另有一致性策略。详见 [§6.3](#6-异步取消与并发)。
- **是否用 `Task.Run` 包装服务器同步 I/O。** 这不会让 I/O 变成非阻塞，只会额外占用线程池线程，高并发时可引发 starvation；token 也不能终止已运行的不可取消同步 API。通过标准是使用底层真正异步 API，无法替换的遗留调用进入有容量和并发预算的适配层/队列。详见 [§6.1](#6-异步取消与并发)。
- **并发 fan-out 是否有限制。** `Task.WhenAll` 只组合任务，不提供限流；一次为巨大输入创建所有请求会压垮连接池和下游。通过标准是用 `Parallel.ForEachAsync`、`SemaphoreSlim` 或 Channel 限制在途数，上限来自下游配额、连接池和延迟目标，大输入分批/流式处理。详见 [§6.6](#6-异步取消与并发)。
- **Channel 是否有界，丢弃策略是否符合业务。** 无界队列会把过载变成内存问题。`Wait` 适合不能静默丢失且生产者可承受背压的任务；`DropOldest` 更适合只关心最新状态的刷新/遥测。订单、支付、审计不应依赖进程内 drop 队列，应用持久化队列/outbox；通过还要有队列深度、等待和丢弃指标。详见 [§6.5](#6-异步取消与并发)。
- **是否在 lock 中 await，或让同一 DbContext 并发使用。** C# 直接禁止 `lock` 中 `await`，但还要发现手工 Monitor、锁内 `.Result`/未等待异步等等价问题；`DbContext` 本身不线程安全。通过标准是异步串行化使用 async-aware primitive 且正确释放，并行数据库工作用 `IDbContextFactory` 创建独立 context，同时限制数据库并发。详见 [§6.7](#6-异步取消与并发) 与 [§11.1](#11-ef-core-中高阶用法)。
- **重试操作是否幂等。** 超时时服务端可能已提交，盲目重放会重复扣款、邮件或消息。通过标准是只重试 transient failure，有总预算/退避/jitter/取消，非天然幂等命令使用持久化幂等 key、唯一约束或 inbox/outbox，并复用首次结果。详见 [§6.9](#6-异步取消与并发)。

### Host 与 Web

- **Singleton 是否捕获 scoped/transient disposable。** Singleton 持有 scoped 会跨请求共享不安全状态；持有 disposable transient 会把它实际提升到根容器寿命，可造成内存/连接积压。通过标准是审查整条依赖链，开启 scope/build validation，短寿命资源在明确 scope 或所有权清楚的 factory 中创建并释放，不用 Service Locator 规避设计。详见 [§9.2](#9-generic-hostdioptions-与后台服务)。
- **BackgroundService 是否每轮创建 scope 并响应停止。** 准确语义是每个 scoped 工作单元建立 scope，工作完成就释放，不覆盖轮询延迟。通过标准是 `stoppingToken` 传到队列、等待、DB/HTTP 和 handler，正常取消不记故障，不 fire-and-forget，停止前等待已启动子任务。详见 [§9.2、§9.5](#9-generic-hostdioptions-与后台服务)。
- **Options 是否 `ValidateOnStart`。** Bind 只转换值，不验证 section 存在、必选字段、范围或跨字段关系；不启动验证时错误可拖到首次解析。通过标准是必选 section/字段和业务规则全部显式声明，`ValidateOnStart` 启动失败，Monitor reload 有无效新值策略，外部依赖可用性另做 health/readiness 检查。详见 [§9.3](#9-generic-hostdioptions-与后台服务)。
- **HttpClient 是否由 factory 管理，请求级 header 是否污染共享状态。** Factory 复用/轮换 handler 与连接池，避免高频新建池和 DNS 长期陈旧。通过标准是 typed/named client 由 factory 创建，固定 header 才放 `DefaultRequestHeaders`，token/租户/correlation 放每个 `HttpRequestMessage` 或无请求级缓存的 handler，handler 不捕获 scoped 用户状态。详见 [§9.4](#9-generic-hostdioptions-与后台服务)。
- **Problem Details 是否隐藏内部细节。** 异常堆栈、SQL、路径、密钥和内部类型名会泄露系统结构和数据。通过标准是对外只返回稳定 type/title/status/error code 与可安全公开的 trace ID，详细异常只进入脱敏、限权日志，并有集成测试断言不泄露。详见 [§10.3](#10-aspnet-core-中高阶用法)。
- **输入 DTO 是否防止 over-posting，授权是否独立于模型绑定。** 绑定/验证只检查格式，不证明当前用户可操作资源。通过标准是输入 DTO 只含客户端可改字段，tenant/owner/role 来自 claims 或服务端，加载资源后再做 resource-based authorization，显式映射 DTO 而不直接绑定 EF entity。详见 [§10.5](#10-aspnet-core-中高阶用法)。
- **Cookie、OpenAPI、异常诊断和 JSON converter 是否通过 .NET 10 迁移检查。** 这四项都有行为/工具链变化：API Cookie 改为 401/403，OpenAPI 3.1 和 OpenAPI.NET 2.x 影响 transformer/client generator，已处理异常默认抑制部分框架诊断，PipeReader 要求 converter 处理分段值。通过标准是针对状态码/Location、OpenAPI snapshot 和下游生成器、日志/trace/metric、`HasValueSequence` 分段输入分别做迁移回归。详见 [§2.8](#2-net-10-与-c-14)。

### EF Core

- **查询是否投影所需列并传递取消。** 返回完整实体会读取/物化/跟踪无用数据；token 只传到仓储入口、却在 `ToListAsync`/`SingleAsync` 等终止 I/O 丢失也无法取消命令。通过标准是数据库端 `Where/Select/OrderBy/Take`，token 传到真正 I/O，并通过 SQL/命令日志确认列和上限。详见 [§11.2](#11-ef-core-中高阶用法)。
- **只读查询是否选择正确 tracking 模式。** 需要修改并保存的 entity 用 tracking；纯读用 `AsNoTracking`；只读实体图又需要同 key 共用实例时用 `AsNoTrackingWithIdentityResolution`。通过标准是每个查询意图明确，不在全局禁用 tracking 后仍期待修改自动保存。详见 [§11.3](#11-ef-core-中高阶用法)。
- **是否存在 N+1、笛卡尔膨胀或无界结果集。** 循环中延迟加载可生成 N+1，多 collection Include 可产生巨大重复行，无界查询还会长时间占用连接和内存。通过标准是观察 SQL 数量/形状，在 projection、Include、split query 中明确选择，服务端强制页大小和稳定排序，深页优先 keyset pagination。详见 [§11.2–11.4](#11-ef-core-中高阶用法)。
- **ExecuteUpdate/Delete 是否绕过了必要领域逻辑。** 它们立即执行 SQL，绕过 change tracker、setter、领域事件和 SaveChanges interceptor，已跟踪实体会过期，多次调用不自动组成一个事务。通过标准是租户/并发/业务条件全在 `Where`，检查受影响行数，需原子的多操作显式事务，必须发事件/outbox 时不走批量捷径。详见 [§11.7](#11-ef-core-中高阶用法)。
- **并发冲突、唯一约束和事务失败是否有明确映射。** 这些不是同一错误，也不应通过本地化异常消息分类。通过标准是基础设施层根据 provider 稳定 error code/约束名映射领域错误，并发/唯一性通常是稳定 `409`，transient 只在整个幂等工作单元可重放时重试，提交结果未知时用业务 key 重查。详见 [§11.6、§11.10](#11-ef-core-中高阶用法)。
- **外部消息是否使用 outbox/幂等，而不是假设跨系统事务。** 本地 DB 事务无法原子提交 broker/HTTP/邮件。通过标准是业务更改和带唯一 MessageId 的 outbox 同事务，dispatcher 接受 at-least-once，消费方用 inbox/唯一约束将去重和业务更改同本地事务，外部副作用另有幂等 key。详见 [§11.5](#11-ef-core-中高阶用法)。
- **provider、迁移 SQL 和生产数据库版本是否在测试矩阵中。** InMemory/SQLite 替身不能证明生产 SQL、约束、类型、事务和迁移正确。通过标准是固定 EF/provider/dotnet-ef/数据库引擎/compatibility level，生成并审查迁移 SQL，在生产版本和代表性数据量上测试锁、回填、索引和回退，滚动发布用 expand/contract。详见 [§11.10](#11-ef-core-中高阶用法)。

### 发布与诊断

- **使用受支持 patch，SDK 是否由 `global.json` 与 CI 镜像共同管理。** `global.json` 只选择已安装 SDK，不负责下载和安全更新；SDK patch 与生产 runtime/base image patch 也是两条链。通过标准是 CI 镜像显式安装受支持 patch，输出 `dotnet --info`/已安装 SDK/runtime，与 `global.json` 同步可审查更新；self-contained/AOT 安全更新后重新 publish。详见 [§13.3](#13-多目标升级与兼容性)。
- **Multi-target 是否真实构建和运行每个 TFM。** 新 SDK 编译旧 TFM 不能取代旧 runtime 执行。通过标准是每个 TFM 分别 restore/build/test，测试项目也 multi-target，应用分别 publish，并在只具有相应 LTS runtime 的干净 runner/容器中启动和 smoke test。详见 [§13.6](#13-多目标升级与兼容性)。
- **Trim/AOT 项目是否执行 `dotnet publish` 并处理所有警告。** Build/analyzer 不会执行最终 RID 闭包分析。通过标准是每个部署 TFM/RID 真实 publish，在干净环境运行制品和动态路径，每个 IL2xxx/IL3xxx 警告追根修复；局部 suppression 必须有理由和测试，禁止全局 `NoWarn`/宽泛保留伪造零警告。详见 [§8.5](#8-json源生成裁剪与-native-aot) 与 [§13.7](#13-多目标升级与兼容性)。
- **日志是否结构化并避免敏感信息。** 字符串插值会丢失可查询字段并可在禁用级别下仍分配；密码、token、Cookie、连接字符串和原始请求体会扩大泄露面。通过标准是使用稳定模板和命名字段，敏感值默认不记录或集中脱敏，日志访问/保留受控，Problem Details 不回传内部信息。详见 [§12.1](#12-日志指标链路与运行时诊断)。
- **Metric label 是否低基数。** 用户 ID、trace ID、原始 URL、异常消息会为几乎每个事件创建新时间序列，放大内存、传输和监控成本。通过标准是 label 只使用有界枚举，如状态、区域、固定 operation；高基数细节放入受采样和隐私约束的 trace/log。详见 [§12.2–12.3](#12-日志指标链路与运行时诊断)。
- **Trace、dump 和诊断文件是否按敏感数据治理。** 完整转储可直接包含 token、密钥、连接字符串和用户数据。通过标准是采集前审批并限定进程/时间/事件，诊断端点最小权限，文件传输/静态加密，临时授权、自动过期/删除/审计，禁止未审查上传公开 issue 或聊天工具。详见 [§12.5](#12-日志指标链路与运行时诊断)。

本文与仓库中面向 Monica 项目的 [.NET 10 技术学习指南](NET10技术学习指南.md) 关注点不同：本文是平台通用语法与运行时指南，后者是具体框架和工程架构审计。两者可交叉阅读，但不要把 Monica 自定义类型当作 .NET 标准 API。
