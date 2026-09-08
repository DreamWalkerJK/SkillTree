# 依赖注入（DI）与 AOP

> 版本信息：Microsoft.Extensions.DependencyInjection 随 .NET Core 1.0 提供，Generic Host 于 .NET Core 2.1 成熟；Keyed services 于 .NET 8 引入；AOP 不是 C# 内置功能，常用 DispatchProxy、装饰器、拦截器或编译期源生成。示例目标为 `net8.0`，可迁移到 .NET 10；.NET 11 Preview 需按目标 SDK 验证。

依赖注入把对象创建和依赖关系交给容器，业务类只声明所需抽象。面向切面编程（AOP）把日志、事务、缓存、授权等横切逻辑集中处理，但必须保持调用链可追踪。

## 基础注册

~~~csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddSingleton<IClock, SystemClock>();
builder.Services.AddTransient<ReceiptFormatter>();

WebApplication app = builder.Build();
~~~

生命周期：

- Singleton 在容器生命周期内单例，必须线程安全，不能直接依赖 Scoped。
- Scoped 每个请求或显式 scope 一个实例。
- Transient 每次解析创建新实例。

后台服务是 Singleton；需要数据库等 Scoped 依赖时创建 IServiceScope：

~~~csharp
public sealed class Worker(IServiceScopeFactory scopes) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken token)
    {
        using IServiceScope scope = scopes.CreateScope();
        var service = scope.ServiceProvider.GetRequiredService<IOrderService>();
        await service.RunAsync(token);
    }
}
~~~

## Keyed services（.NET 8）

~~~csharp
using Microsoft.AspNetCore.Mvc;

builder.Services.AddKeyedSingleton<INotifier, EmailNotifier>("email");
builder.Services.AddKeyedSingleton<INotifier, SmsNotifier>("sms");

public sealed class AlertController
{
    private readonly INotifier _notifier;

    public AlertController(
        [FromKeyedServices("email")] INotifier notifier)
        => _notifier = notifier;

    public Task SendAsync(string text) => _notifier.SendAsync(text);
}
~~~

避免 Service Locator（在业务类中到处调用 IServiceProvider）；构造函数注入让依赖显式、易测。检测循环依赖并在启动时启用 ValidateOnBuild、ValidateScopes。

## AOP 方式

装饰器无需运行时代码生成，适合稳定切面：

~~~csharp
public sealed class LoggingOrderService(
    IOrderService inner, ILogger<LoggingOrderService> logger) : IOrderService
{
    public async Task<Order> GetAsync(
        int id, CancellationToken token)
    {
        var started = Stopwatch.GetTimestamp();
        try { return await inner.GetAsync(id, token); }
        finally
        {
            logger.LogInformation("GetOrder {Id} took {Elapsed} ms",
                id, Stopwatch.GetElapsedTime(started).TotalMilliseconds);
        }
    }
}
~~~

DispatchProxy（.NET Standard 2.0）可拦截虚拟接口调用，但反射和动态代理会增加开销，并可能不兼容 NativeAOT。第三方容器（Autofac、Scrutor、Castle DynamicProxy）提供装饰器扫描和拦截器，选型时评估许可证、启动时间和裁剪支持。

## 高级实践

- 把事务范围放在应用服务或消息处理器，不要在每个仓储方法重复开启事务。
- AOP 切面只处理横切关注点，不改变业务返回语义。
- 日志、指标和追踪应使用 OpenTelemetry 语义，避免切面吞掉异常。
- 用源生成器生成 DI 注册可减少反射；在 NativeAOT 发布中优先编译期方案。

## 生命周期与作用域

Singleton 不能直接保存请求级的 Scoped 服务。后台服务是 Singleton，处理一次消息时应通过 `IServiceScopeFactory` 创建作用域，并在工作单元结束时释放数据库上下文等资源。

~~~csharp
public sealed class InvoiceWorker(
    IServiceScopeFactory scopes,
    ChannelReader<Guid> reader) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken token)
    {
        await foreach (var id in reader.ReadAllAsync(token))
        {
            await using AsyncServiceScope scope =
                scopes.CreateAsyncScope();
            var handler = scope.ServiceProvider
                .GetRequiredService<IInvoiceHandler>();
            await handler.HandleAsync(id, token);
        }
    }
}
~~~

AOP 适合记录耗时、授权和事务边界。切面必须保留取消和异常语义，不能把业务异常转换成成功结果；对于需要调试的系统，还应把 trace id 贯穿切面日志和下游调用。

## 工程示例：装饰器实现审计

装饰器是最容易调试的 AOP 形式之一。它把横切逻辑写成普通类，依赖关系可以在注册处直接看到，也不依赖运行时代理。

~~~csharp
public interface IInvoiceHandler
{
    Task HandleAsync(Guid invoiceId, CancellationToken token);
}

public sealed class InvoiceHandler : IInvoiceHandler
{
    public Task HandleAsync(Guid invoiceId, CancellationToken token)
        => Task.CompletedTask;
}

public sealed class AuditingHandler(
    IInvoiceHandler inner,
    ILogger<AuditingHandler> logger) : IInvoiceHandler
{
    public async Task HandleAsync(Guid invoiceId, CancellationToken token)
    {
        var started = Stopwatch.GetTimestamp();
        try
        {
            await inner.HandleAsync(invoiceId, token);
            logger.LogInformation("Invoice {InvoiceId} handled in {ElapsedMs} ms",
                invoiceId, Stopwatch.GetElapsedTime(started).TotalMilliseconds);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Invoice {InvoiceId} failed", invoiceId);
            throw;
        }
    }
}
~~~

切面日志只记录稳定字段和耗时，不能记录完整请求体、令牌或连接字符串。多个装饰器的顺序会改变语义，例如事务应包住真正的业务调用，重试应位于能够判断幂等性的边界。
