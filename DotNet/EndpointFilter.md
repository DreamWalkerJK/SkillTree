# <center>EndpointFilter</center>

## 目录

- [EndpointFilter 是什么](#endpointfilter-是什么)
- [适用场景](#适用场景)
- [执行模型](#执行模型)
- [注册方式](#注册方式)
- [三种实现方式](#三种实现方式)
- [常见用法](#常见用法)
- [与中间件和 MVC Filter 的区别](#与中间件和-mvc-filter-的区别)
- [关键注意事项](#关键注意事项)
- [参考资料](#参考资料)

## EndpointFilter 是什么

`EndpointFilter` 是 ASP.NET Core Endpoint 层面的过滤器机制，常用于 Minimal API 中，在端点处理程序执行前后插入横切逻辑，例如参数校验、日志记录、结果包装和简单的访问控制。

它的核心接口是 `IEndpointFilter`：

```csharp
public interface IEndpointFilter
{
    ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next);
}
```

其中：

- `EndpointFilterInvocationContext` 提供当前请求的 `HttpContext`、已绑定的端点参数列表 `Arguments`，以及 `GetArgument<T>(index)` 这类快捷方法。
- `EndpointFilterDelegate next` 表示过滤器链中的下一个过滤器；如果当前过滤器是最后一个，则代表实际的端点处理程序。

`EndpointFilter` 不等同于 MVC 的 `ActionFilter`。在较新的 ASP.NET Core 版本中，Endpoint Filter 可以通过 `ControllerActionEndpointConventionBuilder` 应用到 Controller Action，但它仍然是 Endpoint 层的过滤器，不是 MVC Filter 管道里的 `IActionFilter`。

## 适用场景

适合放在 `EndpointFilter` 中的逻辑通常具备两个特点：只关心某些端点，并且需要访问端点绑定后的参数或返回值。

常见场景：

- 参数或请求体校验。
- 记录端点执行前后的日志。
- 根据端点参数做轻量级拦截。
- 修改或包装端点返回值。
- 根据端点签名批量应用某类校验。

如果逻辑需要作用于整个 HTTP 管道，例如统一异常处理、请求日志、CORS、认证授权中间件等，通常优先使用中间件或 ASP.NET Core 内置能力。

## 执行模型

### 执行位置

一次请求进入 ASP.NET Core 管道后，大致顺序如下：

```text
HTTP Middleware
  -> Endpoint Routing
  -> Endpoint Filter
  -> Endpoint Handler
  -> Endpoint Filter
  -> HTTP Middleware
```

对 Minimal API 来说，过滤器执行时，路由匹配和参数绑定已经完成，因此可以直接读取绑定后的参数。

### 多个过滤器的执行顺序

同一个端点上可以注册多个过滤器。它们进入时按注册顺序执行，退出时按相反顺序执行。

```csharp
app.MapGet("/ping", () => "pong")
    .AddEndpointFilter(async (context, next) =>
    {
        Console.WriteLine("A before");
        var result = await next(context);
        Console.WriteLine("A after");
        return result;
    })
    .AddEndpointFilter(async (context, next) =>
    {
        Console.WriteLine("B before");
        var result = await next(context);
        Console.WriteLine("B after");
        return result;
    });
```

执行结果：

```text
A before
B before
Endpoint Handler
B after
A after
```

### 短路

过滤器如果不调用 `next(context)`，而是直接返回结果，就会短路后续过滤器和端点处理程序。

```csharp
app.MapGet("/admin", () => Results.Ok("admin"))
    .AddEndpointFilter((context, next) =>
    {
        var user = context.HttpContext.User;

        if (user.Identity?.IsAuthenticated != true)
        {
            return new ValueTask<object?>(Results.Unauthorized());
        }

        return next(context);
    });
```

短路时直接返回 `Results.Forbid()`、`Results.Unauthorized()`、`Results.BadRequest(...)` 等对象即可。`EndpointFilterInvocationContext` 没有 `Result` 属性，不应写成 `context.Result = ...`。

## 注册方式

### 注册到单个端点

```csharp
app.MapGet("/weather/{city}", (string city) => $"Weather of {city}")
    .AddEndpointFilter<LoggingEndpointFilter>();
```

### 注册到路由分组

当一组端点需要共享过滤逻辑时，优先使用 `MapGroup`：

```csharp
var api = app.MapGroup("/api")
    .AddEndpointFilter<LoggingEndpointFilter>();

api.MapGet("/users/{id:int}", (int id) => Results.Ok(new { Id = id }));
api.MapPost("/users", (CreateUserRequest request) => Results.Created($"/api/users/1", request));
```

分组过滤器会应用到该分组下的所有端点。嵌套分组时，外层过滤器先进入，内层过滤器后进入。

### 注册到 Controller Action

如果项目同时使用 Minimal API 和 Controller，也可以把 Endpoint Filter 应用到 Controller Action 对应的 Endpoint 上：

```csharp
app.MapControllers()
    .AddEndpointFilter(async (context, next) =>
    {
        context.HttpContext.Items["endpointFilterCalled"] = true;
        return await next(context);
    });
```

这种写法适合复用 Endpoint 层过滤逻辑。但如果逻辑依赖 MVC 的模型状态、ActionContext、ResultFilter、ExceptionFilter 等能力，应继续使用 MVC Filter。

## 三种实现方式

### 1. 内联 Lambda

适合只在当前端点使用的简单逻辑。

```csharp
app.MapGet("/color/{name}", (string name) => $"Color: {name}")
    .AddEndpointFilter(async (context, next) =>
    {
        var color = context.GetArgument<string>(0);

        if (string.Equals(color, "red", StringComparison.OrdinalIgnoreCase))
        {
            return Results.BadRequest("Red is not allowed.");
        }

        return await next(context);
    });
```

### 2. 实现 IEndpointFilter

适合可复用逻辑。过滤器类型可以通过构造函数使用 DI 中的服务。

```csharp
public sealed class LoggingEndpointFilter : IEndpointFilter
{
    private readonly ILogger<LoggingEndpointFilter> _logger;

    public LoggingEndpointFilter(ILogger<LoggingEndpointFilter> logger)
    {
        _logger = logger;
    }

    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var endpointName = context.HttpContext.GetEndpoint()?.DisplayName;
        _logger.LogInformation("Before endpoint: {EndpointName}", endpointName);

        var result = await next(context);

        _logger.LogInformation("After endpoint: {EndpointName}", endpointName);
        return result;
    }
}
```

注册：

```csharp
app.MapGet("/data", () => Results.Ok(new[] { 1, 2, 3 }))
    .AddEndpointFilter<LoggingEndpointFilter>();
```

注意：`AddEndpointFilter<TFilter>()` 可以为过滤器构造函数解析依赖，但过滤器类型本身不是通过 `builder.Services.AddScoped<LoggingEndpointFilter>()` 这种方式注册和解析的常规服务。

### 3. AddEndpointFilterFactory

`AddEndpointFilterFactory` 适合根据端点方法签名、元数据等信息决定是否应用某个过滤逻辑。它在端点构建阶段执行，可以缓存反射得到的信息，避免每次请求重复检查。

```csharp
app.MapPost("/todos", (Todo todo) => Results.Created($"/todos/{todo.Id}", todo))
    .AddEndpointFilterFactory((factoryContext, next) =>
    {
        var parameters = factoryContext.MethodInfo.GetParameters();
        var shouldValidateTodo =
            parameters.Length > 0 &&
            parameters[0].ParameterType == typeof(Todo);

        if (!shouldValidateTodo)
        {
            return invocationContext => next(invocationContext);
        }

        return async invocationContext =>
        {
            var todo = invocationContext.GetArgument<Todo>(0);

            if (string.IsNullOrWhiteSpace(todo.Name))
            {
                return Results.BadRequest("Todo name is required.");
            }

            return await next(invocationContext);
        };
    });
```

## 常见用法

### 参数校验

```csharp
public sealed class CreateUserValidationFilter : IEndpointFilter
{
    public ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var request = context.GetArgument<CreateUserRequest>(0);

        if (string.IsNullOrWhiteSpace(request.Name))
        {
            return new ValueTask<object?>(Results.BadRequest("Name is required."));
        }

        return next(context);
    }
}
```

### 包装返回值

```csharp
public sealed class ApiResponseFilter : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var result = await next(context);

        return Results.Ok(new
        {
            Success = true,
            Data = result
        });
    }
}
```

包装返回值时要小心：如果 `result` 本身已经是 `IResult`，再次用 `Results.Ok(...)` 包一层可能改变状态码、响应头或序列化行为。统一响应结构最好结合具体项目约定处理。

### 使用 HttpContext 和 DI 服务

```csharp
public sealed class TenantFilter : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(
        EndpointFilterInvocationContext context,
        EndpointFilterDelegate next)
    {
        var tenantService = context.HttpContext.RequestServices.GetRequiredService<TenantService>();
        var tenantId = context.HttpContext.Request.Headers["X-Tenant-Id"].ToString();

        if (!await tenantService.ExistsAsync(tenantId))
        {
            return Results.Forbid();
        }

        return await next(context);
    }
}
```

对于 Scoped 服务，在过滤器方法内通过 `context.HttpContext.RequestServices` 获取，可以明确依赖属于当前请求作用域。

## 与中间件和 MVC Filter 的区别

| 维度 | EndpointFilter | Middleware | MVC Filter |
| --- | --- | --- | --- |
| 作用层级 | Endpoint 层 | HTTP 管道层 | MVC Action / Result 等阶段 |
| 常见注册位置 | `MapGet`、`MapPost`、`MapGroup`、`MapControllers` 后链式调用 | `app.Use(...)` | Attribute、`MvcOptions.Filters`、`ServiceFilter` 等 |
| 是否能访问绑定后的端点参数 | 可以 | 通常不可以 | 可以访问 MVC Action 参数 |
| 是否适合全局 HTTP 处理 | 不适合 | 适合 | 只适合 MVC 范围 |
| 是否能包装端点返回值 | 可以 | 不直接适合 | 可以包装 MVC Action/Result |
| 典型场景 | Minimal API 参数校验、端点级日志、结果转换 | 全局异常、认证授权、CORS、请求日志 | MVC 授权、资源、Action、异常、Result 处理 |

一句话区分：

- 中间件关注整个 HTTP 请求管道。
- MVC Filter 关注 MVC/Razor Pages 的各个执行阶段。
- EndpointFilter 关注某个 Endpoint 的参数、处理程序和返回值。

## 关键注意事项

- `EndpointFilter` 的短路方式是直接返回结果，并且不调用 `next(context)`。
- 过滤器返回类型是 `ValueTask<object?>`，返回 `Results.*`、普通对象或 `IResult` 都可以，但要留意最终响应语义。
- 读取端点参数优先使用 `context.GetArgument<T>(index)` 或 `context.Arguments`，因为此时参数已经完成绑定。
- 多个过滤器的前置逻辑按注册顺序执行，后置逻辑按注册的反向顺序执行。
- 过滤器应保持轻量。全局异常处理、认证授权、CORS、静态文件、压缩等 HTTP 管道能力应放在中间件或框架内置机制中。
- 授权优先使用 `RequireAuthorization()`、授权策略或内置认证授权中间件；过滤器更适合补充端点级的业务校验。
- 对于需要跨多个端点复用的逻辑，优先注册到 `MapGroup`，避免每个端点重复链式调用。
- 对于依赖端点签名的逻辑，优先考虑 `AddEndpointFilterFactory`，把反射检查放在构建阶段。

## 参考资料

### 官方资料

1. [Filters in Minimal API apps - Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/min-api-filters?view=aspnetcore-10.0)
2. [IEndpointFilter Interface - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.iendpointfilter?view=aspnetcore-10.0)
3. [IEndpointFilter.InvokeAsync Method - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.iendpointfilter.invokeasync?view=aspnetcore-10.0)
4. [Filters in ASP.NET Core - Microsoft Learn](https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/filters?view=aspnetcore-10.0)

### 延伸阅读

1. [ASP.NET Core Minimal API Endpoint Filters - Khalid Abuhakmeh](https://khalidabuhakmeh.com/aspnet-core-minimal-api-endpoint-filters)
2. [Minimal API validation with ASP.NET 7.0 Endpoint Filters - Ben Foster](https://benfoster.io/blog/minimal-api-validation-endpoint-filters/)
