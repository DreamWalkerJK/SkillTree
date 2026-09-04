# Dijkstra 最短路径算法

Dijkstra 算法在边权非负的有向图或无向图中，计算一个源点到其他顶点的最短距离。它采用“每次确定当前距离最小且尚未确定的顶点”的贪心策略；非负边权保证已经确定的距离不会再被更短路径改写。

**示例环境：C# 12、.NET 8。** `PriorityQueue<TElement,TPriority>` 随 .NET 6 引入，下面代码可直接用于 .NET 8 项目。

## 1. 松弛与正确性

设 `dist[v]` 是目前找到的源点到 `v` 的距离。取出未确定顶点中 `dist` 最小的 `u` 后，对每条边 `(u, v, w)` 执行松弛：

```text
if dist[u] + w < dist[v]
    dist[v] = dist[u] + w
```

因为 `w >= 0`，任何经过其他未确定顶点的路径都不会比 `dist[u]` 更短，所以 `u` 的距离可以永久确定。算法不能处理负权边；存在负权时应使用 Bellman-Ford 或 Johnson 算法。

## 2. 复杂度

使用二叉堆优先队列时，时间复杂度为 `O((V + E) log V)`（懒删除实现可能入队多次，严格写法也可记为 `O(E log E)`，两者在常见稀疏图上同阶），空间复杂度 `O(V + E)`。使用邻接矩阵并线性寻找最小值时为 `O(V²)`，适合稠密图。

## 3. 基础实现：返回距离和前驱

```csharp
public readonly record struct WeightedEdge(int To, long Weight);

public sealed class DijkstraResult
{
    public required long[] Distance { get; init; }
    public required int[] Previous { get; init; }

    public IReadOnlyList<int> BuildPath(int target)
    {
        if ((uint)target >= (uint)Distance.Length)
            throw new ArgumentOutOfRangeException(nameof(target));
        if (Distance[target] == long.MaxValue) return Array.Empty<int>();

        var path = new List<int>();
        for (int at = target; at >= 0; at = Previous[at]) path.Add(at);
        path.Reverse();
        return path;
    }
}

public static class Dijkstra
{
    public static DijkstraResult ShortestPaths(
        IReadOnlyList<IReadOnlyList<WeightedEdge>> graph, int source)
    {
        int n = graph.Count;
        if ((uint)source >= (uint)n) throw new ArgumentOutOfRangeException(nameof(source));

        long[] distance = new long[n];
        int[] previous = new int[n];
        Array.Fill(distance, long.MaxValue);
        Array.Fill(previous, -1);
        distance[source] = 0;

        var queue = new PriorityQueue<int, long>();
        queue.Enqueue(source, 0);

        while (queue.TryDequeue(out int u, out long queuedDistance))
        {
            // PriorityQueue 没有 decrease-key；丢弃过期条目。
            if (queuedDistance != distance[u]) continue;

            foreach (WeightedEdge edge in graph[u])
            {
                if (edge.Weight < 0) throw new ArgumentException("Dijkstra 不支持负权边");
                if ((uint)edge.To >= (uint)n)
                    throw new ArgumentOutOfRangeException(nameof(graph), "边的终点编号越界");
                if (distance[u] > long.MaxValue - edge.Weight)
                    throw new OverflowException("路径长度超出 Int64");

                long candidate = distance[u] + edge.Weight;
                if (candidate >= distance[edge.To]) continue;
                distance[edge.To] = candidate;
                previous[edge.To] = u;
                queue.Enqueue(edge.To, candidate);
            }
        }

        return new DijkstraResult { Distance = distance, Previous = previous };
    }
}

// 无向边要在两个方向各加入一条邻接边。
var graph = new List<IReadOnlyList<WeightedEdge>>
{
    new[] { new WeightedEdge(1, 4), new WeightedEdge(2, 1) },
    new[] { new WeightedEdge(3, 1) },
    new[] { new WeightedEdge(1, 2), new WeightedEdge(3, 5) },
    Array.Empty<WeightedEdge>()
};
var result = Dijkstra.ShortestPaths(graph, source: 0);
Console.WriteLine(result.Distance[3]);                    // 4
Console.WriteLine(string.Join(" -> ", result.BuildPath(3))); // 0 -> 2 -> 1 -> 3
```

## 4. 进阶用法

### 4.1 提前结束

只需要源点到一个目标点时，目标顶点第一次从优先队列取出且条目未过期，就可以返回。此时该距离已经最优。若要同时恢复路径，保留 `previous` 数组。

### 4.2 多源最短路径

将所有源点以距离 0 一起入队，即可得到“到最近源点的距离”。若要区分来源，可另外维护 `owner[v]`，松弛时复制 `owner[u]`。

### 4.3 状态图

把“顶点 + 状态”编码成一个节点，可以处理换乘次数、剩余优惠券、方向等约束。例如 `(city, couponsUsed)` 视为一个顶点，边权仍需非负。

## 5. 常见错误

1. 把负权边传给 Dijkstra；结果可能错误，应改用 Bellman-Ford、SPFA（需谨慎）或 Johnson。
2. 直接修改优先队列中的旧优先级。标准 `PriorityQueue` 没有 decrease-key，应重新入队并跳过过期条目。
3. 用 `int.MaxValue + weight` 计算不可达点，造成溢出；先判断是否为无穷或使用安全加法。
4. 无向边只加入一个方向，得到的是有向图结果。
5. 用 `0` 表示不可达，无法区分真实的零成本路径；应使用 `long.MaxValue` 或单独的可达标记。
