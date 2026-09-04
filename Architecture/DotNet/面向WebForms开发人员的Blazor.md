# 面向 Web Forms ASP.NET Web Forms 开发人员的 Blazor

本文按照 Microsoft Architecture Center 的迁移思路，把熟悉 ASP.NET Web Forms 的开发经验映射到 Blazor。示例以 **.NET 10、ASP.NET Core 10、C# 14** 编写；**Blazor Web App 和统一渲染模型在 .NET 8 引入**，需要长期支持时可选择 **.NET 8 LTS**。本文不依赖 .NET 11 的预览 API。

> 主要参考：[面向 Web Forms 开发人员的 Blazor](https://learn.microsoft.com/zh-cn/dotnet/architecture/blazor-for-web-forms-developers/)。

## 1. 编程模型的变化

Web Forms 把页面生命周期、服务器控件和 ViewState 作为主要抽象。Blazor 把 UI 建模为组件：组件拥有参数、可变状态和渲染输出，状态改变后只更新受影响的 DOM。组件通常是 `.razor` 文件，也可以用 `.razor` 加 C# 部分类实现。

| Web Forms 概念 | Blazor 对应物 | 迁移注意事项 |
| --- | --- | --- |
| `.aspx` 页面 | 路由组件（`@page`） | URL 参数通过路由模板或 `[SupplyParameterFromQuery]` 绑定 |
| UserControl | 可复用组件 | 用 `[Parameter]` 暴露输入，用 `EventCallback<T>` 通知父组件 |
| Page_Load / 生命周期 | `OnInitialized{Async}`、`OnParametersSet{Async}`、`OnAfterRender{Async}` | 生命周期可能在预渲染和交互阶段各运行一次，要避免重复副作用 |
| ViewState | 组件字段、浏览器存储或服务器状态 | Blazor 不会自动序列化所有页面状态，需明确选择存储位置 |
| PostBack | 事件回调或表单提交 | 事件在服务器（Interactive Server）或浏览器（WebAssembly）执行 |
| UpdatePanel | 组件级重新渲染 | 不需要局部刷新脚本；大列表应使用虚拟化 |
| Session | `IHttpContextAccessor`（仅静态 SSR）或缓存/数据库 | 交互式组件不应依赖请求级 `HttpContext` |
| `web.config` | `appsettings*.json`、环境变量、托管配置 | 秘密值使用 Key Vault 或平台密钥，不提交到仓库 |

迁移时先划分页面和控件的业务职责，把数据访问移到注入的服务中，再把显示部分转换成组件。不要把现有的 Web Forms 控件逐个“翻译”为组件，否则会保留 ViewState 和事件链造成的隐式耦合。

## 2. .NET 8+ Blazor Web App 架构

从 .NET 8 开始，Blazor Web App 允许一个应用同时使用静态服务器端渲染（Static SSR）和交互式渲染。每个组件可以声明渲染模式：

- **Static**：服务器生成 HTML 后结束请求，适合内容页和搜索引擎索引。
- **Interactive Server**：浏览器通过 SignalR 与服务器保持连接，首屏小、可直接访问服务器资源，但连接数和网络延迟会影响体验。
- **Interactive WebAssembly**：组件在浏览器运行，服务器只提供 API；首次下载较大，适合离线或高交互场景。
- **Interactive Auto**：先使用服务器交互快速响应，客户端资源下载完成后切换到 WebAssembly。切换期间必须保证两端行为一致。

典型部署拓扑如下：

```text
浏览器
  |
Azure Front Door / CDN（TLS、WAF、缓存）
  |
Blazor Web App（ASP.NET Core 10）
  |-- 静态 SSR / Interactive Server（SignalR）
  |-- API、认证、领域服务
  |
Azure SQL / Redis / Blob Storage / 外部 API
```

如果使用 Interactive Server，负载均衡器需要支持 WebSocket，并配置粘性会话或共享 Data Protection 密钥。更大规模的应用可采用 Azure SignalR Service，把连接管理移出应用实例。WebAssembly 模式应将 API 和静态资源分别部署，并为 API 设置 CORS 和令牌验证。

## 3. 创建项目和配置渲染模式

使用 .NET 10 SDK：

```powershell
dotnet new blazor -n Portal --interactivity Auto
dotnet run --project Portal
```

`Program.cs`：

```csharp
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents()
    .AddInteractiveWebAssemblyComponents();
builder.Services.AddCascadingAuthenticationState();
builder.Services.AddAuthentication()
    .AddMicrosoftIdentityWebApp(builder.Configuration.GetSection("AzureAd"));
builder.Services.AddAuthorization();
builder.Services.AddHttpClient<OrderClient>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Backend:BaseUrl"]!);
});

var app = builder.Build();
app.UseExceptionHandler("/Error");
app.UseStaticFiles();
app.UseAntiforgery();
app.UseAuthentication();
app.UseAuthorization();

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode()
    .AddInteractiveWebAssemblyRenderMode();

app.Run();
```

在页面上声明交互模式：

```razor
@page "/orders"
@rendermode InteractiveServer
@inject OrderClient Client

<h1>订单</h1>
<button class="btn btn-primary" @onclick="ReloadAsync">刷新</button>

@if (_orders is null)
{
    <p>正在加载...</p>
}
else
{
    <ul>
        @foreach (var order in _orders)
        {
            <li>@order.Number — @order.Status</li>
        }
    </ul>
}

@code {
    private IReadOnlyList<OrderSummary>? _orders;

    protected override async Task OnInitializedAsync()
        => await ReloadAsync();

    private async Task ReloadAsync()
        => _orders = await Client.ListAsync();
}
```

预渲染时 `OnInitializedAsync` 可能先运行一次，建立交互连接后又运行一次。读取数据的组件应使用持久化组件状态或幂等缓存避免重复请求：

```csharp
public sealed class OrderClient(HttpClient http)
{
    public async Task<IReadOnlyList<OrderSummary>> ListAsync(
        CancellationToken cancellationToken = default)
        => await http.GetFromJsonAsync<IReadOnlyList<OrderSummary>>(
            "/api/orders", cancellationToken) ?? [];
}

public sealed record OrderSummary(string Number, string Status);
```

## 4. 组件通信与表单

父组件通过参数传入数据，子组件通过 `EventCallback<T>` 回传事件：

```csharp
public partial class SearchBox
{
    [Parameter] public string? Value { get; set; }
    [Parameter] public EventCallback<string?> ValueChanged { get; set; }

    private Task OnInput(ChangeEventArgs args)
        => ValueChanged.InvokeAsync(args.Value?.ToString());
}
```

对应的 Razor 标记：

```razor
<input value="@Value" @oninput="OnInput" class="form-control" />
```

表单使用 `EditForm`、`EditContext` 和数据注解验证。复杂规则可实现 `ValidationAttribute` 或自定义 `FieldCssClassProvider`。提交处理程序必须检查授权和并发版本，不能只依赖客户端验证：

```razor
<EditForm Model="_model" OnValidSubmit="SaveAsync">
    <DataAnnotationsValidator />
    <ValidationSummary />
    <InputText @bind-Value="_model.Name" />
    <ValidationMessage For="@(() => _model.Name)" />
    <button type="submit" disabled="@_saving">保存</button>
</EditForm>
```

```csharp
public sealed class CustomerModel
{
    [Required, StringLength(100)]
    public string Name { get; set; } = "";
}
```

## 5. 从 Web Forms 迁移的分阶段方案

1. **建立 API 契约**：把现有页面背后的业务操作抽成 ASP.NET Core API 或应用服务，先用集成测试固定行为。
2. **共享认证**：将 Forms Authentication 迁移到 OpenID Connect/Microsoft Entra ID。迁移期间可在 ASP.NET Core 中验证旧 Cookie，但不要把旧 Cookie 暴露给 WebAssembly。
3. **外壳先行**：创建 Blazor Web App，保留旧 Web Forms 站点，通过反向代理按路径逐步切换。
4. **页面按业务迁移**：先迁移无状态查询页，再迁移包含复杂表单和后台作业的页面。每次迁移都删除旧页面的入口和重复授权规则。
5. **替换控件库**：Web Forms 控件的服务器事件改为组件参数和回调；JavaScript 插件通过 `IJSRuntime` 封装在一个服务中，不要在各组件直接拼接脚本。
6. **下线旧运行时**：完成流量切换、日志比对和回滚演练后，再移除 System.Web 依赖和旧部署管道。

迁移期间要特别检查三类隐含行为：ViewState 中保存的默认值、PostBack 触发的隐式数据绑定，以及页面级静态字段。Blazor 组件实例的生命周期不同于 Web Forms 页面，静态字段会被所有用户共享。

## 6. JavaScript 互操作

把 JavaScript 调用集中到模块中，并在组件销毁时释放 `IJSObjectReference`：

```csharp
public sealed class ChartModule(IJSRuntime js) : IAsyncDisposable
{
    private IJSObjectReference? _module;

    public async ValueTask RenderAsync(ElementReference element,
        IReadOnlyList<double> values)
    {
        _module ??= await js.InvokeAsync<IJSObjectReference>(
            "import", "./js/chart.js");
        await _module.InvokeVoidAsync("render", element, values);
    }

    public async ValueTask DisposeAsync()
    {
        if (_module is not null)
            await _module.DisposeAsync();
    }
}
```

不要把未验证的用户输入拼接进 JavaScript 字符串。交互式服务器模式下，互操作只能在浏览器连接建立后调用，通常放在 `OnAfterRenderAsync(firstRender: true)` 中。

## 7. 认证、授权与数据保护

```csharp
builder.Services.AddMicrosoftIdentityWebAppAuthentication(
        builder.Configuration, "AzureAd")
    .EnableTokenAcquisitionToCallDownstreamApi()
    .AddMicrosoftGraph(builder.Configuration.GetSection("Graph"))
    .AddInMemoryTokenCaches();
```

生产环境把 `ClientSecret` 放入 Azure Key Vault，并使用托管身份读取。多实例 Interactive Server 部署时，将 Data Protection 密钥保存到 Blob Storage 或 Redis，否则重启后用户 Cookie 和防伪令牌可能无法解密。授权策略应在 API 端再次执行，组件上的 `[Authorize]` 只负责界面和路由保护。

## 8. 性能与可用性

- 只对需要交互的组件启用交互渲染；静态内容保持 Static SSR，减少 SignalR 连接。
- 大列表使用 `Virtualize<TItem>`，服务端查询采用分页和投影，不要把整个实体图发送到浏览器。
- WebAssembly 发布启用 Brotli 压缩和缓存控制；为静态资源使用内容哈希，避免旧文件污染。
- Interactive Server 设置连接上限、断线重连策略和反向代理 WebSocket 超时；长任务交给队列和 `BackgroundService`。
- 使用 `EventCounters`、OpenTelemetry 和浏览器性能面板分别观察服务器、网络和客户端。

## 9. 测试

- 组件单元测试使用 bUnit，验证参数、回调、验证消息和渲染分支。
- API 使用 `WebApplicationFactory<TEntryPoint>` 验证认证、授权、序列化和数据库事务。
- Playwright 或 Selenium 覆盖登录、断线重连、表单重复提交和浏览器回退。
- 对 WebAssembly 模式执行真实浏览器测试，不能只在服务器端渲染快照上通过。
- 迁移项目应保留旧页面与新组件的契约测试，比较关键业务操作的结果和审计记录。

## 10. 版本与官方参考

- .NET 8（2023-11，LTS）：Blazor Web App、Static SSR、Interactive Server/WebAssembly/Auto 渲染模式。
- .NET 9（2024-11，STS）：Blazor 性能、表单和开发体验改进。
- .NET 10（2025-11，当前示例）：ASP.NET Core 10 与 C# 14；具体 API 以目标 SDK 文档为准。
- .NET 11（预计 2026-11）：截至本文日期仍为预览版本，部署前需单独验证。

官方资料：

- [Blazor 概述（ASP.NET Core 10）](https://learn.microsoft.com/zh-cn/aspnet/core/blazor/?view=aspnetcore-10.0)
- [ASP.NET Core Blazor 渲染模式](https://learn.microsoft.com/zh-cn/aspnet/core/blazor/components/render-modes)
- [面向 Web Forms 开发人员的 Blazor 电子书](https://learn.microsoft.com/zh-cn/dotnet/architecture/blazor-for-web-forms-developers/)
- [Blazor 表单和验证](https://learn.microsoft.com/zh-cn/aspnet/core/blazor/forms/)
- [Blazor JavaScript 互操作](https://learn.microsoft.com/zh-cn/aspnet/core/blazor/javascript-interoperability/)
- [Blazor 安全性](https://learn.microsoft.com/zh-cn/aspnet/core/blazor/security/)
- [.NET Architecture Center](https://learn.microsoft.com/zh-cn/dotnet/architecture/)
