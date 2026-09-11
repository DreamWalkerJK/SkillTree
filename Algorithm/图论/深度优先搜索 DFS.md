# 深度优先搜索（DFS）

深度优先搜索沿一条分支尽可能深入，走不通时回溯。它是连通性、环检测、拓扑排序、桥和割点、强连通分量以及回溯枚举的基础。图通常用邻接表表示。

**示例环境：C# 14、.NET 10。** 下面给出递归和显式栈两种写法。

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

这里的 `CountComponents` 面向无向图，输入时应把每条无向边写入两个顶点的邻接表。有向图从一个顶点能够到达另一顶点，并不意味着反方向也能到达；把该方法直接用于有向图，得到的数字依赖遍历顺序，既不是强连通分量数，也不一定是弱连通分量数。

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

## 5. 显式保存递归现场：有向环与拓扑序

只把顶点压入 `Stack<int>` 足以判断可达性，却不能直接模拟递归函数返回时执行的逻辑。比如拓扑排序需要在一个顶点的所有后继处理完成之后记录它；有向环检测需要知道顶点是否仍在当前调用链中。为此，栈帧需要同时保存顶点和“下一个要处理的邻接表下标”。

下面的算法返回一个实际的有向环；如果没有环，则返回拓扑序。环的起点会在结尾再出现一次，例如 `[1, 2, 3, 1]` 表示 `1 → 2 → 3 → 1`。空图没有环，拓扑序为空。代码使用 C# 14 / .NET 10。

```csharp
using System;
using System.Collections.Generic;

public readonly record struct DirectedSearchResult(int[] Cycle, int[] TopologicalOrder);

public static class DirectedDepthFirstSearch
{
    public static DirectedSearchResult Analyze(
        IReadOnlyList<IReadOnlyList<int>> graph)
    {
        ArgumentNullException.ThrowIfNull(graph);
        int count = graph.Count;
        foreach (var neighbors in graph)
        {
            ArgumentNullException.ThrowIfNull(neighbors);
            foreach (int next in neighbors)
            {
                if ((uint)next >= (uint)count)
                    throw new ArgumentException("邻接表包含无效顶点。", nameof(graph));
            }
        }

        // 0：未访问；1：当前调用链中；2：全部后继已处理。
        var color = new byte[count];
        var parent = new int[count];
        Array.Fill(parent, -1);
        var finished = new List<int>(count);
        var stack = new Stack<(int Vertex, int NextNeighbor)>();

        for (int start = 0; start < count; start++)
        {
            if (color[start] != 0) continue;
            color[start] = 1;
            stack.Push((start, 0));

            while (stack.TryPop(out var frame))
            {
                int vertex = frame.Vertex;
                if (frame.NextNeighbor == graph[vertex].Count)
                {
                    color[vertex] = 2;
                    finished.Add(vertex);
                    continue;
                }

                int next = graph[vertex][frame.NextNeighbor];
                // 返回该顶点时，从下一条边继续，而不是重新扫描邻接表。
                stack.Push((vertex, frame.NextNeighbor + 1));
                if (color[next] == 0)
                {
                    parent[next] = vertex;
                    color[next] = 1;
                    stack.Push((next, 0));
                }
                else if (color[next] == 1)
                {
                    var cycle = new List<int> { next };
                    for (int at = vertex; at != next; at = parent[at])
                        cycle.Add(at);
                    cycle.Add(next);
                    cycle.Reverse();
                    return new DirectedSearchResult(cycle.ToArray(), []);
                }
                // 指向黑色顶点的边不会构成当前调用链中的环。
            }
        }

        finished.Reverse();
        return new DirectedSearchResult([], finished.ToArray());
    }
}
```

### 5.1 为什么需要三种状态

对于 `0 → 1`、`0 → 2`、`1 → 2`，DFS 可能先沿 `0 → 1 → 2` 完成访问。返回 0 后再次遇到 2，2 已经访问过，但它是黑色，不在当前调用链中，因此这条边不意味着有环。只使用 `bool[] visited` 会丢失这个区别。

相反，如果顶点 `u` 通过一条边访问灰色顶点 `v`，`v` 必然是当前调用链上 `u` 的祖先，父指针提供了 `v → … → u` 的树路径，新发现的 `u → v` 则把路径闭合成环。对于自环 `u → u`，返回结果自然为 `[u, u]`。

若没有环，每条边 `u → v` 都满足：要么 v 在遍历 u 时先完成，要么 v 在此前的搜索中已经完成。因此按完成顺序逆序排列后，u 一定出现在 v 前面，这正是拓扑序的定义。

### 5.2 时间与空间

每个顶点只从白色变成灰色、再变成黑色一次；栈帧中的下标保证每条边只检查一次。预先校验输入也只需要扫描一次邻接表，所以总时间仍为 `O(V + E)`。颜色、父指针、结果和显式栈均为 `O(V)` 空间。

一个常见的低效改写是“每次返回顶点时，从邻接表开头寻找下一个未访问邻居”。高出度顶点会被反复扫描，复杂度可能不再是线性的。保存 `NextNeighbor` 不只是实现细节，它保证了线性时间。

## 6. 测试：环、非连通图和长链

将第 5 节类型放在独立源文件中，下面作为控制台项目的 `Program.cs`。拓扑序不一定唯一，因此测试验证的是每条边的先后关系，而不是某个固定数组。

```csharp
static void Expect(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException($"检查失败：{name}");
}

static bool IsTopological(IReadOnlyList<IReadOnlyList<int>> graph, int[] order)
{
    if (order.Length != graph.Count) return false;
    int[] positions = new int[graph.Count];
    Array.Fill(positions, -1);
    for (int index = 0; index < order.Length; index++)
    {
        int vertex = order[index];
        if ((uint)vertex >= (uint)graph.Count || positions[vertex] >= 0) return false;
        positions[vertex] = index;
    }
    for (int vertex = 0; vertex < graph.Count; vertex++)
        foreach (int next in graph[vertex])
            if (positions[vertex] >= positions[next]) return false;
    return true;
}

IReadOnlyList<IReadOnlyList<int>> dag = new int[][] { [1, 2], [2], [], [4], [] };
var acyclic = DirectedDepthFirstSearch.Analyze(dag);
Expect(acyclic.Cycle.Length == 0 && IsTopological(dag, acyclic.TopologicalOrder),
    "已完成顶点和非连通分量");

IReadOnlyList<IReadOnlyList<int>> cyclic = new int[][] { [1], [2], [3], [1] };
var detected = DirectedDepthFirstSearch.Analyze(cyclic);
Expect(detected.Cycle.SequenceEqual(new[] { 1, 2, 3, 1 }), "恢复有向环");
Expect(detected.TopologicalOrder.Length == 0, "有环时不返回残缺的拓扑序");
Expect(DirectedDepthFirstSearch.Analyze(new int[][] { [0] }).Cycle.Length == 2, "自环");
Expect(DirectedDepthFirstSearch.Analyze(Array.Empty<int[]>()).Cycle.Length == 0, "空图");

const int count = 100_000;
var chain = new IReadOnlyList<int>[count];
for (int vertex = 0; vertex < count; vertex++)
    chain[vertex] = vertex + 1 < count ? new[] { vertex + 1 } : Array.Empty<int>();
var longChain = DirectedDepthFirstSearch.Analyze(chain);
Expect(IsTopological(chain, longChain.TopologicalOrder), "十万顶点长链不使用递归栈");
Console.WriteLine("DFS 检查通过");
```

在依赖管理工具中，单纯报告“存在循环依赖”往往不够；实际的环路径能直接指向需要修改的模块。在工作流系统中，无环结果可以交给拓扑调度器，但拓扑序只规定先后关系，并不意味着必须串行执行，互不依赖的任务仍然可以并发处理。

## 7. 把递归算法改为显式栈时应保留什么

遍历算法通常只需要顶点；路径回溯还需要进入和离开动作；桥与割点算法还需要子树返回后的 `low` 更新。因此，不能把所有递归 DFS 都机械地替换成“邻居全部压栈”。第 3 节的桥算法若要处理极长链，应在栈帧中保存父边 ID、下一个邻居下标，并在子顶点完成时执行 `low[parent] = Min(low[parent], low[child])` 和桥判断。

无向多重图尤其需要测试两条平行边连接相同顶点的情况。第一条边是树边，第二条仍可作为返祖边，使子顶点的 `low` 降到父顶点的进入时间；因此两条边都不是桥。若按“父顶点”跳过全部反向记录，就会错误地把它们当成桥。

递归版适合深度可控、需要直观展示递推关系的输入；显式栈版适合长依赖链、外部导入图和深度难以预估的状态空间。应根据最大深度决定实现方式，而不是仅根据顶点总数判断是否会发生栈溢出。

## 参考资料

- [Depth First Search — cp-algorithms](https://cp-algorithms.com/graph/depth-first-search.html)：进入/退出时刻与显式栈现场。
- [Finding bridges — cp-algorithms](https://cp-algorithms.com/graph/bridge-searching.html)：tin、low 和桥的判定。
- [Topological Sorting — cp-algorithms](https://cp-algorithms.com/graph/topological-sort.html)：DFS 完成顺序与拓扑序。
