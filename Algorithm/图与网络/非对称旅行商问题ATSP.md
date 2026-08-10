# 非对称旅行商问题（Asymmetric Traveling Salesman Problem, ATSP）

非对称旅行商问题（Asymmetric Traveling Salesman Problem，ATSP）研究这样一类有向巡回：访问每个顶点恰好一次并回到起点，使总弧成本最小。道路单行限制、上下坡或风向、方向相关的通行费、设备切换成本等，都可能产生 $c_{ij}\neq c_{ji}$ 的成本矩阵。

ATSP 是旅行商问题的基本变体之一，但“非对称”不等于“非度量”。必须分别判断成本是否满足有向三角不等式，因为这决定了近似算法是否存在理论保证。

## 目录

1. [数学定义与有向图模型](#1-数学定义与有向图模型)
2. [与对称 TSP（STSP）的区别](#2-与对称-tspstsp-的区别)
3. [计算复杂性与可近似性边界](#3-计算复杂性与可近似性边界)
4. [整数规划模型](#4-整数规划模型)
5. [精确算法](#5-精确算法)
6. [Python：可重建回路的 Held–Karp 精确算法](#6-python可重建回路的-heldkarp-精确算法)
7. [度量 ATSP 的近似理论](#7-度量-atsp-的近似理论)
8. [启发式算法与工程求解](#8-启发式算法与工程求解)
9. [ATSP 到 STSP 的转换](#9-atsp-到-stsp-的转换)
10. [数据建模与结果验证](#10-数据建模与结果验证)
11. [与 TSP 文档的关系](#11-与-tsp-文档的关系)
12. [参考资料](#12-参考资料)

## 1. 数学定义与有向图模型

设有向图为

$$
G=(V,A),\qquad V=\{0,1,\ldots,n-1\},
$$

其中弧 $(i,j)\in A$ 的成本为 $c_{ij}$。ATSP 的可行解是一个有向 Hamilton（哈密顿）回路

$$
\pi_0\to \pi_1\to\cdots\to\pi_{n-1}\to\pi_0,
$$

其中 $(\pi_0,\ldots,\pi_{n-1})$ 是 $V$ 的一个排列。目标函数为

$$
\min_{\pi}
\left(
\sum_{k=0}^{n-2} c_{\pi_k,\pi_{k+1}}
+c_{\pi_{n-1},\pi_0}
\right).
$$

回路的循环移位表示同一条巡回；与对称 TSP 不同，反向遍历通常既不等价，也不具有相同成本。

### 1.1 完全图、稀疏图与不可达弧

- 理论分析通常把实例写成完全有向图，即每一对不同顶点都有两条方向相反的候选弧。
- 实际网络可能是稀疏有向图。整数规划中最好只为真实存在的弧建立变量。
- 若算法只能接收完整成本矩阵，可以把不存在的弧设为 $+\infty$；若求解器只接受有限整数，则可用经过严格上界推导的惩罚常数 $M$。随意使用“大数”可能造成整数溢出、数值不稳定，或使启发式算法返回含伪弧的解。
- 强连通是存在有向 Hamilton 回路的必要条件，但不是充分条件。

### 1.2 度量 ATSP

若成本满足

$$
c_{ij}\ge 0,\qquad c_{ii}=0,
$$

以及对任意 $i,j,k\in V$ 都有有向三角不等式

$$
c_{ij}\le c_{ik}+c_{kj},
$$

则称其为度量 ATSP（metric ATSP），相应的成本函数也称有向度量或拟度量。该定义不要求 $c_{ij}=c_{ji}$。

对非负弧权的强连通有向网络，可以用全源最短路得到终端之间的最短路闭包，从而形成满足三角不等式的完整成本矩阵。但是，这一操作把问题语义变成“允许经过中间网络节点的最短闭合游走”。如果业务要求原稀疏图中的每个顶点在物理上恰好出现一次，最短路闭包不一定与原 Hamilton 回路问题等价。

## 2. 与对称 TSP（STSP）的区别

| 比较项 | STSP | ATSP |
| --- | --- | --- |
| 成本 | $c_{ij}=c_{ji}$ | 可以有 $c_{ij}\neq c_{ji}$ |
| 图模型 | 无向边 | 有向弧 |
| 顶点度约束 | 每个顶点度为 2 | 每个顶点入度、出度各为 1 |
| 反向回路 | 与原回路同成本 | 通常成本不同，甚至不可行 |
| 固定起点后的候选回路数 | 至多 $(n-1)!/2$ | 至多 $(n-1)!$ |
| 常见应用 | 欧氏距离、双向等价运输 | 单行路、方向相关时间或成本、切换顺序 |
| 度量近似 | Christofides 算法给出 $3/2$ 保证 | Christofides 不能直接使用；已知保证和算法完全不同 |

STSP 是 ATSP 的特例，因此能处理 ATSP 的精确模型原则上也能处理对称实例，但这通常不能利用对称性带来的变量、搜索空间和割结构优势。反过来，把 $c_{ij}$ 与 $c_{ji}$ 取平均值、最小值或最大值并不是精确转换，会改变目标函数和最优回路。

## 3. 计算复杂性与可近似性边界

ATSP 的判定版本询问：是否存在总成本不超过给定阈值 $B$ 的有向 Hamilton 回路。该问题属于 NP，并且是 **NP-complete** 的 [1]。

即使成本只取 $1$ 和 $2$，度量 ATSP 仍然是 **NP-hard** 的。给定一个有向 Hamilton 回路实例 $H=(V,E)$，令

$$
c_{ij}=
\begin{cases}
1, & (i,j)\in E,\\
2, & (i,j)\notin E.
\end{cases}
$$

所有非对角成本至少为 $1$，所以 $c_{ij}\le 2\le c_{ik}+c_{kj}$，三角不等式成立。原图存在 Hamilton 回路，当且仅当新实例存在成本为 $n$ 的巡回。由于归约只使用常数 $1$ 和 $2$，困难性不依赖大数值编码；按标准数值优化定义，最优化版本因此也是强 NP-hard 的。

由于上述归约只使用常数大小的整数成本，度量 ATSP 的优化版本也是强 NP 困难的。

近似性质必须区分两类输入：

- **一般非度量 ATSP**：除非 $P=NP$，不存在适用于所有实例的固定常数因子多项式时间近似算法。直观上，可把原图弧设为 $1$，非原图弧设为任意大的 $M$，从而用近似算法区分是否存在 Hamilton 回路。
- **度量 ATSP**：存在多项式时间常数因子近似算法，但其理论和 STSP 的 MST、匹配与 Christofides 路线不同，参见第 7 节。

## 4. 整数规划模型

以下模型适用于单旅行商、静态弧成本和单个 Hamilton 回路。时间窗、容量、多车辆、先后关系或随出发时刻变化的成本需要额外变量和约束，不能仅靠修改 $c_{ij}$ 完整表达。

定义二元变量

$$
x_{ij}=
\begin{cases}
1, & \text{回路使用弧 }(i,j),\\
0, & \text{否则},
\end{cases}
\qquad (i,j)\in A.
$$

共同的目标函数与度约束为

$$
\min \sum_{(i,j)\in A} c_{ij}x_{ij},
$$

$$
\sum_{j:(i,j)\in A}x_{ij}=1,\qquad \forall i\in V,
$$

$$
\sum_{i:(i,j)\in A}x_{ij}=1,\qquad \forall j\in V.
$$

仅有度约束时，解可能由多个互不相交的有向环组成，而不是一条覆盖全部顶点的回路。

### 4.1 指派松弛

暂时删除子回路消除约束，只保留入度、出度约束和 $x_{ij}\ge 0$，得到线性指派问题。其约束矩阵具有全幺模性质，因此在标准条件下线性规划极点已经是整数的；最优解是一组覆盖全部顶点的最小成本有向环，即最小成本环覆盖（cycle cover）。

记指派问题最优值为 $z_{\mathrm{AP}}$，ATSP 最优值为 $z^\star$，则

$$
z_{\mathrm{AP}}\le z^\star.
$$

Hungarian 方法由 Kuhn 系统化提出 [13]；常用的 $O(n^3)$ 改进可追溯到 Tomizawa 等后续工作 [15]。因此，指派松弛常用于：

- 分支定界中的下界；
- 初始环覆盖，再通过合并子环构造可行巡回；
- 检测成本矩阵和弧集是否存在明显的入度、出度不可行性。

指派下界可能较弱，因为它完全没有要求不同环之间连通。

### 4.2 DFJ 子回路消除模型

对任意 $S\subset V$，定义离开 $S$ 的有向割

$$
\delta^+(S)=\{(i,j)\in A:i\in S,\ j\notin S\}.
$$

在共同的目标函数和度约束之外，加入

$$
\sum_{(i,j)\in\delta^+(S)}x_{ij}\ge 1,
\qquad
\forall S\subset V,\quad 2\le |S|\le n-1,
$$

$$
x_{ij}\in\{0,1\},\qquad \forall(i,j)\in A.
$$

该割约束要求每个真子集至少有一条弧离开它。在入度、出度平衡成立时，也可等价地写成内部弧形式

$$
\sum_{\substack{(i,j)\in A\\i\in S,\ j\in S}}x_{ij}\le |S|-1.
$$

这就是 DFJ（Dantzig–Fulkerson–Johnson）型有向子回路消除模型 [2]。约束族具有指数规模，但通常不预先枚举，而是在分支切割过程中按需分离：

1. 对整数候选解，沿后继关系找出所有小于 $n$ 的有向环并添加割；
2. 对分数解，可通过有向最小割寻找容量小于 $1$ 的违反割。

把二元条件放松为 $x_{ij}\ge 0$ 后得到 ATSP 的标准 DFJ/Held–Karp 线性规划松弛。若其最优值记为 $z_{\mathrm{HK}}$，则

$$
z_{\mathrm{AP}}\le z_{\mathrm{HK}}\le z^\star.
$$

它加入了全局连通割，因而不弱于单纯的指派松弛。这里的“Held–Karp 松弛”不要与第 6 节的“Held–Karp 子集动态规划”混淆。

### 4.3 MTZ 紧凑模型

选择根顶点 $r$。对每个 $i\in V\setminus\{r\}$ 引入顺序变量 $u_i$，并加入 [3]

$$
1\le u_i\le n-1,\qquad \forall i\in V\setminus\{r\},
$$

$$
u_i-u_j+n x_{ij}\le n-1,
\qquad
\forall(i,j)\in A,\quad i,j\in V\setminus\{r\}.
$$

当 $x_{ij}=1$ 时，上式强制

$$
u_j\ge u_i+1.
$$

因此，不包含根 $r$ 的顶点集合无法形成有向子环；结合入度和出度约束，只能得到一条包含所有顶点的回路。只要 $x$ 保持二元，$u$ 可以声明为连续变量，模型仍然正确。

MTZ 只有 $O(n^2)$ 个约束，便于教学、原型和中小规模模型扩展；但其线性松弛通常明显弱于 DFJ 松弛，较大实例上可能产生更大的分支定界树。

### 4.4 单商品流（SCF）模型

固定根顶点 $r$，令连续变量 $f_{ij}$ 表示沿弧 $(i,j)$ 运输的同一种商品数量。根发出 $n-1$ 单位流，每个非根节点消费 1 单位：

$$
\sum_{j:(r,j)\in A}f_{rj}
-\sum_{i:(i,r)\in A}f_{ir}=n-1,
$$

$$
\sum_{i:(i,v)\in A}f_{iv}
-\sum_{j:(v,j)\in A}f_{vj}=1,
\qquad \forall v\in V\setminus\{r\},
$$

$$
0\le f_{ij}\le (n-1)x_{ij},
\qquad \forall(i,j)\in A.
$$

流只能经过被 $x$ 选中的弧。若某个非根子环与根分离，该子环无法获得其节点总计需要的净流量，因而被排除。Gavish–Graves 是这种单商品流建模的经典来源 [16]。

SCF 只增加 $O(n^2)$ 个连续变量和约束，便于加入容量、先后关系等扩展；但放松 $x\in[0,1]$ 后，一条分数弧可承载最多 $(n-1)x_{ij}$ 单位流，所以其 LP 松弛通常弱于 DFJ/Held–Karp 割松弛。

### 4.5 多商品流（MCF）模型

对每个目的节点 $k\in V\setminus\{r\}$ 建立一种商品。令连续变量 $y_{ij}^{k}$ 表示商品 $k$ 在弧 $(i,j)$ 上的流量，并要求该商品从根 $r$ 向 $k$ 发送 1 单位：

$$
\sum_{j:(v,j)\in A}y_{vj}^{k}
-\sum_{i:(i,v)\in A}y_{iv}^{k}
=
\begin{cases}
1,&v=r,\\
-1,&v=k,\\
0,&v\notin\{r,k\},
\end{cases}
\qquad \forall v\in V,\quad k\in V\setminus\{r\},
$$

$$
0\le y_{ij}^{k}\le x_{ij},
\qquad \forall(i,j)\in A,\quad k\in V\setminus\{r\}.
$$

MCF 包含 $O(n^3)$ 个连续变量和流平衡约束。对标准有向 TSP 模型，其 LP 松弛投影到 $x$ 空间后与有向 DFJ/Held–Karp 割松弛相同 [17]。这一结论针对上面这种每个商品分别受 $y_{ij}^{k}\le x_{ij}$ 约束的标准分解式；共享总容量等其他 MCF 变体未必具有相同投影。MCF 以更高的内存和建模成本换取强于 SCF 的松弛；这并不意味着把 ATSP 化成了多项式时间网络流问题，因为 $x$ 的二元选弧决策仍然存在。

### 4.6 模型选择

| 模型或松弛 | 规模 | 主要用途 | 局限 |
| --- | ---: | --- | --- |
| 指派松弛 | $O(n^2)$ | 快速下界、环覆盖、预处理 | 允许多个子环 |
| MTZ | $O(n^2)$ | 小规模完整 MILP、易于加入业务约束 | LP 松弛较弱 |
| SCF | $O(n^2)$ 连续变量与约束 | 紧凑连通模型、业务约束扩展 | LP 松弛弱于 DFJ/MCF |
| MCF | $O(n^3)$ 连续变量与约束 | 无需动态割且希望获得强松弛 | 内存和模型构造代价高 |
| DFJ + 动态割 | 指数约束，按需生成 | 高质量精确求解、可证明最优性 | 需要割分离和成熟 MILP 框架 |
| Held–Karp 子集 DP | $O(n^2 2^n)$ 时间 | 小规模稠密实例的确定性精确算法 | 指数时间和内存 |

## 5. 精确算法

### 5.1 穷举与子集动态规划

固定起点后直接枚举所有顺序需要检查 $(n-1)!$ 个回路。Held–Karp 动态规划 [4] 通过复用子路径，把时间复杂度降为

$$
O(n^2 2^n),
$$

空间复杂度为

$$
O(n2^n).
$$

固定起点 $r$，对 $S\subseteq V\setminus\{r\}$ 和 $j\in S$，定义

$$
D[S,j]=
\text{从 }r\text{ 出发，恰好访问 }S\text{，并在 }j\text{ 结束的最小成本}.
$$

边界条件为

$$
D[\{j\},j]=c_{rj},
$$

递推式为

$$
D[S,j]=
\min_{i\in S\setminus\{j\}}
\left(D[S\setminus\{j\},i]+c_{ij}\right),
$$

最终答案为

$$
\min_{j\ne r}\left(D[V\setminus\{r\},j]+c_{jr}\right).
$$

递推式保留了弧方向，因此无需对 ATSP 做任何对称化。

### 5.2 分支定界、割平面与分支切割

工程中的精确 ATSP 求解通常结合以下技术：

- 以指派松弛、DFJ 线性松弛或拉格朗日松弛提供下界；
- 用构造式启发式和局部搜索尽早得到较好的上界；
- 对整数子环添加子回路割，对分数解分离有向割；
- 通过分支定界排除不能改进当前上界的搜索节点；
- 在问题特定场景中加入有效不等式、变量固定和弧删除。

求解器报告“最优”时，应同时有可行巡回上界与全局下界相等（允许数值容差）；仅得到一条低成本巡回并不构成最优性证明。

## 6. Python：可重建回路的 Held–Karp 精确算法

下面的实现面向 Python 3.9 及以上版本，不依赖第三方库。位掩码只表示除起点 $0$ 外的顶点；父指针用于重建最优有向回路。闭合回路可循环移位，因此固定表示起点为 $0$ 不会排除任何巡回。可以用 `math.inf` 表示不存在的弧。

```python
from math import inf
from typing import Sequence


def held_karp_atsp(
    cost: Sequence[Sequence[float]],
) -> tuple[float, list[int]]:
    """精确求解小规模 ATSP，返回（最优成本, 闭合回路）。"""
    n = len(cost)
    if n == 0:
        raise ValueError("成本矩阵不能为空")
    if any(len(row) != n for row in cost):
        raise ValueError("成本矩阵必须是方阵")
    if any(value != value for row in cost for value in row):
        raise ValueError("成本矩阵不能包含 NaN")
    if any(value == -inf for row in cost for value in row):
        raise ValueError("成本矩阵不能包含负无穷")
    if n == 1:
        return 0.0, [0, 0]

    start = 0
    # dp[(mask, j)]：0 -> ... -> j，恰好访问 mask 中顶点的最小成本。
    dp: dict[tuple[int, int], float] = {}
    parent: dict[tuple[int, int], int] = {}

    for j in range(1, n):
        bit = 1 << (j - 1)
        dp[(bit, j)] = cost[start][j]
        parent[(bit, j)] = start

    full_mask = (1 << (n - 1)) - 1

    for mask in range(1, full_mask + 1):
        if mask & (mask - 1) == 0:
            continue  # 单元素集合已由边界条件初始化。

        for j in range(1, n):
            bit_j = 1 << (j - 1)
            if not (mask & bit_j):
                continue

            previous_mask = mask ^ bit_j
            best = inf
            best_previous = -1

            for i in range(1, n):
                bit_i = 1 << (i - 1)
                if not (previous_mask & bit_i):
                    continue

                candidate = (
                    dp.get((previous_mask, i), inf) + cost[i][j]
                )
                if candidate < best:
                    best = candidate
                    best_previous = i

            if best_previous != -1:
                dp[(mask, j)] = best
                parent[(mask, j)] = best_previous

    best_total = inf
    last = -1
    for j in range(1, n):
        candidate = dp.get((full_mask, j), inf) + cost[j][start]
        if candidate < best_total:
            best_total = candidate
            last = j

    if last == -1 or best_total == inf:
        raise ValueError("不存在从给定弧集构成的 Hamilton 回路")

    # 从最后一个顶点沿父指针逆向恢复 0 -> ... -> last。
    reversed_path: list[int] = []
    mask = full_mask
    current = last
    while current != start:
        reversed_path.append(current)
        previous = parent[(mask, current)]
        mask ^= 1 << (current - 1)
        current = previous

    tour = [start, *reversed(reversed_path), start]
    return best_total, tour


if __name__ == "__main__":
    costs = [
        [0, 3, 8, 2],
        [5, 0, 2, 7],
        [6, 4, 0, 3],
        [3, 7, 5, 0],
    ]

    optimum, route = held_karp_atsp(costs)
    print(f"最优成本: {optimum:g}")
    print("最优回路:", " -> ".join(map(str, route)))
```

预期输出为

```text
最优成本: 11
最优回路: 0 -> 1 -> 2 -> 3 -> 0
```

该回路的成本为

$$
c_{01}+c_{12}+c_{23}+c_{30}
=3+2+3+3=11.
$$

反向回路 $0\to3\to2\to1\to0$ 的成本为

$$
2+5+4+5=16,
$$

这直观展示了 ATSP 的方向性。

## 7. 度量 ATSP 的近似理论

本节所有乘法近似保证都要求：完整有向图、非负成本和有向三角不等式。一般非度量 ATSP、稀疏图上的严格 Hamilton 回路、时间依赖 ATSP、最大化 ATSP 等问题不能直接套用这些结论。

理论发展的关键结果包括：

1. Asadpour 等给出了
   $$
   O\!\left(\frac{\log n}{\log\log n}\right)
   $$
   近似算法 [5]。
2. Svensson、Tarnawski 与 Végh 首次证明一般度量 ATSP 存在多项式时间常数因子近似算法 [6]。其具体分析给出了常数 $506$。
3. Traub 与 Vygen 将保证改进为：对任意固定的 $\varepsilon>0$，存在多项式时间
   $$
   (22+\varepsilon)
   $$
   近似算法，并把标准 Held–Karp 松弛的整数间隙上界改进到 $22$ [7]。

若把度量 ATSP 的 Held–Karp 整数间隙定义为

$$
\gamma=\sup_{I:\,z_{\mathrm{HK}}(I)>0}
\frac{z^\star(I)}{z_{\mathrm{HK}}(I)},
$$

则 Charikar、Goemans 与 Karloff 构造了达到下界 $\gamma\ge 2$ 的实例族 [18]，而 Traub–Vygen 的结果给出 $\gamma\le 22$ [7]。因此目前这些经典结果共同给出 $2\le\gamma\le22$；它描述的是所有度量实例上的最坏情况 LP 比值，不是某个实际实例必然出现的最优性间隙。

这些结果的意义在于“常数因子存在”以及标准 LP 松弛具有常数整数间隙。它们不是在声明实践中的解通常会比最优解差 22 倍，也不意味着相应理论算法一定比 LKH、局部搜索或 MILP 更适合实际数据。

还需注意：

- Christofides 的 $3/2$ 保证依赖无向度量和奇度顶点匹配，不能移植到 ATSP。
- 将 ATSP 转换为某个对称实例后，转换图通常不再是普通的度量 STSP；因此也不能借此自动获得 Christofides 保证。
- 若先做最短路闭包，必须确认“允许经过中间节点”的问题语义正确，且能把闭包中的弧可靠地展开回原网络。

## 8. 启发式算法与工程求解

### 8.1 构造与改进

常见策略包括：

- **有向最近邻、插入法**：实现简单，可快速提供上界，但最坏情况可能很差；
- **指派环覆盖加合并**：先求低成本环覆盖（cycle cover），再选择有向弧交换以合并子环；
- **局部搜索**：顶点重定位、交换、有向 2-opt、3-opt、Lin–Kernighan 型变邻域；
- **元启发式**：迭代局部搜索、禁忌搜索、模拟退火、遗传算法和蚁群算法；
- **混合方法**：用启发式生成当前最好可行解（incumbent），再由 MILP 或分支切割证明最优性或给出最优性间隙（gap）。

任何启发式都应报告独立计算的回路成本；若需要质量证据，还应同时报告指派或 LP 下界以及相对最优性间隙。

### 8.2 不能直接复用 STSP 的 2-opt 增量公式

设当前回路包含

$$
a\to b=w_0\to w_1\to\cdots\to w_m=c\to d.
$$

普通 2-opt 删除 $a\to b$ 和 $c\to d$，连接 $a\to c$ 与 $b\to d$，同时把 $b,\ldots,c$ 整段反向。ATSP 中真实的成本变化为

$$
\begin{aligned}
\Delta={}&c_{ac}+c_{bd}-c_{ab}-c_{cd}\\
&+\sum_{t=0}^{m-1}
\left(c_{w_{t+1},w_t}-c_{w_t,w_{t+1}}\right).
\end{aligned}
$$

STSP 因为 $c_{ij}=c_{ji}$，第二行完全抵消，所以只需四条边即可计算增量；ATSP 中每条内部弧都改变方向，反向弧还可能不存在。忽略内部项会错误评价移动。工程实现可以预计算方向反转的前缀代价以加速评估，或优先使用保持弧方向结构更容易维护的重定位、交换和专门的有向 $k$-opt 操作。

### 8.3 常见工具的适用性

- **LKH/LKH-3**：Lin–Kernighan 型高质量启发式实现，支持 TSPLIB 的 ATSP 类型；其实现会扩展非对称实例并固定成对边 [10]。它通常用于获得高质量可行解，不提供一般性的全局最优证明。
- **Google OR-Tools Routing**：弧成本回调由“起点索引、终点索引”共同决定，因而可以表达非对称整数成本；适合带附加路由约束的启发式搜索 [11]。达到时间限制时返回的最好解不应自动解释为已证明最优。
- **NetworkX**：`asadpour_atsp` 提供 Asadpour 近似算法的参考实现，要求输入是完整有向图；它适合算法研究与小规模实验，不是稀疏、有时间窗或多车辆问题的通用求解接口 [14]。
- **Concorde**：官方定位是对称 TSP 求解器 [12]，不是原生 ATSP 求解器。要用于 ATSP，必须先做正确且经过验证的精确转换，并承担顶点数增加等代价。
- **通用 MILP 求解器**：适合实现 MTZ，或通过惰性约束（lazy constraints）/回调（callback）实现 DFJ 分支切割；是否获得证明取决于最终最优性间隙，而不取决于求解器是否返回了可行解。

## 9. ATSP 到 STSP 的转换

Jonker–Volgenant 转换是经典的 ATSP 到对称问题转换 [8]。其核心是顶点分裂：

1. 把每个原顶点 $i$ 拆成 $i^{\mathrm{in}}$ 和 $i^{\mathrm{out}}$；
2. 强制选择零成本配对边
   $$
   \{i^{\mathrm{in}},i^{\mathrm{out}}\};
   $$
3. 把原有向弧 $i\to j$ 表示为无向转移边
   $$
   \{i^{\mathrm{out}},j^{\mathrm{in}}\},
   $$
   其成本为 $c_{ij}$；
4. 禁止其余不合法连接，或在普通完整 STSP 表达中以经过严格推导的惩罚结构排除它们。

当所有配对边都被强制选中时，对称回路在“配对边—转移边”之间交替，可以一一解码为原 ATSP 回路。若配对边成本为零，合法转换解与原解同成本；某些完整矩阵构造会引入一个已知的常数偏移，解码时应扣除。

“零成本”本身并不保证配对边一定被选中。若目标求解器支持固定边，应显式固定；若不支持，则必须使用 Jonker–Volgenant 论文及其勘误给出的完整代价构造，不能只把配对边设为零后交给普通 STSP 求解器。

这种转换不是免费的：

- 顶点数从 $n$ 增加到 $2n$；
- 稠密存储仍为 $\Theta(n^2)$，但矩阵维度和常数显著增加；
- 对指数型精确搜索而言，顶点翻倍可能造成远超四倍的实际开销；
- 转换实例包含固定边、禁止边或大惩罚边，通常破坏原问题可能具有的度量和几何结构；
- 不正确的 $M$ 值会造成伪最优解、溢出或严重数值问题；
- 任何求解结果都必须解码后在原有向成本矩阵上重新验证。

因此，原生支持有向变量和有向割的 MILP/CP 方法通常不需要转换。只有在必须复用对称求解器或某个实现明确依赖该转换时，才应采用经过文献或工具实现验证的 Jonker–Volgenant 类构造。

## 10. 数据建模与结果验证

### 10.1 输入检查

1. 明确 $c_{ij}$ 的单位，是距离、时间、费用还是加权综合成本。
2. 对角线通常设为 $0$ 并禁止自环变量 $x_{ii}$。
3. 检查每个顶点至少有一条可用入弧和出弧，并检查强连通分量。
4. 不要因矩阵“近似对称”就直接对称化；应量化差异并依据业务语义决定。
5. 若声称使用度量近似算法，应实际检查非负性和有向三角不等式。
6. 若真实成本依赖出发时刻、前一条道路或车辆状态，应使用时间依赖模型或状态扩展，而不是静态 ATSP。

TSPLIB 的 ATSP 实例通常采用完整显式矩阵 [9]，核心字段形如：

```text
TYPE: ATSP
EDGE_WEIGHT_TYPE: EXPLICIT
EDGE_WEIGHT_FORMAT: FULL_MATRIX
```

不同工具对实数、无穷大、索引起点和矩阵行列方向的约定可能不同。`FULL_MATRIX` 的第 $i$ 行第 $j$ 列表示 $i\to j$ 的成本；转置或对称化后得到的已不是原 ATSP 实例。将实数缩放为整数时，应记录缩放系数和舍入规则。

### 10.2 解的独立验证

给定返回序列 $(v_0,\ldots,v_n)$，至少检查：

- $v_0=v_n$；
- $v_0,\ldots,v_{n-1}$ 恰好包含所有顶点一次；
- 每个 $(v_k,v_{k+1})$ 都是允许的有向弧；
- 用原始 $c_{v_kv_{k+1}}$ 独立重算总成本；
- 若声称最优，保存求解器下界、上界、最优性间隙、版本、参数、随机种子和日志。

### 10.3 方法选择建议

- 顶点很少且需要简单、可复核的精确结果：使用 Held–Karp 动态规划。
- 规模中等、需要最优性证明或有复杂业务约束：使用 MILP；小原型可从 MTZ 或 SCF 开始，若不便动态加割但需要更强松弛可评估 MCF，性能版本通常优先 DFJ 分支切割。
- 规模较大、时限严格：使用 LKH、OR-Tools 或定制局部搜索，并用指派/LP 下界报告解的相对最优性间隙。
- 必须使用仅支持 STSP 的软件：采用经过验证的 Jonker–Volgenant 转换，同时评估顶点翻倍、固定边和大数值的代价。

## 11. 与 TSP 文档的关系

[旅行商问题（TSP）](./旅行商问题TSP.md)介绍旅行商问题的共同背景。本文独立给出 ATSP 所需的有向图定义、入度/出度模型、近似理论和工程注意事项。

阅读或实现时应遵循以下边界：

- 对称成本是 ATSP 的特殊输入，但 STSP 的反向等价、2-opt 常数时间增量和 Christofides 保证不能推广到一般 ATSP；
- DFJ、MTZ、SCF、MCF 和 Held–Karp 动态规划都可以写成有向版本，但变量、流、割和递推中的弧方向不能省略；
- ATSP 转 STSP 是显式的建模转换，不等同于把原成本矩阵数值对称化。

## 12. 参考资料

[1] R. M. Karp. “Reducibility among Combinatorial Problems.” In *Complexity of Computer Computations*, 1972, pp. 85–103. [DOI: 10.1007/978-1-4684-2001-2_9](https://doi.org/10.1007/978-1-4684-2001-2_9).

[2] G. Dantzig, R. Fulkerson, and S. Johnson. “Solution of a Large-Scale Traveling-Salesman Problem.” *Operations Research*, 2(4), 1954, pp. 393–410. [DOI: 10.1287/opre.2.4.393](https://doi.org/10.1287/opre.2.4.393).

[3] C. E. Miller, A. W. Tucker, and R. A. Zemlin. “Integer Programming Formulation of Traveling Salesman Problems.” *Journal of the ACM*, 7(4), 1960, pp. 326–329. [DOI: 10.1145/321043.321046](https://doi.org/10.1145/321043.321046).

[4] M. Held and R. M. Karp. “A Dynamic Programming Approach to Sequencing Problems.” *Journal of the Society for Industrial and Applied Mathematics*, 10(1), 1962, pp. 196–210. [DOI: 10.1137/0110015](https://doi.org/10.1137/0110015).

[5] A. Asadpour, M. X. Goemans, A. Mądry, S. Oveis Gharan, and A. Saberi. “An $O(\log n/\log\log n)$-Approximation Algorithm for the Asymmetric Traveling Salesman Problem.” *Operations Research*, 65(4), 2017, pp. 1043–1061. [DOI: 10.1287/opre.2017.1603](https://doi.org/10.1287/opre.2017.1603).

[6] O. Svensson, J. Tarnawski, and L. A. Végh. “A Constant-factor Approximation Algorithm for the Asymmetric Traveling Salesman Problem.” *Journal of the ACM*, 67(6), 2020, Article 37, pp. 1–53. [DOI: 10.1145/3424306](https://doi.org/10.1145/3424306).

[7] V. Traub and J. Vygen. “An Improved Approximation Algorithm for the Asymmetric Traveling Salesman Problem.” *SIAM Journal on Computing*, 51(1), 2022, pp. 139–173. [DOI: 10.1137/20M1339313](https://doi.org/10.1137/20M1339313). 作者公开稿：[arXiv:1912.00670](https://arxiv.org/abs/1912.00670).

[8] R. Jonker and T. Volgenant. “Transforming Asymmetric into Symmetric Traveling Salesman Problems.” *Operations Research Letters*, 2(4), 1983, pp. 161–163. [DOI: 10.1016/0167-6377(83)90048-2](https://doi.org/10.1016/0167-6377(83)90048-2). 另见 1986 年勘误：[DOI: 10.1016/0167-6377(86)90081-7](https://doi.org/10.1016/0167-6377(86)90081-7).

[9] G. Reinelt. “TSPLIB—A Traveling Salesman Problem Library.” *ORSA Journal on Computing*, 3(4), 1991, pp. 376–384. [DOI: 10.1287/ijoc.3.4.376](https://doi.org/10.1287/ijoc.3.4.376)；[TSPLIB 官方站点](https://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/).

[10] K. Helsgaun. “An Effective Implementation of the Lin–Kernighan Traveling Salesman Heuristic.” *European Journal of Operational Research*, 126(1), 2000, pp. 106–130. [DOI: 10.1016/S0377-2217(99)00284-2](https://doi.org/10.1016/S0377-2217(99)00284-2). LKH-3 官方页面：[LKH-3](http://webhotel4.ruc.dk/~keld/research/LKH-3/).

[11] Google. “Traveling Salesperson Problem.” *OR-Tools Documentation*. [官方文档](https://developers.google.com/optimization/routing/tsp).

[12] University of Waterloo. “Concorde TSP Solver.” [Concorde 官方页面](https://www.math.uwaterloo.ca/tsp/concorde.html).

[13] H. W. Kuhn. “The Hungarian Method for the Assignment Problem.” *Naval Research Logistics Quarterly*, 2(1–2), 1955, pp. 83–97. [DOI: 10.1002/nav.3800020109](https://doi.org/10.1002/nav.3800020109).

[14] NetworkX Developers. [`asadpour_atsp` 官方 API 文档](https://networkx.org/documentation/stable/reference/algorithms/generated/networkx.algorithms.approximation.traveling_salesman.asadpour_atsp.html).

[15] N. Tomizawa. “On Some Techniques Useful for Solution of Transportation Network Problems.” *Networks*, 1(2), 1971, pp. 173–194. [DOI: 10.1002/net.3230010206](https://doi.org/10.1002/net.3230010206).

[16] B. Gavish and S. C. Graves. “The Travelling Salesman Problem and Related Problems.” MIT Operations Research Center Working Paper OR 078-78, 1978. [MIT Open Scholarship](https://hdl.handle.net/1721.1/5363).

[17] A. Claus. “A New Formulation for the Travelling Salesman Problem.” *SIAM Journal on Algebraic Discrete Methods*, 5(1), 1984, pp. 21–25. [DOI: 10.1137/0605004](https://doi.org/10.1137/0605004).

[18] M. Charikar, M. X. Goemans, and H. Karloff. “On the Integrality Ratio for the Asymmetric Traveling Salesman Problem.” *Mathematics of Operations Research*, 31(2), 2006, pp. 245–252. [DOI: 10.1287/moor.1060.0191](https://doi.org/10.1287/moor.1060.0191).

### 延伸阅读（非一手资料）

以下链接来自原文档，可用于了解具体应用或启发式实现；复杂度、近似比和模型等结论应以上述论文及官方资料为准。

- [Deep Paper：用连续数学消除子回路——解决非对称旅行商问题的新方法](https://deep-paper.org/paper/25090_solving_the_asymmetric_t-5690/)
- [CSDN：模拟退火算法求解 ATSP 的 Python 示例](https://blog.csdn.net/qq_38334677/article/details/132593196)
