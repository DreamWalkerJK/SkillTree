# C# 与 .NET LTS 伴随示例

这些项目对应 `DotNet/CSharp和NET-LTS中高阶指南.md`，只覆盖当前两代 LTS：

- `Net10Features`：C# 14 与 .NET 10。
- `Net8Features`：C# 12 与 .NET 8。
- `AdvancedPatterns`：以 .NET 8 为最低基线的泛型、Span、异步流、Channel 和可观测性示例。
- `AdvancedWebApi`：以 .NET 8 为最低基线的 Typed Results、Problem Details、异常处理、Options、Keyed DI 和 JSON 源生成示例；可直接升级到 `net10.0`。

构建全部项目：

```powershell
dotnet build .\CSharpNetLts.slnx
```

运行控制台示例：

```powershell
dotnet run --project .\Net10Features\Net10Features.csproj
dotnet run --project .\Net8Features\Net8Features.csproj
dotnet run --project .\AdvancedPatterns\AdvancedPatterns.csproj
```

运行 Web API：

```powershell
dotnet run --project .\AdvancedWebApi\AdvancedWebApi.csproj --urls http://localhost:5000
```

随后可使用 `AdvancedWebApi/AdvancedWebApi.http` 或任意 HTTP 客户端验证端点。
