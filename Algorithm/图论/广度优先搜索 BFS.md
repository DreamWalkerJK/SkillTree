# 广度优先搜索（BFS）

广度优先搜索按距离分层访问顶点：先访问源点，再访问距离为 1、2……的顶点。边权全部相同（通常为 1）时，BFS 第一次到达顶点的路径就是最短路径。它也用于网格最短步数、二分图判定和层序处理。

**示例环境：C# 12、.NET 8。** 使用 `Queue<int>`，并在入队时标记访问，避免同一顶点重复入队。

## 1. 复杂度

邻接表下时间复杂度 `O(V + E)`，空间复杂度 `O(V)`（不含图存储）。网格 `R × C` 中每个格子至多访问一次，复杂度 `O(RC)`。

## 2. 基础用法：无权图最短路径

```csharp
public static class BreadthFirstSearch
{
    public static (int[] Distance, int[] Previous) ShortestPaths(
        IReadOnlyList<IReadOnlyList<int>> graph, int source)
    {
        int n = graph.Count;
        if ((uint)source >= (uint)n) throw new ArgumentOutOfRangeException(nameof(source));
        int[] distance = new int[n], previous = new int[n];
        Array.Fill(distance, -1); Array.Fill(previous, -1);
        var queue = new Queue<int>();
        distance[source] = 0; queue.Enqueue(source);

        while (queue.TryDequeue(out int u))
        {
            foreach (int v in graph[u])
            {
                if ((uint)v >= (uint)n) throw new ArgumentOutOfRangeException(nameof(graph));
                if (distance[v] >= 0) continue;
                distance[v] = distance[u] + 1;
                previous[v] = u;
                queue.Enqueue(v);
            }
        }
        return (distance, previous);
    }

    public static List<int> BuildPath(int source, int target, int[] distance, int[] previous)
    {
        if ((uint)target >= (uint)distance.Length || distance[target] < 0) return new();
        var path = new List<int>();
        for (int at = target; at >= 0; at = previous[at]) path.Add(at);
        path.Reverse();
        return path.Count > 0 && path[0] == source ? path : new List<int>();
    }
}

var graph = new List<IReadOnlyList<int>>
{
    new[] { 1, 2 },
    new[] { 0, 3 },
    new[] { 0, 3 },
    new[] { 1, 2 }
};
var (distance, previous) = BreadthFirstSearch.ShortestPaths(graph, source: 0);
Console.WriteLine(distance[3]);
```

## 3. 进阶用法

### 3.1 网格最短路

将每个可通行格子视为顶点，四个（或八个）方向视为边。队列元素可保存 `(row, column)`；用 `ReadOnlySpan<int>` 保存方向数组能减少临时对象。边界和障碍判断应在入队前完成。

### 3.2 二分图判定

为每个顶点分配颜色 `-1/0/1`。BFS 从每个未染色分量开始，邻接点染成相反颜色；若发现相邻顶点颜色相同，则图不是二分图。复杂度仍为 `O(V + E)`。

```csharp
public static bool IsBipartite(IReadOnlyList<IReadOnlyList<int>> graph)
{
    int[] color = new int[graph.Count]; Array.Fill(color, -1);
    var q = new Queue<int>();
    for (int start = 0; start < graph.Count; start++)
    {
        if (color[start] != -1) continue;
        color[start] = 0; q.Enqueue(start);
        while (q.TryDequeue(out int u))
            foreach (int v in graph[u])
            {
                if ((uint)v >= (uint)graph.Count)
                    throw new ArgumentOutOfRangeException(nameof(graph));
                if (color[v] == -1) { color[v] = color[u] ^ 1; q.Enqueue(v); }
                else if (color[v] == color[u]) return false;
            }
    }
    return true;
}
```

### 3.3 0-1 BFS

当边权仅为 0 或 1 时，使用 `Deque`：权重 0 的边从队首加入，权重 1 的边从队尾加入，可将 Dijkstra 降为 `O(V + E)`。不能把任意正权图直接套用 0-1 BFS。

## 4. 常见错误

1. 出队时才标记访问，导致顶点被多次入队，时间和内存显著增加；通常应在入队时标记。
2. 用 BFS 处理不同权重的边；边权不全相等时应使用 Dijkstra、0-1 BFS 或其他适合算法。
3. 只从源点遍历，二分图判定或连通分量统计会遗漏非连通分量。
4. 网格坐标换算错误，行列边界判断顺序不当造成越界。
5. `previous` 未初始化为 `-1`，恢复不可达路径时可能死循环。
