# Roslyn

## 目录

- [Roslyn 是什么](#roslyn-是什么)
- [整体模型](#整体模型)
- [常用 NuGet 包](#常用-nuget-包)
- [语法分析](#语法分析)
- [语义分析](#语义分析)
- [创建编译并输出程序集](#创建编译并输出程序集)
- [修改代码](#修改代码)
- [Workspace 与解决方案分析](#workspace-与解决方案分析)
- [分析器、代码修复与源生成器](#分析器代码修复与源生成器)
- [关键注意事项](#关键注意事项)
- [参考资料](#参考资料)

## Roslyn 是什么

Roslyn 是 .NET 编译器平台，包含开源的 C#、Visual Basic 编译器以及编译器公开的分析 API。应用程序可以使用与编译器和 IDE 相同的数据模型读取、理解、修改和生成代码。

常见用途包括：

- 编写静态代码分析器和编译诊断。
- 实现代码修复、重构和 IDE 辅助功能。
- 在构建期间生成源代码。
- 分析整个项目或解决方案的依赖关系。
- 构建脚本引擎、代码转换器或领域专用工具。
- 动态创建编译并输出程序集。

Roslyn 提供的是编译器级代码模型，不是用于匹配源码的普通文本工具。只关心少量、结构固定的文本时，字符串或正则表达式可能更简单；需要正确处理注释、泛型、重载、命名空间、条件编译和类型绑定时，应该使用 Roslyn。

## 整体模型

Roslyn 的主要处理过程可以理解为：

```text
源代码
  |
  v
SyntaxTree / SyntaxNode / SyntaxToken / SyntaxTrivia
  |
  v
Compilation + MetadataReference
  |
  v
SemanticModel / ISymbol / IOperation
  |
  +-- Diagnostics
  +-- Emit
```

如果需要跨文档、项目或解决方案工作，还会使用 Workspace 模型：

```text
Workspace -> Solution -> Project -> Document
```

| 层次 | 主要对象 | 解决的问题 |
| --- | --- | --- |
| 语法层 | `SyntaxTree`、`SyntaxNode`、`SyntaxToken`、`SyntaxTrivia` | 源码写了什么、结构是什么。 |
| 语义层 | `Compilation`、`SemanticModel`、`ISymbol`、`IOperation` | 名称指向什么符号、表达式是什么类型、调用绑定到哪个成员。 |
| 编译层 | `CSharpCompilation`、`Diagnostic`、`EmitResult` | 引用是否完整、代码能否编译、如何输出程序集。 |
| 工作区层 | `Workspace`、`Solution`、`Project`、`Document` | 如何读取和修改多项目代码库。 |
| 扩展层 | `DiagnosticAnalyzer`、`CodeFixProvider`、`IIncrementalGenerator` | 如何把规则、修复和代码生成接入 IDE 或构建。 |

这些核心对象大多是不可变对象。调用 `With...`、`Add...`、`Replace...` 等方法通常会返回一个新对象，原对象不会被原地修改。

## 常用 NuGet 包

| 包 | 主要用途 |
| --- | --- |
| `Microsoft.CodeAnalysis.CSharp` | C# 语法、语义和编译 API。 |
| `Microsoft.CodeAnalysis.CSharp.Workspaces` | C# 的 Workspace、格式化和代码操作支持。 |
| `Microsoft.CodeAnalysis.Workspaces.MSBuild` | 通过 `MSBuildWorkspace` 打开项目和解决方案。 |
| `Microsoft.Build.Locator` | 让进程定位并注册可用的 MSBuild/SDK 实例。 |
| `Microsoft.CodeAnalysis.Analyzers` | 编写 Roslyn 分析器时使用的规则和开发辅助。 |

只做单文件语法或语义分析时，通常从下面的包开始：

```powershell
dotnet add package Microsoft.CodeAnalysis.CSharp
```

需要打开 `.csproj` 或 `.sln` 时，再按需加入 Workspace、MSBuild 和 Locator 相关包。包版本应保持兼容，尤其不要在同一工具中混用不同主版本的 `Microsoft.CodeAnalysis.*` 包。

## 语法分析

### 语法对象

Roslyn 语法树会完整保留源码信息，包括空白、换行、注释和预处理指令，因此可以在分析或重写后尽量保持原始代码形态。

| 对象 | 含义 | 示例 |
| --- | --- | --- |
| `SyntaxTree` | 一份源文件对应的完整语法树。 | `CSharpSyntaxTree.ParseText(source)` |
| `SyntaxNode` | 有内部结构的语法元素。 | 类声明、方法声明、表达式。 |
| `SyntaxToken` | 语法树的终端标记。 | 关键字、标识符、运算符、字面量。 |
| `SyntaxTrivia` | Token 前后的附属内容。 | 空白、换行、注释、指令。 |

语法树即使遇到不完整或错误代码也会尽量构造结果。编译器可能插入 `IsMissing == true` 的缺失 Token，并通过诊断描述错误。这一特性使 IDE 能在用户尚未写完代码时继续提供功能。

### 解析并遍历语法树

```csharp
using System;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

const string source = """
using System;

public sealed class Calculator
{
    public int Add(int left, int right) => left + right;
}
""";

SyntaxTree tree = CSharpSyntaxTree.ParseText(source);
CompilationUnitSyntax root = tree.GetCompilationUnitRoot();

MethodDeclarationSyntax method = root.DescendantNodes()
    .OfType<MethodDeclarationSyntax>()
    .Single();

Console.WriteLine(method.Identifier.ValueText);       // Add
Console.WriteLine(method.ParameterList.Parameters.Count); // 2

foreach (Diagnostic diagnostic in tree.GetDiagnostics())
{
    Console.WriteLine(diagnostic);
}
```

常用查找方式包括：

- `ChildNodes()`：只访问当前节点的直接子节点。
- `DescendantNodes()`：递归访问所有后代节点。
- `DescendantTokens()`：访问后代 Token。
- `Ancestors()`：从当前节点向父级查找。
- `FindNode(...)` / `FindToken(...)`：根据源码位置定位元素。

在大型语法树或分析器中，不要无条件反复调用 `DescendantNodes()` 扫描整棵树。优先从已知节点向下查找，或在分析器中直接注册关心的 `SyntaxKind`。

### 位置与文本范围

每个语法元素都可以映射回源文件位置：

```csharp
FileLinePositionSpan lineSpan = method.Identifier
    .GetLocation()
    .GetLineSpan();

Console.WriteLine(lineSpan.StartLinePosition.Line + 1);
Console.WriteLine(lineSpan.StartLinePosition.Character + 1);
```

- `Span` 不包含节点首尾的 Trivia。
- `FullSpan` 包含首尾 Trivia。
- 行号和列号在 API 中通常从 `0` 开始，展示给用户时一般加 `1`。

## 语义分析

语法层只能告诉我们某段文本是标识符或调用表达式，不能判断它实际绑定到哪个类型、方法或变量。语义信息由 `Compilation` 和 `SemanticModel` 提供。

### 创建 SemanticModel

```csharp
using System;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

const string source = """
public sealed class Calculator
{
    public int Add(int left, int right) => left + right;
}
""";

SyntaxTree tree = CSharpSyntaxTree.ParseText(source);

MetadataReference coreLibrary = MetadataReference.CreateFromFile(
    typeof(object).Assembly.Location);

CSharpCompilation compilation = CSharpCompilation.Create(
    assemblyName: "Analysis",
    syntaxTrees: new[] { tree },
    references: new[] { coreLibrary },
    options: new CSharpCompilationOptions(
        OutputKind.DynamicallyLinkedLibrary));

SemanticModel model = compilation.GetSemanticModel(tree);
MethodDeclarationSyntax method = tree.GetRoot()
    .DescendantNodes()
    .OfType<MethodDeclarationSyntax>()
    .Single();

IMethodSymbol? methodSymbol = model.GetDeclaredSymbol(method);
ITypeSymbol? expressionType = model.GetTypeInfo(method.ExpressionBody!.Expression).Type;

Console.WriteLine(methodSymbol?.ToDisplayString());
Console.WriteLine(expressionType?.ToDisplayString()); // int
```

常用语义 API：

| API | 用途 |
| --- | --- |
| `GetDeclaredSymbol(node)` | 获取声明节点创建的符号，例如类、方法、属性或参数。 |
| `GetSymbolInfo(node)` | 获取名称、成员访问、调用等节点绑定到的符号。 |
| `GetTypeInfo(expression)` | 获取表达式的实际类型和转换后类型。 |
| `GetConstantValue(expression)` | 获取编译期常量值。 |
| `GetOperation(node)` | 获取更适合跨语法形态分析的 `IOperation`。 |
| `LookupSymbols(position)` | 查询某个源码位置可见的符号。 |

比较符号时应使用 `SymbolEqualityComparer.Default`，不要只比较名称，也不要假设符号对象引用一定相同：

```csharp
bool sameType = SymbolEqualityComparer.Default.Equals(leftType, rightType);
```

### Syntax 与 Symbol 的区别

一个符号可能在多处源码中声明，例如 `partial class`；某些符号来自元数据，根本没有本地声明语法。因此二者不是一一对应关系：

- 从声明语法到符号：`SemanticModel.GetDeclaredSymbol(...)`。
- 从符号到源码：`ISymbol.DeclaringSyntaxReferences`。
- 元数据符号的 `DeclaringSyntaxReferences` 通常为空。

## 创建编译并输出程序集

`CSharpCompilation` 表示一次完整编译。除了语法树，还必须提供目标框架的元数据引用和编译选项。

下面的示例使用当前进程的 Trusted Platform Assemblies 构造引用集，适合本地工具演示：

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Emit;

const string source = """
public static class Calculator
{
    public static int Add(int left, int right) => left + right;
}
""";

SyntaxTree tree = CSharpSyntaxTree.ParseText(source);

string trustedAssemblies =
    (string?)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")
    ?? throw new InvalidOperationException("无法获取平台程序集列表。");

IEnumerable<MetadataReference> references = trustedAssemblies
    .Split(Path.PathSeparator)
    .Select(path => MetadataReference.CreateFromFile(path));

CSharpCompilation compilation = CSharpCompilation.Create(
    "GeneratedLibrary",
    new[] { tree },
    references,
    new CSharpCompilationOptions(
        OutputKind.DynamicallyLinkedLibrary,
        optimizationLevel: OptimizationLevel.Release));

using var peStream = new MemoryStream();
EmitResult result = compilation.Emit(peStream);

foreach (Diagnostic diagnostic in result.Diagnostics)
{
    Console.WriteLine(diagnostic);
}

if (!result.Success)
{
    throw new InvalidOperationException("编译失败。");
}

byte[] assemblyBytes = peStream.ToArray();
```

实际产品中应使用目标框架的 reference assemblies，保证编译结果与目标框架一致。直接引用当前运行时目录或 `typeof(...).Assembly.Location` 适合小型分析工具和演示，但可能遗漏依赖，也可能意外使用目标框架不支持的 API。

不要直接加载并执行不可信输入编译出的程序集。Roslyn 负责解析和编译，不提供安全沙箱；在当前进程中执行生成代码等同于执行任意代码。

## 修改代码

由于语法树不可变，修改代码的本质是创建替换节点并获得新树。常见方式有：

- 小范围替换：`ReplaceNode`、`ReplaceToken`、`With...`。
- 批量结构化重写：继承 `CSharpSyntaxRewriter`。
- Workspace 文档修改：使用 `DocumentEditor` 或 `SyntaxEditor`。
- 按符号重命名：使用 Workspace 层的 `Renamer`。

### 使用 CSharpSyntaxRewriter

```csharp
using System;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

const string source = "public class Settings { public int Timeout => 42; }";
SyntaxNode root = CSharpSyntaxTree.ParseText(source).GetRoot();

SyntaxNode newRoot = new NumberRewriter().Visit(root)!;
Console.WriteLine(newRoot.NormalizeWhitespace().ToFullString());

sealed class NumberRewriter : CSharpSyntaxRewriter
{
    public override SyntaxNode? VisitLiteralExpression(
        LiteralExpressionSyntax node)
    {
        if (node.IsKind(SyntaxKind.NumericLiteralExpression)
            && node.Token.ValueText == "42")
        {
            return SyntaxFactory.LiteralExpression(
                    SyntaxKind.NumericLiteralExpression,
                    SyntaxFactory.Literal(30))
                .WithTriviaFrom(node);
        }

        return base.VisitLiteralExpression(node);
    }
}
```

`WithTriviaFrom` 用于保留原节点周围的空白和注释。`NormalizeWhitespace()` 会重新规范整棵树的空白，适合示例或新生成的代码；修改现有项目时通常应结合 `Formatter` 和格式化注解，避免无关的整文件格式变更。

直接替换同名 Identifier 并不能可靠地完成重命名，因为同一文本可能对应不同符号，字符串、注释和 `nameof` 也有特殊语义。跨文档重命名应使用 `Renamer`，让 Roslyn 根据符号关系更新引用。

## Workspace 与解决方案分析

Workspace API 把源码组织为不可变的 `Solution`、`Project` 和 `Document` 快照。`MSBuildWorkspace` 可以读取真实的 `.sln` 和 `.csproj`，包括项目引用、源文件、编译选项和条件属性。

```csharp
using System;
using System.Linq;
using Microsoft.Build.Locator;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.MSBuild;

MSBuildLocator.RegisterDefaults();

using var workspace = MSBuildWorkspace.Create();
workspace.WorkspaceFailed += (_, args) =>
    Console.Error.WriteLine(args.Diagnostic.Message);

Solution solution = await workspace.OpenSolutionAsync("MyApp.sln");

foreach (Project project in solution.Projects)
{
    Compilation? compilation = await project.GetCompilationAsync();
    Console.WriteLine($"{project.Name}: {compilation?.SyntaxTrees.Count()} files");
}
```

使用 `MSBuildWorkspace` 时要确保：

- 机器上存在能构建目标项目的 .NET SDK 或 Visual Studio Build Tools。
- 在创建 Workspace 之前完成 `MSBuildLocator` 注册。
- 检查 `WorkspaceFailed`，不要忽略项目加载警告。
- 还原 NuGet 包，并准备项目依赖的 SDK、工作负载和环境属性。

修改 `Document` 后会得到包含新快照的 `Solution`。只有调用 `workspace.TryApplyChanges(newSolution)` 或自行写回文本，修改才会落到工作区；返回 `false` 时应检查当前 Workspace 是否支持对应变更。

## 分析器、代码修复与源生成器

### DiagnosticAnalyzer

分析器在编译期间检查代码，并返回带编号、严重级别、位置和消息的 `Diagnostic`。初始化时通常需要启用并发执行、声明生成代码策略，并注册尽可能精确的分析回调。

```csharp
using System.Collections.Immutable;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class TypeNameAnalyzer : DiagnosticAnalyzer
{
    private static readonly DiagnosticDescriptor Rule = new(
        id: "DEMO001",
        title: "类型名过短",
        messageFormat: "类型名 '{0}' 至少应包含 3 个字符",
        category: "Naming",
        defaultSeverity: DiagnosticSeverity.Warning,
        isEnabledByDefault: true);

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(Rule);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(
            GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(
            AnalyzeClass,
            SyntaxKind.ClassDeclaration);
    }

    private static void AnalyzeClass(SyntaxNodeAnalysisContext context)
    {
        var declaration = (ClassDeclarationSyntax)context.Node;
        string name = declaration.Identifier.ValueText;

        if (name.Length >= 3)
        {
            return;
        }

        context.ReportDiagnostic(Diagnostic.Create(
            Rule,
            declaration.Identifier.GetLocation(),
            name));
    }
}
```

纯结构规则适合 `SyntaxNodeAction`；需要判断类型、重载或继承关系时使用 `SemanticModel`、`ISymbol` 或 `IOperation`。规则面向操作语义且需要同时支持 C# 和 Visual Basic 时，`IOperation` 通常比直接依赖某一种语言的语法节点更合适。

### CodeFixProvider

代码修复根据某个诊断注册一个或多个 `CodeAction`，返回修改后的 `Document` 或 `Solution`。修复应与分析器使用相同的诊断 ID，并支持 `CancellationToken`。如果希望 IDE 提供“修复全部”，还需要提供合适的 `FixAllProvider`。

### 源生成器

源生成器在编译过程中读取当前编译、语法和额外文件，然后向编译加入新的源文件。新项目优先实现 `IIncrementalGenerator`，通过增量管道缓存中间结果，避免每次编辑都重新处理全部输入。

源生成器适合生成可由输入稳定推导出的代码，但它不能修改用户已有源码，也不应依赖不稳定的网络请求、当前时间或任意磁盘状态。生成提示名必须唯一，输出应确定且编码明确。

## 关键注意事项

### 语法正确不等于语义正确

仅解析语法树不会解析项目引用，也不能确认类型、成员或重载是否存在。涉及类型关系和符号身份时必须创建正确的 `Compilation` 并查询语义模型。

### 引用集决定分析结果

缺少元数据引用会产生大量 `CS0012`、`CS0246` 等诊断，也会让候选符号和类型信息不完整。分析真实项目时优先从 `Project.GetCompilationAsync()` 获取编译，而不是手工猜测引用列表。

### 复用 Compilation 和 SemanticModel

创建编译和语义模型有成本。批量分析时应按项目复用 `Compilation`，按语法树复用 `SemanticModel`，并利用不可变快照进行增量更新。不要为每个节点重新创建编译。

### 区分 Type 与 ConvertedType

`GetTypeInfo(expression).Type` 是表达式本身的类型，`ConvertedType` 是上下文转换后的类型。例如把 `int` 表达式赋给 `long` 变量时，两者可能不同。

### 正确处理取消与并发

Workspace、分析器和生成器可能在 IDE 输入期间被频繁取消或并发调用。长循环和异步 API 应传递 `CancellationToken`；分析器启用并发后，回调不能修改未同步的共享状态。

### 控制分析范围

优先注册具体语法种类、符号种类或操作种类，并在编译开始阶段缓存已解析的目标类型。对每个节点扫描整棵语法树或遍历全部引用符号，会明显拖慢 IDE 和构建。

### 不要依赖内部 API

尽量使用公开的 `Microsoft.CodeAnalysis` API。Roslyn 仓库中的内部类型和实现细节不保证兼容，升级 NuGet 包时可能随时变化。

### 保持编译器版本兼容

分析器或生成器最终在宿主编译器中加载。引用比宿主更新的 Roslyn 程序集可能导致加载失败。库作者应根据目标 IDE、SDK 和构建环境选择依赖版本，并在命令行构建与目标 IDE 中都进行测试。

## 参考资料

### 官方资料

1. [Roslyn SDK 概述 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/roslyn-sdk/)
2. [C# 语法分析入门 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/roslyn-sdk/get-started/syntax-analysis)
3. [C# 语义分析入门 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/roslyn-sdk/get-started/semantic-analysis)
4. [使用语法转换修改代码 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/roslyn-sdk/get-started/syntax-transformation)
5. [Roslyn 分析器教程 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/roslyn-sdk/tutorials/how-to-write-csharp-analyzer-code-fix)
6. [源生成器概述 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/csharp/roslyn-sdk/source-generators-overview)
7. [dotnet/roslyn 文档 - GitHub](https://github.com/dotnet/roslyn/tree/main/docs)

### 延伸阅读

1. [Roslyn 中文文档翻译](https://github.com/WeihanLi/roslyn-docs-zh-cn)
2. [Roslyn 语法分析实践](https://www.cnblogs.com/yuxl01/p/19142945)
3. [Roslyn 语义分析实践](https://www.cnblogs.com/yuxl01/p/19149053)
