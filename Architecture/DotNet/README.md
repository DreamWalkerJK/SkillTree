# .NET 体系结构专题

本目录依据 Microsoft .NET Architecture Center 的主题组织五篇文章。示例统一使用 **.NET 10 / C# 14**：服务端采用 ASP.NET Core 10，客户端采用 .NET MAUI 10。其他版本只用于说明功能历史，不作为示例环境。

- [.NET 微服务：容器化 .NET 应用程序的体系结构](NET微服务-容器化应用程序体系结构.md)
- [面向 Web Forms ASP.NET Web Forms 开发人员的 Blazor](面向WebForms开发人员的Blazor.md)
- [构建适用于 Azure 的云原生 .NET 应用](构建适用于Azure的云原生.NET应用.md)
- [使用 ASP.NET Core 和 Azure 构建新式 Web 应用程序](使用ASP.NETCore和Azure构建新式Web应用程序.md)
- [使用 .NET MAUI 的企业应用程序模式](使用.NETMAUI的企业应用程序模式.md)

## 建议阅读顺序

1. 先阅读新式 Web 应用文章，掌握 ASP.NET Core 请求、身份和数据访问流程。
2. 再阅读云原生和微服务文章，理解容器、消息、可观测性和故障恢复。
3. 使用 Blazor 或 .NET MAUI 文章补充客户端迁移与跨平台交付。

## 如何使用参考资料

每篇文末列出对应官方电子书，以及与正文实现直接相关的 API、发布和故障处理资料。电子书用于理解设计思路，当前产品文档用于核对 .NET 10 的具体配置和行为；不要直接照搬旧电子书的包版本或容器标签。

参考入口：[Microsoft .NET Architecture Center](https://learn.microsoft.com/zh-cn/dotnet/architecture/)。MAUI 工作负载有独立的支持期限，升级客户端时还需核对文中链接的平台支持策略。
