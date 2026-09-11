# IAsyncEnumerable<T> 与异步流

> 版本信息：.NET Core 3.0/C# 8 引入异步迭代器、`IAsyncEnumerable<T>`、`await foreach` 和 `await using`。本文示例使用 .NET 10（C# 14）中的 `Channel<T>`、`ReadAllAsync` 和 `HttpClient` API，目标框架为 `net10.0`。

异步流按需产生数据，每次 MoveNextAsync 都可以异步等待，适合分页 API、日志 tail、消息消费和大型文件处理。它与一次性返回 Task<List<T>> 的区别是内存占用和首项延迟更低。

## 基础用法：生产与消费

~~~csharp
static async IAsyncEnumerable<int> CountAsync(
    int count,
    [System.Runtime.CompilerServices.EnumeratorCancellation]
    CancellationToken cancellationToken = default)
{
    for (int i = 0; i < count; i++)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await Task.Delay(10, cancellationToken);
        yield return i;
    }
}

await foreach (int value in CountAsync(
    5, cancellationToken).ConfigureAwait(false))
{
    Console.WriteLine(value);
}
~~~

EnumeratorCancellation 特性把调用方令牌传给迭代器。await foreach 会在结束时调用 DisposeAsync；如果元素类型实现 IAsyncDisposable，可使用 await using。

## 异步 LINQ

.NET 10 内置 `System.Linq.AsyncEnumerable`，为 `IAsyncEnumerable<T>` 提供 `Where`、`Select`、`ToListAsync` 等 LINQ 运算符，不需要为了这些操作额外安装旧的 `System.Linq.Async` 包。例如可以先筛选分页流，再物化为列表：

~~~csharp
List<Product> products = await ReadPagesAsync(client, token)
    .Where(product => product.Name.Length > 0)
    .Take(100)
    .ToListAsync(token);
~~~

旧项目若已引用 `System.Linq.Async`，升级到 .NET 10 时应检查扩展方法二义性，按迁移文档调整包引用。异步委托重载与旧包的 `SelectAwait` 等名称也不完全相同。需要自定义遍历逻辑时，仍可手写迭代器：

~~~csharp
static async IAsyncEnumerable<string> ReadLinesAsync(
    StreamReader reader,
    [System.Runtime.CompilerServices.EnumeratorCancellation]
    CancellationToken token = default)
{
    while (await reader.ReadLineAsync(token) is { } line)
        yield return line;
}
~~~

## 高级用法：并发与背压

单个 await foreach 默认串行处理。要限制并发，可把生产和消费通过 Channel<T> 解耦：

~~~csharp
var channel = System.Threading.Channels.Channel.CreateBounded<Uri>(100);

Task producer = Task.Run(async () =>
{
    try
    {
        foreach (Uri uri in addresses)
            await channel.Writer.WriteAsync(uri, token);
        channel.Writer.TryComplete();
    }
    catch (Exception error)
    {
        channel.Writer.TryComplete(error);
        throw;
    }
}, CancellationToken.None);

await foreach (Uri uri in channel.Reader.ReadAllAsync(token))
{
    // 这里可调用受控的异步处理
    await ProcessAsync(uri, token);
}
await producer;
~~~

有界 Channel 形成背压，防止生产速度长期超过消费速度。并行消费时使用固定数量 worker，并确保结果顺序需求得到满足。

## 异常、取消与重试

迭代器抛出的异常在 await foreach 处观察；取消通常表现为 OperationCanceledException。重试要从游标或页码重新开始，避免重复提交副作用。对不可重放的消息使用幂等键和确认机制。

## 与 ASP.NET Core 配合

Minimal API 可以直接返回 IAsyncEnumerable<T>，框架按 JSON 数组流式写出；客户端断开连接时 HttpContext.RequestAborted 应传入迭代器。不要在迭代器中捕获并吞掉取消异常，否则服务器会继续占用资源。

## 工程示例：分页流与背压

分页接口不要先把全部页合并成一个列表。迭代器可以在消费方请求下一项时才访问下一页，并把取消令牌传给 HTTP 调用。

~~~csharp
static async IAsyncEnumerable<Product> ReadPagesAsync(
    HttpClient client,
    [System.Runtime.CompilerServices.EnumeratorCancellation]
    CancellationToken token = default)
{
    for (var page = 1; ; page++)
    {
        var response = await client.GetFromJsonAsync<Page<Product>>(
            $"products?page={page}", token);
        if (response is null || response.Items.Count == 0)
            yield break;

        foreach (var item in response.Items)
            yield return item;

        if (!response.HasNext)
            yield break;
    }
}

public sealed record Page<T>(IReadOnlyList<T> Items, bool HasNext);
public sealed record Product(int Id, string Name);
~~~

异步流不是自动的限流器。下游处理速度低于生产速度时，调用方应在消费循环中控制并发，或使用有界 `Channel<T>`；需要重试时按页或按项目设计幂等键，避免重复写入。

## 参考资料

- [异步流（Microsoft Learn）](https://learn.microsoft.com/dotnet/csharp/iterators)：说明异步迭代器、`await foreach` 和取消令牌的编译器行为。
- [`IAsyncEnumerable<T>` API](https://learn.microsoft.com/dotnet/api/system.collections.generic.iasyncenumerable-1?view=net-10.0)：查阅接口成员、异步枚举器生命周期和框架版本信息。
- [`Channel<T>` API](https://learn.microsoft.com/dotnet/api/system.threading.channels.channel-1?view=net-10.0)：了解有界通道、背压和生产者/消费者协调方式。
- [.NET 10 的异步 LINQ 兼容性说明](https://learn.microsoft.com/dotnet/core/compatibility/core-libraries/10.0/asyncenumerable)：介绍内置 `AsyncEnumerable` 后的扩展方法冲突和旧包迁移。
