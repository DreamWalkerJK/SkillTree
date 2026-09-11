# C# 与 .NET 10 伴随示例

这些项目对应 [CSharp 和 .NET Core 的高阶用法](../../CSharp和NET-LTS中高阶指南.md)，全部使用 .NET 10（`net10.0`）和 C# 14。文档中的特性引入版本说明保留不变；较早版本引入的功能，也在 .NET 10 项目中演示。

- `Net10Features`：演示 C# 14 和 .NET 10 新增功能。
- `LanguageFeatures`：演示主构造函数、集合表达式、内联数组、冻结集合和 `TimeProvider` 等较早引入的功能。
- `AdvancedPatterns`：包含泛型、Span、异步流、Channel 和可观测性示例。
- `AdvancedWebApi`：包含 Typed Results、Problem Details、异常处理、Options、Keyed DI 和 JSON 源生成示例。

## 构建与运行

以下命令在当前 README 所在的 `DotNet/Examples/CSharpNetLts` 目录执行。`global.json` 指定 .NET SDK 10.0.102，允许使用同一功能带的较新补丁，不使用预览 SDK；`dotnet --version` 可以确认实际选中的版本。

```powershell
dotnet --version
dotnet restore .\CSharpNetLts.slnx
dotnet build .\CSharpNetLts.slnx --no-restore
```

运行控制台示例：

```powershell
dotnet run --project .\Net10Features\Net10Features.csproj --no-build
dotnet run --project .\LanguageFeatures\LanguageFeatures.csproj --no-build
dotnet run --project .\AdvancedPatterns\AdvancedPatterns.csproj --no-build
```

运行 Web API：

```powershell
dotnet run --project .\AdvancedWebApi\AdvancedWebApi.csproj --no-build -- --urls http://localhost:5000
```

随后可使用 `AdvancedWebApi/AdvancedWebApi.http` 或任意 HTTP 客户端验证端点。

这些项目只包含指南中选取的可执行示例。构建成功能验证项目内的源码，不表示仓库中每个 Markdown 代码片段都已经独立编译，也不代替性能基准测试或真实部署测试。

## 已执行的检查

2026-09-11 在 Windows x64、.NET SDK 10.0.102 下执行了上述还原和构建命令，四个项目均成功，构建输出为 0 个警告、0 个错误；三个控制台程序均正常运行。

Web API 在本机启动后检查了 `/products/1`、`/products?take=2`、`/time` 的成功响应、`/products/999` 的 404 响应以及 `/boom` 的 500 Problem Details 响应。这是本机功能检查，没有覆盖身份认证、负载、容器或云平台部署。

## 其他 .NET 伴随示例

- [`async Task<T>` 与 `Task.FromResult`](../AsyncTaskComparison/README.md)：演示完成任务、真实异步等待以及异常出现时机。

## 参考资料

- [选择 .NET SDK 版本：global.json](https://learn.microsoft.com/zh-cn/dotnet/core/tools/global-json)：说明 SDK 版本选择、补丁滚动和预览版本设置。
- [C# 语言版本配置](https://learn.microsoft.com/zh-cn/dotnet/csharp/language-reference/configure-language-version)：说明目标框架、默认语言版本和 `LangVersion` 的关系。
- [.NET 10 新增功能](https://learn.microsoft.com/zh-cn/dotnet/core/whats-new/dotnet-10/overview)：可用于查阅运行时和基础类库的变化。
