# LINQ：分组、聚合与 IQueryable

> 版本信息：.NET 10（C# 14）。LINQ 于 .NET 3.5/C# 3.0 引入；IQueryable<T> 和表达式树同代提供；Enumerable.Chunk 于 .NET 6；MaxBy/MinBy 于 .NET 6。示例目标为 `net10.0`。

LINQ 有两套主要执行模型：Enumerable 在进程内枚举 IEnumerable<T>；Queryable 把 Expression<Func<...>> 交给远端提供程序（通常是数据库）。两者方法名相似，执行位置和可翻译范围不同。

## 分组与聚合基础

~~~csharp
var totals = orders
    .GroupBy(order => order.CustomerId)
    .Select(group => new
    {
        CustomerId = group.Key,
        Count = group.Count(),
        Amount = group.Sum(order => order.Amount),
        Average = group.Average(order => order.Amount)
    })
    .OrderByDescending(item => item.Amount)
    .ToList();
~~~

GroupBy 默认延迟执行；调用 ToList、ToArray、First 等终结操作才会枚举。对空序列使用 Sum 返回数值类型的零，Average、Min、Max 会抛异常或返回可空重载，需根据业务处理。

~~~csharp
decimal? maximum = orders
    .Select(order => (decimal?)order.Amount)
    .Max();

var byStatus = orders
    .GroupBy(order => order.Status)
    .ToDictionary(group => group.Key, group => group.Count());
~~~

## 高级聚合

Aggregate 可实现自定义折叠，但应保持累加器无副作用：

~~~csharp
string csv = names.Aggregate(
    seed: new StringBuilder(),
    func: (builder, name) =>
    {
        if (builder.Length > 0) builder.Append(',');
        return builder.Append(name);
    },
    resultSelector: builder => builder.ToString());
~~~

对大数据集优先让数据库执行分组聚合；在内存中分组前先过滤字段和行数。避免在循环中对每组再次查询，防止 N+1。

## IQueryable 查询

~~~csharp
IQueryable<OrderTotal> query = db.Orders
    .Where(order => order.Amount >= 100m)
    .GroupBy(order => order.CustomerId)
    .Select(group => new OrderTotal(
        group.Key, group.Sum(order => order.Amount)));

List<OrderTotal> result = await query
    .AsNoTracking()
    .ToListAsync(cancellationToken);
~~~

`IQueryable` 只是查询描述，不代表一定安全或高效。提供程序不能翻译任意 C# 方法；例如 EF Core 遇到无法翻译的 `Where` 条件通常抛出 `InvalidOperationException`，但允许在最外层投影中进行部分客户端计算。应先在服务器端完成筛选、投影和聚合，再明确选择客户端计算：

~~~csharp
var serverRows = await db.Orders
    .Where(o => o.Status == "Paid")
    .Select(o => new { o.Id, o.Amount })
    .ToListAsync(token);

var custom = serverRows.Where(row => IsSpecial(row.Amount));
~~~

不要把用户输入直接拼接到 FromSqlRaw；使用参数化 API。动态筛选可组合表达式树，或使用 EF Core 的参数化 Where。

## 查询性能

- 只投影需要的列，避免 Select(o => o) 加载大对象图。
- 对只读查询使用 AsNoTracking。
- 分页要有稳定排序；大表优先基于键的 seek 分页而非深 OFFSET。
- 检查生成 SQL 和数据库执行计划；Benchmark 只在真实数据规模下有意义。
- 同一个 IQueryable 不要在多个终结操作中重复枚举，必要时物化一次。

## 工程示例：区分本地 LINQ 与数据库查询

先在数据库中筛选和投影，再将有限结果带回内存完成展示聚合。`AsEnumerable()` 会改变执行位置，调用前应确认结果集大小。

~~~csharp
var query = db.Orders
    .Where(o => o.CreatedAt >= from && o.CreatedAt < to)
    .GroupBy(o => o.CustomerId)
    .Select(g => new CustomerTotal(
        g.Key,
        g.Sum(o => o.Amount),
        g.Count()));

var totals = await query
    .OrderByDescending(x => x.Amount)
    .Take(100)
    .AsNoTracking()
    .ToListAsync(cancellationToken);

public sealed record CustomerTotal(Guid CustomerId, decimal Amount, int Count);
~~~

不同数据库提供程序对日期函数、字符串操作和分组投影的翻译能力不同。上线前应检查生成 SQL、索引使用和参数化情况；不要为了复用一个 C# 方法而强行把不可翻译逻辑放进 `IQueryable`。

## 参考资料

- [Language Integrated Query（Microsoft Learn）](https://learn.microsoft.com/dotnet/csharp/linq/)：总览查询语法、标准查询运算符和延迟执行。
- [`IQueryable<T>` API](https://learn.microsoft.com/dotnet/api/system.linq.iqueryable-1?view=net-10.0)：说明表达式树、查询提供程序和执行边界。
- [EF Core 查询概述](https://learn.microsoft.com/ef/core/querying/)：查看数据库翻译、客户端评估和生成 SQL 的实践建议。
