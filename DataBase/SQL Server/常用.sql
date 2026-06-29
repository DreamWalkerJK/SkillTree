use Test;

-- 1.行转列 PIVOT
create table sales(
	id int,
	name varchar(20),
	quarter int,
	number int
);

insert into sales values(1,N'苹果',1,1000);
insert into sales values(1,N'苹果',2,2000);
insert into sales values(1,N'苹果',3,4000);
insert into sales values(1,N'苹果',4,5000);
insert into sales values(2,N'梨子',1,3000);
insert into sales values(2,N'梨子',2,3500);
insert into sales values(2,N'梨子',3,4200);
insert into sales values(2,N'梨子',4,5500);

select * from sales;

select Id, Name,
[1] as '一季度',
[2] as '二季度',
[3] as '三季度',
[4] as '四季度'
from sales
pivot
(
	sum(number) for quarter in ([1],[2],[3],[4])
) as pvt;

-- 2.行转列 通用
-- 多行数据变成一条多列数据，新增列
select id, name,
	sum(case when quarter=1 then number else 0 end) '一季度',
	sum(case when quarter=2 then number else 0 end) '二季度',
	sum(case when quarter=3 then number else 0 end) '三季度',
	sum(case when quarter=4 then number else 0 end) '四季度'
from sales
group by id, name

create table salesTotal
(
	id int,
	name varchar(20),
	Q1 int,
	Q2 int,
	Q3 int,
	Q4 int
);

insert into salesTotal
select Id, name,
[1] as 'Q1',
[2] as 'Q2',
[3] as 'Q3',
[4] as 'Q4'
from sales
pivot
(
	sum(number) for quarter in ([1],[2],[3],[4])
) as pvt;

select * from salesTotal;

-- 3.列转行 UNPIVOT
select id,name,quarter,number
from salesTotal
unpivot
(
	number for quarter in ([Q1],[Q2],[Q3],[Q4])
) as unpvt;

-- 4.字符串替换 substring/replace
select replace ('abcdef', SUBSTRING('abcdefg', 2,4), '**');

-- 5.四舍五入 ROUND 函数
-- 保留小数点后两位，需要四舍五入
select ROUND(150.45648 ,2);

-- 保留小数点后两位，0为默认值，表示进行四舍五入
select ROUND(150.45648, 2, 0);

-- 保留小数点后两位，不需要四舍五入
select ROUND(150.45648, 2, 1);  -- 最后一位参数除了为0，其他数字都是一样的效果

-- 保留小数点后两位，不需要四舍五入
select ROUND(150.45648, 2, 2);

-- 6.COALESCE， 返回其参数中的第一个非空表达式
select coalesce(null, null, 1, 2, 3);
select coalesce(null, 3, 2, 1, null);

-- 7.COUNT
select count(*) from salesTotal;
select count(id) from salesTotal;
select count(1) from salesTotal;

-- 8.查看数据库缓存的SQL
use master;
declare @dbid int
select @dbid=dbid from sysdatabases where name='bookdb_pre';

select dbid,usecounts,refcounts,cacheobjtype,objtype,
db_name(dbid) as databaseName, SQL
from syscacheobjects
where dbid=@dbid
order by dbid,usecounts desc, objtype;

-- 9.删除计划缓存
-- 删除整个数据库的计划缓存
DBCC FREEPROCCACHE

-- 删除某个数据库的计划缓存
use master;
declare @dbid1 int
select @dbid1=dbid from sysdatabases where name='bookdb_pre'
DBCC FLUSHPROCINDB(@dbid1)

-- 10.SQL换行
--制表符 CHAR(9)
--换行符 CHAR(10)
--回车 CHAR(13)

-- 以文本格式显示结果可用select
print 'SQL'+char(13)+'ENTER'

-- 11.TRUNCATE、DELETE
-- truncate 速度快、效率高
-- truncate 比 delete 速度快，且使用的系统和事务日志资源少
-- delete 每删一行，并在事务日志中为所删除的每行记录一项。
-- truncate通过释放存储表数据所用的数据页来删除数据，并且只在事务日志中记录页的释放。
-- truncate 删除所有行，但表结构及列、约束、索引等保持不变，标识计数值重置。
-- delete 保留标识计数值
-- truncate 不能使用有foreign key 约束引用的表，truncate 不记录在日志中，所以不能激活触发器。也不能用于参与了索引视图的表
use Test;
TRUNCATE table sales; 
delete from salesTotal;

-- 12.常用系统检测脚本
-- 查看内存状态
dbcc memorystatus;

-- 查看哪个引起的阻塞， blk
exec sp_who active;

-- 查看锁住了哪个资源id, objid
exec sp_lock;

-- 13.获取脚本的执行时间
declare @timediff datetime;
select @timediff=getdate();
use BookDB_Pre;
select * from book;
print 'total cost time: ' + convert(varchar(10), datediff(ms, @timediff, getdate()))