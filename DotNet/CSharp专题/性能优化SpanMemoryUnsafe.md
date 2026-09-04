# 性能优化：Span、Memory 与 Unsafe

> 版本信息：Span<T>/ReadOnlySpan<T> 的语言支持于 C# 7.2，相关运行时 API 和 Memory<T> 于 .NET Core 2.1 提供，用于高性能内存操作；System.Buffers.ArrayPool<T> 于 .NET Core 2.0；Unsafe API 由 System.Runtime.CompilerServices.Unsafe 包提供，本文按 .NET 8 使用。示例目标 net8.0，可迁移到 net10/11。

性能优化先测量再改动。使用 BenchmarkDotNet、dotnet-counters、dotnet-trace 和内存剖析器确认瓶颈，避免为了少一次分配而牺牲可读性。

## Span<T> 基础

Span<T> 是 ref struct，只能存在于栈上，不能跨 await、yield 或装箱。它提供数组、字符串和非托管缓冲区的统一切片视图：

~~~csharp
static int Sum(ReadOnlySpan<int> values)
{
    int total = 0;
    foreach (int value in values)
        total += value;
    return total;
}

int[] data = [1, 2, 3, 4];
int total = Sum(data.AsSpan(1, 2));
~~~

字符串解析可用 ReadOnlySpan<char> 避免 substring 分配：

~~~csharp
static bool TryParsePort(ReadOnlySpan<char> text, out int port)
    => int.TryParse(text, out port) && port is > 0 and <= 65535;
~~~

## Memory<T> 与异步

Memory<T> 可作为类字段，并跨 await 传递。需要访问时调用 Span 属性：

~~~csharp
static async ValueTask<int> ReadAsync(
    Stream stream, Memory<byte> buffer, CancellationToken token)
{
    int count = await stream.ReadAsync(buffer, token);
    return count;
}
~~~

不要同时让多个异步操作写入同一块 Memory，除非有明确同步协议。

## ArrayPool<T>

~~~csharp
using System.Buffers;

byte[] rented = ArrayPool<byte>.Shared.Rent(4096);
try
{
    int count = await stream.ReadAsync(rented, token);
    await destination.WriteAsync(rented.AsMemory(0, count), token);
}
finally
{
    ArrayPool<byte>.Shared.Return(rented, clearArray: true);
}
~~~

clearArray 在缓冲区包含密钥、令牌等敏感数据时必须为 true；普通数据可根据清零成本评估。

## Unsafe 与内联

Unsafe.ReadUnaligned、MemoryMarshal 和 ref 操作可减少部分复制或检查，但要求调用方保证地址、长度和对齐。JIT 会自动内联小方法；先用基准测试确认收益。任何不安全代码都应封装，并提供安全实现用于验证。

~~~csharp
using System.Runtime.InteropServices;

static int ReadInt32(ReadOnlySpan<byte> bytes)
{
    if (bytes.Length < 4) throw new ArgumentException();
    return MemoryMarshal.Read<int>(bytes);
}
~~~

## 高级优化清单

- 减少短命对象：使用 StringBuilder、ValueTask、对象池，但避免全局池化导致复杂生命周期。
- 用结构化日志模板而不是字符串插值，减少无用格式化。
- 避免 LINQ 在极热循环中的迭代器和闭包分配；用 Span 或手写循环前先测量。
- 控制泛型和代码膨胀；关注 Tiered JIT、PGO 和 ReadyToRun 的发布取舍。
- 服务器应用使用 Server GC；低延迟服务评估 SustainedLowLatency，并监控暂停时间。
