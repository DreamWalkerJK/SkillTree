# <center>多线程并发访问 HashSet</center>

## 目录

- [问题现象](#问题现象)
- [根本原因](#根本原因)
- [常见触发场景](#常见触发场景)
- [解决方案](#解决方案)
- [方案选择建议](#方案选择建议)
- [常见误区](#常见误区)
- [排查清单](#排查清单)
- [HashSet 基础补充](#hashset-基础补充)
- [参考资料](#参考资料)

## 问题现象

`HashSet<T>` 是基于哈希表的唯一元素集合，适合单线程或外部已同步的场景。它本身不是线程安全集合，如果多个线程同时读写同一个 `HashSet<T>` 实例，可能出现以下问题：

- `InvalidOperationException: Collection was modified; enumeration operation may not execute.`
- `IndexOutOfRangeException`、状态不一致、元素丢失、`Count` 不准确等非确定性异常。
- `Contains`、`Add`、`Remove` 的结果不符合预期。
- 在高并发、大数据量、频繁扩容时，问题更容易暴露。

官方文档的核心结论是：

- `System.Collections.Generic` 下的默认泛型集合不提供线程同步。
- 如果多个线程会并发添加或删除元素，调用方必须自己同步，或者改用 `System.Collections.Concurrent` 下的并发集合。
- 枚举集合时，如果集合被修改，枚举器会失效；要保证枚举安全，需要在整个枚举期间加锁，或先创建快照。

## 根本原因

`HashSet<T>` 内部维护桶数组、元素数组、数量、空闲链表和版本号等可变状态。`Add`、`Remove`、`Clear`、`UnionWith`、`IntersectWith` 等操作都会修改这些内部状态。

并发访问的问题主要来自以下几类数据竞争：

1. 多个线程同时 `Add`，可能同时触发扩容或写入同一批内部数组。
2. 一个线程 `Contains` 或枚举时，另一个线程正在 `Add`、`Remove` 或 `Clear`。
3. `Contains` 再 `Add` 这种组合操作不是原子的，两个线程可能同时判断“不存在”，然后同时执行后续逻辑。
4. `HashSet<T>` 元素如果是可变对象，并且参与相等比较或哈希计算的字段被修改，会导致元素落在错误的哈希位置，进一步造成 `Contains` / `Remove` 失效。

## 常见触发场景

### 1. Parallel.ForEach / Task.WhenAll 中共享 HashSet

错误示例：

```csharp
var visited = new HashSet<int>();

await Parallel.ForEachAsync(items, async (item, ct) =>
{
    if (!visited.Contains(item.Id))
    {
        visited.Add(item.Id);
        await ProcessAsync(item, ct);
    }
});
```

`Contains` 和 `Add` 都访问了共享集合，而且这两个操作之间没有同步保护。

### 2. 一个线程枚举，另一个线程修改

错误示例：

```csharp
foreach (var id in ids)
{
    Console.WriteLine(id);
}

// 另一个线程同时执行
ids.Remove(expiredId);
```

枚举器没有独占访问权。只要枚举过程中集合被修改，枚举器就可能失效。

### 3. 缓存、去重集合被多个请求共享

例如把 `HashSet<T>` 放在 singleton 服务、静态字段、后台任务全局缓存中，然后多个 HTTP 请求或消息消费线程同时读写。

### 4. Contains + Add 表示“只处理一次”

错误示例：

```csharp
if (!processedIds.Contains(id))
{
    processedIds.Add(id);
    SendMessage(id);
}
```

即使单个 `Contains` 和 `Add` 分别加锁，如果没有把“检查并加入”作为一个整体同步，也仍然可能重复处理。

## 解决方案

### 方案一：使用 lock 保护 HashSet

适合逻辑简单、读写频率不极端、需要保持 `HashSet<T>` 完整 Set 语义的场景。

```csharp
public sealed class LockedHashSet<T>
{
    private readonly HashSet<T> _set = new();
    private readonly object _syncRoot = new();

    public bool Add(T item)
    {
        lock (_syncRoot)
        {
            return _set.Add(item);
        }
    }

    public bool Remove(T item)
    {
        lock (_syncRoot)
        {
            return _set.Remove(item);
        }
    }

    public bool Contains(T item)
    {
        lock (_syncRoot)
        {
            return _set.Contains(item);
        }
    }

    public T[] Snapshot()
    {
        lock (_syncRoot)
        {
            return _set.ToArray();
        }
    }
}
```

如果业务逻辑需要“如果不存在就加入并执行后续操作”，应把检查和加入放在同一个锁内：

```csharp
bool shouldProcess;

lock (_syncRoot)
{
    shouldProcess = _processedIds.Add(id);
}

if (shouldProcess)
{
    await ProcessAsync(id, cancellationToken);
}
```

这里不要在 `lock` 中执行慢查询、网络请求或 `await`。锁内只完成集合状态修改，后续耗时操作放到锁外。

### 方案二：使用 ReaderWriterLockSlim

适合读多写少，并且希望多个读线程可以并发读取的场景。

```csharp
public sealed class ReadWriteLockedHashSet<T> : IDisposable
{
    private readonly HashSet<T> _set = new();
    private readonly ReaderWriterLockSlim _lock = new();

    public bool Add(T item)
    {
        _lock.EnterWriteLock();
        try
        {
            return _set.Add(item);
        }
        finally
        {
            _lock.ExitWriteLock();
        }
    }

    public bool Contains(T item)
    {
        _lock.EnterReadLock();
        try
        {
            return _set.Contains(item);
        }
        finally
        {
            _lock.ExitReadLock();
        }
    }

    public T[] Snapshot()
    {
        _lock.EnterReadLock();
        try
        {
            return _set.ToArray();
        }
        finally
        {
            _lock.ExitReadLock();
        }
    }

    public void Dispose()
    {
        _lock.Dispose();
    }
}
```

注意：`ReaderWriterLockSlim` 不是 async-aware 锁，不要在持有读锁或写锁时执行 `await`。如果同步范围需要跨异步代码，通常应重新设计临界区，或者使用 `SemaphoreSlim` 做异步互斥。

### 方案三：用 ConcurrentDictionary 模拟 Set

.NET 标准库没有内置 `ConcurrentHashSet<T>`。如果只需要唯一键、快速判断、并发添加和删除，常用做法是用 `ConcurrentDictionary<T, byte>` 模拟 Set。

```csharp
public sealed class ConcurrentSet<T>
    where T : notnull
{
    private readonly ConcurrentDictionary<T, byte> _items;

    public ConcurrentSet()
        : this(null)
    {
    }

    public ConcurrentSet(IEqualityComparer<T>? comparer)
    {
        _items = new ConcurrentDictionary<T, byte>(comparer);
    }

    public bool Add(T item)
    {
        return _items.TryAdd(item, 0);
    }

    public bool Remove(T item)
    {
        return _items.TryRemove(item, out _);
    }

    public bool Contains(T item)
    {
        return _items.ContainsKey(item);
    }

    public T[] Snapshot()
    {
        return _items.ToArray().Select(pair => pair.Key).ToArray();
    }
}
```

用于“只处理一次”的场景时，`TryAdd` 可以把检查和加入合并成一个原子操作：

```csharp
if (_processedIds.TryAdd(id, 0))
{
    await ProcessAsync(id, cancellationToken);
}
```

`ConcurrentDictionary<TKey, TValue>` 的枚举器可以在读写并发时安全使用，但它不是一个固定时刻的快照。需要稳定快照时，先调用 `ToArray()`。

### 方案四：读多写少时使用 ImmutableHashSet

如果集合更新不频繁，但读取非常频繁，可以使用 `ImmutableHashSet<T>`。每次修改都会返回新集合，旧集合不会变化，因此读线程可以安全读取某个版本。

```csharp
using System.Collections.Immutable;
using System.Threading;

private ImmutableHashSet<string> _blockedIds =
    ImmutableHashSet<string>.Empty.WithComparer(StringComparer.OrdinalIgnoreCase);

public bool ContainsBlockedId(string id)
{
    return Volatile.Read(ref _blockedIds).Contains(id);
}

public void AddBlockedId(string id)
{
    ImmutableInterlocked.Update(ref _blockedIds, set => set.Add(id));
}

public void RemoveBlockedId(string id)
{
    ImmutableInterlocked.Update(ref _blockedIds, set => set.Remove(id));
}
```

这种方式适合配置、黑名单、规则集合等读多写少场景。它不适合高频写入，因为每次修改都会创建新版本并带来额外分配。

### 方案五：完全只读时使用 FrozenSet

如果集合在启动或加载配置时创建，运行期间不再变化，可以使用 `FrozenSet<T>`。它是不可变、只读并且面向高性能查找优化的集合。

```csharp
using System.Collections.Frozen;

private readonly FrozenSet<string> _allowedCodes =
    new[] { "A", "B", "C" }.ToFrozenSet(StringComparer.OrdinalIgnoreCase);

public bool IsAllowed(string code)
{
    return _allowedCodes.Contains(code);
}
```

`FrozenSet<T>` 创建成本较高，但查找性能好，适合“构建一次，多次读取”的场景。

### 方案六：异步场景使用 SemaphoreSlim 做互斥

如果访问 `HashSet<T>` 的入口本身是异步方法，可以使用 `SemaphoreSlim`：

```csharp
private readonly HashSet<string> _set = new();
private readonly SemaphoreSlim _mutex = new(1, 1);

public async Task<bool> AddAsync(string item, CancellationToken cancellationToken)
{
    await _mutex.WaitAsync(cancellationToken);
    try
    {
        return _set.Add(item);
    }
    finally
    {
        _mutex.Release();
    }
}
```

即使用 `SemaphoreSlim`，也应尽量让临界区只包住集合操作，不要把数据库查询、HTTP 请求等慢操作放进互斥区。

## 方案选择建议

| 场景 | 推荐方案 |
| --- | --- |
| 简单并发读写，已有代码使用 `HashSet<T>` | `lock` 包装所有访问 |
| 读多写少，需要保留可变 `HashSet<T>` | `ReaderWriterLockSlim` |
| 高频并发添加、删除、判断唯一性 | `ConcurrentDictionary<T, byte>` 模拟 Set |
| 读多写少，允许每次写入生成新版本 | `ImmutableHashSet<T>` |
| 创建后不再修改，追求读取性能 | `FrozenSet<T>` |
| 异步方法中需要互斥访问 | `SemaphoreSlim` |
| 允许重复、只关心生产消费 | `ConcurrentBag<T>`、`ConcurrentQueue<T>` 等并发集合 |

## 常见误区

### ConcurrentBag 不是 HashSet 的替代品

`ConcurrentBag<T>` 是线程安全的无序 Bag，适合多线程生产和消费对象；它允许重复元素，也不支持按值高效删除。它不具备 Set 的唯一性语义，`Contains` 也不是哈希查找，因此通常不适合作为 `HashSet<T>` 的直接替代品。

### 单独给 Contains 和 Add 加锁不够

下面这种写法仍然可能重复处理：

```csharp
if (!Contains(id))
{
    Add(id);
    Process(id);
}
```

因为 `Contains` 和 `Add` 之间可能被其他线程插入。需要把“检查并加入”合并到同一个临界区，或者使用 `ConcurrentDictionary.TryAdd`。

### 只读共享要确保真的不再修改

如果集合构建完成后不会再修改，多个线程共享读取通常没有问题。但只要任意线程可能写入，就必须同步。为了表达“不再修改”的意图，建议暴露为 `IReadOnlySet<T>`、使用 `ImmutableHashSet<T>` 或 `FrozenSet<T>`。

### 枚举时也需要保护

即使每次 `Add` / `Remove` 都加锁，如果枚举时没有加锁，仍然可能在枚举过程中被其他线程修改。常见做法是先在锁内复制快照，再在锁外遍历：

```csharp
string[] snapshot;

lock (_syncRoot)
{
    snapshot = _set.ToArray();
}

foreach (var item in snapshot)
{
    Console.WriteLine(item);
}
```

### 元素的哈希字段不要修改

如果 `HashSet<T>` 中存放的是引用类型，并且 `Equals` / `GetHashCode` 依赖可变字段，那么元素加入集合后不要修改这些字段。否则即使没有多线程，也可能导致 `Contains` 或 `Remove` 找不到元素。

## 排查清单

1. 是否有 singleton、static 字段或全局缓存持有 `HashSet<T>`？
2. 是否有 `Parallel.ForEach`、`Parallel.ForEachAsync`、`Task.WhenAll`、消息队列多消费者并发访问同一个集合？
3. 是否存在 `Contains` 后再 `Add` 的非原子组合操作？
4. 是否一边 `foreach` / LINQ 枚举，一边有其他线程修改集合？
5. 所有 `Add`、`Remove`、`Clear`、`UnionWith`、`IntersectWith`、`ExceptWith` 是否都经过同一把锁？
6. 是否在锁内执行了数据库查询、HTTP 请求、文件 IO 或其他长耗时操作？
7. 集合元素的 `Equals` / `GetHashCode` 是否依赖可变字段？
8. 如果使用 `ConcurrentDictionary`，是否确认需要的是 Set 语义，而不是队列、栈或 Bag 语义？

## HashSet 基础补充

`HashSet<T>` 的主要特点：

- 不允许重复元素。
- 元素没有稳定顺序。
- `Add` 返回 `true` 表示成功加入，返回 `false` 表示元素已存在。
- `Contains`、`Add`、`Remove` 平均时间复杂度接近 O(1)。
- 支持集合运算，例如 `UnionWith`、`IntersectWith`、`ExceptWith`、`SymmetricExceptWith`。

基础示例：

```csharp
var oddNumbers = new HashSet<int>();

for (var i = 0; i < 5; i++)
{
    oddNumbers.Add(2 * i + 1);
}

Console.WriteLine(string.Join(", ", oddNumbers));
```

集合运算示例：

```csharp
var set1 = new HashSet<int> { 1, 2, 3, 4, 5 };
var set2 = new HashSet<int> { 4, 5, 6, 7, 8 };

set1.UnionWith(set2);
Console.WriteLine(string.Join(", ", set1)); // 包含 1 到 8，输出顺序不保证
```

## 参考资料

### 官方资料

1. [HashSet\<T\> Class - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.collections.generic.hashset-1?view=net-10.0)
2. [HashSet\<T\>.GetEnumerator Method - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.collections.generic.hashset-1.getenumerator?view=net-10.0)
3. [Thread-Safe collections - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/standard/collections/thread-safe/)
4. [ConcurrentDictionary\<TKey,TValue\> Class - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.collections.concurrent.concurrentdictionary-2?view=net-10.0)
5. [ConcurrentBag\<T\> Class - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.collections.concurrent.concurrentbag-1?view=net-10.0)
6. [ImmutableHashSet\<T\> Class - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.collections.immutable.immutablehashset-1?view=net-10.0)
7. [FrozenSet\<T\> Class - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.collections.frozen.frozenset-1?view=net-10.0)

### 延伸阅读

1. [C# HashSet 是否线程安全 - 亿速云](https://www.yisu.com/ask/7110559.html)
