# 并查集（Disjoint Set Union）

并查集（Disjoint Set Union，DSU，也称 Union-Find）维护一组互不相交的集合。它只关心两个操作：查询两个元素是否属于同一集合（`Find`），以及合并两个集合（`Union`）。典型用途是无向图连通分量、Kruskal 最小生成树、等价关系归并和离线连通性查询。

## 1. 数据结构与不变量

每个元素保存一个父节点编号。根节点的父节点是自己，根节点代表整个集合。直接按树高合并会退化成链，因此实现通常同时使用：

* **路径压缩**：`Find(x)` 返回根时，把沿途节点直接挂到根上。
* **按大小（或按秩）合并**：总是把较小的树挂到较大的树上。

两种优化同时启用后，连续 `m` 次操作的摊销复杂度为 `O(m α(n))`，其中 `α` 是反阿克曼函数；在实际数据规模下可视为常数。初始化需要 `O(n)` 空间和时间。

## 2. 基础用法：判断连通性

下面代码兼容 C# 8 及以上，示例项目使用 .NET 8（`net8.0`）。`Union` 返回值表示是否真的合并了两个不同集合，可用于统计连通分量数量。

```csharp
public sealed class DisjointSetUnion
{
    private readonly int[] _parent;
    private readonly int[] _size;

    public int ComponentCount { get; private set; }

    public DisjointSetUnion(int count)
    {
        if (count < 0) throw new ArgumentOutOfRangeException(nameof(count));
        _parent = new int[count];
        _size = new int[count];
        for (int i = 0; i < count; i++)
        {
            _parent[i] = i;
            _size[i] = 1;
        }
        ComponentCount = count;
    }

    public int Find(int x)
    {
        CheckIndex(x);
        // 路径压缩：递归深度在按大小合并后为 O(log n)，也可改成迭代写法。
        return _parent[x] == x ? x : _parent[x] = Find(_parent[x]);
    }

    public bool Union(int a, int b)
    {
        int rootA = Find(a), rootB = Find(b);
        if (rootA == rootB) return false;
        if (_size[rootA] < _size[rootB]) (rootA, rootB) = (rootB, rootA);
        _parent[rootB] = rootA;
        _size[rootA] += _size[rootB];
        ComponentCount--;
        return true;
    }

    public bool Connected(int a, int b) => Find(a) == Find(b);

    public int SizeOf(int x) => _size[Find(x)];

    private void CheckIndex(int x)
    {
        if ((uint)x >= (uint)_parent.Length)
            throw new ArgumentOutOfRangeException(nameof(x));
    }
}

// 使用：城市编号 0..4，合并道路后查询是否互通
var dsu = new DisjointSetUnion(5);
dsu.Union(0, 1);
dsu.Union(1, 2);
Console.WriteLine(dsu.Connected(0, 2)); // True
Console.WriteLine(dsu.ComponentCount);  // 3
```

## 3. 进阶用法

### 3.1 在根节点维护聚合信息

只要聚合值满足“两个集合合并时可在常数时间合并”，就能与 DSU 一起维护。例如每个集合的权重和、最大值或成员数量。只有根节点上的值有效，合并后要把被挂载根的值累加到新根。

```csharp
public sealed class WeightedDsu
{
    private readonly int[] _parent;
    private readonly int[] _size;
    private readonly long[] _sum;

    public WeightedDsu(IReadOnlyList<long> weights)
    {
        _parent = new int[weights.Count];
        _size = new int[weights.Count];
        _sum = new long[weights.Count];
        for (int i = 0; i < weights.Count; i++)
        {
            _parent[i] = i;
            _size[i] = 1;
            _sum[i] = weights[i];
        }
    }

    private int Find(int x) => _parent[x] == x ? x : _parent[x] = Find(_parent[x]);

    public void Union(int a, int b)
    {
        a = Find(a); b = Find(b);
        if (a == b) return;
        if (_size[a] < _size[b]) (a, b) = (b, a);
        _parent[b] = a;
        _size[a] += _size[b];
        _sum[a] += _sum[b];
    }

    public long SumOf(int x) => _sum[Find(x)];
}
```

### 3.2 可回滚并查集

离线处理“加边、撤销到某个时间点”的问题时，可以不做路径压缩，只按大小合并，并把每次修改压入栈。记录快照栈长度，回滚时恢复到该长度。单次合并和回滚均为 `O(log n)`（按大小保证树高），适合线段树分治、动态连通性等算法。路径压缩会修改多条父链，难以在常数条记录中撤销，因此回滚版本通常禁用路径压缩。

## 4. 常见错误

1. 只实现 `Union`，却忘记先 `Find`，会把非根节点作为父节点，导致树结构错误。
2. `Union` 时没有按大小/秩合并，极端输入会退化为 `O(n)` 的单次查询。
3. 维护集合信息时读取了非根节点的聚合值；应先 `Find` 再读取。
4. 编号从 1 开始却分配 `new int[n]`；要么统一使用 0 基编号，要么分配 `n + 1`。
5. 并查集只适合无向连通关系。带方向的可达性、最短路径和拓扑约束不能用 DSU 代替。

