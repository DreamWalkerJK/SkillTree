# IAsyncEnumerable<T> 与异步流

> 版本信息：.NET Core 3.0/C# 8 引入异步迭代器、`IAsyncEnumerable<T>`、`await foreach` 和 `await using`。本文示例使用 .NET 8（C# 12）中的 `Channel<T>`、`ReadAllAsync` 和 `HttpClient` API，目标框架为 `net8.0`；可迁移到 .NET 10，.NET 11 Preview 需按目标 SDK 验证。

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

System.Linq.Async（NuGet）提供 SelectAwait、WhereAwait 等扩展；.NET 9/10 的 BCL 可能继续增加异步 LINQ，请以目标 SDK API 为准。没有额外依赖时可手写迭代器：

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
