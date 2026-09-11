# 性能优化：Span、Memory 与 Unsafe

> 版本信息：C# 7.2 引入 `ref struct` 等语言支持，`Span<T>`、`ReadOnlySpan<T>` 和 `Memory<T>` API 随 .NET Core 2.1 提供；`ArrayPool<T>` 在 .NET Core 1.0 已可用。语言语法与运行时类型应分别看待，不能把 `Memory<T>` 当作 C# 7.2 的语言特性。本文使用 .NET 10 / C# 14，目标框架为 `net10.0`。

性能优化先测量再改动。使用 BenchmarkDotNet、dotnet-counters、dotnet-trace 和内存剖析器确认瓶颈，避免为了少一次分配而牺牲可读性。

## Span<T> 基础

`Span<T>` 是 `ref struct`，不能装箱或存入普通类字段。它描述的内存可以来自托管数组、栈或非托管分配，并不要求数据本身位于栈上。C# 13 起允许在异步方法和迭代器中使用 `ref struct` 局部变量，但变量不能跨越 `await` 或 `yield return` 保持有效。需要跨异步挂起点保存缓冲区时使用 `Memory<T>`。

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

## 工程示例：无分配解析固定格式

对于稳定格式的短文本，可以使用 `ReadOnlySpan<char>` 直接切片。切片不复制底层字符串，但返回的数值和错误信息仍应由调用方明确处理。

~~~csharp
static bool TryParsePoint(
    ReadOnlySpan<char> text, out int x, out int y)
{
    var separator = text.IndexOf(',');
    if (separator <= 0 || separator == text.Length - 1)
    {
        x = y = 0;
        return false;
    }

    y = 0; // 左侧解析失败时 && 会短路，仍需保证 out 参数已赋值。
    return int.TryParse(text[..separator], out x)
        && int.TryParse(text[(separator + 1)..], out y);
}
~~~

Span 只解决切片和临时分配问题，不能代替算法优化。优化前后应比较吞吐、P95/P99 延迟、分配字节数和 GC 次数；如果输入很少或路径不热，普通字符串代码通常更容易维护。

## 参考资料

- [Span<T> 和 Memory<T>](https://learn.microsoft.com/dotnet/standard/memory-and-spans/)：介绍切片、异步 API 传递和 `ref struct` 限制。
- [Memory<T> 和 Span<T> 使用指南](https://learn.microsoft.com/dotnet/standard/memory-and-spans/memory-t-usage-guidelines)：说明所有权、借用、生命周期和异步调用期间的内存使用约定。
- [`ArrayPool<T>` API](https://learn.microsoft.com/dotnet/api/system.buffers.arraypool-1?view=net-10.0)：参考数组租用、归还和敏感数据清理。
- [dotnet-trace 性能分析](https://learn.microsoft.com/dotnet/core/diagnostics/dotnet-trace)：用于采集运行时事件并验证优化是否有效。
- [C# 13 的 ref 和 unsafe 限制调整](https://learn.microsoft.com/dotnet/csharp/whats-new/csharp-13)：核对异步方法、迭代器和 `ref struct` 局部变量的使用规则。
