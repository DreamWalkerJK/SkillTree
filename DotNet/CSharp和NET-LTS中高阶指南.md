# CSharp和.NET Core 的高阶用法

> 本文把“CSharp”和“.NET Core”作为检索标题保留。自 .NET 5 起，统一产品名称是 **.NET**；ASP.NET Core、EF Core 等组件继续保留 Core 后缀。示例优先采用 .NET 10（LTS）和 .NET 8（LTS），并在需要时标注 .NET 11 Preview。本文编写时（2026-09）.NET 11 仍属于预览版本，生产系统应以受支持的 .NET 10 或 .NET 8 补丁版本为准。

本文不是 API 目录，而是一份工程手册：先说明运行时如何工作，再讨论类型系统、异步、数据访问、诊断和部署。每个技术点都给出适用版本、基础写法、进阶写法及失效原因。源码示例均为 C#。

## 目录

- [1. 版本、SDK 与项目配置](#1-版本sdk-与项目配置)
- [2. .NET 术语与执行模型](#2-net-术语与执行模型)
- [3. 类型系统、泛型与现代 C#](#3-类型系统泛型与现代-c)
- [4. 异步编程、线程与并发](#4-异步编程线程与并发)
- [5. 集合、LINQ 与异步流](#5-集合linq-与异步流)
- [6. 反射、属性、委托、事件与表达式树](#6-反射属性委托事件与表达式树)
- [7. 源生成器、动态编程与 AOT](#7-源生成器动态编程与-aot)
- [8. Span、Memory、Unsafe 与性能优化](#8-spanmemoryunsafe-与性能优化)
- [9. Generic Host、依赖注入与 AOP](#9-generic-host依赖注入与-aop)
- [10. ASP.NET Core 请求处理](#10-aspnet-core-请求处理)
- [11. EF Core 与数据访问](#11-ef-core-与数据访问)
- [12. 本机互操作与内存管理](#12-本机互操作与内存管理)
- [13. 配置、日志、诊断与测试](#13-配置日志诊断与测试)
- [14. 发布、容器与云环境](#14-发布容器与云环境)
- [15. 版本迁移和代码审查清单](#15-版本迁移和代码审查清单)
- [附录：官方资料](#附录官方资料)

## 1. 版本、SDK 与项目配置

### 1.1 版本矩阵

| 版本 | C# 默认版本 | TFM | 生命周期（2026-09） | 本文定位 |
| --- | --- | --- | --- | --- |
| .NET 11 Preview | C# 15 Preview（随 SDK 变化） | `net11.0` | 预览 | 只用于试验新 API；不用于生产环境。 |
| .NET 10 | C# 14 | `net10.0` | LTS | 新项目首选，本文示例主要采用。 |
| .NET 8 | C# 12 | `net8.0` | LTS 维护期 | 既有生产系统和长期支持环境。 |

语言版本、目标框架和运行时是三个独立概念。将 SDK 升级到 10 并不会让 `net8.0` 自动获得 .NET 10 API；同样，强行设置更高的 `LangVersion` 也不会改变运行时能力。

### 1.2 项目文件

`.NET 10 / C# 14` 控制台项目：

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

`.NET 8 / C# 12` 项目只需将 TFM 和语言版本改为 `net8.0`、`12.0`。类库可同时目标两个 LTS：

```xml
<PropertyGroup>
  <TargetFrameworks>net10.0;net8.0</TargetFrameworks>
  <Nullable>enable</Nullable>
  <ImplicitUsings>enable</ImplicitUsings>
</PropertyGroup>
```

在仓库根目录使用 `global.json` 锁定 SDK，避免开发机和 CI 使用不同编译器：

```json
{
  "sdk": {
    "version": "10.0.102",
    "rollForward": "latestPatch",
    "allowPrerelease": false
  }
}
```

试验 .NET 11 Preview 时，把 `allowPrerelease` 改为 `true` 并单独建立实验项目；不要让预览 SDK 参与生产发布流水线。

### 1.3 常用命令

```powershell
dotnet --info
dotnet workload list
dotnet restore
dotnet build -c Release
dotnet test --no-restore
dotnet publish -c Release -r win-x64 --self-contained false
```

`restore` 解析 NuGet 依赖，`build` 编译 IL，`publish` 生成可部署目录。生产构建建议在干净环境执行，并保存 SDK 版本、依赖锁定文件和发布参数作为构建记录。

## 2. .NET 术语与执行模型

以下术语取自 [Microsoft .NET 术语表](https://learn.microsoft.com/zh-cn/dotnet/standard/glossary)，并补充了实际编码时最常遇到的关系。

| 术语 | 含义与使用场景 |
| --- | --- |
| .NET | 微软的跨平台开发平台，包含运行时、基类库、SDK、编译器和应用框架。 |
| .NET SDK | 创建、还原、编译、测试、发布项目的命令行工具和 MSBuild 目标。SDK 自带编译器，但不等于运行时。 |
| TFM（Target Framework Moniker） | 项目目标框架标识，如 `net8.0`、`net10.0`。它决定编译时可见的 API 集合。 |
| Runtime | 执行已编译程序集的运行时包，例如 `Microsoft.NETCore.App`。框架依赖发布要求目标机器安装兼容运行时。 |
| CLR / CoreCLR | 公共语言运行时；负责加载程序集、JIT 编译、垃圾回收、异常、线程和类型安全。现代 .NET 的跨平台实现通常是 CoreCLR。 |
| BCL（Base Class Library） | `System.*` 等基础类库，提供集合、IO、网络、并发、文本、反射等通用 API。 |
| IL（Intermediate Language） | C# 编译器输出的中间指令。程序集第一次执行时通常由 JIT 转为当前 CPU 的机器码。 |
| 元数据（Metadata） | 程序集中的类型、成员、属性、引用和可见性描述；反射、序列化和依赖注入会读取它。 |
| Assembly（程序集） | `.dll` 或 `.exe` 文件及其清单、IL、元数据和资源，是部署、版本和加载的基本单元。 |
| JIT（Just-In-Time） | 按需把 IL 编译为机器码。RyuJIT 是 CoreCLR 的主要 JIT 编译器；Tiered Compilation 会先快速编译，再优化热点方法。 |
| AOT（Ahead-Of-Time） | 在运行前生成机器码。Native AOT 可缩短启动时间并减小镜像，但反射和动态代码需要显式保留。 |
| GC（Garbage Collector） | 自动管理托管堆，按代回收对象。短命对象进入 Gen 0，长期存活对象晋升到 Gen 1/2；大对象通常进入 LOH。 |
| 托管代码 / 非托管代码 | 由 CLR 管理执行和内存的是托管代码；通过 C/C++ ABI、COM 或系统调用执行的是非托管代码。 |
| NuGet | .NET 的包管理协议、客户端和包格式。包版本、资产类型和还原源会影响最终依赖图。 |
| RID（Runtime Identifier） | 发布平台标识，如 `linux-x64`、`win-arm64`；影响原生资产和运行时选择。 |
| Generic Host | `Microsoft.Extensions.Hosting` 提供的通用进程宿主，统一 DI、配置、日志、生命周期和后台服务。 |
| Kestrel | ASP.NET Core 的跨平台 HTTP 服务器；反向代理通常位于它前面。 |
| Middleware | 请求管道中的委托，每个中间件可在进入下一个组件前后执行逻辑。顺序直接影响认证、异常和响应。 |
| Endpoint | 路由匹配后的可执行处理单元，例如 Minimal API handler、MVC action 或 SignalR hub。 |
| DI（Dependency Injection） | 宿主负责创建和提供依赖，类只声明所需抽象。内置容器支持 Singleton、Scoped、Transient 三种生命周期。 |
| Options pattern | 把配置绑定到强类型选项，并通过验证和快照控制读取时机。 |
| `IEnumerable<T>` / `IQueryable<T>` | 前者表示本地迭代器；后者携带表达式树，查询提供程序可以把它翻译为 SQL 等外部语言。 |
| `IAsyncEnumerable<T>` | 可异步等待的迭代器，适用于分页、流式网络响应和数据库结果。 |
| `Span<T>` / `Memory<T>` | 对连续内存的切片视图。Span 只能在栈安全上下文中使用，Memory 可跨异步边界保存。 |
| SynchronizationContext | 为特定环境（UI、旧式 ASP.NET 等）调度延续的抽象；ASP.NET Core 默认没有专用上下文。 |

### 2.1 从源代码到机器码

```text
C# 源码
  └─ Roslyn 编译器 → IL + 元数据（程序集）
       └─ AssemblyLoadContext 加载
            └─ JIT / Native AOT → 机器码
                 └─ CoreCLR 执行、GC 管理托管对象
```

调试器看到的局部变量、反射读取的属性和序列化器使用的构造函数，都来自 IL 与元数据；被裁剪或 AOT 后，未被静态分析发现的成员可能不存在。因此动态功能必须在发布配置下验证，不能只在 Debug 运行。

### 2.2 GC 与资源释放

GC 只负责托管内存，不会自动关闭文件句柄、套接字、数据库连接等操作系统资源。实现 `IDisposable` 或 `IAsyncDisposable` 的类型要在正确的生命周期结束时释放：

```csharp
await using var stream = File.OpenRead("orders.json");
```

`using` 是编译器生成的 `try/finally`，不是“立即让 GC 回收”。频繁创建大数组会触发 LOH 和完整 GC，热路径应考虑 `ArrayPool<T>`、流式处理或预分配。

## 3. 类型系统、泛型与现代 C#

### 3.1 值类型、引用类型和可空性

值类型变量直接包含数据；引用类型变量包含对象引用。装箱会把值类型复制到托管堆，拆箱要求类型完全匹配：

```csharp
int number = 42;
object boxed = number; // 装箱分配
int copy = (int)boxed;  // 拆箱
```

启用 `<Nullable>enable</Nullable>` 后，编译器用流分析检查可能为 `null` 的引用。它不是运行时保护，外部输入仍需验证：

```csharp
public static string Normalize(string? value)
{
    ArgumentException.ThrowIfNullOrWhiteSpace(value);
    return value.Trim();
}
```

### 3.2 泛型的基础与约束

泛型在编译期保留类型信息，避免大多数装箱和强制转换。约束决定可调用的成员：

```csharp
public static T Max<T>(T left, T right) where T : IComparable<T>
    => left.CompareTo(right) >= 0 ? left : right;
```

`.NET 7 / C# 11` 引入泛型数学接口，可让一个算法直接支持整数和浮点数：

```csharp
using System.Numerics;

public static T Sum<T>(ReadOnlySpan<T> values) where T : INumber<T>
{
    T total = T.Zero;
    foreach (var value in values) total += value;
    return total;
}
```

高级用法包括静态抽象成员、协变/逆变和 `ref struct` 约束。泛型约束越具体，JIT 越容易内联；公开 API 不要为了微小收益堆叠难以理解的约束。

### 3.3 值元组、模式匹配与记录

`System.ValueTuple` 在 .NET Framework 4.7 / .NET Core 2.0 时代成为平台能力；C# 7.0 提供元组语法。它适合返回少量有明确位置的值：

```csharp
public static (bool Found, decimal Total) Calculate(Order order) =>
    order.IsPaid ? (true, order.Lines.Sum(x => x.Price)) : (false, 0m);
```

字段名只是编译期提示，跨程序集契约仍应使用命名类型。C# 9 / .NET 5 引入 `record`，适合不可变数据和按值相等：

```csharp
public sealed record CustomerId(Guid Value);
public sealed record Order(Guid Id, CustomerId Customer, decimal Total);
```

C# 8 的模式匹配和后续版本的属性、列表、关系模式可把校验写成声明式代码：

```csharp
static string Classify(Order order) => order switch
{
    { Total: <= 0 } => "无效金额",
    { Customer.Value: var id } when id == Guid.Empty => "匿名订单",
    _ => "普通订单"
};
```

模式应表达业务分类，不要把复杂副作用塞进 `when` 条件。

## 4. 异步编程、线程与并发

### 4.1 `Task` 与异步状态机

C# 5 引入 `async`/`await`。编译器把方法转换为状态机；遇到未完成的 awaitable 时返回，完成后恢复状态。它不会自动创建线程：I/O 异步通常由操作系统完成，CPU 工作才需要线程池线程。

```csharp
public static async Task<string> DownloadAsync(
    HttpClient client, Uri address, CancellationToken cancellationToken)
{
    using var response = await client.GetAsync(
        address, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
    response.EnsureSuccessStatusCode();
    return await response.Content.ReadAsStringAsync(cancellationToken);
}
```

基础规则：

- 让异步一路向上，库代码通常使用 `ConfigureAwait(false)`（UI 框架按需保留上下文）。
- 总是传递 `CancellationToken`，并区分取消、超时和业务失败。
- 不要在 ASP.NET Core 请求中调用 `.Result`、`.Wait()` 或 `GetAwaiter().GetResult()`。
- `async void` 只用于事件处理器；其异常无法由调用方等待和捕获。

`ValueTask<T>`（.NET Core 2.1）适合“多数调用同步完成且调用频繁”的 API。除非有测量结果，否则优先 `Task<T>`，因为 ValueTask 不能像 Task 一样随意多次等待或缓存。

### 4.2 线程、锁与并发集合

`Thread` 适合需要独立线程身份或特殊调度的场景；一般工作交给线程池：

```csharp
await Task.Run(CpuBoundWork, cancellationToken);
```

`lock`（C# 1）提供互斥；跨进程协调不能依赖 `lock`，需使用数据库锁、命名互斥体或分布式锁。 `ConcurrentDictionary<TKey,TValue>` 的单次操作是线程安全的，但“先检查再写入”仍可能竞态，应使用 `GetOrAdd`、`AddOrUpdate` 或显式锁。

### 4.3 Channel 与并行处理

`System.Threading.Channels`（.NET Core 3.0）适合生产者—消费者队列。使用有界 Channel 让内存占用可预测：

```csharp
var channel = Channel.CreateBounded<WorkItem>(
    new BoundedChannelOptions(256) { FullMode = BoundedChannelFullMode.Wait });

async Task ConsumeAsync(CancellationToken ct)
{
    await foreach (var item in channel.Reader.ReadAllAsync(ct))
        await HandleAsync(item, ct);
}
```

`Parallel.ForEachAsync`（.NET 6）适合独立且有明确并发上限的工作；并发度应根据下游数据库、API 和 CPU 容量测量。

## 5. 集合、LINQ 与异步流

### 5.1 LINQ 的两种执行方式

对 `IEnumerable<T>` 的 LINQ 是本地委托组合，调用终结操作时执行。对 `IQueryable<T>` 的 LINQ 会构造表达式树，由 provider 翻译；EF Core 可能翻译为 SQL。

```csharp
IQueryable<Order> query = db.Orders.Where(x => x.Total >= 100m);
var page = await query
    .OrderByDescending(x => x.CreatedAt)
    .Skip(offset).Take(size)
    .Select(x => new OrderSummary(x.Id, x.Total))
    .AsNoTracking()
    .ToListAsync(ct);
```

不要在 `IQueryable` 中调用任意 C# 方法并假设 provider 能翻译；无法翻译时会抛异常或拉取大量数据。需要本地处理时显式调用 `AsEnumerable`，并记录数据量。

### 5.2 分组、聚合和性能

```csharp
var report = await db.Orders
    .Where(x => x.CreatedAt >= from)
    .GroupBy(x => x.CustomerId)
    .Select(g => new CustomerReport(g.Key, g.Count(), g.Sum(x => x.Total)))
    .ToListAsync(ct);
```

先过滤和投影，再排序和分页；避免无意中的 `ToList()` 触发全表读取。

### 5.3 `IAsyncEnumerable<T>`

C# 8 / .NET Core 3.0 引入异步迭代器。它不会把全部结果缓存到内存：

```csharp
public async IAsyncEnumerable<Order> ReadOrdersAsync(
    [EnumeratorCancellation] CancellationToken ct = default)
{
    await foreach (var order in db.Orders.AsNoTracking()
        .AsAsyncEnumerable().WithCancellation(ct))
        yield return order;
}
```

流式接口需要定义取消、重试和部分结果语义，不能把它当成普通 `IEnumerable` 的异步版。

## 6. 反射、属性、委托、事件与表达式树

### 6.1 属性（Attribute）

C# 1 就支持属性；它们作为元数据附着在程序集、类型或成员上。自定义属性适合声明策略，不适合存放运行时状态：

```csharp
[AttributeUsage(AttributeTargets.Method, AllowMultiple = false)]
public sealed class AuditAttribute(string action) : Attribute
{
    public string Action { get; } = action;
}
```

### 6.2 反射

反射 API 在 .NET 1.0 已存在。高频路径不要重复调用 `GetMethods` 和 `Activator.CreateInstance`；建立缓存，并注意程序集卸载（`AssemblyLoadContext`）。Native AOT 和裁剪会移除未静态引用的成员，动态模型应改用源生成器或显式保留元数据。

### 6.3 委托和事件

委托是类型安全的方法引用；事件封装了发布者对委托字段的写权限：

```csharp
public sealed class ProgressReporter
{
    public event EventHandler<int>? ProgressChanged;
    public void Report(int value) => ProgressChanged?.Invoke(this, value);
}
```

长期存活的发布者持有订阅者引用，可能造成内存泄漏。跨生命周期订阅时提供取消令牌或 `IDisposable` 取消订阅。

### 6.4 表达式树

C# 3 / .NET 3.5 引入 `Expression<TDelegate>`。它保存代码结构，而不是已经编译的委托，适合查询翻译和动态筛选：

```csharp
Expression<Func<Order, bool>> expensive = x => x.Total > 1000m;
Func<Order, bool> local = expensive.Compile();
```

表达式树不支持所有最新 C# 语法；构造动态查询时优先组合已有节点，避免字符串拼接 SQL，并验证 provider 的翻译结果。

## 7. 源生成器、动态编程与 AOT

### 7.1 源生成器

Roslyn 源生成器在 .NET 5 / C# 9 进入正式支持，用编译期输入生成 `.g.cs` 文件。增量生成器（`IIncrementalGenerator`）只处理发生变化的语法节点，并用快照测试验证输出。

### 7.2 动态编程

`dynamic`（C# 4）把成员解析推迟到运行时，适合 COM、脚本宿主和确实动态的协议。业务核心代码应优先使用接口、泛型或模式匹配；`dynamic` 的错误在运行时才出现。

### 7.3 裁剪和 Native AOT

`.NET 7+` 的 Native AOT 适合启动敏感工具和服务。发布前检查反射、动态代理、运行时代码生成和原生库依赖：

```xml
<PropertyGroup>
  <PublishAot>true</PublishAot>
  <TrimMode>partial</TrimMode>
</PropertyGroup>
```

JSON 优先使用 `JsonSerializerContext` 源生成模型，先在 `PublishTrimmed=true` 下运行集成测试，再启用 AOT。

## 8. Span、Memory、Unsafe 与性能优化

### 8.1 `Span<T>` 和 `Memory<T>`

C# 7.2 / .NET Core 2.1 引入 `Span<T>`、`ReadOnlySpan<T>`；同一时期的 BCL 提供 `Memory<T>`、`ReadOnlyMemory<T>`。Span 是栈限定的 `ref struct`，不能存入字段、装箱或跨 `await`；Memory 可以保存并传入异步方法。

```csharp
public static int CountCommas(ReadOnlySpan<char> text)
{
    var count = 0;
    foreach (var c in text)
        if (c == ',') count++;
    return count;
}
```

### 8.2 池化和栈分配

```csharp
byte[] rented = ArrayPool<byte>.Shared.Rent(4096);
try
{
    int length = await stream.ReadAsync(rented, ct);
    Parse(rented.AsSpan(0, length));
}
finally
{
    ArrayPool<byte>.Shared.Return(rented, clearArray: true);
}
```

`stackalloc` 只用于很小且大小受控的缓冲区；用户可控长度不能直接放到栈上。向量化和 `Unsafe` 代码必须用 BenchmarkDotNet 及真实数据验证，不能凭直觉优化。

## 9. Generic Host、依赖注入与 AOP

### 9.1 DI 生命周期

```csharp
var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddSingleton<IClock, SystemClock>();
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddTransient<PlaceOrderHandler>();
using var host = builder.Build();
await host.RunAsync();
```

Singleton 必须线程安全且不能直接捕获 Scoped 服务；Scoped 通常对应 HTTP 请求或显式工作单元；Transient 适合轻量无状态对象。后台服务要通过 `IServiceScopeFactory` 创建作用域。

### 9.2 装饰器和 AOP

内置容器没有完整的动态代理 AOP。日志、重试、授权等横切行为优先使用显式装饰器、middleware 或 source generator。引入 Castle DynamicProxy 等库时，评估裁剪、AOT、代理生成成本和调试体验；不要隐藏事务提交和远程调用等副作用。

## 10. ASP.NET Core 请求处理

ASP.NET Core（.NET Core 1.0）把请求处理组织成有序 middleware 管道。异常处理应靠近外层，认证必须位于授权之前：

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddAuthentication().AddBearerToken();
builder.Services.AddAuthorization();
builder.Services.AddProblemDetails();

var app = builder.Build();
app.UseExceptionHandler();
app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();
app.MapGet("/orders/{id:guid}", async (
    Guid id, IOrderQueries queries, CancellationToken ct) =>
{
    var order = await queries.FindAsync(id, ct);
    return order is null ? Results.NotFound() : Results.Ok(order);
}).RequireAuthorization();
await app.RunAsync();
```

`.NET 8` 提供 Typed Results 和原生 OpenAPI 支持；`.NET 10` 示例沿用相同模型。 `.NET 11 Preview` 的 API 可能变化，应在独立项目验证。

## 11. EF Core 与数据访问

EF Core 1.0 随 .NET Core 发布，当前 .NET 10 对应 EF Core 10。推荐把查询投影到 DTO，避免加载完整实体图：

```csharp
public sealed record OrderSummary(Guid Id, decimal Total, DateTimeOffset CreatedAt);

public static Task<List<OrderSummary>> GetPageAsync(
    OrdersDbContext db, int skip, int take, CancellationToken ct) =>
    db.Orders.AsNoTracking()
        .OrderByDescending(x => x.CreatedAt)
        .Skip(skip).Take(take)
        .Select(x => new OrderSummary(x.Id, x.Total, x.CreatedAt))
        .ToListAsync(ct);
```

一个 `DbContext` 只在一个逻辑流中使用；读查询使用 `AsNoTracking`；迁移脚本在 CI 生成并审阅；跨消息发布采用 Outbox，而不是把数据库事务和远程消息事务混在一起。

## 12. 本机互操作与内存管理

`.NET 7` 的 `LibraryImport` 通过源生成器生成 P/Invoke 封送代码，新代码优先使用它：

```csharp
using System.Runtime.InteropServices;

internal static partial class NativeMethods
{
    [LibraryImport("kernel32", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool GetSystemPowerStatus(
        out SYSTEM_POWER_STATUS status);

    [StructLayout(LayoutKind.Sequential)]
    internal struct SYSTEM_POWER_STATUS
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte Reserved;
        public int BatteryLifeTime;
        public int BatteryFullLifeTime;
    }
}
```

必须确认调用约定、结构体布局、字符集、所有权和错误码。 `NativeMemory.Alloc`（.NET 6）返回的指针要在 `finally` 中释放；可行时优先使用 `SafeHandle`。

## 13. 配置、日志、诊断与测试

使用强类型 Options 并在启动时验证：

```csharp
public sealed class StorageOptions
{
    public const string Section = "Storage";
    public required string ConnectionString { get; init; }
    public int TimeoutSeconds { get; init; } = 30;
}

builder.Services.AddOptions<StorageOptions>()
    .BindConfiguration(StorageOptions.Section)
    .Validate(o => o.TimeoutSeconds is > 0 and <= 300)
    .ValidateOnStart();
```

日志采用稳定的结构化模板；`ActivitySource` 用于分布式跟踪，`Meter` 用于计数器和直方图。OpenTelemetry exporter 放在宿主配置，领域层只依赖窄接口。单元、集成、组件和端到端测试分层，性能结论用 BenchmarkDotNet 验证。

## 14. 发布、容器与云环境

框架依赖发布要求目标机器安装兼容运行时；自包含发布把 runtime 一起带上。Native AOT 和 ReadyToRun 都应在 Release 发布后做启动、内存和功能测试：

```powershell
dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishReadyToRun=true
```

容器应使用小型 runtime 镜像、非 root 用户、只读文件系统、健康检查和明确的关闭超时。Kubernetes readiness 表示是否接收流量，liveness 表示进程是否需要重启，两者不能混用。

## 15. 版本迁移和代码审查清单

从 .NET 8 迁移到 .NET 10 时，先更新 SDK、CI 镜像和 TFM，再阅读 breaking changes，运行全量测试、裁剪测试和发布测试，最后用指标比较启动时间、P95/P99 延迟、分配量、GC 暂停和错误率。

代码审查至少回答：

- 异步方法是否阻塞线程，取消令牌是否传到最底层？
- DI 生命周期是否匹配，Singleton 是否捕获 Scoped 对象？
- `IQueryable` 查询在哪里执行，是否意外客户端求值？
- 反射、动态代理和源生成器在裁剪/AOT 发布中是否可用？
- Span/Memory 引用的内存由谁拥有，何时失效？
- 非托管句柄和内存是否有确定的释放路径？
- 日志和诊断数据是否包含凭据或个人信息？
- 示例是否标明 .NET 8、.NET 10 或 .NET 11 Preview？

## 附录：官方资料

- [.NET 术语表](https://learn.microsoft.com/zh-cn/dotnet/standard/glossary)
- [.NET 支持策略](https://dotnet.microsoft.com/zh-cn/platform/support/policy/dotnet-core)
- [.NET 10 新增功能](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-10/overview)
- [C# 14 新增功能](https://learn.microsoft.com/zh-cn/dotnet/csharp/whats-new/csharp-14)
- [异步编程概述](https://learn.microsoft.com/zh-cn/dotnet/csharp/asynchronous-programming/)
- [泛型](https://learn.microsoft.com/zh-cn/dotnet/standard/generics)
- [反射概述](https://learn.microsoft.com/zh-cn/dotnet/fundamentals/reflection/)
- [表达式树](https://learn.microsoft.com/zh-cn/dotnet/csharp/advanced-topics/expression-trees/)
- [源生成器](https://learn.microsoft.com/zh-cn/dotnet/csharp/roslyn-sdk/source-generators-overview)
- [高性能代码](https://learn.microsoft.com/zh-cn/dotnet/csharp/advanced-topics/performance/)
- [依赖注入](https://learn.microsoft.com/zh-cn/dotnet/core/extensions/dependency-injection)
- [Generic Host](https://learn.microsoft.com/zh-cn/dotnet/core/extensions/generic-host)
- [ASP.NET Core](https://learn.microsoft.com/zh-cn/aspnet/core/)
- [EF Core](https://learn.microsoft.com/zh-cn/ef/core/)
- [.NET 本机互操作](https://learn.microsoft.com/zh-cn/dotnet/standard/native-interop/)
- [Native AOT 部署](https://learn.microsoft.com/zh-cn/dotnet/core/deploying/native-aot/)
- [OpenTelemetry .NET](https://learn.microsoft.com/zh-cn/dotnet/core/diagnostics/observability-with-otel)

仓库中的专题文章提供更完整的可复制示例：

- [C#/.NET 专题目录](CSharp专题/README.md)
- [基础数据结构目录](../Algorithm/数据结构/README.md)
- [图论算法目录](../Algorithm/图论/README.md)
- [.NET 体系结构专题目录](../Architecture/DotNet/README.md)
