# <center>ChangeTracker.TrackGraph</center>

## 目录

- [ChangeTracker.TrackGraph 是什么](#changetrackertrackgraph-是什么)
- [适用场景](#适用场景)
- [执行模型](#执行模型)
- [方法重载](#方法重载)
- [EntityState 决策](#entitystate-决策)
- [代码示例](#代码示例)
- [与 Add、Attach、Update 的区别](#与-addattachupdate-的区别)
- [关键注意事项](#关键注意事项)
- [参考资料](#参考资料)

## ChangeTracker.TrackGraph 是什么

`ChangeTracker.TrackGraph` 是 EF Core 提供的实体图追踪 API。它从一个根实体开始，沿着导航属性递归遍历整张对象图，并在访问每个实体时调用回调函数，让调用方决定该实体应该以什么 `EntityState` 被当前 `DbContext` 追踪。

它主要用于断开连接场景，例如 Web API 中：

1. 第一次请求用一个 `DbContext` 查询实体。
2. 实体被序列化并发送到客户端。
3. 客户端修改后再提交回来。
4. 服务端使用新的 `DbContext` 保存这些改动。

此时新的 `DbContext` 并不知道这些对象是新增、修改、删除还是保持不变。`TrackGraph` 的价值就是把“每个节点如何保存”的判断权交给业务代码。

需要注意：`TrackGraph` 只负责把实体放入变更追踪器并设置状态，不会自动调用 `SaveChanges`，也不会自动从数据库补齐未加载的导航属性。

## 适用场景

适合使用 `TrackGraph` 的情况通常具备两个特征：实体图来自当前 `DbContext` 之外，并且图中不同节点需要不同的处理方式。

常见场景：

- 客户端提交一整棵聚合对象，其中部分节点新增，部分节点更新，部分节点删除。
- 请求 DTO 中带有 `IsNew`、`IsChanged`、`IsDeleted` 等标记，需要按标记设置实体状态。
- 自动生成主键的实体可以通过 `IsKeySet` 判断新增或已有，但还需要对部分节点做特殊处理。
- 某些导航分支只用于展示或引用，例如字典表、分类、用户信息，需要标记为 `Unchanged` 或停止继续遍历。
- 需要在图遍历过程中携带状态，例如访问集合、深度、租户信息、跳过规则等。

不一定需要 `TrackGraph` 的情况：

- 整张图都是新增实体，直接使用 `Add` 更简单。
- 整张图都是已有实体并且允许全量更新，直接使用 `Update` 更直接。
- 需要精确比较数据库原值和客户端值，通常应先查询现有实体，再用 `CurrentValues.SetValues(...)` 或显式设置属性级 `IsModified`。

## 执行模型

`TrackGraph` 的执行过程可以理解为：

```text
rootEntity
  -> 获取根实体的 EntityEntry
  -> 遍历已加载到对象图中的导航属性
  -> 对每个发现的实体调用 callback
  -> callback 设置 Entry.State
  -> 继续向下遍历或停止当前分支
```

核心规则：

- 遍历是递归的，会继续扫描已发现实体的导航属性。
- 回调函数会拿到 `EntityEntryGraphNode`，其中最常用的是 `node.Entry`。
- 如果回调中没有把实体状态设置为非 `Detached` 状态，该实体不会开始被追踪。
- 基础重载遇到已经被当前上下文追踪的实体时，不会再次处理该实体，也不会继续遍历它的导航属性。
- 带 `Func<..., bool>` 的重载由回调返回值决定是否继续遍历当前分支；返回 `false` 会停止向下遍历。

`EntityEntryGraphNode` 中常用属性：

| 属性 | 说明 |
| --- | --- |
| `Entry` | 当前节点实体对应的 `EntityEntry`，通过它设置 `State`、读取主键、访问元数据。 |
| `SourceEntry` | 从哪个上游实体的导航属性遍历到当前节点；根节点通常为 `null`。 |
| `InboundNavigation` | 到达当前节点时经过的导航属性；可用于按导航名称跳过某些分支。 |
| `NodeState` | 带状态重载中传递和沿图传播的自定义状态对象。 |

## 方法重载

### 基础重载

```csharp
public virtual void TrackGraph(
    object rootEntity,
    Action<EntityEntryGraphNode> callback)
```

这是最常用的重载。它适合按每个实体自身的数据或标记设置状态。

```csharp
context.ChangeTracker.TrackGraph(rootEntity, node =>
{
    node.Entry.State = node.Entry.IsKeySet
        ? EntityState.Modified
        : EntityState.Added;
});
```

基础重载的回调没有返回值。如果回调没有设置 `State`，实体会保持 `Detached`，该实体及其后续分支不会被追踪。

### 带状态重载

```csharp
public virtual void TrackGraph<TState>(
    object rootEntity,
    TState state,
    Func<EntityEntryGraphNode<TState>, bool> callback)
```

这个重载允许携带一个自定义状态对象，并通过返回值控制遍历是否继续。

```csharp
var visited = new HashSet<object>(ReferenceEqualityComparer.Instance);

context.ChangeTracker.TrackGraph(rootEntity, visited, node =>
{
    if (!node.NodeState.Add(node.Entry.Entity))
    {
        return false;
    }

    node.Entry.State = node.Entry.IsKeySet
        ? EntityState.Modified
        : EntityState.Added;

    return true;
});
```

如果回调返回 `false`，EF Core 不会继续遍历当前实体下面的导航分支。使用这个重载时，调用方需要自己确保不会因为循环引用或重复对象导致无限遍历。

### 旧式带状态回调

```csharp
public virtual void TrackGraph<TState>(
    object rootEntity,
    TState state,
    Func<EntityEntryGraphNode, TState, bool> callback)
```

这个签名把自定义状态作为回调的第二个参数传入。新代码通常优先使用 `EntityEntryGraphNode<TState>` 版本，因为状态在 `node.NodeState` 上更集中。

## EntityState 决策

`TrackGraph` 本身不替你判断业务意图，最终保存行为取决于你给每个节点设置的 `EntityState`。

| 状态 | 保存行为 | 常见含义 |
| --- | --- | --- |
| `Added` | `SaveChanges` 时执行插入。 | 新增实体，数据库中还不存在。 |
| `Modified` | `SaveChanges` 时执行更新。 | 已有实体发生修改。 |
| `Unchanged` | 不产生插入或更新。 | 已有实体仅作为关系引用，或本次没有变化。 |
| `Deleted` | `SaveChanges` 时执行删除。 | 已有实体需要删除。 |
| `Detached` | 不被当前上下文追踪。 | 跳过该节点；基础重载中通常也会停止该分支。 |

常见判断规则：

- 自动生成主键：优先在设置 `State` 前读取 `node.Entry.IsKeySet`。未设置主键通常表示新增。
- 显式主键：不能只靠主键默认值判断，通常需要客户端传状态标记，或先查数据库确认是否存在。
- 客户端标记：可以根据 DTO 或实体上的 `IsNew`、`IsChanged`、`IsDeleted` 等字段设置状态。
- 删除：客户端没有提交某个子节点，并不等于 EF Core 自动删除它；删除通常需要明确标记为 `Deleted`，或先查询数据库做图差异比较。

## 代码示例

### 根据客户端标记保存实体图

假设客户端返回的实体都带有保存意图：

```csharp
public abstract class EntityBase
{
    public bool IsNew { get; set; }

    public bool IsChanged { get; set; }

    public bool IsDeleted { get; set; }
}
```

可以在 `TrackGraph` 中统一解释这些标记：

```csharp
context.ChangeTracker.TrackGraph(rootEntity, node =>
{
    var entity = (EntityBase)node.Entry.Entity;

    node.Entry.State = entity.IsNew
        ? EntityState.Added
        : entity.IsDeleted
            ? EntityState.Deleted
            : entity.IsChanged
                ? EntityState.Modified
                : EntityState.Unchanged;
});

await context.SaveChangesAsync();
```

实际项目中更推荐把这些标记放在请求 DTO 或命令对象中，而不是长期污染领域实体。示例写在实体上只是为了展示核心思路。

### 根据主键判断新增或更新

对于自动生成主键的模型，可以用 `IsKeySet` 做基础判断：

```csharp
context.ChangeTracker.TrackGraph(order, node =>
{
    node.Entry.State = node.Entry.IsKeySet
        ? EntityState.Modified
        : EntityState.Added;
});

await context.SaveChangesAsync();
```

这种方式适合“有主键就更新、没主键就插入”的简单规则。缺点是已有实体会被标记为 `Modified`，通常会按实体状态更新属性；如果只想更新真正变化的列，需要额外使用原值、查询后赋值或属性级修改标记。

### 跳过引用数据分支

有些实体只是引用数据，例如分类、地区、标签字典。它们不应随着业务实体一起被更新：

```csharp
context.ChangeTracker.TrackGraph(product, node =>
{
    if (node.Entry.Entity is Category)
    {
        node.Entry.State = EntityState.Unchanged;
        return;
    }

    node.Entry.State = node.Entry.IsKeySet
        ? EntityState.Modified
        : EntityState.Added;
});
```

如果还希望跳过 `Category` 下面的导航分支，可以使用带返回值的重载：

```csharp
var visited = new HashSet<object>(ReferenceEqualityComparer.Instance);

context.ChangeTracker.TrackGraph(product, visited, node =>
{
    if (!node.NodeState.Add(node.Entry.Entity))
    {
        return false;
    }

    if (node.Entry.Entity is Category)
    {
        node.Entry.State = EntityState.Unchanged;
        return false;
    }

    node.Entry.State = node.Entry.IsKeySet
        ? EntityState.Modified
        : EntityState.Added;

    return true;
});
```

### 显式处理删除

如果客户端能明确告诉服务端某个节点要删除，可以在回调中设置 `Deleted`：

```csharp
context.ChangeTracker.TrackGraph(blog, node =>
{
    var entity = (EntityBase)node.Entry.Entity;

    if (entity.IsDeleted)
    {
        node.Entry.State = EntityState.Deleted;
        return;
    }

    node.Entry.State = node.Entry.IsKeySet
        ? EntityState.Modified
        : EntityState.Added;
});
```

如果客户端只是少传了某个子集合元素，EF Core 不会仅凭“请求中不存在”自动删除数据库中的行。真正的删除同步通常需要先加载数据库中的现有图，再和客户端提交的图做差异比较。

### 查看追踪结果

调试复杂实体图时，可以在保存前查看变更追踪器状态：

```csharp
Console.WriteLine(context.ChangeTracker.DebugView.LongView);
```

这能帮助确认每个实体最终是 `Added`、`Modified`、`Deleted` 还是 `Unchanged`，比直接猜 SQL 更可靠。

## 与 Add、Attach、Update 的区别

`Add`、`Attach`、`Update` 内部也会处理实体图，但它们使用的是固定规则。`TrackGraph` 则允许你对每个节点做自定义判断。

| 方法 | 默认图处理规则 | 适合场景 |
| --- | --- | --- |
| `Add` | 整张图通常标记为 `Added`。 | 明确都是新增实体。 |
| `Attach` | 整张图通常标记为 `Unchanged`；自动生成主键且未设置键的节点会被识别为 `Added`。 | 已有实体重新附加，仅少量后续手动修改。 |
| `Update` | 整张图通常标记为 `Modified`；自动生成主键且未设置键的节点会被识别为 `Added`。 | 允许已有实体全量更新，新实体自动插入。 |
| `TrackGraph` | 每个节点由回调自行设置状态。 | 同一图中混合新增、修改、删除、跳过和引用数据。 |

选择建议：

- 能用 `Add`、`Attach`、`Update` 表达清楚时，优先用它们。
- 当图中不同实体有不同保存意图时，再使用 `TrackGraph`。
- 当需要最小化更新列或解决并发冲突时，优先考虑查询已有实体后应用差异，而不是直接把整张图标为 `Modified`。

## 关键注意事项

### 必须显式设置 State

`TrackGraph` 的回调只是一个决策点。实体要开始被追踪，必须设置 `node.Entry.State`。如果保持 `Detached`，`SaveChanges` 不会对该实体产生数据库操作。

### IsKeySet 要在追踪前使用

对于自动生成主键，`IsKeySet` 常用于判断实体是否新增。应在设置 `State` 前使用它，因为实体一旦开始被追踪，EF Core 可能会为新增实体分配临时键值。

### Modified 不等于差异更新

把实体设置为 `EntityState.Modified` 通常表示“这个实体需要更新”，而不是“EF Core 已经知道哪些属性真的变了”。如果要避免更新未变化的列，可以考虑：

- 查询数据库中的现有实体，然后用 `CurrentValues.SetValues(...)` 应用客户端值。
- 传回原始值，让 EF Core 根据原值和当前值判断修改列。
- 手动设置具体属性的 `Property(...).IsModified`。

### 一个 DbContext 只能追踪同主键的一个实例

实体图中如果有多个对象实例拥有同一个主键，EF Core 不能同时追踪它们。序列化复杂图时要尽量避免重复对象；如果已经产生重复，需要在调用 `TrackGraph` 前先合并成单一实例。

### 删除需要明确语义

`TrackGraph` 能把节点标记为 `Deleted`，但它不能自动推断“客户端没有传回来”的子实体是否应该删除。真实删除通常使用以下方式之一：

- 客户端显式传删除标记。
- 使用软删除，把删除转为普通更新。
- 服务端先查询现有图，再和提交图做差异比较。

### 谨慎使用长生命周期 DbContext

断开连接场景更适合每个工作单元使用短生命周期 `DbContext`。如果一个上下文已经追踪了很多实体，再对外部实体图调用 `TrackGraph`，更容易遇到重复实例、旧状态残留和意外更新。

### 控制图大小和遍历范围

`TrackGraph` 会递归遍历对象图。对于深层嵌套、大集合或循环引用图，需要控制根对象、序列化范围和回调返回值。带状态重载中最好维护访问集合，避免重复处理。

### 不要把实体图当作授权边界

客户端提交的状态标记和主键值都不应被无条件信任。保存前仍应结合当前用户、租户、业务规则和数据库现状校验，避免越权更新或删除不属于当前请求范围的数据。

## 参考资料

### 官方资料

1. [ChangeTracker.TrackGraph Method - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.changetracking.changetracker.trackgraph?view=efcore-10.0)
2. [ChangeTracker.TrackGraph 方法 - Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/microsoft.entityframeworkcore.changetracking.changetracker.trackgraph?view=efcore-10.0)
3. [Disconnected entities - EF Core](https://learn.microsoft.com/en-us/ef/core/saving/disconnected-entities)
4. [Explicitly Tracking Entities - EF Core](https://learn.microsoft.com/en-us/ef/core/change-tracking/explicit-tracking)
5. [Identity Resolution in EF Core](https://learn.microsoft.com/en-us/ef/core/change-tracking/identity-resolution)
6. [EntityEntryGraphNode Class - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.changetracking.entityentrygraphnode?view=efcore-10.0)
7. [EntityEntryGraphNode<TState> Class - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.changetracking.entityentrygraphnode-1?view=efcore-10.0)

### 延伸阅读

1. [EF Core 系列之 ChangeTracker.TrackGraph - 博客园](https://www.cnblogs.com/AlexanderZhao/p/12878801.html)
2. [Entity Framework Core ChangeTracker.TrackGraph - CSDN](https://blog.csdn.net/catshitone/article/details/117295005)
3. [Entity Framework Core 实体状态跟踪 - 博客园](https://www.cnblogs.com/zy8899/p/18106539)
