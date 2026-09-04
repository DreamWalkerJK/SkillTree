# .NET 微服务：容器化 .NET 应用程序的体系结构

本文以微软《.NET 微服务：容器化 .NET 应用程序的体系结构》为主线，说明如何把一个业务系统拆分为可独立发布的服务，并使用容器运行。示例代码以 **.NET 10、ASP.NET Core 10、C# 14** 为目标；需要长期支持版本时可将目标框架改为 **.NET 8 LTS**。文中提到的 .NET 11 均表示截至 2026 年仍处于预览阶段的 API，生产环境应先验证兼容性。

> 主要参考：[微服务 .NET 应用体系结构](https://learn.microsoft.com/zh-cn/dotnet/architecture/microservices/)。

## 1. 何时采用微服务

微服务不是把一个项目机械地拆成很多 Web API。拆分的依据是业务能力、数据所有权和发布节奏：订单、库存、结算等能力各自拥有代码、数据模型和运行实例，服务之间通过明确的契约通信。下面的条件同时满足时，拆分才有收益：

- 某项业务需要独立扩缩容或独立发布。
- 团队可以为该业务维护接口、数据迁移和运行监控。
- 调用方能接受网络延迟、重试和暂时不可用。

如果系统规模较小，先做模块化单体通常更经济。模块之间使用内部接口和独立数据库迁移，今后再把模块提取成服务。

## 2. 参考体系结构

```text
客户端/合作方
       |
  Front Door / API 网关（TLS、限流、路由）
       |
  +----+-------------+----------------+
  |                  |                |
订单服务           库存服务         身份服务
  |                  |                |
订单数据库         库存数据库       Entra ID
  +---------异步事件总线--------------+
            Service Bus / RabbitMQ
       |
日志、指标、分布式跟踪（OpenTelemetry + Application Insights）
```

每个服务只直接访问自己的数据库。跨服务查询通过 API 组合、读模型或事件驱动的投影完成；不要让服务共享同一组表。同步调用适合需要立即返回结果的查询，状态变化则优先发布事件。例如订单服务提交 `OrderPlaced`，库存服务消费该事件并扣减库存，失败时通过重试和补偿流程恢复。

### 2.1 解决方案布局

```text
src/
  BuildingBlocks/       # 只放稳定的契约和基础设施抽象
  Order.Api/             # HTTP 入口
  Order.Application/     # 用例、命令、查询
  Order.Domain/          # 聚合和领域规则
  Order.Infrastructure/ # EF Core、消息、外部系统
  Inventory.Api/
tests/
  Order.UnitTests/
  Order.IntegrationTests/
  Order.ContractTests/
deploy/
  docker-compose.yml
  k8s/
```

`BuildingBlocks` 不应成为所有服务的“公共工具箱”。只有跨服务稳定且语义明确的类型（例如事件信封、追踪上下文）才放入其中，否则会把服务重新耦合在一起。

## 3. ASP.NET Core 服务骨架（.NET 10）

下面的示例提供健康检查、问题详情响应、结构化日志和 OpenTelemetry。业务代码应放到应用层，端点只负责协议转换。

```csharp
using System.Diagnostics;
using Microsoft.AspNetCore.Diagnostics;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);

const string serviceName = "orders-api";
builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks()
    // 自检同时用于示例；数据库、消息代理等依赖检查应额外标记为 "ready"。
    .AddCheck("self", () => Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Healthy(), tags: ["live", "ready"]);
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService(serviceName))
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation())
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddRuntimeInstrumentation());
builder.Logging.AddOpenTelemetry(o =>
{
    o.IncludeFormattedMessage = true;
    o.IncludeScopes = true;
});

builder.Services.AddHttpClient<IInventoryClient, InventoryClient>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Inventory:BaseUrl"]!);
    client.Timeout = TimeSpan.FromSeconds(2);
});
builder.Services.AddScoped<OrderApplication>();

var app = builder.Build();
app.UseExceptionHandler();
app.MapHealthChecks("/health/live", new() { Predicate = check => check.Tags.Contains("live") });
app.MapHealthChecks("/health/ready", new() { Predicate = check => check.Tags.Contains("ready") });

app.MapPost("/orders", async (CreateOrderRequest request,
    OrderApplication application, CancellationToken cancellationToken) =>
{
    var id = await application.PlaceAsync(request, cancellationToken);
    return Results.Created($"/orders/{id}", new { id });
});

app.Run();

public sealed record CreateOrderRequest(IReadOnlyList<OrderLine> Lines);
public sealed record OrderLine(string Sku, int Quantity);

public sealed class OrderApplication(IInventoryClient inventory)
{
    public async Task<Guid> PlaceAsync(
        CreateOrderRequest request, CancellationToken cancellationToken)
    {
        if (request.Lines.Count == 0)
            throw new ArgumentException("订单至少包含一项商品");

        await inventory.ReserveAsync(request.Lines, cancellationToken);
        // 实际项目在此处写入订单聚合，并将事件写入 Outbox 表。
        return Guid.NewGuid();
    }
}

public interface IInventoryClient
{
    Task ReserveAsync(IReadOnlyList<OrderLine> lines,
        CancellationToken cancellationToken);
}

public sealed class InventoryClient(HttpClient http) : IInventoryClient
{
    public async Task ReserveAsync(IReadOnlyList<OrderLine> lines,
        CancellationToken cancellationToken)
    {
        using var response = await http.PostAsJsonAsync(
            "/reservations", lines, cancellationToken);
        response.EnsureSuccessStatusCode();
    }
}
```

生产环境不要在每个请求中直接创建 `HttpClient`。`IHttpClientFactory` 会复用连接并处理 DNS 更新；跨服务调用还应配置指数退避、熔断和总超时。可以使用 `Microsoft.Extensions.Http.Resilience`（.NET 8 起提供）统一策略：

```csharp
builder.Services.AddHttpClient<IInventoryClient, InventoryClient>()
    .AddStandardResilienceHandler(options =>
    {
        options.TotalRequestTimeout.Timeout = TimeSpan.FromSeconds(5);
        options.Retry.MaxRetryAttempts = 3;
    });
```

重试只适用于幂等操作。创建订单、扣款等写操作必须使用幂等键（例如 `Idempotency-Key`）或业务流水号，避免重试造成重复扣款。

## 4. 数据一致性与消息

### 4.1 Outbox

数据库提交和事件发送不是一个事务。服务先在同一数据库事务中写入业务数据和 `OutboxMessages`，后台发布器再把未发送消息投递到总线：

```csharp
public sealed class OutboxPublisher(IServiceScopeFactory scopeFactory,
    IMessageBus bus, ILogger<OutboxPublisher> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var scope = scopeFactory.CreateAsyncScope();
                var db = scope.ServiceProvider.GetRequiredService<OrderDbContext>();
                var messages = await db.OutboxMessages
                    .Where(x => x.PublishedAt == null)
                    .OrderBy(x => x.Id)
                    .Take(100)
                    .ToListAsync(stoppingToken);

                foreach (var message in messages)
                {
                    await bus.PublishAsync(message.Type, message.Payload,
                        message.Id, stoppingToken); // message.Id 作为幂等键
                    message.PublishedAt = DateTimeOffset.UtcNow;
                }

                await db.SaveChangesAsync(stoppingToken);
                await Task.Delay(TimeSpan.FromSeconds(1), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "发布 Outbox 消息失败");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }
    }
}
```

消费者必须支持重复投递。可以保存已处理的事件 ID，或让更新语句天然幂等（例如 `UPDATE ... WHERE Version < @EventVersion`）。消息应带有 `MessageId`、`CorrelationId`、`OccurredAt` 和版本号，契约变更采用向后兼容的新增字段。

### 4.2 Saga 与补偿

跨服务业务流程使用 Saga。编排式 Saga 由一个协调器按顺序调用服务；协作式 Saga 由各服务监听事件。每一步定义补偿动作，例如“扣库存成功、支付失败”时释放库存。补偿不是数据库回滚，必须记录状态、重试次数和人工介入入口。

## 5. 容器镜像

`Dockerfile` 使用多阶段构建，运行阶段只保留 ASP.NET Core Runtime。下面示例对应 .NET 10；将两个基础镜像标签同时改为 `8.0` 即可用于 .NET 8 LTS。

```dockerfile
# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ["src/Order.Api/Order.Api.csproj", "src/Order.Api/"]
RUN dotnet restore "src/Order.Api/Order.Api.csproj"
COPY . .
RUN dotnet publish "src/Order.Api/Order.Api.csproj" \
    -c Release -o /app/publish --no-restore \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
EXPOSE 8080
USER $APP_UID
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "Order.Api.dll"]
```

容器内应用应把日志写到标准输出，把配置放到环境变量或密钥提供程序中，不要把连接字符串写进镜像。固定基础镜像摘要并定期扫描漏洞；发布时为镜像标记不可变的 Git 提交号，而不是只使用 `latest`。

## 6. 本地组合与 Kubernetes

本地开发可用 Docker Compose 启动服务和依赖：

```yaml
services:
  orders:
    build:
      context: .
      dockerfile: src/Order.Api/Dockerfile
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ConnectionStrings__Orders: Host=postgres;Database=orders;Username=app;Password=dev-only
      Inventory__BaseUrl: http://inventory:8080
    ports: ["8081:8080"]
    depends_on:
      postgres:
        condition: service_healthy
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: app
      POSTGRES_PASSWORD: dev-only
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d orders"]
      interval: 5s
      timeout: 3s
      retries: 10
```

Kubernetes 部署至少应定义探针、资源限制和滚动更新策略：

> 以下 `myregistry.azurecr.io` 是镜像仓库占位符。部署流水线应在渲染清单时替换为实际 Azure Container Registry 登录服务器，并优先使用不可变 digest。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-api
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxUnavailable: 0, maxSurge: 1 }
  selector:
    matchLabels: { app: orders-api }
  template:
    metadata:
      labels: { app: orders-api }
    spec:
      containers:
      - name: orders
        image: myregistry.azurecr.io/orders-api:git-abc123
        ports: [{ containerPort: 8080 }]
        readinessProbe:
          httpGet: { path: /health/ready, port: 8080 }
        livenessProbe:
          httpGet: { path: /health/live, port: 8080 }
        resources:
          requests: { cpu: 100m, memory: 256Mi }
          limits: { cpu: 500m, memory: 512Mi }
---
apiVersion: v1
kind: Service
metadata: { name: orders-api }
spec:
  selector: { app: orders-api }
  ports: [{ port: 80, targetPort: 8080 }]
```

数据库迁移不要在每个副本启动时同时执行。将 `dotnet ef database update` 放到一次性的发布作业中，或使用版本化迁移工具；应用启动只检查兼容性。先部署可读旧字段的代码，再迁移数据，最后删除旧字段，保证滚动发布期间新旧版本都能工作。

## 7. 安全、配置与可观测性

- 使用 OAuth 2.0/OIDC（Azure 上通常为 Microsoft Entra ID），服务间使用客户端凭据或工作负载身份。JWT 验证必须检查签发者、受众、签名和有效期。
- 使用 Key Vault、Kubernetes Secret 或云平台托管密钥。应用通过 `DefaultAzureCredential` 获取令牌，开发机可使用 Azure CLI 登录，生产环境使用托管身份。
- 每个请求生成或转发 `traceparent`；日志包含 `TraceId`、业务键和用户/租户标识，但不要记录令牌和个人敏感数据。
- 为 HTTP、数据库、消息队列记录延迟、错误率、队列积压和重试次数。定义服务级别目标（例如 99.9% 请求在 500 ms 内完成），并为告警设置持续时间，避免单次尖峰触发。

## 8. 测试与发布检查

1. 单元测试验证领域规则，不依赖数据库和网络。
2. 集成测试使用 Testcontainers 启动真实 PostgreSQL、Redis 或消息代理，验证迁移、事务和序列化。
3. 契约测试确保提供方和消费者对事件/API 的理解一致；破坏性变更先在 CI 中拒绝。
4. 端到端测试覆盖关键 Saga，并模拟超时、重复消息和依赖不可用。
5. 负载测试观察 P95/P99 延迟、连接池、GC 和队列积压；根据结果设置副本数和资源请求。
6. 发布流水线执行镜像扫描、依赖审计、迁移作业和冒烟测试，再逐步放量。保留上一版本镜像和数据库备份，回滚时同时考虑事件和数据兼容性。

## 9. 常见误区

- 服务只是按技术层拆分，订单和库存仍共享表；这会使发布和故障恢复重新绑定。
- 把所有调用都改成异步消息，导致查询链路难以追踪。根据一致性要求选择同步或异步。
- 无限制重试。重试应有总超时、退避和熔断，并区分可重试的瞬态错误与业务拒绝。
- 只监控容器存活，不监控依赖可用性和业务指标。存活探针与就绪探针应承担不同职责。
- 把配置、证书或开发密码烘焙到镜像层。镜像层会长期保留这些内容，即使后来删除文件也可能被恢复。

## 10. 版本提示

| 能力 | 首次可用/当前示例 |
| --- | --- |
| .NET 8 LTS、容器化 ASP.NET Core | 2023-11，生产支持至 2026-11 |
| `Microsoft.Extensions.Http.Resilience` 标准弹性处理程序 | .NET 8 生态，示例按 .NET 10 API 编写 |
| .NET 9 | 2024-11，标准期限支持 |
| .NET 10、C# 14、ASP.NET Core 10 | 2025-11，本文主要示例版本 |
| .NET 11 | 预计 2026-11；截至本文日期为预览，不用于生产环境 |

## 官方参考

- [微服务 .NET 应用的体系结构](https://learn.microsoft.com/zh-cn/dotnet/architecture/microservices/)
- [多容器和微服务型 .NET 应用](https://learn.microsoft.com/zh-cn/dotnet/architecture/microservices/multi-container-microservice-net-applications/)
- [使用 Docker 容器化 .NET 应用](https://learn.microsoft.com/zh-cn/dotnet/core/docker/build-container)
- [ASP.NET Core Docker 部署](https://learn.microsoft.com/zh-cn/aspnet/core/host-and-deploy/docker/)
- [ASP.NET Core 健康检查](https://learn.microsoft.com/zh-cn/aspnet/core/host-and-deploy/health-checks)
- [OpenTelemetry .NET 可观测性](https://learn.microsoft.com/zh-cn/dotnet/core/diagnostics/observability-with-otel)
- [Azure 架构中心：微服务](https://learn.microsoft.com/zh-cn/azure/architecture/guide/architecture-styles/microservices)
