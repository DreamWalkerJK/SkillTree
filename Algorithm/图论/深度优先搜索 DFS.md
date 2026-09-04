# 深度优先搜索（DFS）

深度优先搜索沿一条分支尽可能深入，走不通时回溯。它是连通性、环检测、拓扑排序、桥和割点、强连通分量以及回溯枚举的基础。图通常用邻接表表示。

**示例环境：C# 12、.NET 8。** 下面给出递归和显式栈两种写法。

## 1. 复杂度

邻接表下每个顶点和边最多访问一次，时间复杂度 `O(V + E)`，访问标记和递归/显式栈空间 `O(V)`。邻接矩阵扫描邻居会变成 `O(V²)`。

## 2. 基础用法：遍历与连通分量

```csharp
public static class DepthFirstSearch
{
    public static void Traverse(IReadOnlyList<IReadOnlyList<int>> graph, int start,
        Action<int> visit)
    {
        bool[] seen = new bool[graph.Count];
        void Dfs(int u)
        {
            seen[u] = true;
            visit(u);
            foreach (int v in graph[u])
            {
                if ((uint)v >= (uint)graph.Count)
                    throw new ArgumentOutOfRangeException(nameof(graph));
                if (!seen[v]) Dfs(v);
            }
        }
        if ((uint)start >= (uint)graph.Count) throw new ArgumentOutOfRangeException(nameof(start));
        Dfs(start);
    }

    public static int CountComponents(IReadOnlyList<IReadOnlyList<int>> graph)
    {
        bool[] seen = new bool[graph.Count]; int components = 0;
        for (int i = 0; i < graph.Count; i++)
        {
            if (seen[i]) continue;
            components++;
            var stack = new Stack<int>(); stack.Push(i); seen[i] = true;
            while (stack.TryPop(out int u))
                foreach (int v in graph[u])
                {
                    if ((uint)v >= (uint)graph.Count)
                        throw new ArgumentOutOfRangeException(nameof(graph));
                    if (!seen[v]) { seen[v] = true; stack.Push(v); }
                }
        }
        return components;
    }
}
```

有向图中的“已访问”不能简单等同于“当前路径上”：检测环时应使用三色状态。状态为灰色的邻接点代表后向边；黑色邻接点只表示该分支已处理完成。

## 3. 进阶：桥（Tarjan 低链接值）

无向图 DFS 中记录 `tin[u]`（进入时间）和 `low[u]`（通过树边及至多一条返祖边能到达的最早时间）。若树边 `u-v` 满足 `low[v] > tin[u]`，该边是桥。整体复杂度 `O(V + E)`。

```csharp
public readonly record struct NumberedEdge(int To, int Id);

public static List<(int U, int V)> FindBridges(
    IReadOnlyList<IReadOnlyList<NumberedEdge>> graph)
{
    int n = graph.Count, timer = 0;
    int[] tin = new int[n], low = new int[n];
    Array.Fill(tin, -1);
    var bridges = new List<(int, int)>();

    void Dfs(int u, int parentEdgeId)
    {
        tin[u] = low[u] = timer++;
        foreach (NumberedEdge edge in graph[u])
        {
            int v = edge.To;
            if ((uint)v >= (uint)n)
                throw new ArgumentOutOfRangeException(nameof(graph));
            if (edge.Id == parentEdgeId) continue;
            if (tin[v] >= 0) low[u] = Math.Min(low[u], tin[v]);
            else
            {
                Dfs(v, edge.Id);
                low[u] = Math.Min(low[u], low[v]);
                if (low[v] > tin[u]) bridges.Add((u, v));
            }
        }
    }
    for (int i = 0; i < n; i++) if (tin[i] < 0) Dfs(i, -1);
    return bridges;
}
```

例如无向边 `(u,v)` 使用同一个 `Id` 加入两份邻接记录：`adj[u].Add(new(v, id)); adj[v].Add(new(u, id));`。不要用局部下标或 `edgeId ^ 1` 推断反向边，邻接表排序、过滤或存在多重边时都会失效。

## 4. 常见错误

1. 无向图不跳过“父边”，会把树边误判为返祖边；多重边还需要按边 ID 区分。
2. 在递归进入前后标记时机不一致，导致重复访问或环检测失效。
3. 深度很大的图使用递归，触发 `StackOverflowException`；改用显式 `Stack<int>`。
4. 遍历非连通图只从一个起点调用 DFS，遗漏其他分量。
5. 把 DFS 的遍历顺序当成最短路径；无权最短路应使用 BFS。
