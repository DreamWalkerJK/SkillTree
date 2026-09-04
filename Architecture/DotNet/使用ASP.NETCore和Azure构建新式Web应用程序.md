# 使用 ASP.NET Core 和 Azure 构建新式 Web 应用程序

本文面向需要在 Azure 上交付现代 Web 应用的团队，覆盖 ASP.NET Core 10 的请求处理、数据访问、身份、安全、可观测性和部署。代码以 **.NET 10、C# 14** 为例，也适用于 **.NET 8 LTS**；.NET 11 在 2026 年 9 月仍是预览阶段，不作为生产依赖。

> 主要参考：[使用 ASP.NET Core 和 Azure 构建新式 Web 应用程序](https://learn.microsoft.com/zh-cn/dotnet/architecture/modern-web-apps-azure/)。

## 1. 端到端架构

```text
浏览器 / 移动端 / 合作方
          |
Azure Front Door（CDN、WAF、TLS、全球路由）
          |
Azure App Service 或 Container Apps
  ASP.NET Core 10（MVC / Razor Pages / Minimal API / Blazor）
          |
  应用服务和领域层
    |          |             |
Azure SQL   Redis       Blob Storage
    |
Application Insights + Log Analytics + OpenTelemetry
```

请求链路按职责分层：边缘层处理 TLS/WAF，ASP.NET Core 中间件处理关联 ID、异常、认证和限流，端点映射到应用服务，应用服务调用领域模型和基础设施。页面渲染与 API 可以放在同一主机，也可以独立部署；无论哪种方式，都应保持清晰的 API 契约和独立的授权检查。

## 2. 项目结构与启动配置

```text
src/WebApp/
  Program.cs
  Features/Orders/          # 按业务功能组织端点、模型和验证
  Domain/                   # 领域实体和规则
  Infrastructure/          # EF Core、Blob、Redis、外部 API
  wwwroot/
tests/
  WebApp.UnitTests/
  WebApp.IntegrationTests/
```

按功能切片比把所有 Controller、Service 和 DTO 分成三个大目录更容易维护。`Program.cs` 只负责组合依赖和中间件顺序：

```csharp
using Microsoft.AspNetCore.HttpLogging;
using Microsoft.EntityFrameworkCore;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorPages();
builder.Services.AddControllers();
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("MainDb")));
builder.Services.AddStackExchangeRedisCache(options =>
    options.Configuration = builder.Configuration.GetConnectionString("Redis"));
builder.Services.AddProblemDetails();
builder.Services.AddHttpLogging(o =>
{
    o.LoggingFields = HttpLoggingFields.RequestPropertiesAndHeaders |
                      HttpLoggingFields.ResponsePropertiesAndHeaders;
});
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService("modern-web"))
    .WithTracing(t => t.AddAspNetCoreInstrumentation()
                       .AddHttpClientInstrumentation()
                       .AddEntityFrameworkCoreInstrumentation());
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>("sql");

builder.Services.AddAuthentication("Cookies")
    .AddCookie("Cookies", options =>
    {
        options.LoginPath = "/account/sign-in";
        options.AccessDeniedPath = "/account/denied";
    });
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("orders.read", p => p.RequireClaim("permission", "orders.read"));

var app = builder.Build();
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/error");
    app.UseHsts();
}
app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseHttpLogging();
app.UseAuthentication();
app.UseAuthorization();
app.MapHealthChecks("/health");
app.MapControllers();
app.MapRazorPages();
app.Run();

public partial class Program { } // 供 WebApplicationFactory 使用
```

中间件顺序有实际语义：异常处理应尽量靠前，静态文件可在认证前短路，认证必须早于授权，端点映射放在末尾。生产环境不要记录请求体和 `Authorization` 标头；如需审计，使用脱敏的业务事件。

## 3. Minimal API 与 API 契约

Minimal API 适合职责明确的小型端点，也适合按功能切片的大型应用。使用 `TypedResults` 可让 OpenAPI 和编译器获得更精确的返回类型：

```csharp
public static class OrderEndpoints
{
    public static IEndpointRouteBuilder MapOrderEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/orders")
            .RequireAuthorization("orders.read")
            .WithTags("Orders");

        group.MapGet("/{id:guid}", async Task<Results<Ok<OrderDto>, NotFound>>
            (Guid id, AppDbContext db, CancellationToken ct) =>
        {
            var dto = await db.Orders.AsNoTracking()
                .Where(o => o.Id == id)
                .Select(o => new OrderDto(o.Id, o.Number, o.Status))
                .SingleOrDefaultAsync(ct);
            return dto is null ? TypedResults.NotFound() : TypedResults.Ok(dto);
        });
        return endpoints;
    }
}

public sealed record OrderDto(Guid Id, string Number, string Status);
```

公开 API 要有版本策略。可以在 URL（`/api/v1/orders`）、请求头或媒体类型中版本化；一旦发布，不能随意修改字段含义。使用 `Microsoft.AspNetCore.OpenApi` 生成 OpenAPI 文档，再在 CI 中比较契约，发现破坏性变更时阻止合并。

## 4. 数据访问和缓存

EF Core 查询使用投影、分页和 `AsNoTracking`，避免将实体图直接暴露给 API：

```csharp
public sealed class OrderQuery(AppDbContext db, IDistributedCache cache)
{
    public async Task<IReadOnlyList<OrderDto>> ListAsync(
        int page, int size, CancellationToken ct)
    {
        page = Math.Max(page, 1);
        size = Math.Clamp(size, 1, 100);
        var key = $"orders:{page}:{size}";
        var bytes = await cache.GetAsync(key, ct);
        if (bytes is not null)
            return JsonSerializer.Deserialize<IReadOnlyList<OrderDto>>(bytes)!;

        var rows = await db.Orders.AsNoTracking()
            .OrderByDescending(x => x.CreatedAt)
            .Skip((page - 1) * size)
            .Take(size)
            .Select(x => new OrderDto(x.Id, x.Number, x.Status))
            .ToListAsync(ct);
        await cache.SetStringAsync(key, JsonSerializer.Serialize(rows),
            new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(30)
            }, ct);
        return rows;
    }
}
```

缓存是性能优化，不是数据源。写入后删除相关键或使用版本化键；设置 TTL 和容量上限，避免缓存雪崩。对需要强一致性的余额、库存等数据直接读数据库，并通过并发令牌或数据库约束防止覆盖更新。

## 5. 身份、授权和密钥

Azure 应用常使用 Microsoft Entra ID 的 OpenID Connect。Web 应用验证 Cookie，API 验证 Bearer 令牌：

```csharp
builder.Services.AddAuthentication()
    .AddMicrosoftIdentityWebApp(builder.Configuration.GetSection("Entra"),
        cookieScheme: "Cookies")
    .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("Entra"),
        jwtBearerScheme: "Bearer");
```

业务授权应使用策略或资源授权，而不是在页面中判断角色字符串：

```csharp
public sealed class OrderOwnerHandler :
    AuthorizationHandler<OperationAuthorizationRequirement, Order>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        OperationAuthorizationRequirement requirement,
        Order resource)
    {
        var subject = context.User.FindFirst("sub")?.Value;
        if (requirement.Name == "Read" && resource.OwnerId == subject)
            context.Succeed(requirement);
        return Task.CompletedTask;
    }
}
```

使用 `DefaultAzureCredential` 访问 Key Vault、Storage 和 Service Bus；本地可使用 Azure CLI 凭据，云上使用托管身份。轮换密钥时让应用同时接受旧/新密钥一段时间，并监控获取令牌失败率。

## 6. 前端与实时通信

Razor Pages/MVC 适合服务器渲染和内容站点；Blazor 适合组件化交互；SPA 则通过 API 与后端分离。不要因为“现代”而默认选择 SPA：首屏、SEO、团队技能和缓存要求可能更适合服务器渲染。实时功能可使用 SignalR：

```csharp
builder.Services.AddSignalR();
app.MapHub<NotificationHub>("/hubs/notifications");

public sealed class NotificationHub : Hub
{
    public Task JoinTenant(string tenantId) =>
        Groups.AddToGroupAsync(Context.ConnectionId, $"tenant:{tenantId}");
}
```

客户端订阅前必须通过服务端验证租户权限。多实例部署时使用 Azure SignalR Service 或 Redis backplane；不要把连接状态放在单实例内存中。

## 7. 部署到 Azure App Service

App Service 适合无状态 Web 应用和中等流量 API。发布前设置目标框架、健康检查和部署槽位：

```powershell
dotnet publish -c Release -f net10.0
az webapp deploy --resource-group rg-modern-web `
  --name modern-web-prod --src-path .\bin\Release\net10.0\publish
az webapp config set --resource-group rg-modern-web `
  --name modern-web-prod --generic-configurations '{"healthCheckPath":"/health"}'
```

将 `staging` 槽位连接到同版本数据库，执行冒烟测试后交换槽位。数据库迁移采用向后兼容的两阶段脚本，避免交换期间旧实例无法读取新结构。为 App Service 设置最小实例数、自动扩展规则、部署槽位和备份策略；诊断日志发送到 Log Analytics，不要依赖实例本地文件。

## 8. 部署到 Azure Container Apps

Container Apps 支持 HTTP、队列和自定义 KEDA 缩放。镜像使用非 root 用户，应用监听 `8080`，通过就绪探针控制流量。每次发布使用唯一镜像标签并保留上一个修订版本，可快速回滚：

> `registry.azurecr.io` 为 Azure Container Registry 登录服务器示例，部署前替换为实际注册表名称；生产流水线应锁定镜像 digest。

```powershell
az containerapp update --name modern-web --resource-group rg-modern-web `
  --image registry.azurecr.io/modern-web:git-abc123 `
  --revision-suffix abc123 --min-replicas 2 --max-replicas 20
```

密钥通过 Container Apps Secret 引用，应用只读取环境变量名；日志和指标接入 Azure Monitor。若需要自定义网络、节点池或服务网格，评估 AKS 的额外运维成本后再迁移。

## 9. 测试和质量门禁

- **单元测试**：领域规则、授权处理程序、序列化和错误映射。
- **集成测试**：`WebApplicationFactory` + Testcontainers 验证真实数据库、缓存和消息代理。
- **契约测试**：OpenAPI 和事件模式向后兼容；消费者驱动测试防止字段误删。
- **浏览器测试**：Playwright 验证登录、CSRF、重试、SignalR 断线和关键表单。
- **安全测试**：依赖漏洞扫描、静态分析、令牌过期、越权和注入测试。
- **性能测试**：k6/ NBomber 测量 P50/P95/P99、吞吐、GC、数据库连接和缓存命中率。

流水线最少包括 `dotnet restore --locked-mode`、`dotnet build -warnaserror`、测试覆盖率、镜像扫描、IaC 校验和部署后健康检查。故障注入测试要覆盖数据库不可用、令牌服务超时、第三方 429 和消息重复。

## 10. 版本与官方参考

- ASP.NET Core 8/.NET 8（2023-11，LTS）：本文部署模型可采用的稳定版本。
- ASP.NET Core 9/.NET 9（2024-11，STS）：性能和诊断改进。
- ASP.NET Core 10/.NET 10（2025-11，当前示例）：C# 14 和最新 SDK 工具链。
- .NET 11（预计 2026-11）：预览版本，需单独验证后再采用。

官方资料：

- [ASP.NET Core 文档](https://learn.microsoft.com/zh-cn/aspnet/core/)
- [.NET Architecture Center](https://learn.microsoft.com/zh-cn/dotnet/architecture/)
- [Azure Web 应用体系结构](https://learn.microsoft.com/zh-cn/azure/architecture/web-apps/)
- [Azure Well-Architected Framework：可靠性](https://learn.microsoft.com/zh-cn/azure/well-architected/reliability/)
- [ASP.NET Core 在 Azure 上的部署](https://learn.microsoft.com/zh-cn/aspnet/core/host-and-deploy/azure-apps)
- [ASP.NET Core SignalR](https://learn.microsoft.com/zh-cn/aspnet/core/signalr/introduction)
- [Azure App Configuration](https://learn.microsoft.com/zh-cn/azure/azure-app-configuration/overview)
- [Azure Key Vault](https://learn.microsoft.com/zh-cn/azure/key-vault/general/overview)
