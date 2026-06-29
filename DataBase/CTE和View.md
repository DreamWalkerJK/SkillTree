# <center>CTE 和 View</center>

CTE（Common Table Expression，公共表表达式）和 View（视图）都可以把一段查询逻辑命名后再使用，但二者的生命周期、作用范围和管理方式不同。

## 核心区别

| 对比项 | CTE | View |
| --- | --- | --- |
| 中文名称 | 公共表表达式 | 视图 |
| 定义方式 | `WITH ... AS (...)` | `CREATE VIEW ... AS ...` |
| 对象级别 | 语句级临时结果集 | 数据库模式级持久对象 |
| 生命周期 | 仅在当前 SQL 语句执行期间存在 | 创建后持续存在，直到被删除 |
| 命名范围 | 当前 SQL 语句内 | 同一 `schema` 下名称必须唯一 |
| 是否存储数据 | 通常不存储，只参与当前查询优化 | 普通视图不存储数据，只保存查询定义 |
| 典型用途 | 拆分复杂查询、递归查询、临时复用中间结果 | 封装查询逻辑、权限控制、对外提供稳定接口 |

简单理解：

- **CTE** 是语句级的“临时视图”，只服务于当前这一条 SQL。
- **View** 是数据库中的持久化对象，可以被多个查询、会话或应用反复使用。

## CTE：语句级的临时结果集

CTE 是通过 `WITH` 子句定义的临时命名结果集。它相当于给子查询起一个名字，让后续查询可以更清晰地引用这部分逻辑。

### 基本语法

```sql
WITH CTE_Name (Column1, Column2) AS (
    SELECT Column1, Column2
    FROM Some_Table
    WHERE Some_Condition
)
SELECT *
FROM CTE_Name;
```

说明：

- `CTE_Name` 是 CTE 名称。
- `(Column1, Column2)` 是可选的列名列表。
- `AS (...)` 中是 CTE 的查询定义。
- CTE 必须紧跟一条使用它的 SQL 语句，例如 `SELECT`、`INSERT`、`UPDATE`、`DELETE` 或 `MERGE`。

### 非递归 CTE

非递归 CTE 不引用自身，常用于拆分查询步骤或生成中间结果。

```sql
WITH RowCTE (RowNumber) AS (
    SELECT ROW_NUMBER() OVER (ORDER BY name ASC) AS RowNumber
    FROM sys.databases
    WHERE database_id <= 10
)
SELECT *
FROM RowCTE;
```

这个例子中，`RowCTE` 保存了一个临时结果集，其中 `RowNumber` 是生成的行号。

### 递归 CTE

递归 CTE 可以在定义中引用自身，通常用于处理层级结构，例如组织架构、菜单树、分类树等。

```sql
WITH RecursiveCTE AS (
    SELECT 1 AS Value

    UNION ALL

    SELECT Value + 1
    FROM RecursiveCTE
    WHERE Value < 10
)
SELECT *
FROM RecursiveCTE;
```

这个例子会生成从 `1` 到 `10` 的结果。

递归 CTE 一般由两部分组成：

- **锚点成员**：递归的起始查询，例如 `SELECT 1 AS Value`。
- **递归成员**：引用 CTE 自身的查询，例如 `SELECT Value + 1 FROM RecursiveCTE`。

### 使用场景

- 将复杂 SQL 拆分为多个逻辑清晰的步骤。
- 避免在同一条 SQL 中重复书写相同的子查询。
- 编写递归查询，处理树形或层级数据。
- 临时使用类似视图的逻辑，但不想在数据库中创建持久对象。

### 注意事项

- CTE 的作用范围只限于当前 SQL 语句，不能跨语句、跨会话复用。
- CTE 不一定会带来性能提升。不同数据库优化器可能会选择内联、物化或重复计算，具体效果需要结合执行计划判断。
- SQL Server 中递归 CTE 默认有递归层数限制，可用 `OPTION (MAXRECURSION n)` 调整。

## View：持久化的虚拟表

View 是基于一个或多个表的查询定义创建出来的虚拟表。普通视图本身不保存实际数据，只保存 SQL 查询定义；每次查询视图时，数据库会根据定义从底层表中获取数据。

### 创建视图

```sql
CREATE VIEW CurrentProductList AS
SELECT ProductID, ProductName
FROM Products
WHERE Discontinued = 0;
```

查询视图：

```sql
SELECT *
FROM CurrentProductList;
```

### 修改视图

不同数据库的语法略有差异：

```sql
-- PostgreSQL、MySQL、Oracle 等常见写法
CREATE OR REPLACE VIEW CurrentProductList AS
SELECT ProductID, ProductName, Category
FROM Products
WHERE Discontinued = 0;
```

```sql
-- SQL Server 常见写法
CREATE OR ALTER VIEW CurrentProductList AS
SELECT ProductID, ProductName, Category
FROM Products
WHERE Discontinued = 0;
```

### 删除视图

```sql
DROP VIEW CurrentProductList;
```

删除视图只会删除视图定义，不会删除底层表中的数据。

### 核心特性

- **持久化对象**：视图创建后会保存在数据库中，直到显式删除。
- **动态数据**：普通视图不保存数据，每次查询时从底层表获取最新结果。
- **逻辑封装**：可以把复杂的连接、过滤、计算逻辑封装成一个简单查询入口。
- **权限控制**：可以只授权用户访问视图，而不直接访问底层表。
- **可更新性有限**：简单视图在满足条件时可以更新底层表；包含聚合、分组、去重、多表复杂连接等逻辑的视图通常不可直接更新。

### 主要类型

- **普通视图**：只保存查询定义，不保存查询结果。
- **物化视图**：保存查询结果，读取速度通常更快，但数据不是实时的，需要手动或定时刷新。不同数据库对物化视图的支持和语法不同。

### 使用场景

- 封装复杂多表查询，让使用者像查询单表一样使用。
- 屏蔽敏感字段或复杂底层表结构，增强权限控制。
- 为应用程序提供稳定的数据接口，降低底层表结构变化带来的影响。
- 统一常用业务口径，例如“当前有效产品”“活跃用户”“最近订单”等。

## 选择建议

| 场景 | 推荐 |
| --- | --- |
| 只在当前 SQL 中临时使用一次或多次 | CTE |
| 需要拆分复杂查询，提高可读性 | CTE |
| 需要递归处理层级数据 | CTE |
| 查询逻辑需要被多个 SQL 或应用复用 | View |
| 需要通过数据库对象做权限控制 | View |
| 需要对外提供稳定的数据访问接口 | View |
| 查询结果需要物理保存并定期刷新 | 物化视图 |

## 一句话总结

CTE 更适合**当前语句内的临时组织和递归查询**；View 更适合**跨语句复用、封装业务逻辑和权限控制**。
