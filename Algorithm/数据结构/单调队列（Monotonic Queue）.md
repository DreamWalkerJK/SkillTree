# 单调队列（Monotonic Queue）

单调队列是一个双端队列，队列中的元素按照值保持单调递增或递减。处理数组的固定长度滑动窗口时，队首始终是窗口最值；每个元素最多入队、出队一次，因此总复杂度为线性。

**示例环境：C# 12、.NET 8（`net8.0`）。** `ReadOnlySpan<T>` 在 C# 7.2/.NET Core 2.1 时代引入，示例用它避免复制输入数组。

## 1. 滑动窗口最大值

维护“值递减”的队列，队列存数组下标而非值：

1. 新下标 `i` 入队前，弹出队尾所有 `a[index] <= a[i]` 的元素，它们不可能成为未来窗口最大值。
2. 弹出已经离开窗口（`index <= i - k`）的队首。
3. 当前窗口最大值为队首下标对应的值。

每个下标只进出一次，时间复杂度 `O(n)`，额外空间 `O(k)`。示例采用 .NET 8 的数组手写环形双端队列，避免 `LinkedList<T>` 节点分配。

```csharp
public static int[] MaxSlidingWindow(ReadOnlySpan<int> values, int windowSize)
{
    if (windowSize <= 0 || windowSize > values.Length)
        throw new ArgumentOutOfRangeException(nameof(windowSize));

    // 环形数组存下标，count 表示当前元素个数，空间严格为 O(k)。
    int[] deque = new int[windowSize];
    int head = 0, count = 0;
    int[] answer = new int[values.Length - windowSize + 1];
    int output = 0;

    for (int i = 0; i < values.Length; i++)
    {
        while (count > 0 && deque[head] <= i - windowSize)
        {
            head = (head + 1) % deque.Length;
            count--;
        }
        while (count > 0)
        {
            int backOffset = count - 1;
            int backIndex = deque[(head + backOffset) % deque.Length];
            if (values[backIndex] > values[i]) break;
            count--;
        }
        deque[(head + count) % deque.Length] = i;
        count++;
        if (i >= windowSize - 1) answer[output++] = values[deque[head]];
    }
    return answer;
}

int[] result = MaxSlidingWindow(new[] { 1, 3, -1, -3, 5, 3, 6, 7 }, 3);
Console.WriteLine(string.Join(", ", result)); // 3, 3, 5, 5, 6, 7
```

求最小值时把比较符号改为 `>=`，使队列中的值递增。若要保留相同值的最早下标，可使用严格比较并在队首过期时再删除；两种策略都正确，但要保持规则一致。

## 2. 进阶：和单调队列相关的 DP 优化

对递推式

`dp[i] = value[i] + min(dp[j])，其中 j ∈ [i - k, i - 1]`

可用存放 `dp` 下标的递增队列把每一步从 `O(k)` 降为 `O(1)`，总复杂度由 `O(nk)` 降为 `O(n)`。例如“跳跃游戏”最小代价：

```csharp
public static long MinJumpCost(ReadOnlySpan<int> cost, int maxJump)
{
    if (cost.Length == 0) return 0;
    if (maxJump <= 0) throw new ArgumentOutOfRangeException(nameof(maxJump));
    int[] q = new int[cost.Length];
    int head = 0, tail = 0;
    long[] dp = new long[cost.Length];
    q[tail++] = 0;
    dp[0] = cost[0];

    for (int i = 1; i < cost.Length; i++)
    {
        while (head < tail && q[head] < i - maxJump) head++;
        dp[i] = dp[q[head]] + cost[i];
        while (head < tail && dp[q[tail - 1]] >= dp[i]) tail--;
        q[tail++] = i;
    }
    return dp[^1];
}
```

另一个常见模型是“前缀和 + 单调队列”：求和至少为 `target` 的最短子数组时，维护前缀和递增队列；当当前前缀和减去队首前缀和达到 `target`，持续弹出队首并更新答案。数组含负数时，普通双指针不再正确，单调队列仍然适用。

## 3. 常见错误

1. 队列存值而不存下标，无法判断元素何时离开窗口。
2. 先读取队首、后删除过期元素，窗口边界会多包含一个旧元素。
3. 最大值队列的比较方向写反；应保持值递减，最小值则保持值递增。
4. `tail` 不回收或环形下标处理错误，长数组会越界；固定窗口可用容量 `k`，一般场景使用真正的环形队列。
5. 把单调队列当作优先队列使用。单调队列只适用于窗口边界按顺序移动的场景。

## 4. 前缀和与最短子数组

给定可能包含负数的数组，求和至少为 `target` 的最短连续子数组。令 `prefix[i]` 表示前 `i` 个元素的和。对当前下标 `i`：

- 如果 `prefix[i] - prefix[队首] >= target`，队首对应的区间已经满足条件，应持续弹出并更新最短长度；
- 如果新前缀和不小于队尾前缀和，队尾永远不会成为最优起点，应弹出；
- 剩余下标保持前缀和递增。

```csharp
public static int ShortestSubarrayAtLeast(
    ReadOnlySpan<int> values, long target)
{
    if (values.Length == 0) return 0;
    long[] prefix = new long[values.Length + 1];
    for (int i = 0; i < values.Length; i++)
        prefix[i + 1] = checked(prefix[i] + values[i]);

    int[] deque = new int[prefix.Length];
    int head = 0, tail = 0;
    int answer = int.MaxValue;
    for (int i = 0; i < prefix.Length; i++)
    {
        while (head < tail && prefix[i] - prefix[deque[head]] >= target)
        {
            answer = Math.Min(answer, i - deque[head++]);
        }
        while (head < tail && prefix[i] <= prefix[deque[tail - 1]])
            tail--;
        deque[tail++] = i;
    }
    return answer == int.MaxValue ? 0 : answer;
}

Console.WriteLine(ShortestSubarrayAtLeast([2, -1, 2], 3)); // 3
Console.WriteLine(ShortestSubarrayAtLeast([1, 2, 3], 4));  // 2
Console.WriteLine(ShortestSubarrayAtLeast([-1, -2], 1));   // 0
```

前缀和使用 `long`，避免 `int` 累加溢出。返回 `0` 表示不存在满足条件的区间；如果业务需要区分“空输入”和“无解”，应改为返回 `int?`。总时间和额外空间均为 `O(n)`。

## 5. 与优先队列的选择

优先队列允许任意顺序插入和删除全局最小（或最大）元素，通常为 `O(log n)`；单调队列依赖窗口左端只向右移动，并主动丢弃不可能成为答案的元素，单次操作摊销 `O(1)`。任务调度、全局最小堆和 Dijkstra 应使用优先队列；固定窗口、前缀和区间优化才适合单调队列。选择错误会导致结果错误，或在本可线性的算法中引入不必要的对数开销。
