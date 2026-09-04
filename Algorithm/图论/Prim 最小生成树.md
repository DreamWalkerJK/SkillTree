# Prim 最小生成树

Prim 算法从一个顶点开始，维护“已加入树的顶点集合”和它们连接到外部顶点的最小边。每次取出跨越该割的最轻边，把新顶点及其边加入树。它与 Dijkstra 使用相似的优先队列，但 Prim 的优先级是“连接边权”，不是从源点累积的路径距离。

**示例环境：C# 12、.NET 8。** 采用邻接表和 `PriorityQueue`，适合稀疏图。

## 1. 复杂度与选择

二叉堆实现复杂度 `O((V + E) log V)`，空间 `O(V + E)`；邻接矩阵 + 线性选点为 `O(V²)`，适合稠密图。图不连通时，从一个起点只能生成一个连通分量；若要生成最小生成森林，应对每个未访问顶点重新启动 Prim。

## 2. 基础实现：连通图

```csharp
public readonly record struct AdjacentEdge(int To, long Weight);
public readonly record struct SelectedEdge(int From, int To, long Weight);

public static class Prim
{
    public static (long TotalWeight, List<SelectedEdge> Edges, int Components)
        Build(IReadOnlyList<IReadOnlyList<AdjacentEdge>> graph)
    {
        int n = graph.Count;
        var visited = new bool[n];
        var queue = new PriorityQueue<(int From, int To, long Weight), long>();
        var result = new List<SelectedEdge>(Math.Max(0, n - 1));
        long total = 0;
        int components = 0;

        for (int start = 0; start < n; start++)
        {
            if (visited[start]) continue;
            components++;
            queue.Enqueue((-1, start, 0), 0); // 根节点没有真实父边
            while (queue.TryDequeue(out var item, out _))
            {
                (int from, int to, long weight) = item;
                if (visited[to]) continue;
                visited[to] = true;
                if (from >= 0)
                {
                    checked { total += weight; }
                    result.Add(new SelectedEdge(from, to, weight));
                }
                foreach (AdjacentEdge edge in graph[to])
                {
                    if ((uint)edge.To >= (uint)n) throw new ArgumentOutOfRangeException(nameof(graph));
                    if (!visited[edge.To]) queue.Enqueue((to, edge.To, edge.Weight), edge.Weight);
                }
            }
        }
        return (total, result, components);
    }
}

// 无向图要双向添加边：adj[u].Add((v,w)); adj[v].Add((u,w));
var graph = new List<IReadOnlyList<AdjacentEdge>>
{
    new[] { new AdjacentEdge(1, 1), new AdjacentEdge(2, 3) },
    new[] { new AdjacentEdge(0, 1), new AdjacentEdge(2, 2) },
    new[] { new AdjacentEdge(0, 3), new AdjacentEdge(1, 2) }
};
var mst = Prim.Build(graph);
Console.WriteLine(mst.TotalWeight); // 3
```

## 3. 进阶用法

### 3.1 稠密图的矩阵版本

若图以 `weight[u,v]` 矩阵给出，使用 `minKey[]` 保存每个未加入顶点的最小连接边，重复线性扫描选取最小值即可，代码更短且缓存局部性较好。不存在的边用 `Inf` 表示；每次选择不到有限边时，说明图不连通。

### 3.2 动态更新与预检查

Prim 是静态算法，每次插入或删除边都可能改变整棵树。边频繁变化时可考虑动态 MST 数据结构（Link-Cut Tree 等），或按批次重算。实际服务中，先用并查集检查连通分量，再选择 Kruskal/Prim，可更早报告数据问题。

### 3.3 与 Dijkstra 的区别

两者都可用优先队列，但 Dijkstra 的 `key[v]` 是源点到 `v` 的最短路径，Prim 的 `key[v]` 是树到 `v` 的最小单边权。把累计距离误用于 Prim 会得到最短路径树，而不是 MST。

## 4. 常见错误

1. 只从顶点 0 启动并认为一定得到 `V - 1` 条边；图不连通时需要遍历所有起点。
2. 邻接表的无向边只添加一次，算法实际处理成有向图。
3. 访问顶点后仍把其所有旧队列条目当成有效；必须跳过 `visited[to]`。
4. 优先级使用累计路径值，结果变成 Dijkstra 风格的树。
5. 负权边并不违反 Prim 的割性质，但若输入语义要求非负，仍应在校验层明确约束；不要将 Prim 与 Dijkstra 的负权限制混为一谈。

