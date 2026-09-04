# 构建适用于 Azure 的云原生 .NET 应用

本文结合 Microsoft .NET Cloud Native 和 Azure Architecture Center 的建议，介绍从设计到上线的一套云原生实现。示例以 **.NET 10、ASP.NET Core 10、C# 14** 为主，兼顾 **.NET 8 LTS**；不使用尚未稳定的 .NET 11 API。云原生的重点不是“把程序放进云服务器”，而是让应用能够在自动化平台上独立部署、弹性伸缩、故障恢复和持续交付。

> 主要参考：[构建适用于 Azure 的云原生 .NET 应用](https://learn.microsoft.com/zh-cn/dotnet/architecture/cloud-native/)。

## 1. 云原生设计原则

应用应尽量无状态、可观测、可自动化：

1. **以容器为交付单元**：构建结果可在开发、测试和生产环境一致运行。
2. **外部化配置和状态**：配置来自环境或托管配置中心，状态放在数据库、缓存和对象存储。
3. **自动化生命周期**：基础设施、迁移、部署和回滚都由流水线执行。
4. **弹性优先**：为超时、重试、限流、熔断、降级和重复消息定义明确策略。
5. **可观测性内建**：日志、指标、分布式跟踪和业务审计在第一版就加入。
6. **零信任安全**：服务和用户都必须显式认证、授权，网络位置不能代替权限判断。

## 2. Azure 参考架构

```text
用户 / 合作方
        |
Azure Front Door + WAF + CDN
        |
API Management（版本、配额、策略）
        |
Azure Container Apps Environment 或 AKS
  +-----+---------+------------+
  |               |            |
ASP.NET Core    Worker       Blazor/静态资源
API             Service      Storage + CDN
  |               |
Azure Service Bus  <---->  Event Grid
  |
Azure SQL / PostgreSQL  Redis  Blob Storage
        |
Key Vault + Managed Identity
        |
Azure Monitor + Application Insights + Log Analytics
```

选择托管方式时，优先明确运维职责：

| 服务 | 适用场景 | 主要约束 |
| --- | --- | --- |
| Azure Container Apps | 无需维护 Kubernetes、希望按请求/事件弹性缩放 | 高级网络和调度能力少于 AKS |
| Azure Kubernetes Service（AKS） | 需要自定义调度、服务网格、GPU 或现有 K8s 平台 | 需要维护节点、升级和策略 |
| Azure App Service | 单体或少量 Web API，部署简单 | 复杂事件驱动和多容器编排能力有限 |
| Azure Functions | 事件处理、定时作业、短生命周期函数 | 执行时间、冷启动和状态模型需评估 |

数据库和消息服务尽量使用 PaaS，减少自建集群。跨区域部署时，明确数据驻留、复制延迟和灾难恢复目标（RPO/RTO），不要把“多区域”当成默认答案。

## 3. ASP.NET Core 10 服务实现

### 3.1 配置、健康检查和 OpenTelemetry

```csharp
using Azure.Identity;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);

// .NET 8+：优先使用托管身份从 App Configuration/Key Vault 读取配置。
if (!builder.Environment.IsDevelopment())
{
    var credential = new DefaultAzureCredential();
    builder.Configuration.AddAzureAppConfiguration(options =>
        options.Connect(new Uri(builder.Configuration["AppConfig:Endpoint"]!), credential)
               .UseFeatureFlags());
    builder.Configuration.AddAzureKeyVault(
        new Uri(builder.Configuration["KeyVault:Uri"]!), credential);
}

builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy(), tags: ["live"])
    .AddSqlServer(builder.Configuration.GetConnectionString("MainDb")!,
        tags: ["ready"]);
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService(builder.Environment.ApplicationName))
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddSqlClientInstrumentation())
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddRuntimeInstrumentation()
        .AddProcessInstrumentation());

builder.Services.AddProblemDetails();
builder.Services.AddAzureClients(clients =>
{
    clients.AddBlobServiceClient(new Uri(builder.Configuration["Storage:BlobEndpoint"]!));
    clients.UseCredential(new DefaultAzureCredential());
});

var app = builder.Build();
app.UseExceptionHandler();
app.MapHealthChecks("/health/live", new() { Predicate = c => c.Tags.Contains("live") });
app.MapHealthChecks("/health/ready", new() { Predicate = c => c.Tags.Contains("ready") });
app.MapGet("/api/version", (IHostEnvironment env) =>
    Results.Ok(new { service = env.ApplicationName, version = "2026.09" }));
app.Run();
```

`/health/live` 只判断进程是否能够工作，不访问外部依赖；`/health/ready` 才检查数据库和关键服务。这样数据库短暂故障时，平台会停止分发流量，但不会反复重启所有实例。

### 3.2 事件驱动后台服务

长耗时工作放入 Service Bus 队列，由 `BackgroundService` 消费。每条消息要设置锁续期、最大重试次数和死信处理：

```csharp
using Azure.Messaging.ServiceBus;

public sealed class InvoiceWorker(
    ServiceBusClient bus,
    IServiceScopeFactory scopes,
    ILogger<InvoiceWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await using var processor = bus.CreateProcessor("invoices", new()
        {
            MaxConcurrentCalls = 8,
            PrefetchCount = 32,
            MaxAutoLockRenewalDuration = TimeSpan.FromMinutes(5)
        });
        processor.ProcessMessageAsync += HandleMessageAsync;
        processor.ProcessErrorAsync += args =>
        {
            logger.LogError(args.Exception, "Service Bus 处理错误，实体 {Entity}",
                args.EntityPath);
            return Task.CompletedTask;
        };

        await processor.StartProcessingAsync(stoppingToken);
        try
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
        finally
        {
            await processor.StopProcessingAsync();
        }
    }

    private async Task HandleMessageAsync(ProcessMessageEventArgs args)
    {
        var command = args.Message.Body.ToObjectFromJson<GenerateInvoice>();
        await using var scope = scopes.CreateAsyncScope();
        var handler = scope.ServiceProvider.GetRequiredService<IInvoiceHandler>();
        await handler.HandleAsync(command!, args.CancellationToken);
        await args.CompleteMessageAsync(args.Message);
    }
}

public sealed record GenerateInvoice(Guid OrderId, string IdempotencyKey);
```

处理程序要以 `MessageId` 或业务幂等键去重。对于无法处理的消息，记录原因并转入死信队列；运维人员修复数据后再重放，而不是无限重试。

## 4. 弹性和流量控制

从 .NET 8 开始可使用 `Microsoft.Extensions.Http.Resilience`：

```csharp
builder.Services.AddHttpClient("catalog", client =>
    client.BaseAddress = new Uri(builder.Configuration["Catalog:Url"]!))
    .AddStandardResilienceHandler(options =>
    {
        options.Retry.MaxRetryAttempts = 3;
        options.Retry.Delay = TimeSpan.FromMilliseconds(200);
        options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(3);
        options.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(30);
    });
```

重试必须只针对幂等请求和瞬态错误（连接重置、429、部分 5xx）。为每个依赖设置总超时，保证调用链的超时预算逐层递减。入口使用 ASP.NET Core Rate Limiting（.NET 7 引入，.NET 10 示例）保护共享资源：

```csharp
builder.Services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("api", limiter =>
    {
        limiter.PermitLimit = 100;
        limiter.Window = TimeSpan.FromSeconds(1);
        limiter.QueueLimit = 0;
    });
});
app.UseRateLimiter();
app.MapPost("/api/orders", HandleOrder).RequireRateLimiting("api");
```

## 5. 容器和供应链安全

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ["src/Cloud.Api/Cloud.Api.csproj", "src/Cloud.Api/"]
RUN dotnet restore "src/Cloud.Api/Cloud.Api.csproj"
COPY . .
RUN dotnet publish "src/Cloud.Api/Cloud.Api.csproj" -c Release -o /out \
    --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER $APP_UID
COPY --from=build /out .
ENTRYPOINT ["dotnet", "Cloud.Api.dll"]
```

CI 阶段应锁定 NuGet 版本、启用 `dotnet restore --locked-mode`，生成 SBOM，扫描镜像和依赖漏洞，并使用签名（例如 Notation/Cosign）验证发布来源。运行时使用非 root 用户、只读文件系统和最小 Linux 镜像；不要将编译器和源代码放入最终层。

## 6. 基础设施即代码与部署

Azure 环境可使用 Bicep 或 Terraform。Bicep 片段（.NET 10 Container Apps）：

```bicep
param location string = resourceGroup().location
param image string

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'orders-env'
  location: location
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'orders-api'
  location: location
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      ingress: { external: true, targetPort: 8080, transport: 'auto' }
      dapr: { enabled: false }
      secrets: [{ name: 'registry-password', value: 'set-by-pipeline' }]
    }
    template: {
      containers: [{
        name: 'orders'
        image: image
        resources: { cpu: 0.5, memory: '1Gi' }
        probes: [
          { type: 'Readiness', httpGet: { path: '/health/ready', port: 8080 } },
          { type: 'Liveness', httpGet: { path: '/health/live', port: 8080 } }
        ]
      }]
      scale: {
        minReplicas: 2
        maxReplicas: 20
        rules: [{ name: 'http', http: { metadata: { concurrentRequests: '50' } } }]
      }
    }
  }
}
```

生产流水线建议分为：构建/测试 → 生成并签名镜像 → 部署基础设施 → 执行向后兼容的数据库迁移 → 金丝雀或蓝绿发布 → 冒烟与业务指标验证。将环境参数和密钥作为流水线变量或托管机密注入，代码仓库只保存模板和默认值。

## 7. 数据、缓存和一致性

- Azure SQL/PostgreSQL 保存事务数据；EF Core 迁移由单独作业执行。
- Azure Cache for Redis 用于短 TTL 缓存和分布式锁。缓存失效不是一致性机制，写入数据库后再删除/更新缓存，并设置随机抖动避免同时过期。
- Blob Storage 保存文件和大对象，数据库只存 URL、哈希和内容类型。上传使用短期 SAS，服务端验证大小、扩展名和内容签名。
- Service Bus 用于需要顺序、去重、死信和事务的业务消息；Event Grid 适合资源事件和广播通知。

跨存储写入采用 Outbox/Inbox 或 Saga。不要依赖分布式事务把 SQL、Redis 和消息代理绑定在一起；明确最终一致性的可接受时间和补偿操作。

## 8. 可观测性与运行手册

统一记录 `trace_id`、`span_id`、服务版本、区域和租户（脱敏）。Application Insights 采集请求、依赖、异常和自定义指标；Log Analytics 保存查询和告警规则。至少建立以下仪表板：请求成功率/P95 延迟、CPU/内存/GC、数据库连接池、队列积压、重试/熔断次数、业务转化率。

运行手册应包含：依赖故障时的降级开关、死信重放步骤、数据库恢复和密钥轮换、容量扩展阈值、联系人和最近一次演练时间。告警指向可执行动作，不要为每一条日志创建告警。

## 9. 安全设计

```csharp
builder.Services.AddAuthentication()
    .AddJwtBearer(options =>
    {
        options.Authority = builder.Configuration["Entra:Authority"];
        options.Audience = builder.Configuration["Entra:Audience"];
        options.RequireHttpsMetadata = true;
    });
builder.Services.AddAuthorization(options =>
    options.AddPolicy("orders.write", p =>
        p.RequireClaim("scp", "orders.write")));
```

服务间使用 Managed Identity 获取 Azure 资源令牌；为每个身份授予最小 RBAC 角色。网络层使用私有终结点、VNet 集成和 NSG，公开入口只保留 Front Door/API Management。对输入做长度、格式和业务权限校验，审计高风险操作；日志和追踪中禁止令牌、密码和完整个人信息。

## 10. 测试和灾难恢复

1. 单元测试覆盖领域规则和重试/超时策略。
2. 使用 Testcontainers 或 Azure 开发环境验证真实 SQL、Service Bus 和 Redis 行为。
3. 使用 WireMock.Net 模拟第三方超时、429、错误响应和协议变更。
4. 契约测试锁定事件 JSON、版本和必填字段。
5. 在预生产执行负载、故障注入和滚动升级，观察恢复时间和数据一致性。
6. 定期演练区域故障、数据库 PITR、密钥轮换和消息重放，记录实际 RPO/RTO。

## 11. 版本提示与官方参考

- .NET 8（2023-11，LTS）：容器、Generic Host、HTTP 弹性库生态和 Blazor Web App 的稳定版本，可用于生产环境。
- .NET 9（2024-11，STS）：运行时、容器和云原生工具改进。
- .NET 10（2025-11，当前示例）：ASP.NET Core 10、C# 14；API 以正式 SDK 文档为准。
- .NET 11（预计 2026-11）：截至 2026-09 仍为预览版本，不建议用于生产环境。

官方参考：

- [.NET 云原生应用概述](https://learn.microsoft.com/zh-cn/dotnet/architecture/cloud-native/)
- [Azure Architecture Center](https://learn.microsoft.com/zh-cn/azure/architecture/)
- [Azure 容器应用](https://learn.microsoft.com/zh-cn/azure/container-apps/)
- [AKS 基线参考体系结构](https://learn.microsoft.com/zh-cn/azure/architecture/reference-architectures/containers/aks/secure-baseline-aks)
- [Azure Well-Architected Framework](https://learn.microsoft.com/zh-cn/azure/well-architected/)
- [Azure 托管标识](https://learn.microsoft.com/zh-cn/entra/identity/managed-identities-azure-resources/overview)
- [OpenTelemetry .NET](https://learn.microsoft.com/zh-cn/dotnet/core/diagnostics/observability-with-otel)
