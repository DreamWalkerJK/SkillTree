# <center>DistinctBy 性能</center>

## 目录

- [核心结论](#核心结论)
- [API 语义](#api-语义)
- [实现机制](#实现机制)
- [性能表现](#性能表现)
- [与其他去重方式对比](#与其他去重方式对比)
- [代码示例](#代码示例)
- [使用注意事项](#使用注意事项)
- [常见误区](#常见误区)
- [参考资料](#参考资料)

## 核心结论

`DistinctBy` 是 .NET 6 引入的 LINQ 方法，用于按指定 key 对序列去重。它适合“对象整体不方便比较，但可以按某个属性或组合属性判断唯一”的场景，例如按 `UserId`、`Email`、`(TenantId, Code)` 去重。

在 LINQ to Objects 中，`DistinctBy` 基于哈希集合记录已经出现过的 key：

- 平均时间复杂度接近 `O(n)`。
- 额外空间复杂度为 `O(k)`，`k` 是不同 key 的数量，最坏为 `O(n)`。
- 按源序列顺序返回每个 key 第一次出现的元素。
- 采用延迟执行，只有枚举结果时才真正开始去重。

如果只是按某个属性取第一条记录，`DistinctBy(x => x.Key)` 通常比 `GroupBy(x => x.Key).Select(g => g.First())` 更直接，也更节省内存。

## API 语义

常用重载：

```csharp
IEnumerable<TSource> DistinctBy<TSource, TKey>(
    this IEnumerable<TSource> source,
    Func<TSource, TKey> keySelector);

IEnumerable<TSource> DistinctBy<TSource, TKey>(
    this IEnumerable<TSource> source,
    Func<TSource, TKey> keySelector,
    IEqualityComparer<TKey>? comparer);
```

它和 `Distinct` 的区别在于：

- `Distinct` 比较的是元素本身。
- `DistinctBy` 比较的是 `keySelector` 生成的 key，但返回的仍然是原始元素。

示例：

```csharp
var users = new[]
{
    new User(1, "Alice", "alice@example.com"),
    new User(2, "Alice Zhang", "alice@example.com"),
    new User(3, "Bob", "bob@example.com")
};

var uniqueUsers = users.DistinctBy(user => user.Email);

// 结果保留 alice@example.com 第一次出现的 User，以及 bob@example.com 对应的 User。
```

`DistinctBy` 不会对结果排序。它返回的是“每个 key 第一次出现的元素”，所以当业务需要保留最新记录、最大值、最小值或排序后的第一条记录时，应先明确排序或改用更合适的聚合逻辑。

## 实现机制

`Enumerable.DistinctBy` 的核心流程可以理解为：

1. 创建一个 `HashSet<TKey>`，用于保存已经见过的 key。
2. 遍历 `source`。
3. 对每个元素执行 `keySelector` 得到 key。
4. 调用 `HashSet<TKey>.Add(key)`。
5. 如果 `Add` 返回 `true`，说明这个 key 第一次出现，返回当前元素；如果返回 `false`，跳过当前元素。

近似伪代码：

```csharp
var seenKeys = new HashSet<TKey>(comparer);

foreach (var item in source)
{
    if (seenKeys.Add(keySelector(item)))
    {
        yield return item;
    }
}
```

因此，`DistinctBy` 的性能主要受这几个因素影响：

- 输入序列长度。
- 不同 key 的数量。
- key 的 `GetHashCode` / `Equals` 成本。
- `keySelector` 本身的计算成本。
- 是否提供了合适的 `IEqualityComparer<TKey>`。

## 性能表现

### 时间复杂度

在哈希分布正常、比较器实现合理的情况下，`HashSet<TKey>.Add` 平均接近 `O(1)`，整体只需要遍历一次序列，因此平均时间复杂度为 `O(n)`。

需要注意的是，哈希集合的复杂度依赖哈希质量。如果大量 key 哈希冲突，或者比较器实现很慢，性能会明显下降。实际项目中，更常见的性能瓶颈不是 `DistinctBy` 本身，而是：

- `keySelector` 访问了复杂导航属性。
- key 是很大的字符串、集合或复杂对象。
- 自定义比较器的 `GetHashCode` / `Equals` 逻辑过重。
- 在数据库查询上过早切到内存再执行去重。

### 空间复杂度

`DistinctBy` 需要保存已经出现过的 key，额外空间复杂度为 `O(k)`，其中 `k` 是不同 key 的数量。最坏情况下，所有元素 key 都不同，空间复杂度为 `O(n)`。

与 `GroupBy(...).Select(g => g.First())` 相比，`DistinctBy` 通常更省内存，因为它只保存 key 集合，不需要为每个 key 构建完整分组，也不需要保存每个分组里的所有元素。

### 延迟执行

`DistinctBy` 是延迟执行方法。调用 `source.DistinctBy(...)` 时不会立即遍历源序列，只有 `foreach`、`ToList()`、`Count()` 等触发枚举时才执行。

这一点带来两个影响：

- 可以与 `Take` 等方法组合，提前停止枚举。
- 如果源序列在创建查询后、真正枚举前发生变化，结果也会反映枚举时的状态。

示例：

```csharp
var firstTwoKinds = orders
    .DistinctBy(order => order.ProductId)
    .Take(2)
    .ToList();
```

这里最多只需要找到两个不同的 `ProductId`，不一定会遍历完整的 `orders`。

## 与其他去重方式对比

| 方法 | 平均时间复杂度 | 额外空间复杂度 | 返回内容 | 适用场景 |
| --- | --- | --- | --- | --- |
| `DistinctBy` | `O(n)` | `O(k)` | 每个 key 第一次出现的原始元素 | .NET 6+ 按属性或表达式去重 |
| `Distinct` | `O(n)` | `O(k)` | 唯一元素本身 | 元素自身已经能表达相等性 |
| `GroupBy(...).Select(g => g.First())` | `O(n)` | `O(n)` | 每组第一条原始元素 | 需要兼容旧版本，或后续还要使用分组 |
| 手写 `HashSet<TKey>` | `O(n)` | `O(k)` | 可自定义 | 需要复杂控制流程、统计或副作用 |
| 数据库 `GROUP BY` / 窗口函数 | 取决于执行计划 | 由数据库处理 | 查询结果 | 大数据集应优先在数据库侧去重 |

说明：

- `GroupBy` 本身通常也是哈希分组，平均时间复杂度可以接近 `O(n)`；它的问题主要是会构建完整分组，内存占用和首个结果延迟通常高于 `DistinctBy`。
- 如果已经需要每个分组的数量、总和、最大值等聚合结果，`GroupBy` 仍然是更自然的选择。
- 如果源数据来自数据库，优先考虑让数据库完成去重、排序和分页，避免把大量数据拉到内存中再 `DistinctBy`。

## 代码示例

### 按单个属性去重

```csharp
var uniqueUsers = users
    .DistinctBy(user => user.Email)
    .ToList();
```

### 忽略字符串大小写

```csharp
var uniqueUsers = users
    .DistinctBy(user => user.Email, StringComparer.OrdinalIgnoreCase)
    .ToList();
```

如果 key 是字符串，并且业务规则要求大小写不敏感，应显式传入比较器，避免默认区分大小写造成重复数据。

### 按组合 key 去重

```csharp
var uniqueItems = items
    .DistinctBy(item => (item.TenantId, item.Code))
    .ToList();
```

ValueTuple 已经实现了基于成员的相等性和哈希计算，适合表达简单组合 key。

### 保留最新记录

`DistinctBy` 保留的是每个 key 第一次出现的元素。如果要保留最新记录，可以先排序：

```csharp
var latestOrders = orders
    .OrderByDescending(order => order.CreatedAt)
    .DistinctBy(order => order.CustomerId)
    .ToList();
```

这种写法语义清楚，但排序会引入 `O(n log n)` 成本。数据量较大且数据源是数据库时，更推荐使用 SQL 排序、窗口函数或对应 ORM 能翻译的查询。

### .NET 6 之前的替代写法

如果项目还不能使用 .NET 6，可以用 `GroupBy` 替代：

```csharp
var uniqueUsers = users
    .GroupBy(user => user.Email)
    .Select(group => group.First())
    .ToList();
```

或者手写 `HashSet<TKey>` 扩展方法：

```csharp
public static IEnumerable<TSource> DistinctByCompat<TSource, TKey>(
    this IEnumerable<TSource> source,
    Func<TSource, TKey> keySelector,
    IEqualityComparer<TKey>? comparer = null)
{
    var seenKeys = new HashSet<TKey>(comparer);

    foreach (var item in source)
    {
        if (seenKeys.Add(keySelector(item)))
        {
            yield return item;
        }
    }
}
```

## 使用注意事项

### 版本要求

`Enumerable.DistinctBy` 从 .NET 6 开始可用。较低版本的项目可以使用 `GroupBy + First`、手写扩展方法，或引入提供类似能力的工具库。

### IQueryable 与 EF Core

`Enumerable.DistinctBy` 适用于内存中的 `IEnumerable<T>`。对于 `IQueryable<T>`，虽然也存在 `Queryable.DistinctBy` API，但具体能否翻译成 SQL 取决于查询提供程序。

在 EF Core 场景中要特别谨慎：

- 不要假设 `DistinctBy` 一定会被翻译为 SQL。
- 如果查询被切换到客户端执行，可能会把大量数据加载到内存中。
- 大表去重应优先使用数据库能稳定翻译的写法，例如 `GroupBy` 聚合、`Distinct` 投影、窗口函数或原生 SQL。

尤其要避免这类写法：

```csharp
var users = await db.Users
    .AsEnumerable()
    .DistinctBy(user => user.Email)
    .ToListAsync(); // 错误：AsEnumerable 后已经不再是 EF 异步查询
```

如果确实需要在内存中去重，也应先限制数据范围：

```csharp
var recentUsers = await db.Users
    .Where(user => user.CreatedAt >= startTime)
    .Select(user => new UserDto(user.Id, user.Email, user.CreatedAt))
    .ToListAsync();

var uniqueUsers = recentUsers
    .DistinctBy(user => user.Email)
    .ToList();
```

### keySelector 成本

`keySelector` 会对枚举到的每个元素执行一次。它应该尽量保持简单、稳定、无副作用。

不推荐：

```csharp
var result = users.DistinctBy(user => NormalizeByCallingRemoteService(user.Email));
```

推荐先预处理或使用本地可计算的 key：

```csharp
var result = users
    .Select(user => new
    {
        User = user,
        NormalizedEmail = user.Email.Trim().ToUpperInvariant()
    })
    .DistinctBy(x => x.NormalizedEmail)
    .Select(x => x.User)
    .ToList();
```

### 可变 key 风险

如果 key 是可变对象，或者 key 的相等性依赖可变字段，应避免在去重过程中修改这些字段。哈希集合依赖 key 的哈希值和相等性保持稳定，否则可能得到难以排查的结果。

### 多线程场景

每次枚举 `DistinctBy` 查询都会创建自己的 `HashSet<TKey>`，这个内部集合不会在不同枚举之间共享。但源集合本身如果被多个线程并发修改，仍然可能导致枚举异常或结果不稳定。

## 常见误区

### DistinctBy 不等于 SQL DISTINCT

SQL `DISTINCT` 针对投影后的整行去重，而 `DistinctBy` 是按 key 去重并返回原始元素。两者语义不同：

```csharp
var result = users.DistinctBy(user => user.Email);
```

这段代码不是“只返回不重复的 Email 字符串”，而是“每个 Email 保留一个 User 对象”。

### DistinctBy 不会自动选择最新或最大

如果同一个 key 对应多条数据，`DistinctBy` 保留源序列中最先遇到的那条。需要最新记录时，应先排序或使用分组聚合。

### DistinctBy 不会降低整体算法中的排序成本

如果前面已经调用了 `OrderBy`，整体复杂度仍然包含排序的 `O(n log n)`。`DistinctBy` 本身是线性遍历，但不能抵消上游操作成本。

### GroupBy 不一定是 O(n log n)

`GroupBy` 常见实现也是哈希分组，平均时间复杂度通常接近 `O(n)`。它相对 `DistinctBy` 的主要劣势不是多了排序，而是需要维护完整分组结构，内存和首个结果延迟更高。

## 参考资料

### 官方资料

1. [Enumerable.DistinctBy 方法 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.linq.enumerable.distinctby?view=net-10.0)
2. [Queryable.DistinctBy 方法 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.linq.queryable.distinctby?view=net-10.0)
3. [Distinct.cs - dotnet/runtime](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Linq/src/System/Linq/Distinct.cs)
4. [.NET 6 的新增功能 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-6)
5. [EF Core issue: Translate LINQ DistinctBy - GitHub](https://github.com/dotnet/efcore/issues/27470)

### 延伸阅读

1. [C# 中 Linq 的 Distinct 和 DistinctBy 去重 - 博客园](https://www.cnblogs.com/lgx5/p/18662841)
2. [C# 中 DistinctBy 的使用场景和性能分析 - 知乎](https://zhuanlan.zhihu.com/p/1999165192332927894)
3. [C# LINQ 中的 DistinctBy 性能分析 - CSDN](https://blog.csdn.net/weixin_43797501/article/details/154661069)
