# <center>object.GetHashCode()</center>  


### 不适用场景

在这里给出结论， .NET Core 下 object.GetHashCode() 方法不适用于跨进程数据比对功能。

首先，默认实现的 Object.GetHashCode() 方法是根据当前对象实例的地址来计算的，在不同的进程内，在这种情况下，同一 Id 的实体数据其引用地址是不一样的，即使数据相同，跨进程通过 object.GetHashCode() 得出的哈希值结果不一样，所以通过 object.GetHashCode() 计算哈希值此方法不可行。官方文档中也有说明

```
Two objects that are equal return hash codes that are equal. However, the reverse is not true: equal hash codes do not imply object equality, because different (unequal) objects can have identical hash codes. Furthermore, .NET does not guarantee the default implementation of the GetHashCode method, and the value this method returns might differ between .NET implementations and platforms, such as between 32-bit and 64-bit platforms. For these reasons, do not use the default implementation of this method as a unique object identifier for hashing purposes. Two consequences follow from this:

- You should not assume that equal hash codes imply object equality.
- You should never persist or use a hash code outside the application domain in which it was created, because the same object may hash across application domains, processes, and platforms.
```


其次，即便使用 HashCode.Combine(...) 然后继承重写 GetHashCode() ,也不可行。System.HashCode 的实现为： [dotnet/runtime HashCode.cs](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Private.CoreLib/src/System/HashCode.cs)（CoreCLR 核心库）。Combine、Add 最终都是 new HashCode() + Add(...) + ToHashCode()，实例的初始化状态(_v1..._v4) 是由一个静态种子驱动。[dotnet/runtime HashCodeRandomization.cs](https://github.com/dotnet/runtime/blob/6fb75bf148c442d4cad1c4298e45d99c7f7867c8/src/libraries/Common/src/System/HashCodeRandomization.cs) 是一个 per-process 的随机种子，进程启动时生成一次（基于加密随机数），之后整个进程内不变，所以即使相等的实体数据，但跨进程结果依然不同。这个类型产出的哈希值不是用来设计跨进程使用的，在为 System.HashCode 写的安全威胁模型设计文档 [docs/design/security/System.HashCode.md](https://github.com/GrabYourPitchforks/runtime/blob/threat_models/docs/design/security/System.HashCode.md) 中专门讨论了哈希随机化策略(防哈希洪水攻击)，明确提示这个类型产出的哈希值不是设计来跨进程/跨运行使用的。

```
Step 3 - Generating and consuming the hash code
Once all data has been ingested, the ToHashCode method returns a 32-bit hash code. The hash code computation uses a seeded function, where the seed is chosen randomly at app start. The computation is stable for any set of inputs for the lifetime of the process, but the hash code has no meaning outside the current process. It is not intended that these hash codes be transmitted outside the current process or otherwise persisted.

The most common use of these hash codes is for bucket-based keyed collections to choose a bucket index where this entry will be stored. For non-adversarial inputs, these hash codes are sufficient and will result in a generally uniform selection of bucket. For adversarial inputs, these hash codes might be insufficient, and the adversary could attempt to exploit inefficiencies in the data structure's layout, significantly affecting the collection's performance. This is the crux of a hash flooding attack.

HashCode explicitly disclaims that a hash code generated from adversarial input is fit for consumption by the caller.
```


官方 issue [System.HashCode creates a different hash code every time an application is run #27905](https://github.com/dotnet/runtime/issues/27905) 提出 “同一个值通过 System.HashCode 每次运行哈希都不同”，最后的回复说这是有意为之（by design）。

需明确，哈希碰撞是存在数据不同但哈希值有可能相同的风险，而 object.GetHashCode() 则是在跨进程中相同数据却得到不同哈希值，这两种对于数据比对功能都是弊端。

综上所述，object.GetHashCode() 并不适用于跨进程数据比对哈希值的获取，其相同的数据在不同的进程内计算出的哈希值是不一样的。


### 参考资料  
https://learn.microsoft.com/en-us/dotnet/api/system.object.gethashcode?view=net-10.0  
https://github.com/GrabYourPitchforks/runtime/blob/threat_models/docs/design/security/System.HashCode.md  
https://github.com/dotnet/runtime/issues/27905  
https://www.cnblogs.com/sauronKing/p/5946613.html  




