# LINQ：分组、聚合与 IQueryable

> 版本信息：.NET 8（C# 12）。LINQ 于 .NET 3.5/C# 3.0 引入；IQueryable<T> 和表达式树同代提供；Enumerable.Chunk 于 .NET 6；MaxBy/MinBy 于 .NET 6。示例目标为 `net8.0`，可迁移到 .NET 10；.NET 11 Preview 需按目标 SDK 验证。

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

IQueryable 只是查询描述，不代表一定安全或高效。提供程序可能无法翻译任意 C# 方法；在数据库查询中使用本地方法会抛 NotSupportedException。先在服务器端完成 Where、Select、GroupBy，再调用 AsEnumerable 切换到内存：

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
