# Floyd-Warshall 全源最短路径

Floyd-Warshall 算法通过动态规划计算所有顶点对之间的最短路径。它允许负权边，也能检测负权环；受到负权环影响的点对没有有限的最短距离。核心状态是：只允许使用编号不超过 `k` 的中间顶点时，`dist[i,j]` 的最短距离。

**示例环境：C# 14、.NET 10。** 距离使用 `long`，不可达值用 `long.MaxValue / 4`，并对输入边权和计算结果进行范围检查。

## 1. 状态转移

初始化时 `dist[i,i] = 0`，每条边取最小权重；随后按中间顶点 `k` 更新：

```text
dist[i,j] = min(dist[i,j], dist[i,k] + dist[k,j])
```

`k` 必须放在最外层循环。若 `dist[v,v] < 0`，说明图中存在从 `v` 可达的负权环，最短路没有有限定义。

## 2. 复杂度

时间复杂度 `O(V³)`，空间复杂度 `O(V²)`。它不依赖边数，适合顶点数较小、需要大量点对查询的稠密图。顶点数达到几千时，三重循环和内存通常不可接受，应考虑 Dijkstra（非负权）或 Johnson。

## 3. 基础实现：距离矩阵

```csharp
public static class FloydWarshall
{
    public const long Inf = long.MaxValue / 4;

    public static long[,] Compute(int vertexCount,
        IEnumerable<(int From, int To, long Weight)> edges,
        bool directed = true)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(vertexCount);
        ArgumentNullException.ThrowIfNull(edges);
        var dist = new long[vertexCount, vertexCount];
        for (int i = 0; i < vertexCount; i++)
            for (int j = 0; j < vertexCount; j++)
                dist[i, j] = i == j ? 0 : Inf;

        foreach (var (from, to, weight) in edges)
        {
            CheckVertex(from, vertexCount); CheckVertex(to, vertexCount);
            if (weight <= -Inf || weight >= Inf)
                throw new ArgumentOutOfRangeException(nameof(edges),
                    "边权必须严格位于 (-Inf, Inf) 内。");
            dist[from, to] = Math.Min(dist[from, to], weight);
            if (!directed) dist[to, from] = Math.Min(dist[to, from], weight);
        }

        for (int k = 0; k < vertexCount; k++)
        for (int i = 0; i < vertexCount; i++)
        {
            if (dist[i, k] == Inf) continue;
            for (int j = 0; j < vertexCount; j++)
            {
                if (dist[k, j] == Inf) continue;
                long throughK = AddFiniteDistances(dist[i, k], dist[k, j]);
                if (throughK < dist[i, j]) dist[i, j] = throughK;
            }
        }
        return dist;
    }

    public static bool HasNegativeCycle(long[,] dist)
    {
        int n = dist.GetLength(0);
        for (int i = 0; i < n; i++) if (dist[i, i] < 0) return true;
        return false;
    }

    public static bool[,] IsUndefinedByNegativeCycle(long[,] dist)
    {
        int n = dist.GetLength(0);
        var result = new bool[n, n];
        for (int k = 0; k < n; k++)
        {
            if (dist[k, k] >= 0) continue;
            for (int i = 0; i < n; i++)
            {
                if (dist[i, k] == Inf) continue;
                for (int j = 0; j < n; j++)
                    if (dist[k, j] != Inf) result[i, j] = true;
            }
        }
        return result;
    }

    private static long AddFiniteDistances(long left, long right)
    {
        long sum = checked(left + right);
        if (sum <= -Inf || sum >= Inf)
            throw new OverflowException("路径计算超过示例支持的距离范围。");
        return sum;
    }

    private static void CheckVertex(int v, int n)
    {
        if ((uint)v >= (uint)n) throw new ArgumentOutOfRangeException(nameof(v));
    }
}
```

将类型保存为 `FloydWarshall.cs` 后，在控制台项目的 `Program.cs` 中调用：

```csharp
var distances = FloydWarshall.Compute(4,
    new[] { (0, 1, 5L), (0, 3, 10L), (1, 2, 3L), (2, 3, 1L) });
Console.WriteLine(distances[0, 3]); // 9
```

## 4. 进阶：恢复路径

除距离矩阵外维护 `next[i,j]`：若存在直接边，初始化为 `j`；当通过 `k` 改善 `dist[i,j]` 时令 `next[i,j] = next[i,k]`。查询时从 `i` 沿 `next` 反复前进，直到 `j`。若检测到负权环，经过该环的点对不能恢复为有限最短路径。

```csharp
public static List<int> Reconstruct(int from, int to, int[,] next)
{
    if (next[from, to] < 0) return new List<int>();
    var path = new List<int> { from };
    while (from != to)
    {
        from = next[from, to];
        if (from < 0 || path.Count > next.GetLength(0))
            throw new InvalidOperationException("路径矩阵损坏或含负环");
        path.Add(from);
    }
    return path;
}
```

### 4.1 传递闭包

把 `dist[i,j]` 换成布尔值并把“加法”换成逻辑与、“最小值”换成逻辑或，就得到 Warshall 传递闭包算法，复杂度仍为 `O(V³)`。它可回答任意两点是否存在路径，但不提供路径长度。

## 5. 常见错误

1. 将 `k` 循环放在内层，状态含义被破坏，结果不再保证正确。
2. 对不可达值直接相加，`Inf + Inf` 可能溢出并变成负数；相加前先判断。
3. 重边只保留最后一条而不是最小权重边。
4. 发现负权环后仍把所有距离当成有效最短距离；涉及负环的点对应视为无定义。
5. 无向图忘记写入对称位置；有向图误用对称更新会改变问题。

## 6. 负环影响范围与安全加法

`dist[v,v] < 0` 表示存在从 `v` 出发并回到 `v` 的负权闭合游走，即 `v` 能往返某个负权环；它不要求 `v` 本身位于负权简单环上。若 `i` 能到达 `v` 且 `v` 能到达 `j`，则 `i` 到 `j` 的路径权值可以不断降低，没有有限下界。第 3 节的 `FloydWarshall.IsUndefinedByNegativeCycle` 在计算完成后标记这些点对，额外耗时 `O(V³)`；未被标记的点对仍可读取正常答案。

仅把 `Inf` 设为 `long.MaxValue / 4` 并不能支持任意 `long` 边权。这个实现要求输入边权和计算过程中出现的所有有限路径和都严格位于 `(-Inf, Inf)`，否则抛出异常，不会截断数据或返回错误的不可达结果。`HasNegativeCycle` 和 `IsUndefinedByNegativeCycle` 接受 `Compute` 正常返回的方阵。负权环在迭代中可能使负值迅速增大，因此即使边权较小，也不能对任意规模的负环图保证不会触发范围异常。

需要处理没有上述数值限制的输入时，可以改用 `System.Numerics.BigInteger` 保存有限距离，并用独立的布尔矩阵表示可达性。不要仅把大正数截断为 `Inf`：含负权边时，后续路径可能从该大正数下降到可表示的有效距离。实际项目应先根据顶点数、边权限制和是否允许负环选择数值表示，再决定使用 `long` 还是任意精度整数。

## 7. 运行检查

```csharp
var distances = FloydWarshall.Compute(3,
    new[] { (0, 1, 2L), (1, 2, -1L), (2, 1, -2L) });
var undefined = FloydWarshall.IsUndefinedByNegativeCycle(distances);
if (!undefined[0, 2] || distances[1, 1] >= 0)
    throw new InvalidOperationException("负环传播检查失败");

var finite = FloydWarshall.Compute(3,
    new[] { (0, 1, 5L), (1, 2, 2L) });
if (finite[0, 2] != 7 || finite[2, 0] != FloydWarshall.Inf)
    throw new InvalidOperationException("不可达和最短距离检查失败");
Console.WriteLine("Floyd-Warshall 检查通过");
```

还应检查两种数值错误：单条边权等于 `FloydWarshall.Inf` 时应抛出 `ArgumentOutOfRangeException`；三顶点链的两条边权都为 `FloydWarshall.Inf - 1` 时，有限距离相加超出范围，应抛出 `OverflowException`。后者虽然不一定使 `long` 本身溢出，但已与示例的不可达标记冲突，必须拒绝计算。

## 参考资料

- [Floyd-Warshall — cp-algorithms](https://cp-algorithms.com/graph/all-pair-shortest-path-floyd-warshall.html)：动态规划阶段、路径恢复、负权环与距离溢出。
- [Bellman-Ford — cp-algorithms](https://cp-algorithms.com/graph/bellman_ford.html)：比较带负权边的单源最短路场景。
