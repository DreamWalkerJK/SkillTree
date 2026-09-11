# async Task 与 Task.FromResult 伴随示例

本项目对应 [`DotNet/AsyncTask与Task.FromResult.md`](../../AsyncTask与Task.FromResult.md)，使用 .NET 10（`net10.0`）和 C# 14，演示：

- 已知同步结果如何使用 `Task.FromResult`。
- 存在真实等待时如何使用 `async` / `await`。
- 普通 `Task<T>` 返回方法与 `async Task<T>` 方法的异常出现时机差异。

在当前 README 所在的 `DotNet/Examples/AsyncTaskComparison` 目录执行。此目录的 `global.json` 选择 .NET SDK 10.0.102 或同一功能带的较新补丁，排除预览 SDK。

```powershell
dotnet --version
dotnet restore .\AsyncTaskComparison.csproj
dotnet build .\AsyncTaskComparison.csproj --no-restore
dotnet run --project .\AsyncTaskComparison.csproj --no-build
```

运行结果中，普通 `Task<T>` 返回方法在参数校验失败时直接抛出 `ArgumentException`；`async Task<T>` 方法先返回处于 `Faulted` 状态的任务，在读取任务结果时才观察到该异常。

本项目用于验证行为，不是性能基准。它也没有逐段编译对应文档中的全部代码片段。

2026-09-11 已在 Windows x64、.NET SDK 10.0.102 下完成还原、构建和运行。构建输出为 0 个警告、0 个错误，异常出现时机与上述说明一致。

## 参考资料

- [异步编程中的异常处理](https://learn.microsoft.com/zh-cn/dotnet/csharp/asynchronous-programming/#handle-asynchronous-exceptions)：解释异常如何存储在任务中，以及 `await` 如何重新抛出异常。
- [Task.FromResult<TResult>](https://learn.microsoft.com/zh-cn/dotnet/api/system.threading.tasks.task.fromresult?view=net-10.0)：查阅创建已完成任务的 API 契约。
