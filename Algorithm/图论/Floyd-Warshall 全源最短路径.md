# Floyd-Warshall 全源最短路径

Floyd-Warshall 算法通过动态规划计算所有顶点对之间的最短路径。它允许负权边，但不能存在负权环。核心状态是：只允许使用编号不超过 `k` 的中间顶点时，`dist[i,j]` 的最短距离。

**示例环境：C# 12、.NET 8。** 距离使用 `long`，不可达值用 `long.MaxValue / 4`，避免加法溢出。

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
        var dist = new long[vertexCount, vertexCount];
        for (int i = 0; i < vertexCount; i++)
            for (int j = 0; j < vertexCount; j++)
                dist[i, j] = i == j ? 0 : Inf;

        foreach (var (from, to, weight) in edges)
        {
            CheckVertex(from, vertexCount); CheckVertex(to, vertexCount);
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
                long throughK = dist[i, k] + dist[k, j];
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

    private static void CheckVertex(int v, int n)
    {
        if ((uint)v >= (uint)n) throw new ArgumentOutOfRangeException(nameof(v));
    }
}

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

