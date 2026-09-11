# 广度优先搜索（BFS）

广度优先搜索按距离分层访问顶点：先访问源点，再访问距离为 1、2……的顶点。边权全部相同（通常为 1）时，BFS 第一次到达顶点的路径就是最短路径。它也用于网格最短步数、二分图判定和层序处理。

**示例环境：C# 14、.NET 10。** 使用 `Queue<int>`，并在入队时标记访问，避免同一顶点重复入队。

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
```

在控制台项目的 `Program.cs` 中调用，上面的类型可以放在另一个文件中：

```csharp
var graph = new List<IReadOnlyList<int>>
{
    new[] { 1, 2 },
    new[] { 0, 3 },
    new[] { 0, 3 },
    new[] { 1, 2 }
};
var (distance, previous) = BreadthFirstSearch.ShortestPaths(graph, source: 0);
Console.WriteLine(distance[3]); // 2
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

当边权仅为 0 或 1 时，使用双端队列：权重 0 的边从队首加入，权重 1 的边从队尾加入，时间复杂度为 `O(V + E)`。不能把任意正权图直接套用 0-1 BFS。.NET 10 没有名为 `Deque<T>` 的内置集合，教学实现可以使用 `LinkedList<T>`；需要减少节点分配时，再改成环形数组实现的双端队列。

## 4. 常见错误

1. 出队时才标记访问，导致顶点被多次入队，时间和内存显著增加；通常应在入队时标记。
2. 用 BFS 处理不同权重的边；边权不全相等时应使用 Dijkstra、0-1 BFS 或其他适合算法。
3. 只从源点遍历，二分图判定或连通分量统计会遗漏非连通分量。
4. 网格坐标换算错误，行列边界判断顺序不当造成越界。
5. `previous` 未初始化为 `-1`，恢复不可达路径时可能死循环。

## 5. 多源 BFS：计算到最近设施的距离

假设园区用一个矩形网格表示，`0` 是可通行位置，`1` 是墙。现在有多个服务点，需要计算每个位置走到最近服务点的最少步数。逐个服务点运行 BFS 会重复访问网格；多源 BFS 则把所有服务点同时设为第 0 层，放进同一个队列。

以下代码适用于 C# 14 / .NET 10。距离为 `-1` 表示墙或不可到达的位置，调用方可通过原网格区分两者。四个方向的移动代价相同，不允许斜向移动。

```csharp
using System;
using System.Collections.Generic;

public static class GridDistances
{
    public static int[,] ToNearestSource(
        int[,] cells, IEnumerable<(int Row, int Column)> sources)
    {
        ArgumentNullException.ThrowIfNull(cells);
        ArgumentNullException.ThrowIfNull(sources);
        int rows = cells.GetLength(0);
        int columns = cells.GetLength(1);
        var distance = new int[rows, columns];
        for (int row = 0; row < rows; row++)
        {
            for (int column = 0; column < columns; column++)
            {
                if (cells[row, column] is not (0 or 1))
                    throw new ArgumentException("网格只能包含 0 和 1。", nameof(cells));
                distance[row, column] = -1;
            }
        }

        var queue = new Queue<(int Row, int Column)>();
        foreach (var (row, column) in sources)
        {
            if ((uint)row >= (uint)rows || (uint)column >= (uint)columns)
                throw new ArgumentOutOfRangeException(nameof(sources));
            if (cells[row, column] == 1)
                throw new ArgumentException("服务点不能位于墙内。", nameof(sources));
            if (distance[row, column] == 0) continue; // 重复的服务点只入队一次。
            distance[row, column] = 0;
            queue.Enqueue((row, column));
        }

        ReadOnlySpan<int> rowOffsets = [-1, 1, 0, 0];
        ReadOnlySpan<int> columnOffsets = [0, 0, -1, 1];
        while (queue.TryDequeue(out var cell))
        {
            for (int direction = 0; direction < 4; direction++)
            {
                int nextRow = cell.Row + rowOffsets[direction];
                int nextColumn = cell.Column + columnOffsets[direction];
                if ((uint)nextRow >= (uint)rows ||
                    (uint)nextColumn >= (uint)columns)
                    continue;
                if (cells[nextRow, nextColumn] == 1 ||
                    distance[nextRow, nextColumn] >= 0)
                    continue;

                distance[nextRow, nextColumn] = distance[cell.Row, cell.Column] + 1;
                queue.Enqueue((nextRow, nextColumn));
            }
        }
        return distance;
    }
}
```

例如，输入网格为 `[[0,0,1,0],[0,0,1,0],[0,0,0,0]]`，服务点为 `(0,0)` 和 `(0,3)`，返回矩阵如下：

```text
 0  1 -1  0
 1  2 -1  1
 2  3  3  2
```

为什么“同时出发”仍然能得到最短距离？队列先取出所有距离为 0 的格子，再取出所有距离为 1 的格子，以此类推。如果某格子第一次被发现时距离为 `d`，那么长度小于 `d` 的路径已经在前几层处理完了，不可能再出现更短的到达方式。这个论证与单源 BFS 相同，只是第 0 层由一个顶点变成了一组顶点。

初始化和搜索均为 `O(RC)`；若源点枚举含有 `S` 条记录，总时间为 `O(RC + S)`，额外空间为 `O(RC)`。没有服务点时结果全部为 `-1`。如果要恢复路线，可以在第一次发现格子时保存父格子；沿父格子前进就会到达最近服务点，不需要再运行一次搜索。

## 6. 0-1 BFS：免费通道和收费通道

普通 BFS 使用“第一次发现即确定距离”的规则，但遇到 0 权边时不能再这样做。顶点可能先通过一条权重为 1 的边到达，随后又通过若干条权重为 0 的边得到更短距离。下面只在出队且距离仍有效时确定顶点，并把过期的队列记录丢弃。

```csharp
using System;
using System.Collections.Generic;

public readonly record struct BinaryEdge(int To, int Weight);

public static class ZeroOneSearch
{
    public static long[] Distances(
        IReadOnlyList<IReadOnlyList<BinaryEdge>> graph, int source)
    {
        ArgumentNullException.ThrowIfNull(graph);
        int count = graph.Count;
        if ((uint)source >= (uint)count)
            throw new ArgumentOutOfRangeException(nameof(source));

        // 先检查全部输入；不可达部分的非法边也必须报告。
        foreach (var edges in graph)
        {
            ArgumentNullException.ThrowIfNull(edges);
            foreach (var edge in edges)
            {
                if ((uint)edge.To >= (uint)count || edge.Weight is not (0 or 1))
                    throw new ArgumentException("顶点编号无效，或边权不是 0/1。", nameof(graph));
            }
        }

        var distance = new long[count];
        Array.Fill(distance, long.MaxValue);
        var settled = new bool[count];
        var deque = new LinkedList<(int Vertex, long Distance)>();
        distance[source] = 0;
        deque.AddFirst((source, 0));

        while (deque.Count != 0)
        {
            var current = deque.First!.Value;
            deque.RemoveFirst();
            int vertex = current.Vertex;
            if (settled[vertex] || current.Distance != distance[vertex]) continue;
            settled[vertex] = true;

            foreach (var edge in graph[vertex])
            {
                long candidate = current.Distance + edge.Weight;
                if (candidate >= distance[edge.To]) continue;
                distance[edge.To] = candidate;
                if (edge.Weight == 0) deque.AddFirst((edge.To, candidate));
                else deque.AddLast((edge.To, candidate));
            }
        }
        return distance;
    }
}
```

每次取出距离为 `d` 的有效记录时，后续有效记录的距离只可能是 `d` 或 `d + 1`。0 权边产生的记录放在队首，1 权边产生的记录放在队尾，因此最先确定的总是当前最小距离。每个顶点只扫描一次邻接表，每条边最多触发一次松弛，时间为 `O(V + E)`。这份实现保留过期记录，队列最坏占用 `O(E)`，连同距离数组的额外空间为 `O(V + E)`，不能把它误写成始终只有 `O(V)` 个队列节点。

## 7. 可直接运行的检查

把本节代码放进控制台项目的 `Program.cs`，第 5、6 节的类型放进各自的 `.cs` 文件。检查使用显式异常，Release 构建也会执行，不依赖测试框架。

```csharp
static void Expect(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException($"检查失败：{name}");
}

int[,] cells = { { 0, 0, 1, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 0 } };
int[,] distances = GridDistances.ToNearestSource(cells, [(0, 0), (0, 3), (0, 0)]);
Expect(distances[2, 1] == 3 && distances[2, 2] == 3, "多个源点与重复源点");
Expect(distances[0, 2] == -1, "墙保持不可达");
Expect(GridDistances.ToNearestSource(new int[1, 1], []) [0, 0] == -1, "没有源点");
Expect(GridDistances.ToNearestSource(new int[1, 1], [(0, 0)])[0, 0] == 0, "单格网格");
int[,] separated = { { 0, 1, 0 } };
Expect(GridDistances.ToNearestSource(separated, [(0, 0)])[0, 2] == -1, "障碍隔断");

IReadOnlyList<IReadOnlyList<BinaryEdge>> graph = new BinaryEdge[][]
{
    [new(1, 1), new(2, 0)],
    [new(3, 1)],
    [new(1, 0)],
    [],
    []
};
long[] weighted = ZeroOneSearch.Distances(graph, 0);
Expect(weighted[1] == 0 && weighted[3] == 1, "后发现的零权路径更短");
Expect(weighted[4] == long.MaxValue, "不可达顶点");
Console.WriteLine("BFS 检查通过");
```

在业务系统中，多源 BFS 可用于地图距离场、最近出口和规则相同的状态转换；0-1 BFS 适合“保持当前状态免费、切换状态花费一次”这类模型。若一次操作可能花费 2 或更多，则需要重新选择算法，例如使用 Dijkstra，不能仅把该权重放到队尾。

## 参考资料

- [Breadth-first search — cp-algorithms](https://cp-algorithms.com/graph/breadth-first-search.html)：分层遍历、无权最短路和路径恢复。
- [0-1 BFS — cp-algorithms](https://cp-algorithms.com/graph/01_bfs.html)：双端队列处理 0/1 权边。
- [Queue<T> — Microsoft Learn](https://learn.microsoft.com/zh-cn/dotnet/api/system.collections.generic.queue-1?view=net-10.0)：C# FIFO 容器 API。
