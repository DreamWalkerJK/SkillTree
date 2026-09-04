# 线段树（Segment Tree）

线段树把一个数组递归划分为区间，每个节点保存其区间的聚合值。它适合处理“区间查询 + 单点/区间更新”：例如区间和、最小值、最大值、最大公约数以及带懒标记的区间加法。与前缀和相比，线段树允许更新；与逐项扫描相比，它把一次查询或更新降到对数复杂度。

## 1. 结构与复杂度

**示例环境：C# 12、.NET 8（`net8.0`）。** 线段树是算法层面的数据结构，.NET 版本只影响示例使用的集合和语言语法。

节点 `[l, r)` 表示半开区间。叶节点长度为 1；内部节点由左右子节点合并。树高为 `O(log n)`，节点数小于 `4n`（递归数组实现的常用上界）。

* 建树：`O(n)`。
* 单点更新、区间查询：`O(log n)`。
* 带懒传播的区间更新：`O(log n)`。
* 空间：`O(n)`。

聚合操作必须满足结合律。求和、最小值等满足结合律，减法和除法不满足，不能直接套用普通线段树。

## 2. 基础用法：区间和与单点更新（.NET 8）

```csharp
public sealed class SumSegmentTree
{
    private readonly int _length;
    private readonly long[] _tree;

    public SumSegmentTree(IReadOnlyList<long> values)
    {
        _length = values.Count;
        _tree = new long[Math.Max(1, values.Count * 4)];
        if (_length > 0) Build(1, 0, _length, values);
    }

    private void Build(int node, int left, int right, IReadOnlyList<long> values)
    {
        if (right - left == 1) { _tree[node] = values[left]; return; }
        int mid = left + (right - left) / 2;
        Build(node * 2, left, mid, values);
        Build(node * 2 + 1, mid, right, values);
        _tree[node] = _tree[node * 2] + _tree[node * 2 + 1];
    }

    // 将 values[index] 设为 value
    public void Set(int index, long value)
    {
        CheckRange(index, index + 1);
        Set(1, 0, _length, index, value);
    }

    private void Set(int node, int left, int right, int index, long value)
    {
        if (right - left == 1) { _tree[node] = value; return; }
        int mid = left + (right - left) / 2;
        if (index < mid) Set(node * 2, left, mid, index, value);
        else Set(node * 2 + 1, mid, right, index, value);
        _tree[node] = _tree[node * 2] + _tree[node * 2 + 1];
    }

    // 查询半开区间 [queryLeft, queryRight)
    public long Query(int queryLeft, int queryRight)
    {
        CheckRange(queryLeft, queryRight);
        return Query(1, 0, _length, queryLeft, queryRight);
    }

    private long Query(int node, int left, int right, int ql, int qr)
    {
        if (qr <= left || right <= ql) return 0;
        if (ql <= left && right <= qr) return _tree[node];
        int mid = left + (right - left) / 2;
        return Query(node * 2, left, mid, ql, qr)
             + Query(node * 2 + 1, mid, right, ql, qr);
    }

    private void CheckRange(int left, int right)
    {
        if (_length == 0 || left < 0 || right > _length || left >= right)
            throw new ArgumentOutOfRangeException();
    }
}

var tree = new SumSegmentTree(new long[] { 2, 1, 3, 4, 5 });
Console.WriteLine(tree.Query(1, 4)); // 1 + 3 + 4 = 8
tree.Set(2, 10);
Console.WriteLine(tree.Query(1, 4)); // 15
```

## 3. 进阶用法：懒传播区间加法

当更新覆盖一个内部节点的整个区间时，不必立即向下修改所有叶节点。节点保存 `lazy[node]`，表示尚未下推给子节点的增量；访问子区间前调用 `Push`。下面示例同时支持区间加法和区间求和。

```csharp
public sealed class RangeAddSumTree
{
    private readonly int _n;
    private readonly long[] _sum;
    private readonly long[] _lazy;

    public RangeAddSumTree(IReadOnlyList<long> values)
    {
        _n = values.Count;
        _sum = new long[Math.Max(1, _n * 4)];
        _lazy = new long[_sum.Length];
        if (_n > 0) Build(1, 0, _n, values);
    }

    private void Build(int p, int l, int r, IReadOnlyList<long> a)
    {
        if (r - l == 1) { _sum[p] = a[l]; return; }
        int m = (l + r) / 2;
        Build(p * 2, l, m, a); Build(p * 2 + 1, m, r, a);
        Pull(p);
    }

    private void Pull(int p) => _sum[p] = _sum[p * 2] + _sum[p * 2 + 1];

    private void Apply(int p, int l, int r, long delta)
    {
        _sum[p] += delta * (r - l);
        _lazy[p] += delta;
    }

    private void Push(int p, int l, int r)
    {
        if (_lazy[p] == 0 || r - l == 1) return;
        int m = (l + r) / 2;
        Apply(p * 2, l, m, _lazy[p]);
        Apply(p * 2 + 1, m, r, _lazy[p]);
        _lazy[p] = 0;
    }

    public void Add(int ql, int qr, long delta)
    {
        CheckRange(ql, qr);
        Add(1, 0, _n, ql, qr, delta);
    }

    private void Add(int p, int l, int r, int ql, int qr, long delta)
    {
        if (qr <= l || r <= ql) return;
        if (ql <= l && r <= qr) { Apply(p, l, r, delta); return; }
        Push(p, l, r);
        int m = (l + r) / 2;
        Add(p * 2, l, m, ql, qr, delta);
        Add(p * 2 + 1, m, r, ql, qr, delta);
        Pull(p);
    }

    public long Query(int ql, int qr)
    {
        CheckRange(ql, qr);
        return Query(1, 0, _n, ql, qr);
    }

    private long Query(int p, int l, int r, int ql, int qr)
    {
        if (qr <= l || r <= ql) return 0;
        if (ql <= l && r <= qr) return _sum[p];
        Push(p, l, r);
        int m = (l + r) / 2;
        return Query(p * 2, l, m, ql, qr) + Query(p * 2 + 1, m, r, ql, qr);
    }

    private void CheckRange(int left, int right)
    {
        if (_n == 0 || left < 0 || right > _n || left >= right)
            throw new ArgumentOutOfRangeException();
    }
}
```

区间赋值、区间取最小值等操作需要为每种更新定义合并顺序（例如“赋值”要覆盖已有加法标记），不能简单复制 `lazy` 字段。数据量很大时可使用迭代线段树或按需开点的动态线段树；坐标范围达到 `10^9` 而实际更新点很少时，动态开点更节省内存。

## 4. 常见错误

1. 混用闭区间 `[l, r]` 和半开区间 `[l, r)`，导致少算一个元素或递归不终止。
2. 空数组仍从根节点递归，`right - left` 为 0 时会无限递归；构造时应显式处理 `n == 0`。
3. 使用懒标记更新后忘记 `Pull`，父节点聚合值会过期。
4. 查询前不 `Push`，子节点仍是旧值，部分覆盖查询会返回错误结果。
5. 和、乘积可能溢出 `int`；根据约束选 `long`，并注意 `delta * (r - l)` 的乘法类型。
