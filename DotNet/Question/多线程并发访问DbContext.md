# <center>多线程并发访问 DbContext</center>

## 问题现象

在 .NET 中，如果多个线程、多个异步任务并发访问同一个 `DbContext` 实例，常见异常如下：

```text
System.InvalidOperationException: A second operation was started on this context instance before a previous operation completed. This is usually caused by different threads concurrently using the same instance of DbContext.
```

官方文档的核心结论是：

- `DbContext` 不是线程安全的。
- EF Core 不支持在同一个 `DbContext` 实例上运行多个并行操作。
- 这既包括多个异步查询并行执行，也包括多个线程显式并发使用同一个实例。
- 异步方法应立即 `await`；真正需要并行时，应为每个并行任务使用不同的 `DbContext` 实例。

## 根本原因

`DbContext` 是按 Unit of Work 设计的，生命周期通常很短：创建上下文、查询或跟踪实体、修改实体、调用 `SaveChanges` / `SaveChangesAsync`、释放上下文。

并发使用同一个 `DbContext` 会有几个问题：

1. `DbContext` 内部维护变更跟踪、状态管理、并发检测等状态，这些实例成员不保证线程安全。
2. 一个 `DbContext` 底层关联一个数据库连接，数据库连接以及 EF Core 内部组件不能被同一个上下文并发使用。
3. 即使是只读查询，跟踪查询也可能写入 ChangeTracker；`AsNoTracking()` 虽然不跟踪实体，但仍然不能让同一个 `DbContext` 支持并发查询。
4. 如果 EF Core 没有检测到并发访问，可能出现未定义行为、程序崩溃或数据损坏。

## 常见触发场景

### 1. 启动多个 EF Core 异步操作后再统一等待

错误示例：

```csharp
var usersTask = dbContext.Users.ToListAsync();
var ordersTask = dbContext.Orders.ToListAsync();

await Task.WhenAll(usersTask, ordersTask);
```

两个查询共享同一个 `dbContext`，并且在前一个操作完成前启动了第二个操作。

推荐写法：

```csharp
var users = await dbContext.Users.ToListAsync();
var orders = await dbContext.Orders.ToListAsync();
```

如果这些查询确实需要并行，应使用不同的 `DbContext` 实例。

### 2. `Parallel.ForEachAsync` 中复用外层注入的 Repository / UnitOfWork

错误示例：

```csharp
await Parallel.ForEachAsync(items, async (item, ct) =>
{
    await repository.InsertAsync(item, ct);
});
```

如果 `repository` 或它背后的 UnitOfWork / `DbContext` 是外层 scope 注入的，那么所有并行任务可能会共享同一个上下文。

### 3. 作用域服务被单例对象长期持有

例如中间件、后台服务、单例缓存类、静态字段等持有了 Repository、UnitOfWork 或 `DbContext`。这类对象生命周期更长，后续多个请求或消息处理可能复用同一个上下文相关对象。

在 Azure Functions、ASP.NET Core middleware 等场景中，应在每次请求 / 每次函数执行时从当前请求作用域解析服务，或手动创建 scope。

### 4. 查询结果还在枚举时触发第二个查询

例如：

- `await foreach` 枚举异步查询结果时，又在循环中用同一个 `DbContext` 发起新查询。
- 枚举查询结果过程中触发 Lazy Loading，导致同一个连接仍在读取结果集时又尝试执行新查询。

## 解决方案

### 方案一：顺序执行，每个 EF Core 异步操作立即 await

如果多个数据库操作之间不需要真正并行，这是最简单、最稳定的方式：

```csharp
var users = await dbContext.Users.ToListAsync();
var orders = await dbContext.Orders.ToListAsync();
var products = await dbContext.Products.ToListAsync();
```

注意：`async` 不等于并行。只要每次都等待前一个数据库操作完成，同一个 `DbContext` 在单个 Unit of Work 内顺序使用是正常的。

### 方案二：为每个并行任务创建独立 DI scope

适合已有 Repository / UnitOfWork 依赖注入体系的项目：

```csharp
await Parallel.ForEachAsync(
    items,
    new ParallelOptions { MaxDegreeOfParallelism = 8 },
    async (item, ct) =>
    {
        await using var scope = serviceScopeFactory.CreateAsyncScope();

        var repository = scope.ServiceProvider.GetRequiredService<IMetricsRepository>();
        await repository.InsertAsync(item, ct);
    });
```

每个并行任务都有自己的 DI scope，因此也会拿到独立的 scoped `DbContext`。

### 方案三：使用 IDbContextFactory 创建独立 DbContext

EF Core 官方推荐在一个 DI scope 内需要多个 Unit of Work，或应用模型无法自然对齐 `DbContext` 生命周期时使用 `AddDbContextFactory`。

注册：

```csharp
builder.Services.AddDbContextFactory<AppDbContext>(options =>
{
    options.UseSqlServer(connectionString);
});
```

使用：

```csharp
await Parallel.ForEachAsync(
    items,
    new ParallelOptions { MaxDegreeOfParallelism = 8 },
    async (item, ct) =>
    {
        await using var dbContext = await dbContextFactory.CreateDbContextAsync(ct);

        dbContext.Set<Metric>().Add(item);
        await dbContext.SaveChangesAsync(ct);
    });
```

通过 factory 创建的 `DbContext` 不由当前 DI scope 自动释放，需要调用方自行 `Dispose` / `DisposeAsync`。

### 方案四：并行任务中隔离 AsyncLocal 上下文

一些框架会用 `AsyncLocal<T>` 保存当前 UnitOfWork、租户、用户、请求 ID 等环境数据。`ExecutionContext` 默认会把这些 `AsyncLocal<T>` 数据流入新任务，因此并行任务即使创建了新 scope，也可能仍然读到外层的“当前 UnitOfWork”。

这种情况下可以在创建并行任务时短暂使用 `ExecutionContext.SuppressFlow()`，阻止外层 `AsyncLocal<T>` 流入并行任务：

```csharp
Task task;

using (ExecutionContext.SuppressFlow())
{
    task = Parallel.ForEachAsync(
        items,
        new ParallelOptions { MaxDegreeOfParallelism = 8 },
        async (item, ct) =>
        {
            await using var uow = uowManager.BeginScope();

            await repositoryMetrics.InsertAsync(item, ct);
            await uow.CompleteAsync(ct);
        });
}

await task;
```

注意点：

- `SuppressFlow()` 只包住“创建任务”的代码，不要让它跨越 `await`。
- 离开 `using` 后再 `await task`，避免在错误的执行流中恢复上下文。
- 这只能解决 `AsyncLocal<T>` 环境数据被错误传递的问题，不能让同一个 `DbContext` 变成线程安全。

## DI 生命周期建议

`AddDbContext` 默认把 `DbContext` 注册为 scoped。对大多数 ASP.NET Core Web 应用来说，这是合理默认值，因为每个 HTTP 请求都有独立 scope，一个请求通常对应一个 Unit of Work。

在显式并行执行数据库操作时，有两种常见做法：

- 保持 `DbContext` 为 scoped，并为每个并行任务创建独立 scope。
- 使用 `IDbContextFactory<TContext>`，在每个并行任务中显式创建并释放 `DbContext`。

把 `DbContext` 改成 transient 不是万能解法。它可以让每次解析得到新实例，但也可能让同一个业务操作里的多个 Repository 拿到不同上下文，破坏原本希望共享的 Unit of Work。是否使用 transient，需要结合事务边界和 Repository 设计判断。

不要把 `DbContext` 注册成 singleton，也不要让 singleton 服务持有 scoped Repository / `DbContext`。

## 常见误区

### AsNoTracking 不能解决并发访问

`AsNoTracking()` 只是关闭实体跟踪，不能改变 `DbContext`、底层连接和内部组件不能并发使用的事实。多个 `AsNoTracking()` 查询也不能并行跑在同一个 `DbContext` 上。

### MultipleActiveResultSets 不是根本解法

SQL Server 的 `MultipleActiveResultSets=True` 只影响底层连接是否支持多个活动结果集。EF Core 官方限制仍然存在：同一个 `DbContext` 实例不支持多个并行操作。因此不应把 MARS 当作解决 `DbContext` 并发问题的主要方案。

### ConfigureAwait(false) 不会阻止 AsyncLocal 传递

`ConfigureAwait(false)` 影响的是是否回到捕获的 `SynchronizationContext` 或非默认 `TaskScheduler`，不会阻止 `ExecutionContext` / `AsyncLocal<T>` 流动。

如果需要阻止 `AsyncLocal<T>` 上下文传入新任务，应使用 `ExecutionContext.SuppressFlow()`，并严格控制作用域。

## 排查清单

1. 是否有同一个 `DbContext` 上多个 `ToListAsync()` / `FirstOrDefaultAsync()` / `SaveChangesAsync()` 被 `Task.WhenAll` 并行等待？
2. 是否有 `Parallel.ForEachAsync`、`Task.Run`、消息队列批处理并发复用同一个 Repository / UnitOfWork？
3. 是否有 singleton / static 对象持有 scoped 服务？
4. 是否在异步枚举查询结果时，又用同一个 `DbContext` 发起了新查询？
5. 是否有 `AsyncLocal<T>` 保存当前 UnitOfWork，导致并行任务继承了外层上下文？
6. 每个并行任务是否创建并释放了自己的 `DbContext` 或 DI scope？

## 参考资料

1. [DbContext Lifetime, Configuration, and Initialization - Avoiding DbContext threading issues](https://learn.microsoft.com/en-us/ef/core/dbcontext-configuration/#avoiding-dbcontext-threading-issues)
2. [Asynchronous Programming - EF Core](https://learn.microsoft.com/en-us/ef/core/miscellaneous/async)
3. [ExecutionContext 和 SynchronizationContext](/DotNet/ExecutionContext和SynchronizationContext.md)
4. [Allow multithreading for "AsNoTracking()" - dotnet/efcore#18094](https://github.com/dotnet/efcore/issues/18094)
5. [EntityFramework DbContext 线程安全 - 阿里云开发者社区](https://developer.aliyun.com/article/381001)
6. [EF Core 报错："A second operation started on this context before a previous operation completed" - 博客园](https://q.cnblogs.com/q/125710)
7. [Microsoft Q&A: A second operation was started on this context instance before a previous operation completed](https://learn.microsoft.com/en-us/answers/questions/1698874/a-second-operation-was-started-on-this-context-ins)
