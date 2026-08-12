# async Task 与 Task.FromResult 伴随示例

本项目对应 [`DotNet/AsyncTask与Task.FromResult.md`](../../AsyncTask与Task.FromResult.md)，目标框架为 .NET 8，演示：

- 已知同步结果如何使用 `Task.FromResult`。
- 存在真实等待时如何使用 `async` / `await`。
- 普通 `Task<T>` 返回方法与 `async Task<T>` 方法的异常出现时机差异。

运行：

```powershell
dotnet run --project .\DotNet\Examples\AsyncTaskComparison\AsyncTaskComparison.csproj
```
