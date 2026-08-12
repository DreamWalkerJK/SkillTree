# <center>async Task&lt;T&gt; 与 Task.FromResult：语义、状态机与性能</center>

## 目录

- [核心结论](#核心结论)
- [问题中的两种写法](#问题中的两种写法)
- [async 到底做了什么](#async-到底做了什么)
- [Task.FromResult 到底做了什么](#taskfromresult-到底做了什么)
- [性能影响](#性能影响)
- [异常与参数校验语义](#异常与参数校验语义)
- [已有异步任务应该直接返回还是 await](#已有异步任务应该直接返回还是-await)
- [常见场景与推荐写法](#常见场景与推荐写法)
- [基准测试方法](#基准测试方法)
- [常见误区](#常见误区)
- [决策表](#决策表)
- [参考资料](#参考资料)

## 核心结论

下面两种方法对调用方都返回 `Task<Res>`，但实现语义和成本并不完全相同：

```csharp
public async Task<Res> GetAsync()
{
    return new Res();
}
```

```csharp
public Task<Res> GetAsync()
{
    return Task.FromResult(new Res());
}
```

应优先根据方法内部是否存在真正的异步等待来选择，而不是为了让签名看起来“异步”而添加 `async`：

- 方法内部需要 `await`，并且还要在等待后继续处理、转换结果或使用 `try` / `catch` / `finally`：使用 `async Task<Res>`。
- 方法只需把一个已经得到的同步结果包装成 `Task<Res>`：去掉 `async`，返回 `Task.FromResult(result)`。
- 方法只负责转发另一个 `Task<Res>`，不需要在本层处理结果或异常：通常直接返回原任务。
- 没有 `await` 的 `async` 方法会触发 `CS1998`。它同步执行，但仍经过编译器生成的异步方法基础设施，通常比直接返回完成任务多一些指令开销。
- “`async` 一定多分配一个状态机对象”并不准确。现代 C# 编译器通常生成结构体状态机；如果方法同步完成，状态机可以留在栈上。真正遇到尚未完成的 `await` 并发生挂起时，状态机才通常需要提升到堆上。
- `Task.FromResult` 也不保证零分配。从 .NET 6 开始，部分类型和值可能命中运行时的已完成任务缓存；其他结果通常仍需创建新的 `Task<Res>`。
- `Task.FromResult` 不会把 CPU 密集型或阻塞式代码变成异步，也不会创建线程、切换线程或把工作排入线程池。

除非特别说明，本文的运行时实现与性能结论以 .NET 6+，尤其是当前 LTS 版本 .NET 8 / .NET 10 为范围；.NET Framework 和较早的 .NET Core 在任务缓存与 builder 实现上可能不同。

## 问题中的两种写法

以下示例使用一个简单的结果类型：

```csharp
public sealed record Res(int Code, string Message);
```

### 无 await 的 async 方法

```csharp
public async Task<Res> GetAsync()
{
    return new Res(0, "OK");
}
```

这里的 `async` 允许方法体使用 `await`，并让编译器负责把 `Res` 结果转换成最终的 `Task<Res>`。但是方法体根本没有 `await`，所以：

- 整个方法在调用线程上同步执行完毕。
- 返回给调用方的任务已经完成。
- 编译器产生 `CS1998` 警告。
- 没有任何 I/O 等待、线程切换或并发收益。

### 直接返回 Task.FromResult

```csharp
public Task<Res> GetAsync()
{
    return Task.FromResult(new Res(0, "OK"));
}
```

这里不生成异步方法状态机。方法先同步构造 `Res`，再返回一个已成功完成的 `Task<Res>`。

两种写法的正常结果对普通 `await` 调用方通常相同：

```csharp
Res result = await service.GetAsync();
```

但是它们在编译器转换、异常出现时机、调试堆栈和微观执行成本上存在差异，因此不能简单认定为“完全等价”。

## async 到底做了什么

### async 本身不会启动后台线程

`async` 是编译器功能，不是线程调度指令。一个 `async` 方法从入口开始同步执行，直到遇到第一个尚未完成的可等待对象：

```csharp
public async Task<Res> LoadAsync(CancellationToken cancellationToken)
{
    Console.WriteLine("这行在调用线程上立即执行");

    string json = await File.ReadAllTextAsync(
        "response.json",
        cancellationToken);

    return new Res(0, json);
}
```

如果 `File.ReadAllTextAsync` 返回的任务尚未完成，当前方法才会挂起，把控制权交回调用方，并在操作完成后运行后续代码。异步 I/O 在等待期间通常不占用一个线程；只有显式使用 `Task.Run` 等 API 时，才会把 CPU 工作调度到线程池。

### 编译器生成状态机

概念上，编译器会把 `async` 方法改写为一个实现 `IAsyncStateMachine` 的状态机，并使用 `AsyncTaskMethodBuilder<Res>` 管理最终任务。下列伪代码只用于解释结构，不等同于编译器的精确输出：

```csharp
public Task<Res> LoadAsync(CancellationToken cancellationToken)
{
    var stateMachine = new LoadAsyncStateMachine
    {
        State = -1,
        Builder = AsyncTaskMethodBuilder<Res>.Create(),
        CancellationToken = cancellationToken
    };

    stateMachine.Builder.Start(ref stateMachine);
    return stateMachine.Builder.Task;
}
```

状态机负责保存：

- 当前执行到了哪个 `await`。
- 跨 `await` 仍要使用的参数和局部变量。
- `try` / `catch` / `finally` 等控制流状态。
- 成功结果、异常或取消状态。
- 异步操作完成后要继续执行的代码。

### 同步完成快路径

`await` 并不必然挂起。如果等待的任务已经完成，状态机会直接取得结果并继续执行：

```csharp
public async Task<Res> NormalizeAsync(Task<Res> source)
{
    Res result = await source;
    return result with { Message = result.Message.Trim() };
}
```

当 `source.IsCompletedSuccessfully` 为 `true` 时，这次 `await` 可以同步继续。现代 .NET 为这种情况提供了快路径：状态机通常仍是栈上的结构体，不需要仅因为存在 `async` 关键字就把状态机对象分配到托管堆。

### 真正挂起时的成本

如果等待对象尚未完成，方法需要先返回一个代表未来完成状态的任务。此时通常会发生更多工作：

- 状态机需要存活到当前方法返回以后，通常会提升到堆上。
- 需要向等待对象注册 continuation（延续回调）。
- 需要保存跨 `await` 使用的字段。
- 完成时需要恢复 `ExecutionContext`；某些应用模型还涉及 `SynchronizationContext` 或非默认 `TaskScheduler`。
- 最终把结果、异常或取消写入返回任务。

这部分成本是真正异步语义的必要代价。只要方法确实需要非阻塞地等待 I/O，通常不应该为了省掉少量状态机开销而改回同步阻塞。关于上下文流转可参阅 [ExecutionContext 与 SynchronizationContext](/DotNet/ExecutionContext和SynchronizationContext.md)。

## Task.FromResult 到底做了什么

`Task.FromResult<TResult>(TResult result)` 创建或取得一个已经以指定结果成功完成的 `Task<TResult>`：

```csharp
Task<Res> task = Task.FromResult(new Res(0, "OK"));

Console.WriteLine(task.IsCompletedSuccessfully); // True
Console.WriteLine(task.Result.Message);           // OK
```

它表达的是“结果现在已经可用，但 API 契约要求返回任务”，而不是“稍后在后台计算这个结果”。因此它不会：

- 创建新线程。
- 把委托排入线程池。
- 推迟 `result` 表达式的求值。
- 让同步 I/O 或 CPU 计算变成非阻塞操作。

下面的代码仍会先阻塞当前线程，完成全部计算后才创建任务：

```csharp
public Task<Res> CalculateAsync()
{
    Res result = RunExpensiveCalculation(); // 仍然同步占用当前线程
    return Task.FromResult(result);
}
```

如果 `RunExpensiveCalculation` 是必须移出 UI 线程的 CPU 密集型工作，可以由上层明确决定是否使用 `Task.Run`；ASP.NET Core 服务端代码则不应为了“看起来异步”而随意把普通计算丢到线程池，因为这通常不能增加服务器吞吐量。

### 已完成任务缓存

从 .NET 6 开始，`Task.FromResult` 对部分 `TResult` 类型和部分结果值可能返回缓存的单例任务，而不是每次分配新对象。当前运行时实现会优化若干常见值，例如布尔值、部分小整数以及某些类型的默认值；但这属于实现细节，不应成为业务正确性的依据。

```csharp
Task<bool> first = Task.FromResult(false);
Task<bool> second = Task.FromResult(false);

// 当前 .NET 版本通常为 True，但业务代码不应依赖任务引用相等。
Console.WriteLine(ReferenceEquals(first, second));
```

应遵循以下原则：

- 只依赖任务的完成状态和结果，不依赖引用是否相同。
- 不假定任意 `Task.FromResult(value)` 都是零分配。
- 不手工复制运行时的内部缓存范围；如果确实需要缓存一个稳定结果，可以显式保存自己的只读任务。

```csharp
private static readonly Task<Res> HealthyTask =
    Task.FromResult(new Res(0, "Healthy"));

public Task<Res> GetHealthAsync()
{
    return HealthyTask;
}
```

只有当结果对象本身是不可变的、可安全共享，并且任务永远保持成功完成时，才适合这样缓存。

## 性能影响

### 成本模型

| 成本项 | 无 `await` 的 `async Task<Res>` | `Task.FromResult(result)` |
| --- | --- | --- |
| 编译器状态机 | 会生成。 | 不生成。 |
| 方法是否同步执行 | 是。 | 是。 |
| 是否调度线程 | 否。 | 否。 |
| 状态机堆分配 | 同步完成时通常没有。 | 无状态机。 |
| `Task<Res>` 分配 | 取决于结果是否命中运行时缓存。 | 同样取决于结果是否命中运行时缓存。 |
| 指令成本 | 需要初始化并驱动 builder / 状态机，通常更高。 | 直接调用 `Task.FromResult`，通常更低。 |
| 异常语义 | 未处理异常进入故障任务。 | 创建任务前抛出的异常直接从方法调用抛出。 |
| 编译器诊断 | 没有 `await` 时产生 `CS1998`。 | 无此警告。 |

### 不要把“状态机存在”和“状态机分配”混为一谈

这是性能分析中最常见的表述错误：

- 编译产物中存在状态机类型，不代表每次调用都会为状态机单独分配一个对象。
- 同步完成时，状态机通常是栈上的结构体。
- 真正挂起后，状态机才通常需要在堆上继续存活。
- 即使状态机不分配，初始化 builder、进入 `MoveNext`、设置结果等额外指令仍然存在。

因此，无 `await` 的 `async` 方法通常比 `Task.FromResult` 慢，但常见差距是纳秒级控制流开销；是否产生 Gen 0 压力，则更多取决于最终 `Task<Res>` 和 `Res` 本身是否需要分配。

### Task 分配取决于结果

在当前 .NET 运行时中，如果 `AsyncTaskMethodBuilder<TResult>` 尚未创建代表异步操作的任务，同步成功时的 `SetResult` 会通过 `Task.FromResult(result)` 取得最终任务。因此，无 `await` 的 `async Task<TResult>` 与直接调用 `Task.FromResult` 会共享当前运行时的结果任务缓存策略。这是运行时实现细节，不是 C# 语言保证，也解释了为什么二者常有相同的分配量、但 CPU 指令成本不同。

以下两个方法在现代 .NET 上都可能复用同一个缓存的 `Task<bool>`：

```csharp
#pragma warning disable CS1998
public async Task<bool> AsyncFalseAsync()
{
    return false;
}
#pragma warning restore CS1998

public Task<bool> FromResultFalseAsync()
{
    return Task.FromResult(false);
}
```

而对于任意新建引用对象，两者通常都至少涉及结果对象与完成任务的分配：

```csharp
#pragma warning disable CS1998
public async Task<Res> AsyncResultAsync()
{
    return new Res(0, "OK");
}
#pragma warning restore CS1998

public Task<Res> FromResultAsync()
{
    return Task.FromResult(new Res(0, "OK"));
}
```

把第一种改成第二种，可以去掉无意义状态机的执行成本，但并不会自动消除 `Res` 或 `Task<Res>` 的所有分配。

### 性能差异什么时候值得关心

通常值得优化：

- 每秒调用数很高的底层库或协议解析器。
- 紧密循环内反复返回同步完成结果。
- 缓存命中率极高、绝大多数调用同步完成的 API。
- 分配数据已经证明此方法是 GC 热点。

通常不值得优先优化：

- 方法主要耗时来自网络、数据库或磁盘 I/O。
- 一次调用耗时为毫秒级，而包装成本只有纳秒级。
- 去掉 `async` 会显著破坏异常处理、资源释放或代码可读性。
- 尚未通过 profiler 或基准测试确认这里是瓶颈。

## 异常与参数校验语义

两种写法最容易被忽略的差异是：异常是在“调用方法时”直接抛出，还是保存在返回任务中并在 `await` 时重新抛出。

### async 方法把异常存入任务

即使异常发生在第一个 `await` 之前，`async Task<T>` 方法中未处理的异常通常也会被 builder 捕获并写入故障任务：

```csharp
#pragma warning disable CS1998
public async Task<Res> GetWithAsyncKeywordAsync(string input)
{
    ArgumentException.ThrowIfNullOrWhiteSpace(input);
    return new Res(0, input);
}
#pragma warning restore CS1998
```

调用方法本身会返回一个 `Faulted` 任务，异常通常在等待时出现：

```csharp
Task<Res> task = GetWithAsyncKeywordAsync("");
Console.WriteLine(task.Status); // Faulted

Res result = await task;       // 此处重新抛出 ArgumentException
```

普通未处理异常使任务进入 `Faulted`；未处理的 `OperationCanceledException` 则通常使返回任务进入 `Canceled`。

### 普通 Task 返回方法可以同步抛出

去掉 `async` 后，创建任务之前执行的代码遵循普通同步方法语义：

```csharp
public Task<Res> GetWithFromResultAsync(string input)
{
    ArgumentException.ThrowIfNullOrWhiteSpace(input);
    return Task.FromResult(new Res(0, input));
}
```

此时下面第一行调用就会直接抛出异常，`task` 根本来不及赋值：

```csharp
Task<Res> task = GetWithFromResultAsync("");
Res result = await task;
```

这不代表同步抛出一定是坏事。Microsoft 的 TAP 设计指南建议参数错误等“用法错误”从异步方法调用处直接抛出，而运行过程中的其他错误进入返回任务。关键是 API 契约要明确并保持一致。

### 需要故障或取消任务时使用专用工厂

如果方法有意用任务表示失败或取消，可以显式使用：

```csharp
public Task<Res> GetFailedAsync(Exception exception)
{
    return Task.FromException<Res>(exception);
}

public Task<Res> GetCanceledAsync(CancellationToken cancellationToken)
{
    // Task.FromCanceled 要求令牌已经处于请求取消状态。
    return Task.FromCanceled<Res>(cancellationToken);
}
```

不要为了让异常进入任务而保留一个没有 `await` 的 `async` 方法；显式工厂通常更清楚。

### 同步校验与异步核心分层

如果参数错误需要在调用点同步抛出，但真正的运行错误仍应进入任务，可以使用普通外层方法加异步局部函数：

```csharp
public Task<Res> GetAsync(
    string key,
    CancellationToken cancellationToken)
{
    ArgumentException.ThrowIfNullOrWhiteSpace(key);
    return CoreAsync(key, cancellationToken);

    async Task<Res> CoreAsync(
        string validatedKey,
        CancellationToken token)
    {
        Res result = await _repository.LoadAsync(
            validatedKey,
            token);

        return result with { Message = result.Message.Trim() };
    }
}
```

这样可以同时得到两种明确语义：

- `key` 非法属于调用方用法错误，直接从 `GetAsync(...)` 抛出。
- I/O、取消和结果处理发生在 `CoreAsync` 中，通过返回任务传播。

## 已有异步任务应该直接返回还是 await

问题不只存在于同步结果。包装一个已经存在的异步任务时，也常见以下两种写法：

```csharp
public async Task<Res> GetAsync(CancellationToken cancellationToken)
{
    return await _client.GetAsync(cancellationToken);
}
```

```csharp
public Task<Res> GetAsync(CancellationToken cancellationToken)
{
    return _client.GetAsync(cancellationToken);
}
```

如果本层只是透明转发，第二种写法通常更直接，并避免本层状态机和额外的 continuation。它还原样保留下游返回的任务，而不是创建一个代表本层异步方法的新任务。

但是以下情况应保留 `async` / `await`：

### 需要转换结果

```csharp
public async Task<Res> GetAsync(CancellationToken cancellationToken)
{
    ApiResponse response = await _client.GetAsync(cancellationToken);
    return new Res(response.Code, response.Message.Trim());
}
```

### 需要在本层处理异常

```csharp
public async Task<Res> GetAsync(CancellationToken cancellationToken)
{
    try
    {
        return await _client.GetAsync(cancellationToken);
    }
    catch (HttpRequestException exception)
    {
        throw new ServiceUnavailableException(
            "下游服务不可用。",
            exception);
    }
}
```

如果在 `try` 中直接 `return _client.GetAsync(...)`，`try` 的同步范围在任务完成前就结束，后续异步异常不会被该 `catch` 捕获。

### 需要让 using 覆盖整个异步操作

```csharp
public async Task<Res> ReadAsync(CancellationToken cancellationToken)
{
    await using Stream stream = OpenStream();
    return await ReadResponseAsync(stream, cancellationToken);
}
```

如果直接返回 `ReadResponseAsync` 的任务，当前方法退出时资源可能过早释放。`await` 可以让资源作用域持续到异步操作完成。

### 需要 finally 在完成后执行

```csharp
public async Task<Res> GetMeasuredAsync(
    CancellationToken cancellationToken)
{
    long startedAt = Stopwatch.GetTimestamp();

    try
    {
        return await _client.GetAsync(cancellationToken);
    }
    finally
    {
        _metrics.RecordElapsed(
            Stopwatch.GetElapsedTime(startedAt));
    }
}
```

### 需要改善本层异步调用链的可观测性

直接返回任务会省去一层状态机，但也意味着本方法没有自己的异步 continuation。现代 .NET 对 async 堆栈已有较好支持；在诊断价值明显高于微小开销时，保留 `await` 是合理的工程选择。

## 常见场景与推荐写法

### 同步缓存命中，未命中时异步读取

这种“经常同步完成、偶尔异步等待”的 API 适合保留真正的异步慢路径：

```csharp
public Task<Res> GetAsync(
    string key,
    CancellationToken cancellationToken)
{
    ArgumentException.ThrowIfNullOrWhiteSpace(key);

    if (_cache.TryGetValue(key, out Res? cached))
    {
        return Task.FromResult(cached);
    }

    return LoadAndCacheAsync(key, cancellationToken);
}

private async Task<Res> LoadAndCacheAsync(
    string key,
    CancellationToken cancellationToken)
{
    Res result = await _repository.LoadAsync(
        key,
        cancellationToken);

    _cache[key] = result;
    return result;
}
```

外层快路径不需要状态机；慢路径仍使用 `async` / `await` 表达真实异步流程。

### 为接口提供同步占位实现

接口要求 `Task<Res>`，但某个实现的数据天然已经在内存中：

```csharp
public interface IHealthProbe
{
    Task<Res> CheckAsync(CancellationToken cancellationToken);
}

public sealed class InMemoryHealthProbe : IHealthProbe
{
    private static readonly Task<Res> HealthyTask =
        Task.FromResult(new Res(0, "Healthy"));

    public Task<Res> CheckAsync(
        CancellationToken cancellationToken)
    {
        return cancellationToken.IsCancellationRequested
            ? Task.FromCanceled<Res>(cancellationToken)
            : HealthyTask;
    }
}
```

### 只有副作用、没有结果

如果返回的是非泛型 `Task`，同步完成时使用 `Task.CompletedTask`：

```csharp
public Task WarmUpAsync()
{
    _cache.WarmUpSynchronously();
    return Task.CompletedTask;
}
```

同样要注意：`WarmUpSynchronously` 仍然同步占用调用线程。方法名是否应该带 `Async`，取决于它是否在实现接口或统一的 TAP 契约；对于新设计的纯同步 API，通常直接提供同步方法更诚实。

### 如果能够设计新 API，先问它是否真的异步

如果一个操作永远同步完成，又没有必须遵守的异步接口，优先提供同步 API：

```csharp
public Res Get()
{
    return new Res(0, "OK");
}
```

不要仅因为上层使用 `await`，就把所有叶子方法都包装成 `Task.FromResult`。异步签名应表达操作可能异步完成或为了多态契约必须返回可等待对象。

## 基准测试方法

不要用一次 `Stopwatch` 调用得出结论。JIT 预热、内联、死代码消除、GC 和运行时版本都会影响纳秒级结果。建议使用 BenchmarkDotNet，并同时观察时间和分配：

```csharp
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Jobs;
using BenchmarkDotNet.Running;

BenchmarkRunner.Run<CompletedTaskBenchmarks>();

[MemoryDiagnoser]
[SimpleJob(warmupCount: 2, iterationCount: 3)]
public class CompletedTaskBenchmarks
{
    private static readonly Res Result = new(0, "OK");

    [Benchmark(Baseline = true)]
    public Task<Res> FromResult()
    {
        return Task.FromResult(Result);
    }

#pragma warning disable CS1998
    [Benchmark]
    public async Task<Res> AsyncWithoutAwait()
    {
        return Result;
    }
#pragma warning restore CS1998

    [Benchmark]
    public async Task<Res> AwaitCompletedTask()
    {
        return await Task.FromResult(Result);
    }
}

public sealed record Res(int Code, string Message);
```

运行：

```powershell
dotnet add package BenchmarkDotNet
dotnet run -c Release
```

一次本机验证结果如下，仅用于展示数量级和分配关系，不能当作跨环境常数：

| 环境 | 值 |
| --- | --- |
| Runtime | .NET 10.0.2，X64 RyuJIT |
| CPU | Intel Core Ultra 5 125H |
| BenchmarkDotNet | 0.15.8 |
| GC | Concurrent Workstation |

| 方法 | Mean | Allocated |
| --- | ---: | ---: |
| `FromResult` | 9.909 ns | 72 B |
| `AsyncWithoutAwait` | 14.869 ns | 72 B |
| `AwaitCompletedTask` | 24.695 ns | 144 B |

这个结果说明：无 `await` 的 `async` 方法与直接 `Task.FromResult` 都只为同一个未缓存的引用结果创建一个完成任务，因此分配量相同；前者主要多出状态机 / builder 的执行成本。`await Task.FromResult(...)` 先创建一个源任务，再由当前异步方法创建自己的结果任务，所以这个特定基准中分配翻倍。

预期观察方向，而不是跨机器固定数字：

- `FromResult` 通常具有最少的控制流开销。
- `AsyncWithoutAwait` 通常分配量与相同结果的 `FromResult` 接近，但会多出状态机 / builder 的指令成本。
- `AwaitCompletedTask` 虽然走同步完成快路径，仍通常比直接返回多一层 `await` 处理。
- 如果结果没有命中任务缓存，三者都可能显示一次 `Task<Res>` 分配。
- 如果把结果改成可缓存的 `bool` 或小整数，现代 .NET 上可能看到零 Task 分配，此时时间差异更能体现状态机的纯指令开销。

基准报告必须记录目标框架、.NET 运行时版本、CPU、GC 模式和 BenchmarkDotNet 版本。不要把某个版本的缓存范围或对象大小当作跨版本 API 保证。

仓库内还提供了一个不依赖第三方包的[可运行伴随示例](/DotNet/Examples/AsyncTaskComparison/README.md)，用于验证完成任务与异常出现时机。

## 常见误区

### async 表示在新线程运行

错误。`async` 只允许使用 `await` 并触发编译器转换。方法在当前线程同步执行到首个未完成的 `await`；`Task.FromResult` 也完全不调度线程。

### Task.FromResult 会延迟执行表达式

错误。参数必须先被求值，才能调用 `Task.FromResult`：

```csharp
return Task.FromResult(QueryDatabaseSynchronously());
```

数据库查询先同步完成，然后才得到一个已完成任务。

### async 方法每次必然分配状态机对象

错误。编译器通常生成结构体状态机，同步完成时它可以留在栈上。发生真正的异步挂起时，才通常需要堆上状态。

### Task.FromResult 永远不分配

错误。只有部分结果可能命中运行时缓存。任意业务对象通常仍需要一个已完成的 `Task<T>`；对象结果本身也可能是新分配的。

### await Task.FromResult 可以“模拟异步”

错误。下面的 `await` 会立即同步完成，既不让出线程，也不增加并发能力：

```csharp
public async Task<Res> GetAsync()
{
    return await Task.FromResult(new Res(0, "OK"));
}
```

它通常只是同时引入 `Task.FromResult` 和状态机两层包装。

### 为消除状态机，任何地方都应该直接返回 Task

错误。需要结果转换、异步异常处理、`using` / `finally` 生命周期或清晰调用链时，`async` / `await` 提供的是正确性和可维护性，而不只是语法糖。

### ValueTask 总是更快

错误。`ValueTask<T>` 可以减少高同步完成率热路径上的 `Task<T>` 分配，但它更大、消费约束更多，组合和多次等待也更容易出错。只有基准测试证明 `Task<T>` 分配是瓶颈，并且 API 消费者能够遵守约束时，才应考虑它。

## 决策表

| 方法内部情况 | 推荐写法 | 原因 |
| --- | --- | --- |
| 已有同步结果，但接口要求 `Task<Res>` | `return Task.FromResult(result);` | 没有必要生成状态机。 |
| 无结果且已经同步完成 | `return Task.CompletedTask;` | 复用已完成的非泛型任务。 |
| 需要返回失败或取消状态 | `Task.FromException<Res>` / `Task.FromCanceled<Res>` | 显式表达任务状态。 |
| 只透明转发已有 `Task<Res>` | `return dependency.GetAsync(...);` | 避免无意义包装。 |
| 等待后还要转换结果 | `async` + `await` | 需要 continuation 保存后续逻辑。 |
| 要捕获异步异常 | `async` + `await`，并把 `await` 放在 `try` 内 | 直接返回任务时，本层 `catch` 捕获不到其后续异步异常。 |
| 资源必须活到异步操作完成 | `async` + `await using` / `using` | 保证释放时机正确。 |
| 操作永远同步且可重新设计 API | 直接返回 `Res` | 不伪装成异步操作。 |
| 同步完成率极高且分配已成为热点 | 先基准测试，再评估 `ValueTask<Res>` | 用复杂度换分配收益必须有数据支持。 |

一句话总结：**有真实异步控制流时使用 `async` / `await`；只有现成结果时返回完成任务；只有现成任务时通常直接透传。先保证语义正确，再用基准数据决定是否优化。**

## 参考资料

### 官方资料

1. [`async` 关键字 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/keywords/async)
2. [异步返回类型 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/asynchronous-programming/async-return-types)
3. [`Task.FromResult<TResult>` 方法 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.tasks.task.fromresult?view=net-10.0)
4. [`Task.CompletedTask` 属性 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.tasks.task.completedtask?view=net-10.0)
5. [`Task.FromException<TResult>` 方法 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.tasks.task.fromexception?view=net-10.0)
6. [`Task.FromCanceled<TResult>` 方法 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.tasks.task.fromcanceled?view=net-10.0)
7. [基于任务的异步模式（TAP）- Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/standard/asynchronous-programming-patterns/task-based-asynchronous-pattern-tap)
8. [async / await 编译器错误与警告（含 CS1998）- Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/compiler-messages/async-await-errors)
9. [How async/await really works - .NET Blog](https://devblogs.microsoft.com/dotnet/how-async-await-really-works/)
10. [Understanding the Whys, Whats, and Whens of ValueTask - .NET Blog](https://devblogs.microsoft.com/dotnet/understanding-the-whys-whats-and-whens-of-valuetask/)
11. [Task.FromResult 在 .NET 6+ 可能返回缓存实例 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/core/compatibility/core-libraries/6.0/task-fromresult-returns-singleton)
12. [创建和引发异常：Task 返回方法中的异常 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/fundamentals/exceptions/creating-and-throwing-exceptions)
13. [C# 语言规范：Task 类型生成器模式 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/language-specification/classes#15142-task-type-builder-pattern)
14. [C# 语言规范：返回 Task 的 async 函数求值 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/language-specification/classes#15143-evaluation-of-a-task-returning-async-function)

### 运行时源码

1. [`Task.FromResult` 与任务缓存 - dotnet/runtime](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Threading/Tasks/Task.cs)
2. [`AsyncTaskMethodBuilder<TResult>`（同步 `SetResult` 路径）- dotnet/runtime](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/Runtime/CompilerServices/AsyncTaskMethodBuilderT.cs)
