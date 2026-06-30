# <center>ExecutionContext 和 SynchronizationContext</center>

## 目录

- [ExecutionContext](#executioncontext)
- [SynchronizationContext](#synchronizationcontext)
- [两者对比](#两者对比)
- [常见误区](#常见误区)
- [参考资料](#参考资料)

## ExecutionContext

`ExecutionContext` 表示“逻辑执行流”的环境数据容器。它关注的不是代码在哪个物理线程上运行，而是当异步代码从一个线程切换到另一个线程时，哪些环境信息应该跟着这条逻辑调用链一起移动。

常见会随 `ExecutionContext` 流动的内容包括：

- `AsyncLocal<T>` 中保存的环境数据，例如请求 ID、租户 ID、链路追踪 ID。
- 当前区域性信息，例如 `CultureInfo.CurrentCulture`。
- 在 .NET Framework 中，还可能包含安全上下文、调用上下文和同步上下文等信息。
- 在 .NET Core / .NET 5+ 中，安全上下文和调用上下文不再按 .NET Framework 的方式支持；`SynchronizationContext` 也不会随 `ExecutionContext` 一起流动。

### 为什么需要它

同步代码通常运行在同一个线程上，`ThreadStatic` 或 `ThreadLocal<T>` 一类的线程本地数据看起来足够好用。但在异步代码中，`await` 之后的继续执行可能发生在另一个线程上。如果仍然只依赖线程本地数据，请求 ID、区域性等环境信息就可能丢失。

`ExecutionContext` 的作用就是在异步边界处捕获这些环境信息，并在后续继续执行时恢复它们，让异步代码尽量保持和同步代码相近的语义。

### 代码示例：AsyncLocal 随执行上下文流动

```csharp
using System;
using System.Threading;
using System.Threading.Tasks;

class Program
{
    private static readonly AsyncLocal<string?> TraceId = new();

    static async Task Main()
    {
        TraceId.Value = "trace-001";

        await Task.Run(() =>
        {
            Console.WriteLine(TraceId.Value); // trace-001
        });

        Task task;
        using (ExecutionContext.SuppressFlow())
        {
            task = Task.Run(() =>
            {
                Console.WriteLine(TraceId.Value ?? "<null>"); // <null>
            });
        }

        await task;
    }
}
```

这个示例里，第一次 `Task.Run` 会捕获调用方的 `ExecutionContext`，所以后台任务能读到 `AsyncLocal<T>` 的值。第二次调用前使用了 `ExecutionContext.SuppressFlow()`，因此新任务不会继承当前执行上下文。

注意：不要让 `SuppressFlow()` 的作用域跨越 `await`。它返回的 `AsyncFlowControl` 需要在原来的执行流中恢复，最稳妥的写法是像上面这样先创建任务，再离开 `using`，最后再 `await`。

### 常用 API

| API | 作用 |
| --- | --- |
| `ExecutionContext.Capture()` | 捕获当前执行上下文；如果已经禁止流动，可能返回 `null`。 |
| `ExecutionContext.Run(...)` | 在指定执行上下文中运行回调。 |
| `ExecutionContext.SuppressFlow()` | 禁止当前执行上下文流入后续异步操作。 |
| `ExecutionContext.RestoreFlow()` | 恢复执行上下文流动；通常更推荐使用 `SuppressFlow()` 返回值的 `Dispose()`。 |

一般业务代码很少需要直接调用 `Capture()` 和 `Run()`。更常见的入口是 `AsyncLocal<T>`，或者在性能敏感、需要刻意隔离环境数据的场景里短暂使用 `SuppressFlow()`。

## SynchronizationContext

`SynchronizationContext` 是一种“调度抽象”。它描述的是：一段代码应该被投递到什么环境中执行。

它最典型的用途是 UI 框架。WinForms、WPF 等 UI 框架要求控件只能在创建它的 UI 线程上访问，因此后台线程完成工作后，需要把更新 UI 的回调切回 UI 线程。不同 UI 框架有不同的派发机制，`SynchronizationContext` 用统一的 `Post` / `Send` API 抽象了这些差异。

常见实现包括：

- WinForms：`WindowsFormsSynchronizationContext`。
- WPF：`DispatcherSynchronizationContext`。
- 单元测试框架或自定义运行环境：可能实现自己的 `SynchronizationContext`，例如限制并发度。
- 控制台应用和 ASP.NET Core：通常没有自定义 `SynchronizationContext`，`SynchronizationContext.Current` 往往是 `null`。

### Post 和 Send

| API | 特点 | 常见用途 |
| --- | --- | --- |
| `Post(callback, state)` | 异步投递，不等待回调执行完成。 | 从后台线程切回 UI 线程更新界面。 |
| `Send(callback, state)` | 同步投递，调用方等待回调执行完成。 | 少量必须同步完成的框架级场景。 |

业务代码里优先使用 `Post` 或直接使用 `async` / `await`。在 UI 线程或单线程上下文里滥用 `Send`、`.Result`、`.Wait()`，很容易造成阻塞或死锁。

### 代码示例：手动切回 UI 上下文

```csharp
private void button1_Click(object? sender, EventArgs e)
{
    SynchronizationContext uiContext =
        SynchronizationContext.Current
        ?? throw new InvalidOperationException("需要在 UI 线程调用。");

    button1.Text = "运算中...";
    button1.Enabled = false;

    Task.Run(() =>
    {
        Thread.Sleep(3000);

        uiContext.Post(_ =>
        {
            button1.Text = "点击运算";
            button1.Enabled = true;
        }, null);
    });
}
```

这里在 UI 线程中捕获 `SynchronizationContext.Current`，后台任务完成后通过 `Post` 把更新 UI 的回调派发回 UI 线程。

### async/await 与 SynchronizationContext

在 UI 应用中，直接使用 `await` 通常已经足够：

```csharp
private async void button1_Click(object? sender, EventArgs e)
{
    button1.Text = "运算中...";
    button1.Enabled = false;

    try
    {
        await Task.Run(() => Thread.Sleep(3000));
        button1.Text = "点击运算";
    }
    finally
    {
        button1.Enabled = true;
    }
}
```

默认情况下，`await Task` 会捕获当前 `SynchronizationContext`；如果没有同步上下文，则会考虑当前非默认 `TaskScheduler`。因此在 UI 事件处理器里，`await` 之后的代码通常会回到 UI 线程执行。

如果使用 `await task.ConfigureAwait(false)`，则表示后续代码不强制回到捕获到的 `SynchronizationContext` 或 `TaskScheduler`。这常用于类库代码，因为类库通常不应该假设调用方有 UI 上下文，也不应该无谓地把继续执行派发回调用方上下文。

## 两者对比

| 维度 | ExecutionContext | SynchronizationContext |
| --- | --- | --- |
| 解决的问题 | 环境数据如何跟随逻辑执行流。 | 代码应该被调度到哪里执行。 |
| 关注点 | “带着什么上下文运行”。 | “在哪个上下文运行”。 |
| 典型数据或实现 | `AsyncLocal<T>`、区域性、模拟上下文等。 | UI 线程、消息循环、并发限制器、自定义调度环境。 |
| 是否自动参与 `await` | 是，运行时会自动流动执行上下文。 | 对 `Task` await，默认会捕获当前同步上下文；可用 `ConfigureAwait(false)` 跳过。 |
| 常用控制方式 | `AsyncLocal<T>`、`SuppressFlow()`。 | `Current`、`Post()`、`Send()`、`SetSynchronizationContext()`。 |
| 常见风险 | 滥用 `AsyncLocal<T>` 会增加异步流动成本，也可能造成隐式依赖。 | 同步阻塞或错误使用 `Send` 可能导致 UI 卡顿、死锁。 |

一句话区分：

- `ExecutionContext` 像是跟着异步调用链一起走的“环境数据包”。
- `SynchronizationContext` 像是告诉代码“回到哪个地方执行”的调度入口。

## 常见误区

### ConfigureAwait(false) 不会关闭 ExecutionContext

`ConfigureAwait(false)` 影响的是是否继续使用捕获到的 `SynchronizationContext` 或非默认 `TaskScheduler`。它不会阻止 `ExecutionContext` 流动，所以 `AsyncLocal<T>` 的值通常仍然会跨 `await` 保留。

如果确实要阻止执行上下文流入新任务，需要使用 `ExecutionContext.SuppressFlow()`，并且要非常谨慎地限定作用域。

### SynchronizationContext 不等于线程

很多 UI 场景里，一个 `SynchronizationContext` 最终会把回调派发到 UI 线程，所以容易把它理解成“线程”。但它本质上是调度模型抽象，具体实现可以决定把回调放进消息循环、线程池、并发限制队列，或者其他执行环境。

### 控制台程序里 Current 可能是 null

不要假设 `SynchronizationContext.Current` 一定存在。控制台程序、后台服务、ASP.NET Core 中通常没有自定义同步上下文。需要切回特定线程或调度器时，应显式建立自己的调度机制。

### 不要轻易手写 ExecutionContext.Capture/Run

`Task.Run`、线程池、`await` 等运行时定义的异步点通常已经处理了 `ExecutionContext` 的捕获和恢复。除非在写底层框架、调度器、性能敏感库，否则大多数代码不需要手动操作它。

## 参考资料

### 官方资料

1. [ExecutionContext vs SynchronizationContext - .NET Blog](https://devblogs.microsoft.com/dotnet/executioncontext-vs-synchronizationcontext/)
2. [ConfigureAwait FAQ - .NET Blog](https://devblogs.microsoft.com/dotnet/configureawait-faq/)
3. [ExecutionContext 类 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.executioncontext?view=net-10.0)
4. [SynchronizationContext 类 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.synchronizationcontext?view=net-10.0)
5. [AsyncLocal\<T\> 类 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.asynclocal-1?view=net-10.0)

### 延伸阅读

1. [C# 中的 ExecutionContext 和 SynchronizationContext](https://zhuanlan.zhihu.com/p/378386442?share_code=K0BIbVJXFXhr&utm_psn=1926690459117401047)
2. [C# SynchronizationContext 和 ExecutionContext 使用总结](https://www.cnblogs.com/wwkk/p/17814057.html)
3. [理解 C# 中的 ExecutionContext vs SynchronizationContext](https://www.cnblogs.com/xiaoxiaotank/p/13666913.html)
