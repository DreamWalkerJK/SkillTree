# C# / .NET 专题

本目录按主题拆分 C# 语言特性与 .NET 运行时组件。文章示例采用 **.NET 10 / C# 14**，目标框架为 `net10.0`；文首会标出特性的首次引入版本，历史版本差异会在正文说明。示例代码均为 C#。

## 语言与类型

- [泛型](泛型.md)
- [值元组](值元组.md)
- [模式匹配](模式匹配.md)
- [记录类型](记录类型.md)
- [拓展方法](拓展方法.md)
- [属性](属性.md)
- [委托和事件](委托和事件.md)

## 运行时与动态特性

- [反射](反射.md)
- [表达式树](表达式树.md)
- [动态编程](动态编程.md)
- [源生成器](源生成器.md)
- [本机互操作](本机互操作.md)
- [不安全代码](不安全代码.md)

## 异步与并发

- [异步编程](异步编程.md)
- [异步编程模型](异步编程模型.md)
- [IAsyncEnumerable 与异步流](IAsyncEnumerable.md)
- [线程处理](线程处理.md)
- [并行编程](并行编程.md)
- [依赖注入与 AOP](依赖注入与AOP.md)

## 数据、性能与资源

- [LINQ：分组、聚合与 IQueryable](LINQ分组聚合与IQueryable.md)
- [性能优化：Span、Memory 与 Unsafe](性能优化SpanMemoryUnsafe.md)
- [内存管理](内存管理.md)

### 版本阅读顺序

1. 先阅读泛型、记录类型、模式匹配和值元组，建立类型和数据模型基础。
2. 再阅读异步编程、线程处理、并行编程和异步流，区分 I/O 并发与 CPU 并行。
3. 需要框架扩展时阅读反射、表达式树、源生成器和 DI/AOP，并在裁剪或 Native AOT 发布中复测。
4. 最后根据性能剖析结果选择 Span、Memory、池化或不安全代码；不要以基准测试之外的直觉替代测量。

## 参考资料

- [C# 文档](https://learn.microsoft.com/dotnet/csharp/)：语言教程、参考和版本历史的入口。
- [.NET API 浏览器](https://learn.microsoft.com/dotnet/api/?view=net-10.0)：按命名空间和程序集查询运行时 API 及支持版本。
- [.NET 平台概述](https://learn.microsoft.com/dotnet/core/introduction)：了解 SDK、运行时、目标框架和部署模型之间的关系。
