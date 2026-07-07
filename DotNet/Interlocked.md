# <center>Interlocked</center>

## 目录

- [Interlocked 是什么](#interlocked-是什么)
- [为什么需要原子操作](#为什么需要原子操作)
- [常用 API](#常用-api)
- [典型使用场景](#典型使用场景)
- [代码示例](#代码示例)
- [Interlocked、Volatile 和 lock 的区别](#interlockedvolatile-和-lock-的区别)
- [关键注意事项](#关键注意事项)
- [参考资料](#参考资料)

## Interlocked 是什么

`Interlocked` 是 .NET 在 `System.Threading` 命名空间中提供的原子操作工具类，用于对多个线程共享的变量执行不可中断的读、写、交换、递增、递减、比较交换等操作。

它适合处理“单个内存位置”的轻量级并发更新，例如计数器、状态标志、一次性初始化标记等。相比 `lock` / `Monitor`，`Interlocked` 不会进入互斥锁临界区，也不会阻塞等待锁对象，因此在简单高频操作中通常更轻量。

需要注意：`Interlocked` 不是 `lock` 的完全替代品。它保证的是某一次原子操作本身的正确性，不负责保护多字段一致性，也不适合表达复杂业务逻辑。

## 为什么需要原子操作

很多看起来简单的语句并不是原子的。例如：

```csharp
counter++;
```

它通常可以拆成三个步骤：

1. 从内存读取 `counter` 的当前值。
2. 在寄存器中加 `1`。
3. 把结果写回 `counter`。

如果两个线程同时执行这段逻辑，就可能都读到相同的旧值，然后分别写回相同的新值，导致其中一次递增丢失。

`Interlocked.Increment(ref counter)` 会把“读取、加一、写回”作为一个原子操作完成，从而避免这种竞争条件。

## 常用 API

| API | 作用 | 返回值 | 常见用途 |
| --- | --- | --- | --- |
| `Increment(ref location)` | 原子递增 `1`。 | 递增后的新值。 | 请求计数、任务完成数。 |
| `Decrement(ref location)` | 原子递减 `1`。 | 递减后的新值。 | 引用计数、剩余任务数。 |
| `Add(ref location, value)` | 原子加上指定整数。 | 相加后的新值。 | 批量累加、统计指标。 |
| `Exchange(ref location, value)` | 原子替换变量值。 | 替换前的旧值。 | 状态切换、发布引用、清零并取旧值。 |
| `CompareExchange(ref location, value, comparand)` | 如果当前值等于 `comparand`，则替换为 `value`。 | 替换前的旧值。 | CAS、无锁更新、一次性初始化。 |
| `Read(ref long location)` / `Read(ref ulong location)` | 原子读取 64 位整数。 | 读取到的值。 | 32 位平台上的 64 位安全读取。 |
| `And(ref location, value)` / `Or(ref location, value)` | 原子按位与 / 按位或。 | 操作前的旧值。 | 位标志更新。 |
| `MemoryBarrier()` | 插入当前线程内的内存屏障。 | 无。 | 底层并发原语，业务代码很少直接使用。 |

部分方法支持 `int`、`long`、`uint`、`ulong`、`nint`、`nuint`、`IntPtr`、`UIntPtr` 等数值类型；`Exchange` 和 `CompareExchange` 还支持引用类型以及部分浮点类型。具体重载应以当前目标框架的官方 API 为准。

## 典型使用场景

### 高频计数器

例如统计请求数、缓存命中数、对象创建总数、任务完成数量等。只要操作是单变量递增、递减或累加，`Interlocked` 通常比 `lock` 更直接。

### 状态标志切换

例如“只允许一个线程启动任务”“只执行一次初始化”“把运行状态从 0 切到 1”。这类场景经常使用 `CompareExchange` 判断旧状态并原子切换。

### 原子发布或替换引用

例如更新一个共享缓存对象、替换配置快照、交换当前处理器实例等。`Exchange` 可以在发布新引用的同时拿到旧引用。

### 无锁数据结构

无锁栈、无锁队列等底层结构通常依赖 `CompareExchange` 加循环重试。普通业务代码不建议轻易手写复杂无锁结构，因为 ABA 问题、内存回收、竞争退避都会让实现难度显著上升。

## 代码示例

### 线程安全计数器

```csharp
using System;
using System.Threading;
using System.Threading.Tasks;

class Program
{
    private static int _counter;

    static async Task Main()
    {
        Task[] tasks = new Task[10];

        for (int i = 0; i < tasks.Length; i++)
        {
            tasks[i] = Task.Run(() =>
            {
                for (int j = 0; j < 1000; j++)
                {
                    Interlocked.Increment(ref _counter);
                }
            });
        }

        await Task.WhenAll(tasks);

        Console.WriteLine($"最终计数值: {_counter}");
    }
}
```

这里如果写成 `_counter++`，多个线程并发时可能丢失更新；使用 `Interlocked.Increment` 后，每次递增都是不可分割的原子操作。

### 原子切换状态

```csharp
using System;
using System.Threading;
using System.Threading.Tasks;

class Worker
{
    private int _started;

    public Task StartAsync()
    {
        if (Interlocked.CompareExchange(ref _started, 1, 0) != 0)
        {
            throw new InvalidOperationException("Worker 已经启动。");
        }

        return RunAsync();
    }

    private static async Task RunAsync()
    {
        await Task.Delay(1000);
    }
}
```

`CompareExchange(ref _started, 1, 0)` 的含义是：只有当 `_started` 当前值仍然是 `0` 时，才把它改成 `1`。如果返回值不是 `0`，说明已经有其他线程抢先完成了状态切换。

### 使用 CAS 循环实现复合单变量更新

`Interlocked` 没有“原子乘法”或“按自定义规则更新”的直接 API。可以用 `CompareExchange` 写一个 CAS 循环：

```csharp
using System.Threading;

class ScoreBoard
{
    private int _score;

    public int AddBonus(int bonus)
    {
        while (true)
        {
            int snapshot = Volatile.Read(ref _score);
            int next = snapshot + bonus * 2;

            int original = Interlocked.CompareExchange(
                ref _score,
                next,
                snapshot);

            if (original == snapshot)
            {
                return next;
            }
        }
    }
}
```

循环中的 `snapshot` 只是一个快照。若其他线程在当前线程写入前改过 `_score`，`CompareExchange` 会失败并返回新的旧值，当前线程再重新计算。

这种写法只适合更新单个变量。如果计算依赖多个字段的一致快照，通常应该使用 `lock`。

### 清零并获取旧值

统计类场景里，经常需要“把计数器清零，并拿到清零前的数值”：

```csharp
using System.Threading;

class Metrics
{
    private int _requestCount;

    public void IncrementRequestCount()
    {
        Interlocked.Increment(ref _requestCount);
    }

    public int ResetAndGetCount()
    {
        return Interlocked.Exchange(ref _requestCount, 0);
    }
}
```

`Exchange` 可以避免“先读旧值，再写 0”之间被其他线程插入更新。

## Interlocked、Volatile 和 lock 的区别

| 维度 | Interlocked | Volatile | lock |
| --- | --- | --- | --- |
| 核心能力 | 单变量原子读改写。 | 控制单次读写的可见性和重排序。 | 保护一段临界区。 |
| 是否互斥 | 否。 | 否。 | 是。 |
| 是否适合多字段一致性 | 不适合。 | 不适合。 | 适合。 |
| 常见用途 | 计数器、状态切换、CAS。 | 发布/观察状态标志、配合底层并发逻辑。 | 复杂状态修改、集合操作、业务事务。 |
| 使用难度 | 中等，CAS 循环需要谨慎。 | 偏高，容易误解内存模型。 | 较低，语义更清晰。 |

一般建议：

- 单个整数递增、递减、累加：优先考虑 `Interlocked`。
- 一个线程发布状态，另一个线程只观察状态变化：可以考虑 `Volatile.Read` / `Volatile.Write`，但要清楚它不提供互斥。
- 多个字段必须一起保持一致，或逻辑包含多步业务判断：优先使用 `lock`。

## 关键注意事项

### ref 参数必须指向可取地址的变量

`Interlocked` 方法通常要求 `ref` 参数，因此目标必须是字段、局部变量或数组元素等可取地址的位置。

```csharp
private int _count;

public int Count
{
    get => Volatile.Read(ref _count);
}

public void Increment()
{
    Interlocked.Increment(ref _count);
}
```

不能直接对自动属性调用：

```csharp
public int Count { get; private set; }

// 编译错误：属性不是变量，不能作为 ref 参数传入。
Interlocked.Increment(ref Count);
```

### 只保护一个内存位置

下面这种逻辑不是整体原子的：

```csharp
if (_stock > 0)
{
    Interlocked.Decrement(ref _stock);
}
```

检查 `_stock > 0` 和递减之间可能被其他线程插入。若库存不能减成负数，应使用 `CompareExchange` 循环，或直接用 `lock` 包住完整逻辑。

### 不要混用同步策略

如果某个字段用 `Interlocked` 更新，就尽量让该字段的所有并发读写都采用同一套策略，例如 `Interlocked`、`Volatile.Read` 或受同一把锁保护。最危险的写法是有的地方原子更新，有的地方普通读写，还有的地方用另一把锁保护，这会让代码很难推理。

### 读取也要考虑可见性

对 `int` 这类类型，普通读取本身通常是原子的，但这不等于它一定满足你想要的线程间可见性语义。读取由其他线程频繁更新的字段时，常见选择是：

```csharp
int current = Volatile.Read(ref _counter);
```

如果读取动作本身也需要和更新动作绑定成一个不可分割的读改写操作，则应继续使用对应的 `Interlocked` 方法。

### 64 位读取的特殊性

`Interlocked.Read(ref long)` 和 `Interlocked.Read(ref ulong)` 主要用于 32 位平台，因为 32 位平台上的普通 64 位读取可能不是原子的。在 64 位平台上，64 位读取本身已经是原子的。

官方文档还特别说明：在 32 位平台上，`Interlocked.Read` 内部可能需要通过 `CompareExchange` 保证原子性，因此即使参数形式允许只读引用，也可能需要对该内存位置拥有写访问权限。

### 浮点数支持有限

`Exchange` 和 `CompareExchange` 有 `float` / `double` 重载，但没有 `Interlocked.Add(ref double, double)` 这种原子浮点累加 API。需要并发累加浮点值时，通常使用 `lock`，或根据业务改用整数刻度值。

### CAS 循环可能自旋

`CompareExchange` 循环在竞争激烈时可能反复失败并重试，导致 CPU 消耗上升。高竞争、复杂计算、长时间循环的场景，`lock` 可能更简单也更稳定。

### 只适用于同一进程内的共享内存

`Interlocked` 解决的是同一进程内多个线程访问共享变量的问题。跨进程、跨机器、多实例部署时，应使用数据库事务、分布式锁、Redis `INCR`、消息队列等外部一致性机制。

## 参考资料

### 官方资料

1. [Interlocked 类 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.interlocked?view=net-10.0)
2. [Interlocked.Read 方法 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.interlocked.read?view=net-10.0)
3. [Interlocked.MemoryBarrier 方法 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.interlocked.memorybarrier?view=net-10.0)
4. [Volatile 类 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.volatile?view=net-10.0)

### 延伸阅读

1. [C# Interlocked 原子操作](https://www.cnblogs.com/Manuel/p/13456640.html)
2. [Interlocked 原子操作介绍](https://juejin.cn/post/7551254626882224138)
3. [.NET 多线程同步之 Interlocked](https://www.cnblogs.com/TangQF/articles/19445422)
4. [C# Memory Model in Theory and Practice - Microsoft Learn](https://learn.microsoft.com/en-us/archive/msdn-magazine/2012/december/csharp-the-csharp-memory-model-in-theory-and-practice)
