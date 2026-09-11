# Kruskal 最小生成树

Kruskal 算法在带权无向图中按边权从小到大选边：如果当前边连接了两个不同连通分量，就加入生成树；否则跳过以避免环。并查集负责判断分量是否相同，因此算法也适合边集形式输入的稀疏图。

**示例环境：C# 14、.NET 10。** 下面的 `DisjointSetUnion` 可复用 `Algorithm/数据结构/并查集（Disjoint Set Union）.md` 中的实现。

## 1. 正确性与复杂度

按全局边权顺序找到第一条连接不同分量的边时，这条边是其中一个分量与其余顶点构成的割上的最轻边，因而是安全边（割性质），加入它不会失去最优性。不断应用该性质，直到选出 `V - 1` 条边或所有边处理完毕。不能任意指定两个分量，再把它们之间的最轻边当作安全边。

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

这里要求输入图连通，并将“第二小”定义为总权值严格大于 MST。先求 MST，再对树做倍增 LCA，记录路径上的最大边权 `max1` 和严格小于它的最大边权 `max2`，即最大的两个不同权值。枚举未选边 `(u,v,w)` 时，如果 `w > max1`，删除权值为 `max1` 的树边；如果 `w == max1`，则必须删除 `max2` 才能得到严格更大的总权值，没有 `max2` 时跳过。取所有严格更大候选中的最小值；不存在候选则不存在严格第二小生成树。预处理 `O(V log V)`，枚举非树边 `O(E log V)`。

### 3.3 最大生成树与边约束

按权重降序排序即可求最大生成树。若必须包含某条边，可先将其 Union 并计入结果，再继续 Kruskal；若这条边形成环，则约束不可行。对于“恰好选 k 条边”等约束，需要额外的 matroid/动态规划分析，不能只改排序方向。

## 4. 常见错误

1. 在有向图上直接运行 Kruskal；最小生成树定义在无向图，方向图应考虑最小树形图等不同问题。
2. 只检查边数，不检查图是否连通，返回不完整的“树”。
3. 相同权重边的排序不稳定却假设结果唯一；MST 权值可能唯一，但边集不一定唯一。
4. `total += weight` 使用 `int` 导致总权重溢出；示例使用 `long` 和 `checked`。
5. 并查集没有路径压缩/按大小合并，大量边时性能明显下降。

## 5. 正确性、森林结果与第二小生成树

Kruskal 每次选择当前尚未成环的最轻边。设已选边构成森林 `F`，取一棵包含 `F` 的最小生成树 `T`。若候选边 `e` 不在 `T` 中，将它加入会产生唯一的环；环上必然存在另一条跨越该分量与其余顶点所构成割的边 `f`。由于 `e` 是这个割上的最轻边，`weight(e) <= weight(f)`；删除 `f` 后得到的树仍包含 `F`，且总权值不增加。因此存在包含 `F + e` 的最小生成树。重复这个交换论证即可证明算法正确。

```csharp
public static (long Weight, IReadOnlyList<UndirectedEdge> Edges, int Components)
    BuildMinimumSpanningForest(int vertexCount, IEnumerable<UndirectedEdge> input)
{
    ArgumentNullException.ThrowIfNull(input);
    if (vertexCount < 0) throw new ArgumentOutOfRangeException(nameof(vertexCount));

    var edges = input.OrderBy(e => e.Weight).ThenBy(e => e.From).ThenBy(e => e.To).ToArray();
    var dsu = new DisjointSetUnion(vertexCount);
    var chosen = new List<UndirectedEdge>(Math.Max(0, vertexCount - 1));
    long total = 0;
    foreach (var edge in edges)
    {
        if ((uint)edge.From >= (uint)vertexCount || (uint)edge.To >= (uint)vertexCount)
            throw new ArgumentException("边的顶点编号超出范围。", nameof(input));
        if (edge.From == edge.To) continue;
        if (!dsu.Union(edge.From, edge.To)) continue;
        chosen.Add(edge);
        total = checked(total + edge.Weight);
    }

    return (total, chosen, vertexCount - chosen.Count);
}
```

无向图不连通时，结果是最小生成森林，而不是一棵生成树；`Components` 可用于明确判断输入是否连通。重复边和负权边不需要特殊处理，只要排序使用 `long` 累加并在并查集合并前校验顶点编号即可。空图的森林权值为 0，顶点数为 0 时不要访问数组下标。

严格第二小生成树不能只维护路径最大值，再把等权候选跳过。例如三角形边权为 `1、2、2`，MST 权值为 `3`。将未选的权 `2` 边加入后，删除路径最大边 `2` 仍得到 `3`；删除严格次大边 `1` 才得到正确答案 `4`。这也是第 3.2 节需要维护两个不同权值的原因。若只要求另一棵边集不同的生成树而允许总权值相等，则等权替换可以保留，只维护路径最大值即可；重边必须有独立的边编号，不能仅凭端点和权值区分是否被选中。

建议至少测试以下情况：只有一个顶点、包含自环、重复权值边、负权边、孤立顶点、完全不连通图，以及总权值接近 `long.MaxValue` 的输入。测试应同时检查所选边数、连通分量数和总权值，不能只检查边集文本顺序，因为等权 MST 的边集可能不唯一。

## 参考资料

- [Kruskal with DSU — cp-algorithms](https://cp-algorithms.com/graph/mst_kruskal_with_dsu.html)：边排序、并查集合并和最小生成森林。
- [Second Best MST — cp-algorithms](https://cp-algorithms.com/graph/second_best_mst.html)：非树边替换、倍增查询及严格第二小权值处理。
