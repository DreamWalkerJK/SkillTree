# Kruskal 最小生成树

Kruskal 算法在带权无向图中按边权从小到大选边：如果当前边连接了两个不同连通分量，就加入生成树；否则跳过以避免环。并查集负责判断分量是否相同，因此算法也适合边集形式输入的稀疏图。

**示例环境：C# 12、.NET 8。** 下面的 `DisjointSetUnion` 可复用 `Algorithm/数据结构/并查集（Disjoint Set Union）.md` 中的实现。

## 1. 正确性与复杂度

对任意尚未连通的两个分量，连接它们的最轻边是某个割的安全边（割性质），加入该边不会失去最优性。不断应用该性质，直到选出 `V - 1` 条边。

排序占 `O(E log E)`；并查集操作为 `O(E α(V))`，总复杂度为 `O(E log E)`，空间 `O(V + E)`。图不连通时，算法返回最小生成森林，而不是一棵完整树。

## 2. 基础实现：返回最小生成树边集

```csharp
public readonly record struct UndirectedEdge(int From, int To, long Weight);

public static class Kruskal
{
    public static (long TotalWeight, List<UndirectedEdge> Edges, int Components)
        Build(int vertexCount, IEnumerable<UndirectedEdge> input)
    {
        if (vertexCount < 0) throw new ArgumentOutOfRangeException(nameof(vertexCount));
        var edges = input.ToArray();
        Array.Sort(edges, static (x, y) => x.Weight.CompareTo(y.Weight));
        var dsu = new DisjointSetUnion(vertexCount);
        var selected = new List<UndirectedEdge>(Math.Max(0, vertexCount - 1));
        long total = 0;

        foreach (UndirectedEdge edge in edges)
        {
            if ((uint)edge.From >= (uint)vertexCount || (uint)edge.To >= (uint)vertexCount)
                throw new ArgumentOutOfRangeException(nameof(input), "顶点编号越界");
            if (!dsu.Union(edge.From, edge.To)) continue;
            checked { total += edge.Weight; }
            selected.Add(edge);
            if (selected.Count == vertexCount - 1) break;
        }
        return (total, selected, dsu.ComponentCount);
    }
}

var result = Kruskal.Build(4, new[]
{
    new UndirectedEdge(0, 1, 1), new UndirectedEdge(1, 2, 2),
    new UndirectedEdge(0, 2, 3), new UndirectedEdge(2, 3, 1)
});
Console.WriteLine(result.TotalWeight); // 4
```

示例依赖如下并查集类型（可放在同一项目的公共文件中）：

```csharp
public sealed class DisjointSetUnion
{
    private readonly int[] parent, size;
    public int ComponentCount { get; private set; }
    public DisjointSetUnion(int n)
    {
        parent = new int[n]; size = new int[n]; ComponentCount = n;
        for (int i = 0; i < n; i++) { parent[i] = i; size[i] = 1; }
    }
    public int Find(int x) => parent[x] == x ? x : parent[x] = Find(parent[x]);
    public bool Union(int a, int b)
    {
        a = Find(a); b = Find(b); if (a == b) return false;
        if (size[a] < size[b]) (a, b) = (b, a);
        parent[b] = a; size[a] += size[b]; ComponentCount--; return true;
    }
}
```

## 3. 进阶用法

### 3.1 处理不连通图

不要求 `selected.Count == vertexCount - 1`，即可得到每个连通分量的最小生成树。`Components` 大于 1 时应明确向调用方报告“图不连通”，不要把森林误标为 MST。

### 3.2 第二小生成树

先求 MST，再对树做倍增 LCA，记录任意两点路径上的最大边。对每条未选边 `(u,v,w)`，用 `MSTWeight - maxEdge(u,v) + w` 计算候选值，取严格大于 MST 的最小候选。预处理 `O(V log V)`，枚举非树边 `O(E log V)`。

### 3.3 最大生成树与边约束

按权重降序排序即可求最大生成树。若必须包含某条边，可先将其 Union 并计入结果，再继续 Kruskal；若这条边形成环，则约束不可行。对于“恰好选 k 条边”等约束，需要额外的 matroid/动态规划分析，不能只改排序方向。

## 4. 常见错误

1. 在有向图上直接运行 Kruskal；最小生成树定义在无向图，方向图应考虑最小树形图等不同问题。
2. 只检查边数，不检查图是否连通，返回不完整的“树”。
3. 相同权重边的排序不稳定却假设结果唯一；MST 权值可能唯一，但边集不一定唯一。
4. `total += weight` 使用 `int` 导致总权重溢出；示例使用 `long` 和 `checked`。
5. 并查集没有路径压缩/按大小合并，大量边时性能明显下降。

