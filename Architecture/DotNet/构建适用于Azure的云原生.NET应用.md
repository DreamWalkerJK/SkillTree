# 构建适用于 Azure 的云原生 .NET 应用

本文结合 Microsoft .NET Cloud Native 和 Azure Architecture Center 的建议，介绍从设计到上线的一套云原生实现。示例统一采用 **.NET 10、ASP.NET Core 10、C# 14**，应用目标框架为 `net10.0`，不使用预览 API。云原生的重点不是“把程序放进云服务器”，而是让应用能够在自动化平台上独立部署、弹性伸缩、故障恢复和持续交付。

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

// .NET 10：优先使用托管身份从 App Configuration/Key Vault 读取配置。
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
            AutoCompleteMessages = false,
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
        p.RequireAuthenticatedUser().RequireAssertion(context =>
            context.User.FindAll("scp").Any(claim =>
                claim.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries)
                    .Contains("orders.write", StringComparer.Ordinal)))));
```

服务间使用 Managed Identity 获取 Azure 资源令牌；为每个身份授予最小 RBAC 角色。网络层使用私有终结点、VNet 集成和 NSG，公开入口只保留 Front Door/API Management。对输入做长度、格式和业务权限校验，审计高风险操作；日志和追踪中禁止令牌、密码和完整个人信息。

## 10. 测试和灾难恢复

1. 单元测试覆盖领域规则和重试/超时策略。
2. 使用 Testcontainers 或 Azure 开发环境验证真实 SQL、Service Bus 和 Redis 行为。
3. 使用 WireMock.Net 模拟第三方超时、429、错误响应和协议变更。
4. 契约测试锁定事件 JSON、版本和必填字段。
5. 在预生产执行负载、故障注入和滚动升级，观察恢复时间和数据一致性。
6. 定期演练区域故障、数据库 PITR、密钥轮换和消息重放，记录实际 RPO/RTO。

## 11. 根据积压计算消费者容量

队列深度只能说明有多少工作尚未领取，最老消息的等待时间更接近用户感受到的延迟。发布器停止发送时，队列深度甚至会下降，因此还要同时观察 Outbox 积压、消息进入速率、处理成功速率和死信数量。

用平均处理时间做一次粗略估算：若每秒进入 50 条消息，每条平均处理 0.4 秒，系统至少需要约 20 个同时执行的处理位置。每个副本并行处理 8 条，以 70% 的目标利用率留出波动余量，副本数约为 `ceil(50 × 0.4 / (8 × 0.7)) = 4`。这不是容量承诺：长尾任务、锁竞争、外部 API 限额和数据库连接池都可能改变结果，应通过负载测试修正。

扩容上限还要服从下游容量。例如数据库允许该工作负载最多使用 80 个连接，20 个副本各并行 8 条且每条长期持有连接，就可能产生 160 个并发请求。此时只增加副本会把排队位置从消息代理转移到数据库，吞吐不一定增加。可以减少消费者并行度、缩短事务、批量写入，或按租户/业务优先级建立独立队列。

### 11.1 记录真正有解释力的处理指标

以下代码使用 **.NET 10 / C# 14 的 `System.Diagnostics.Metrics` 和 `TimeProvider`**，测量一次处理尝试的时间和结果。`TimeProvider` 在 .NET 8 引入，便于在测试中控制时间；`Meter` 指标 API 在 .NET 6 引入。

```csharp
using System.Diagnostics.Metrics;

public sealed class ProcessingMetrics(TimeProvider clock)
{
    public const string MeterName = "FieldOps.Worker";
    private static readonly Meter Meter = new(MeterName, "1.0.0");
    private static readonly Histogram<double> Duration =
        Meter.CreateHistogram<double>("work.attempt.duration", "s");
    private static readonly Counter<long> Attempts =
        Meter.CreateCounter<long>("work.attempts");

    public async Task MeasureAsync(
        Func<CancellationToken, Task> action, CancellationToken ct)
    {
        long started = clock.GetTimestamp();
        string outcome = "failure";
        try
        {
            await action(ct);
            outcome = "success";
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            outcome = "canceled";
            throw;
        }
        finally
        {
            var tag = new KeyValuePair<string, object?>("outcome", outcome);
            Duration.Record(clock.GetElapsedTime(started).TotalSeconds, tag);
            Attempts.Add(1, tag);
        }
    }
}
```

在启动代码中注册 `TimeProvider.System` 和 `ProcessingMetrics`，并在 OpenTelemetry 指标配置中调用 `AddMeter(ProcessingMetrics.MeterName)`。还需配置实际的指标导出器；只注册采集库不会自动把数据送到 Azure Monitor。不要把订单 ID、完整 URL 或用户 ID 当作指标标签，否则时间序列数量会随业务数据持续增长。业务 ID 放入经过脱敏的日志或采样追踪，指标标签使用少量固定类别。

上述成功数表示“处理尝试成功”，可能包括 Inbox 命中的重复投递，不等于新增发票数。业务指标应在事务提交后按实际变化记录；需要财务准确性的统计仍应从业务账表生成，不能用可能丢失或重复采集的遥测代替。

### 11.2 扩容和停机应遵循同一套处理约定

容器收到停止通知后，消费者应先停止领取新消息，再等待在途事务结束。已提交业务但未确认的消息可以重新投递；未提交的事务应回滚。不要为了让停止更快，在业务完成之前确认消息。

ASP.NET Core/Generic Host 可以配置优雅停机等待时间，以下为 **.NET 10 / C# 14** 启动片段：

```csharp
builder.Services.Configure<HostOptions>(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(45);
});
```

该设置只控制主机愿意等待多久，平台的终止宽限时间必须比它更长，并留出网络连接关闭的时间。若业务经常超过该期限，应把任务拆成可恢复步骤，而不是无限延长停机。消息锁失效后不能继续假设自己独占处理权；处理状态需要数据库条件更新或 Inbox 约束保护。

Service Bus 的预取也会消耗消息锁时间。处理很慢时，将 `PrefetchCount` 设置得过大，会使消息还在本地缓冲区就接近锁过期。根据最大处理时间、并行数和锁续期行为做实测，不要仅以减少网络请求为目标增大预取。

## 12. 把区域恢复写成可执行演练

先给数据分类：数据库事务记录、尚未发布的 Outbox、消息代理里的待处理消息、Blob 对象和配置密钥具有不同复制方式，不能用一个“跨区域复制已打开”结论代表全部数据已经安全。RPO 是可接受的数据丢失时间，RTO 是恢复服务所需时间；目标应对应具体业务，例如“订单不丢失”和“报表允许落后 15 分钟”可以采用不同方案。

一次预生产演练可按以下顺序执行：

1. 在写入测试订单时记录最后成功业务号和数据库恢复点，停止主区域的测试入口。
2. 在恢复区域还原数据库，确认应用身份能访问数据库、Key Vault 和 Blob；避免临时使用管理员密码掩盖权限配置缺失。
3. 核对消息产品当前选用的复制功能究竟复制实体配置还是消息数据，并检查未发布 Outbox 是否随数据库恢复。不能假设仅有命名空间别名切换就恢复所有消息。
4. 先让消费者按受控速率恢复，验证 Inbox 去重与库存/账目不变量，再逐步开放请求入口。
5. 对比恢复后的业务号、文件引用和补偿记录，分别记录数据缺口、恢复耗时及人工步骤。

不要在故障尚未排除时让两个区域同时接受同一业务键的写入。决定谁可以写入需要明确的主写区域切换和旧区域隔离方案；DNS 已切换不代表旧连接已经终止。演练报告应保留还原点、镜像版本、配置版本和验证结果，下一次发布才能判断恢复步骤是否仍然有效。

## 13. 版本提示与官方参考

- .NET 8（2023-11，LTS）：容器、Generic Host、HTTP 弹性库生态和 Blazor Web App 的稳定版本，可用于生产环境。
- .NET 9（2024-11，STS）：运行时、容器和云原生工具改进。
- .NET 10（2025-11，当前示例）：ASP.NET Core 10、C# 14；API 以正式 SDK 文档为准。
- .NET 11（预计 2026-11）：截至 2026-09 仍为预览版本，不建议用于生产环境。

### 参考资料

- [云原生应用的弹性模式](https://learn.microsoft.com/zh-cn/dotnet/architecture/cloud-native/application-resiliency-patterns)：区分超时、重试、熔断各自处理的问题。
- [Service Bus 消息锁与确认](https://learn.microsoft.com/zh-cn/azure/service-bus-messaging/message-transfers-locks-settlement)：对照本文的续锁、处理失败和重复投递场景。
- [Azure Container Apps 修订版本](https://learn.microsoft.com/zh-cn/azure/container-apps/revisions)：核对发布、流量分配与回滚的实际操作。

- [.NET 云原生应用概述](https://learn.microsoft.com/zh-cn/dotnet/architecture/cloud-native/)
- [Azure Architecture Center](https://learn.microsoft.com/zh-cn/azure/architecture/)
- [Azure 容器应用](https://learn.microsoft.com/zh-cn/azure/container-apps/)
- [AKS 基线参考体系结构](https://learn.microsoft.com/zh-cn/azure/architecture/reference-architectures/containers/aks/secure-baseline-aks)
- [Azure Well-Architected Framework](https://learn.microsoft.com/zh-cn/azure/well-architected/)
- [Azure 托管标识](https://learn.microsoft.com/zh-cn/entra/identity/managed-identities-azure-resources/overview)
- [OpenTelemetry .NET](https://learn.microsoft.com/zh-cn/dotnet/core/diagnostics/observability-with-otel)
