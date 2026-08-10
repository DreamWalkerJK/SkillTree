# 旅行商问题（Traveling Salesman Problem, TSP）

## 目录

1. [问题定义](#1-问题定义)
2. [整数规划模型](#2-整数规划模型)
3. [计算复杂度与可近似性](#3-计算复杂度与可近似性)
4. [精确算法](#4-精确算法)
5. [具有理论保证的近似算法](#5-具有理论保证的近似算法)
6. [启发式与元启发式](#6-启发式与元启发式)
7. [常见变体](#7-常见变体)
8. [工程求解流程](#8-工程求解流程)
9. [Python 示例：Held–Karp 精确算法](#9-python-示例heldkarp-精确算法)
10. [结果验证与边界条件](#10-结果验证与边界条件)
11. [参考资料](#11-参考资料)

## 1. 问题定义

旅行商问题研究如下组合优化任务：给定若干城市及任意两座城市之间的旅行成本，寻找一条从某座城市出发、恰好访问每座城市一次并回到出发城市的闭合回路，使总成本最小。图论上，该回路是一个最小成本 Hamilton（哈密顿）回路 [1]。

设加权图为

$$
G=(V,E),\qquad |V|=n,
$$

边或弧的成本为 $c_{ij}$。一个从 $v_0$ 开始的巡回可写为排列

$$
\pi=(v_0,v_1,\ldots,v_{n-1},v_0),
$$

其成本为

$$
C(\pi)=\sum_{k=0}^{n-2}c_{v_kv_{k+1}}+c_{v_{n-1}v_0}.
$$

最优化版本要求计算

$$
\operatorname{OPT}=\min_{\pi} C(\pi),
$$

并返回达到该值的巡回。判定版本则额外给定阈值 $B$，询问是否存在成本不超过 $B$ 的巡回。

### 1.1 常见输入模型

- **对称 TSP（STSP）**：$c_{ij}=c_{ji}$，通常用无向完全图表示。
- **非对称 TSP（ATSP）**：允许 $c_{ij}\ne c_{ji}$，用有向图表示。详见[非对称旅行商问题（ATSP）](./非对称旅行商问题ATSP.md)。
- **度量 TSP（metric TSP）**：除对称性外，还满足 $c_{ii}=0$、$c_{ij}\ge 0$ 以及三角不等式

  $$
  c_{ij}\le c_{ik}+c_{kj},\qquad \forall i,j,k\in V.
  $$

- **欧几里得 TSP**：城市是欧氏空间中的点，成本为欧氏距离；它是度量 TSP 的重要特例。
- **稀疏或不完全图**：可以只保留允许使用的边，也可在成本矩阵中把禁用边记为 $+\infty$。后一做法便于统一实现，但可能破坏近似算法所需的完全性和三角不等式。

“城市”只是抽象节点，成本也不必是物理距离；它可以表示时间、费用、能耗或风险。若成本依赖访问时刻、车辆载荷或历史路径，则问题已经超出静态 TSP，必须在模型中显式加入相应状态。

## 2. 整数规划模型

### 2.1 对称 TSP 的 DFJ 模型

令 $G=(V,E)$ 为无向完全图，二元变量

$$
x_{ij}=
\begin{cases}
1,&\{i,j\}\text{ 被巡回选中},\\
0,&\text{否则}.
\end{cases}
$$

Dantzig、Fulkerson 与 Johnson（DFJ）模型为 [3]：

$$
\min \sum_{\{i,j\}\in E}c_{ij}x_{ij},
$$

满足

$$
\sum_{j:\{i,j\}\in E}x_{ij}=2,
\qquad \forall i\in V,
$$

$$
\sum_{e\in\delta(S)}x_e\ge 2,
\qquad \forall\,\varnothing\ne S\subsetneq V,
$$

$$
x_{ij}\in\{0,1\}.
$$

其中 $\delta(S)$ 是一个端点在 $S$、另一个端点在 $V\setminus S$ 的割边集合。度约束保证每个节点的度为 2；子环消除约束（subtour elimination constraints, SEC）保证任意真子集至少有两条边连向外部，从而排除多个互不连通的小环。

SEC 也可等价写成

$$
\sum_{\{i,j\}\subseteq S}x_{ij}\le |S|-1,
\qquad 2\le |S|\le n-1.
$$

该模型具有指数数量的 SEC。工程求解器通常不会预先加入全部约束，而是先求较松的模型，再通过割分离检测当前解中的违规子集并动态加入约束。对整数候选解，可由连通分量直接找到子环；对分数解，对称 SEC 的分离可转化为寻找容量小于 2 的割。

### 2.2 有向 DFJ 模型

令 $x_{ij}=1$ 表示使用弧 $(i,j)$。有向模型的核心约束为

$$
\sum_{j\ne i}x_{ij}=1,
\qquad
\sum_{j\ne i}x_{ji}=1,
\qquad \forall i\in V,
$$

以及

$$
\sum_{i\in S}\sum_{\substack{j\in S\\j\ne i}}x_{ij}\le |S|-1,
\qquad 2\le |S|\le n-1.
$$

仅有入度、出度约束时，模型是指派松弛，解可能由多个有向子环组成；SEC 将其限制为单一 Hamilton 回路。对称实例也可以用此模型，但同一条无向边会对应两个方向变量，通常不如无向模型紧凑。

### 2.3 MTZ 紧凑模型

Miller–Tucker–Zemlin（MTZ）模型使用顺序变量消除子环 [12]。选定节点 0 为起点，对 $i\in V\setminus\{0\}$ 引入

$$
1\le u_i\le n-1,
$$

并在有向度约束之外加入

$$
u_i-u_j+n x_{ij}\le n-1,
\qquad i\ne j,\quad i,j\in V\setminus\{0\}.
$$

若 $x_{ij}=1$，则约束迫使 $u_j\ge u_i+1$，因此不可能在不经过起点的节点集合中形成有向环。MTZ 只有 $O(n^2)$ 个约束，适合教学、小规模模型或不便使用惰性割回调的环境；但其线性规划松弛通常弱于 DFJ，规模增大后往往需要更多分支节点。紧凑不等于计算上一定更快。

### 2.4 单商品流与多商品流模型

将有向候选弧集记为 $A$。流模型在有向度约束的基础上，用连续流变量保证所有节点都与选定根节点 $r$ 连通。它们仍是整数规划模型：网络流部分可以连续，但选择弧的 $x_{ij}$ 仍须为二元变量。

**单商品流（single-commodity flow, SCF）模型。** 令 $f_{ij}$ 表示沿已选弧 $(i,j)$ 输送的同一种商品数量。根节点发出 $n-1$ 单位，每个非根节点消费 1 单位：

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

容量联动使流只能经过已选弧；若 $x$ 形成一个不含根的子环，该子环无法从根获得其节点所需的净流量，因此会被排除。Gavish–Graves 模型是这一思路的经典来源 [15]。SCF 只增加 $O(n^2)$ 个连续变量和约束，较易扩展，但其 LP 松弛通常弱于 DFJ 割松弛。

**多商品流（multi-commodity flow, MCF）模型。** 对每个目的节点 $k\ne r$ 建立一种商品，并令 $y_{ij}^{k}$ 表示该商品在弧 $(i,j)$ 上的流量。每种商品都从 $r$ 发送 1 单位到 $k$：

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

标准 MCF 模型包含 $O(n^3)$ 个连续变量。其 LP 松弛投影到 $x$ 空间后与有向 DFJ/Held–Karp 割松弛相同 [16]，因此比紧凑的 SCF 付出更多内存，换取更强的线性松弛。该等价性针对上面这种“每个商品分别满足 $y_{ij}^{k}\le x_{ij}$”的标准分解式；共享总容量等其他 MCF 变体不应未经证明直接套用。流模型的存在并不使 TSP 变成多项式时间网络流问题；计算困难仍来自二元选弧决策。

## 3. 计算复杂度与可近似性

### 3.1 最优化版与判定版

- TSP **最优化问题是 NP-hard**。
- 当成本为以有限位数编码的整数或有理数时，判定问题“是否存在成本不超过 $B$ 的巡回”属于 NP：给定一个节点排列，可在多项式时间内检查合法性并计算成本。由 Hamilton 回路问题可作多项式归约，因此该判定问题是 **NP-complete** [2]。
- “NP-complete”严格用于判定问题；不应直接把最优化版本称为 NP-complete。

固定起点后，有向巡回仍有 $(n-1)!$ 种排列。对称 TSP 中，一条巡回及其反向代表同一组无向边，因此当 $n\ge 3$ 时有 $(n-1)!/2$ 个不同巡回。直接枚举的阶乘增长解释了穷举法只能处理很小的实例。

即使成本只取 1 和 2 且满足三角不等式，TSP 仍然是 NP-hard：可令原图中的边成本为 1、非边成本为 2，并据最优值是否为 $n$ 判断 Hamilton 回路是否存在。

### 3.2 为什么一般 TSP 没有固定常数近似保证

若允许任意非负、但不满足三角不等式的成本，则除非 $P=NP$，不存在对所有实例都保证固定常数近似比的多项式时间算法 [5]。直观归约如下：给定 Hamilton 回路实例，将原图边的成本设为 1，非边成本设为一个大于 $\rho n$ 的数 $M$。若存在 Hamilton 回路，最优成本为 $n$，任何 $\rho$-近似解的成本小于 $M$；若不存在，任何巡回都必须使用至少一条成本为 $M$ 的边。于是任意预先固定的 $\rho$ 都会使该近似算法能够判定 Hamilton 回路。

因此，后文的 2-近似和 $3/2$-近似**仅适用于对称度量 TSP**，不能外推到任意对称 TSP、ATSP 或含禁用边的稀疏实例。

## 4. 精确算法

精确算法返回可证明最优的巡回。除穷举和动态规划外，成熟实现通常同时维护：

- 当前最好可行解，即上界（incumbent/upper bound）；
- 对尚未搜索区域的下界（lower bound）；
- 当上下界相等或达到规定最优性间隙时的证明。

### 4.1 穷举与回溯

固定起点后枚举其余节点的排列，计算每条闭合巡回的成本并取最小值。时间复杂度为 $O(n!)$，若流式生成排列，额外空间可为 $O(n)$。常见剪枝包括：

- 当所有尚未计入的成本都非负时，当前部分路径成本已不小于最好完整解即可回溯；若允许负成本，则必须先加上一个合法的剩余成本下界，不能只比较当前累计成本；
- 预先固定一个方向以消除对称巡回的反转重复；
- 使用剩余节点的连接成本下界提前截断。

穷举最适合作为小规模测试预言机，用于验证更复杂算法，而不是作为通用求解方法。

### 4.2 Held–Karp 子集动态规划

固定起点 $s$。对 $S\subseteq V\setminus\{s\}$ 和 $j\in S$，定义

$$
D[S,j]=\text{从 }s\text{ 出发，恰好访问 }S\text{ 中的节点并停在 }j\text{ 的最小成本}.
$$

边界条件为

$$
D[\{j\},j]=c_{sj},
$$

状态转移为

$$
D[S,j]=\min_{k\in S\setminus\{j\}}
\left(D[S\setminus\{j\},k]+c_{kj}\right),
$$

最终答案为

$$
\min_{j\ne s}\left(D[V\setminus\{s\},j]+c_{js}\right).
$$

状态数为 $\Theta(n2^n)$，每个状态最多检查 $O(n)$ 个前驱，因此时间复杂度为 $O(n^2 2^n)$，保存全部状态和前驱时空间复杂度为 $O(n2^n)$ [4]。它比 $O(n!)$ 枚举显著改进，但仍是指数算法，内存通常先成为瓶颈。

> “Held–Karp”在文献中至少有三种相关但不同的含义：1962 年的子集动态规划 [4]、DFJ 子回路 LP 的 Held–Karp 松弛，以及 1970 年基于 1-tree 与拉格朗日乘子的 Held–Karp 下界 [13]。阅读算法或求解器日志时必须结合上下文区分。

### 4.3 分支定界

分支定界把解空间递归拆分，例如分别要求某条边必须选中或必须排除。每个搜索节点计算下界；若下界不小于当前最好可行解，则该子树不可能改进上界，可被安全剪枝。

常用下界包括：

- 对称 TSP 的最小 1-tree 下界及其 Lagrangian 强化；
- 有向 TSP 的指派问题松弛；
- 最小生成树与必要连接边构造出的简单下界；
- 线性规划松弛给出的下界。

搜索效率高度依赖初始可行解、下界强度、分支规则和节点选择策略。其最坏时间复杂度仍为指数级，不能因为某些实例求解很快就推断具有多项式保证。

### 4.4 割平面与分支切割

割平面法从度约束等较小松弛开始，反复求解线性规划、寻找被当前解违反的有效不等式并加入模型。只做割平面未必得到整数解；分支切割（branch-and-cut）把割分离嵌入分支定界，在需要时再分支。

除 SEC 外，高性能对称 TSP 求解器还会使用 2-matching、comb 等 TSP 多面体有效不等式，以及强启发式、变量定价和精心设计的分支策略。Concorde 是针对对称 TSP 的代表性精确求解系统 [10]。DFJ 模型之所以在现代实现中实用，关键正是按需分离约束，而不是显式创建指数数量的全部 SEC。

## 5. 具有理论保证的近似算法

本节统一假定成本非负、对称且满足三角不等式，并且任意两节点之间均有可用边。

### 5.1 基于最小生成树的 2-近似

算法步骤如下：

1. 求一个最小生成树 $T$。
2. 将 $T$ 的每条边复制一次，得到所有节点度数均为偶数的连通多重图。
3. 求该多重图的一条 Euler 回路。
4. 按 Euler 回路次序行走；遇到已访问节点时直接跳到下一个未访问节点，最后回到起点。

从最优 TSP 巡回删除任意一条边可得到一棵生成树，因此

$$
c(T)\le \operatorname{OPT}.
$$

复制后的 Euler 回路成本为 $2c(T)$。三角不等式保证“捷径化”不会增加成本，故最终巡回满足

$$
c(\text{tour})\le 2c(T)\le 2\operatorname{OPT}.
$$

实际实现也常对生成树作先序遍历并按首次出现次序输出节点，这与上述 Euler 回路捷径化具有相同的 2-近似逻辑。

### 5.2 Christofides 的 $3/2$-近似

Christofides 算法在最小生成树上只修复奇度节点，而不是复制所有边 [6]：

1. 求最小生成树 $T$。
2. 取 $T$ 中所有奇度节点组成集合 $O$。由握手定理，$|O|$ 为偶数。
3. 在 $O$ 的完全诱导图上求最小成本完美匹配 $M$。
4. 合并 $T$ 与 $M$。所得连通多重图中每个节点的度均为偶数。
5. 求 Euler 回路，再利用三角不等式跳过重复节点。

仍有 $c(T)\le\operatorname{OPT}$。按最优巡回中奇度节点的出现顺序连接它们并交替取边，可得到两个完美匹配；两者总成本不超过 $\operatorname{OPT}$，所以最小完美匹配满足

$$
c(M)\le \frac{1}{2}\operatorname{OPT}.
$$

于是

$$
c(\text{tour})\le c(T)+c(M)
\le \frac{3}{2}\operatorname{OPT}.
$$

该证明的每个关键步骤都依赖对称度量条件。若距离不满足三角不等式，跳过重复节点可能使成本上升；若成本非对称，无向完美匹配与反向等价关系也不再成立。

### 5.3 理论前沿与工程边界

Christofides 的 $3/2$ 保证长期以来是一般对称度量 TSP 的经典界。Karlin、Klein 与 Oveis Gharan 后来给出了随机多项式时间的 $(3/2-\varepsilon)$-近似算法，其中某个 $\varepsilon>10^{-36}$ [14]。这一结果在理论上首次严格突破 $3/2$，但改进常数极小，分析与实现也远比 Christofides 复杂，不能据此推断常规工程求解器会自动获得可观的同等改进。

固定维数的欧几里得 TSP（尤其是二维情形）还存在对任意固定 $\varepsilon>0$ 的多项式时间近似方案（PTAS）[7]。这里“多项式时间”是对固定维数和固定 $\varepsilon$ 而言；当维数增长或要求更小误差时，隐藏常数和指数依赖可能很大。因此，近似方案的理论存在性、实际可实现性和给定时间预算下的解质量必须分别评价。

## 6. 启发式与元启发式

启发式通常能较快生成高质量可行解，但除非另有证明，不能把实验效果解释为最优性或固定近似比保证。

### 6.1 构造启发式

- **最近邻**：每次访问离当前节点最近的未访问节点。实现简单，但对起点和局部结构敏感；常采用所有起点或随机起点的多次运行。
- **最近、最远或最便宜插入**：从一个小环开始，按某种规则把未访问节点插入使增量较小的位置。
- **贪心选边**：按成本从小到大考虑边，同时避免节点度超过 2 以及过早形成子环。

构造算法常用于产生分支定界的初始上界，随后再交给局部搜索改进。

### 6.2 局部搜索

- **2-opt**：删除两条边并以另一种方式重连；在对称 TSP 中，这等价于反转一段路径。
- **3-opt**：删除三条边并考察多种重连方式，邻域更大、计算也更昂贵。
- **Lin–Kernighan / Lin–Kernighan–Helsgaun（LKH）**：动态选择交换深度，并结合候选边集、增益准则等机制，是大型 TSP 实践中的重要方法 [8]。

对称 2-opt 中，若删除 $(a,b),(c,d)$ 并加入 $(a,c),(b,d)$，可用

$$
\Delta=c_{ac}+c_{bd}-c_{ab}-c_{cd}
$$

在 $O(1)$ 时间判断该交换是否改进。ATSP 中反转路径会改变路径内部所有弧的方向，不能直接套用这一增量公式。

### 6.3 元启发式与混合方法

模拟退火、禁忌搜索、遗传算法、蚁群算法、迭代局部搜索和大邻域搜索均可用于 TSP。工程上更常见的是混合方案：高质量构造解 + 2-opt/3-opt/LK 改进 + 多起点或扰动重启。比较元启发式时至少应报告随机种子、运行时间、停止条件、实例集合、最好值、均值和方差；只展示单次最好结果会产生选择偏差。

## 7. 常见变体

- **TSP path**：不要求回到起点，或指定起点与终点。
- **多旅行商问题（mTSP）**：使用多个巡回覆盖全部节点；通常还需规定车辆数、共同仓库及负载平衡目标。
- **广义 TSP（GTSP）**：节点被分组，每组选择一个或规定数量的节点访问。
- **收益型、选择型 TSP**：节点带收益，不再强制访问全部节点；相关模型包括 prize-collecting TSP 和 orienteering problem。
- **带时间窗 TSP**：节点只能在给定时间区间内访问，状态不仅取决于当前位置和已访问集合。
- **容量、多个车辆、取送约束**：通常应建模为车辆路径问题（VRP），而非继续套用基础 TSP。
- **固定维数欧几里得 TSP**：仍为 NP-hard，但存在多项式时间近似方案（PTAS）；其结论不能推广到维数随输入增长的情形或任意度量 TSP [7]。

不同变体的复杂度、可行性约束与近似界可能完全不同。使用“TSP 求解器”前应先确认软件接口实际支持的是哪一种模型。

## 8. 工程求解流程

### 8.1 明确成本语义

首先确认成本是否对称、是否静态以及是否满足三角不等式。例如，道路最短行驶时间常因单行道而非对称；随出发时刻变化的交通时间则是时变成本。把这类数据强行对称化可能改变业务问题本身，而不只是造成数值误差。

### 8.2 清洗与核验数据

- 检查矩阵是否为 $n\times n$，节点标识是否唯一，所有必需边是否有有限成本。
- 对称实例应在给定容差内检查 $c_{ij}=c_{ji}$。浮点数据不宜直接用严格相等比较。
- 度量算法使用前应检查非负性、对称性和三角不等式。完整检查三角不等式需要 $O(n^3)$ 时间；抽样检查只能发现反例，不能证明全部成立。
- 经纬度数据应明确使用球面距离、投影距离还是道路距离。直接把经纬度当平面坐标可能产生系统性误差。
- 读取 TSPLIB 实例时必须遵守 `EDGE_WEIGHT_TYPE`、坐标到整数距离的取整规则和显式矩阵格式，不能用未经说明的浮点欧氏距离替代 [9]。例如 `EUC_2D` 使用对非负距离取 `int(d + 0.5)` 的最近整数规则；Python 的 `round` 采用 ties-to-even（中点取偶），不能直接替代。
- TSPLIB 的坐标实例也不能仅凭 `TYPE: TSP` 和 `EDGE_WEIGHT_TYPE: EUC_2D` 就断言整数成本严格满足三角不等式。点 $(0,0)$、$(1,1)$、$(2,2)$ 经上述取整后距离为 $1,1,3$，会出现 $3>1+1$。因此，若算法证明依赖度量条件，应对最终使用的整数成本矩阵进行验证，而不是只检查原始坐标。
- `GEO` 使用 TSPLIB 特定的度分编码和球面距离公式，不是普通十进制度；`ATT` 是伪欧氏距离。两者都必须按规范解码，不能用通用欧氏距离函数替代。
- 若求解器偏好整数系数，可按确定比例缩放并记录舍入方式，同时检查总成本是否可能溢出。

### 8.3 根据目标选择算法

| 方法 | 最坏时间/主要代价 | 输出性质 | 典型用途 |
| --- | ---: | --- | --- |
| 穷举/回溯 | $O(n!)$ | 精确 | 极小实例、测试预言机 |
| Held–Karp DP | $O(n^2 2^n)$ 时间，$O(n2^n)$ 空间 | 精确 | 小规模基准、独立校验 |
| 分支定界/分支切割 | 最坏指数；实际性能依实例与实现而异 | 精确，可给下界和最优性间隙 | 需要最优性证明的中等或结构化实例 |
| MST 倍增 | 多项式 | 对称度量 TSP 的 2-近似 | 需要快速且可证明上界 |
| Christofides | 多项式，包含最小权完美匹配 | 对称度量 TSP 的 $3/2$-近似 | 需要更强理论保证 |
| 局部搜索/元启发式 | 由时间预算和停止条件控制 | 通常无通用最优性保证 | 大规模、重视可行解质量与速度 |

不存在脱离硬件、实现和实例结构的统一规模分界。使用字典保存全部状态的 Held–Karp 实现，常在二十余个节点附近就出现明显内存压力，但该数字只能作为量级提示，必须在目标环境中基准测试。

Google OR-Tools 的 Routing 求解器提供 TSP/VRP 建模与多种构造、局部搜索策略 [11]；其常规路由搜索结果应视为可行解或启发式结果，不能在没有可验证下界或求解证明的情况下宣称全局最优。对称精确 TSP 可考虑 Concorde；通用约束较多时，可使用支持整数规划和割回调的求解器自行建模。

### 8.4 记录可复现信息

至少记录实例版本、节点顺序、成本生成方式、求解器及版本、参数、随机种子、线程数、时间和内存限制、最终路线、独立重算成本、下界与最优性间隙。并行和随机化可能导致相同时间预算下结果不同。

## 9. Python 示例：Held–Karp 精确算法

下面的程序适用于 Python 3.10 及以上版本，仅使用标准库，可独立运行。它采用位掩码表示已访问集合，返回 `(最小成本, 闭合巡回)`。成本矩阵可以非对称；正无穷表示禁用弧。整数成本会保持整数运算，浮点成本则仍受 IEEE 754 精度限制。若不存在 Hamilton 回路则抛出 `ValueError`。

```python
from __future__ import annotations

from math import inf, isnan
from typing import Sequence

Cost = int | float


def held_karp_tsp(
    cost: Sequence[Sequence[Cost]], start: int = 0
) -> tuple[Cost, list[int]]:
    """用 Held–Karp 动态规划求最短闭合巡回。

    参数:
        cost: n×n 成本矩阵。cost[i][j] 是 i 到 j 的成本；
              +inf 表示该弧不可用。对角元素不会被计入。
        start: 返回路线使用的起点编号。

    返回:
        (minimum_cost, tour)，其中 tour 的形式为
        [start, ..., start]，每个节点在闭合前恰好出现一次。

    复杂度:
        时间 O(n^2 * 2^n)，空间 O(n * 2^n)。
    """
    n = len(cost)
    if any(len(row) != n for row in cost):
        raise ValueError("cost 必须是方阵")

    # 保留整数的精确算术；只接受 int/float，并拒绝 NaN 和 -inf。
    matrix: list[list[Cost]] = []
    for row in cost:
        converted: list[Cost] = []
        for value in row:
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise TypeError("成本必须是 int 或 float")
            if (isinstance(value, float) and isnan(value)) or value == -inf:
                raise ValueError("成本不能是 NaN 或 -inf；禁用弧请使用 +inf")
            converted.append(value)
        matrix.append(converted)

    # 空实例和单节点实例采用文末“边界条件”中的约定。
    if n == 0:
        return 0, []
    if not 0 <= start < n:
        raise ValueError("start 超出节点范围")
    if n == 1:
        return 0, [start, start]

    others = [city for city in range(n) if city != start]
    bit_of = {city: 1 << position for position, city in enumerate(others)}
    full_mask = (1 << len(others)) - 1

    # dp[(mask, j)]：从 start 出发，恰好访问 mask 中的节点并停在 j
    # 的最小成本。parent 保存一个最优前驱，用于恢复路线。
    dp: dict[tuple[int, int], Cost] = {}
    parent: dict[tuple[int, int], int] = {}

    for city in others:
        edge_cost = matrix[start][city]
        if edge_cost != inf:
            mask = bit_of[city]
            dp[(mask, city)] = edge_cost
            parent[(mask, city)] = start

    for mask in range(1, full_mask + 1):
        # 单元素状态已在上面初始化。
        if mask & (mask - 1) == 0:
            continue

        for city in others:
            city_bit = bit_of[city]
            if mask & city_bit == 0:
                continue

            previous_mask = mask ^ city_bit
            best_cost: Cost = inf
            best_previous: int | None = None

            for previous in others:
                previous_bit = bit_of[previous]
                if previous_mask & previous_bit == 0:
                    continue

                prefix_cost = dp.get((previous_mask, previous), inf)
                edge_cost = matrix[previous][city]
                if prefix_cost == inf or edge_cost == inf:
                    continue

                candidate = prefix_cost + edge_cost
                if candidate < best_cost:
                    best_cost = candidate
                    best_previous = previous

            if best_previous is not None:
                dp[(mask, city)] = best_cost
                parent[(mask, city)] = best_previous

    # 补上最后一个节点回到 start 的弧。
    minimum_cost: Cost = inf
    last_city: int | None = None
    for city in others:
        path_cost = dp.get((full_mask, city), inf)
        return_cost = matrix[city][start]
        if path_cost == inf or return_cost == inf:
            continue

        candidate = path_cost + return_cost
        if candidate < minimum_cost:
            minimum_cost = candidate
            last_city = city

    if last_city is None:
        raise ValueError("给定成本矩阵不存在 Hamilton 回路")

    # 沿 parent 反向恢复 start 与末节点之间的访问序列。
    reversed_middle: list[int] = []
    mask = full_mask
    current = last_city
    while True:
        reversed_middle.append(current)
        previous = parent[(mask, current)]
        mask ^= bit_of[current]
        if previous == start:
            break
        current = previous

    tour = [start, *reversed(reversed_middle), start]
    return minimum_cost, tour


if __name__ == "__main__":
    costs = [
        [0, 10, 15, 20],
        [10, 0, 35, 25],
        [15, 35, 0, 30],
        [20, 25, 30, 0],
    ]

    best_cost, best_tour = held_karp_tsp(costs)
    print("最短成本:", best_cost)
    print("回路:", best_tour)
```

一种可能的输出为：

```text
最短成本: 80
回路: [0, 2, 3, 1, 0]
```

该实例存在反向等价的另一条最优巡回，因此不同但正确的实现可能返回 `[0, 1, 3, 2, 0]`。起点只改变闭合巡回的表示，不改变其成本。

## 10. 结果验证与边界条件

### 10.1 可行性与目标值检查

对返回的 `tour` 应独立检查：

1. 当 $n>0$ 时长度是否为 $n+1$，首尾节点是否相同。
2. `tour[:-1]` 是否恰好包含全部节点且无重复。
3. 相邻节点之间的每条边或弧是否允许使用。
4. 是否用原始成本数据独立重算

   $$
   \sum_{k=0}^{n-1} c_{\text{tour}[k],\text{tour}[k+1]}.
   $$

5. 若算法声称精确，是否有穷举对照、小规模 DP 对照，或由求解器给出的匹配下界/零最优性间隙。

仅验证“每个节点出现一次”不够：遗漏闭合边、把路径当巡回、方向索引写反和使用禁用边都是常见错误。

### 10.2 推荐测试

- 对随机小实例同时运行全排列枚举和 Held–Karp，比较最优成本。
- 节点重编号后，最优成本应保持不变。
- 所有有限成本同乘正数 $\alpha$ 后，最优巡回集合不变，最优成本应乘 $\alpha$。
- 对称实例中，巡回及其反向成本应相同；该性质不适用于 ATSP。
- 对满足度量条件的小实例，将近似算法结果与精确最优值比较，检查 2 或 $3/2$ 上界。有限样本通过只能验证实现，不能证明算法定理。
- 对分支定界或整数规划结果，始终检查 `lower_bound <= incumbent`，并明确求解器报告的绝对/相对间隙定义。

### 10.3 小规模和异常输入约定

标准简单无向 Hamilton 回路通常假设 $n\ge 3$。距离矩阵软件往往采用更宽松的闭合路线约定：

- $n=0$：返回成本 0 和空路线；
- $n=1$：返回成本 0 和 `[start, start]`，不收取自环成本；
- $n=2$：返回 `[start, other, start]`，分别计算两个方向的弧成本。在无向解释下，这相当于往返使用同一连接，严格说不是简单无向环。

上面的 Python 示例采用这些约定。生产接口应把约定写进契约，避免不同系统对 1、2 个节点的含义不一致。此外还应显式处理：矩阵非方阵、`NaN`、无穷负成本、断连或不存在 Hamilton 回路、重复坐标但节点身份不同、零成本边，以及浮点误差。

## 11. 参考资料

以下资料优先列出经典论文、官方项目和标准实例库。

[1] NIST Dictionary of Algorithms and Data Structures. [Traveling Salesman](https://xlinux.nist.gov/dads/HTML/travelingSalesman.html).

[2] R. M. Karp. “Reducibility Among Combinatorial Problems.” In *Complexity of Computer Computations*, 1972, pp. 85–103. [DOI: 10.1007/978-1-4684-2001-2_9](https://doi.org/10.1007/978-1-4684-2001-2_9).

[3] G. Dantzig, R. Fulkerson, and S. Johnson. “Solution of a Large-Scale Traveling-Salesman Problem.” *Operations Research*, 2(4), 1954, pp. 393–410. [DOI: 10.1287/opre.2.4.393](https://doi.org/10.1287/opre.2.4.393).

[4] M. Held and R. M. Karp. “A Dynamic Programming Approach to Sequencing Problems.” *Journal of the Society for Industrial and Applied Mathematics*, 10(1), 1962, pp. 196–210. [DOI: 10.1137/0110015](https://doi.org/10.1137/0110015).

[5] S. Sahni and T. Gonzalez. “P-Complete Approximation Problems.” *Journal of the ACM*, 23(3), 1976, pp. 555–565. [DOI: 10.1145/321958.321975](https://doi.org/10.1145/321958.321975).

[6] N. Christofides. “Worst-Case Analysis of a New Heuristic for the Travelling Salesman Problem.” *Operations Research Forum*, 3(1), Article 20, 2022（1976 年技术报告的再发表版本）. [DOI: 10.1007/s43069-021-00101-z](https://doi.org/10.1007/s43069-021-00101-z).

[7] S. Arora. “Polynomial Time Approximation Schemes for Euclidean Traveling Salesman and Other Geometric Problems.” *Journal of the ACM*, 45(5), 1998, pp. 753–782. [DOI: 10.1145/290179.290180](https://doi.org/10.1145/290179.290180).

[8] S. Lin and B. W. Kernighan. “An Effective Heuristic Algorithm for the Traveling-Salesman Problem.” *Operations Research*, 21(2), 1973, pp. 498–516. [DOI: 10.1287/opre.21.2.498](https://doi.org/10.1287/opre.21.2.498).

[9] G. Reinelt. “TSPLIB—A Traveling Salesman Problem Library.” *ORSA Journal on Computing*, 3(4), 1991, pp. 376–384. [DOI: 10.1287/ijoc.3.4.376](https://doi.org/10.1287/ijoc.3.4.376)；[TSPLIB 官方站点](https://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/).

[10] University of Waterloo. [Concorde TSP Solver 官方主页](https://www.math.uwaterloo.ca/tsp/concorde.html).

[11] Google for Developers. [OR-Tools: Traveling Salesperson Problem](https://developers.google.com/optimization/routing/tsp).

[12] C. E. Miller, A. W. Tucker, and R. A. Zemlin. “Integer Programming Formulation of Traveling Salesman Problems.” *Journal of the ACM*, 7(4), 1960, pp. 326–329. [DOI: 10.1145/321043.321046](https://doi.org/10.1145/321043.321046).

[13] M. Held and R. M. Karp. “The Traveling-Salesman Problem and Minimum Spanning Trees.” *Operations Research*, 18(6), 1970, pp. 1138–1162. [DOI: 10.1287/opre.18.6.1138](https://doi.org/10.1287/opre.18.6.1138).

[14] A. R. Karlin, N. Klein, and S. Oveis Gharan. “A (Slightly) Improved Approximation Algorithm for Metric TSP.” *Operations Research*, 72(6), 2024, pp. 2543–2594. [DOI: 10.1287/opre.2022.2338](https://doi.org/10.1287/opre.2022.2338)；[作者预印本](https://arxiv.org/abs/2007.01409).

[15] B. Gavish and S. C. Graves. “The Travelling Salesman Problem and Related Problems.” MIT Operations Research Center Working Paper OR 078-78, 1978. [MIT Open Scholarship](https://hdl.handle.net/1721.1/5363).

[16] A. Claus. “A New Formulation for the Travelling Salesman Problem.” *SIAM Journal on Algebraic Discrete Methods*, 5(1), 1984, pp. 21–25. [DOI: 10.1137/0605004](https://doi.org/10.1137/0605004).

### 延伸阅读（非一手资料）

以下链接来自原文档，已去除重复项。它们可用于辅助理解，但算法结论、复杂度和适用条件应以上述论文或官方资料为准。

- [博客园：旅行商问题相关文章](https://www.cnblogs.com/haohai9309/p/18410905)
- [知乎：旅行商问题相关文章 1](https://zhuanlan.zhihu.com/p/1908661145784543084)
- [知乎：旅行商问题相关文章 2](https://zhuanlan.zhihu.com/p/102709464)
- [CSDN：旅行商问题相关文章 1](https://blog.csdn.net/qq_39559641/article/details/101209534)
- [CSDN：旅行商问题相关文章 2](https://blog.csdn.net/qq_20604231/article/details/142323288)
