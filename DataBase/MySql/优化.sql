-- 一、查询数据库引擎
show engines;
show variables like '%storage_engine%';
-- 指定数据库对象的存储引擎
drop table if exists test;
create table test
(
	id int(5) auto_increment,
	name varchar(20),
	primary key(id)
)engine=MEMORY auto_increment=1 default charset=utf8;

-- 二、索引
-- 不适用情况：少量数据、频繁改动的字段、很少使用的字段
-- 会提高数据查询效率，降低IO和CPU使用率，但会降低增删改的效率
-- 分类：单值索引、唯一索引、复合索引
drop table if exists test;
create table test
(
	id int(4) not null auto_increment,
	workno varchar(6) not null,
	name varchar(20),
	dept varchar(4),
	primary key(id)
)engine=innodb auto_increment=1 charset=utf8;
-- 查询表结构
desc test;

-- create 创建索引
-- 创建单值索引
create index index_dept on test(dept);
-- 创建唯一索引
create unique index index_workno on test(workno);
-- 创建复合索引
create index index_dept_name on test(dept,name);
-- 查看表索引
show index from test;
-- delete 删除索引
drop index index_dept on test;
drop index index_workno on test;
drop index index_dept_name on test;

-- alter table 创建索引
-- 创建单值索引
alter table test add index index_dept(dept);
-- 创建唯一索引
alter table test add unique index index_workno(workno);
-- 创建复合索引
alter table test add index index_dept_name(dept,name);
show index from test;
-- alter table 删除索引
alter table test drop index index_dept;
alter table test drop index index_workno;
alter table test drop index index_dept_name;

-- 如果某个字段是primary key，则默认为主键索引，主键索引和唯一索引列中的数据都不能有相同值，但唯一索引可以为null值，主键索引不可以

-- 三、SQL性能
-- 人为优化：采用explain分析SQL的执行计划
-- 自动优化：SQL优化器

-- 查看执行计划
explain select * from test;
-- id:编号
-- select_type:查询类型
-- table:表
-- type:索引类型
-- possible_key:预测会用到的索引
-- key:实际使用的索引
-- key_len:实际使用的索引长度
-- ref:表之间的引用
-- rows:通过索引查询到的数据量
-- extra:额外的信息

-- id:编号
insert into teacher(Tid, Tname, TGender, Tage)
values
('T_1001', '张三','male', 25),
('T_1002', '李四','female', 30),
('T_1003', '王五','male', 28);

explain
	select s.*
	from student s, class c, teacher t
	where s.ClassId = c.CId and c.TeacherId = t.Tid
	and (c.CId = 'c_1004' or t.Tid = 'T_1001');

insert into teacher(Tid, Tname, TGender, Tage)
values
('T_1004', '赵六','male', 40),
('T_1005', '陈真','female', 45),
('T_1006', '贾假','male', 50),
('T_1007','路人甲','female',39);

explain
	select s.*
	from student s, class c, teacher t
	where s.ClassId = c.CId and c.TeacherId = t.Tid
	and (c.CId = 'c_1004' or t.Tid = 'T_1001');
--  id值相同，从上往下顺序执行，表的执行顺序会因表数据量而改变的原因是笛卡尔积
-- 	2*3*4=6*4=24 4*3*2=12*2=24 虽然结果一致，但是第一种方式临时数据是6，第二种方式是12，对于内存来说数据量越小越好，因此优化器会选择第一种方式

explain 
	select t.tname from teacher t
	where t.tid = 
	(
		select c.teacherid from class c
		where c.cid = 
		(
			select s.classid from student s where s.sname='xiyangyang'
		)
	);
-- id值不同，id值越大越优先查询，进行嵌套子查询时，先查内层再外层
-- 修改
explain 
	select c.CName,t.tname from class c, teacher t
	where c.TeacherId=t.Tid 
	and c.CId = 
	(
		select s.classid from student s where s.sname='xiyangyang'
	);
-- 	id值相同又不相同，id值越大越优先，id值相同从上至下顺序执行

-- select_type:查询类型
-- simple:简单查询，不包含子查询和union查询
explain select * from test;
-- primary:包含子查询的主查询（最外层）
-- subquery:包含子查询的著查询（非最外层）
-- derived:衍生查询（用到了临时表）
-- from子查询中只有一张表
-- from子查询中，如果tableA union tableB，则tableA就是derived表
explain 
	select s.sname
	from 
	(
		select * from student where sid='s_1003'
		union 
		select * from student where sid='s_1004'
	) s;
-- union:union之后的表为union表
-- union result:说明哪些表使用了union查询

-- type:索引类型
-- system const eq_ref ref range index all
-- 理想状况system、const，实际只能优化到index->range->ref，且优化type的前提是得创建索引

-- system
-- 源表只有一条数据
-- 衍生表只有一条数据的主查询

-- const
-- 仅能查到一条数据的SQL，仅针对primary key 或 unique索引类型有效
explain select sid from student s where sid='s_1003';
show index from student ;
-- 删除主键
alter table student drop primary key;
create index index_SId on student(SId);
explain select sid from student s where SId = 's_1003';
drop index index_SId on student;
-- 设置主键
alter table student add primary key(sid);

-- eq_ref
-- 唯一性索引，对于每个索引键的查询，返回匹配唯一行数据（有且只有一个），并且查询结果和数据条数必须一致
-- 常见于唯一索引和主键索引
alter table class add constraint un_teacherid unique key(teacherid);
explain select c.TeacherId  from class c, teacher t where c.TeacherId = t.Tid ;
-- 需要class表中的数据行数和最后连接查询行数一致，则有可能满足eq_ref级别
drop index un_teacherid on class;

-- ref 
-- 非唯一性索引，对于每个索引键的查询，返回匹配的所有行（0|1|*）
alter table teacher add index tname_index(tname);
explain select * from teacher where Tname = '张三';
drop index tname_index on teacher;

-- range
-- 检索指定范围的行，where后是一个范围查询（between|>|<|>=|<=|in），in有时会失效转为无索引时候的all
alter table teacher add index tname_index(tname);
explain select t.* from teacher t where tname in ('张三','李四');
drop index tname_index on teacher;

-- index
-- 查询全部索引中的数据（扫描整个索引）

-- all 
-- 查询全部源表中的数据（暴力扫描全表）
show index from teacher;
alter table teacher add index tname_index(tname);
-- tname 设为了索引字段，索引只需扫描索引表，但tgender不是索引字段，所以需要暴力扫描整个源表，会消耗更多的资源
explain select tname from teacher;
explain select TGender  from teacher;
drop index tname_index on teacher;

-- possible_keys和key
-- possible_keys表示可能用到的索引
-- key是实际使用的索引
create index sname_index on student(sname);
explain 
	select c.CName,t.Tname,t.TGender from class c, teacher t
	where c.TeacherId = t.Tid 
	and c.CId = 
	(
		select s.classid from student s where s.sname='xiyangyang'
	);
-- 如果possible_keys|key是null，则说明没用索引

-- key_len
-- 索引的长度，可用于判断复合索引是否被完全使用(a,b,c)
drop table if exists keylenTest;
create table keylenTest
(
	name char(20) not null default ''
)engine=innodb default charset=utf8;
create index name_index on keylenTest(name);
explain select * from keylenTest where name=''; -- 60
alter table keylentest add column name1 char(20);
create index name1_index on keylenTest(name1);
explain select * from keylentest k where name1=''; -- 61
-- 如果索引字段可以为null，则mysql底层会使用1个字节标识
drop index name_index on keylentest;
drop index name1_index on keylentest;
create index name_name1_index on keylentest(name, name1);
explain select * from keylentest k where name = ''; -- 60
explain select * from keylentest k where name1 = ''; -- 121 = 60 + 61
-- 使用复合索引的第二个索引字段会默认使用复合索引的第一个字段，由于name1可以是null，所以是60+61
alter table keylentest add column name2 varchar(20);
create index name2_index on keylentest(name2);
explain select * from keylentest k where name2=''; -- 63
-- key_len = 60 + 1 + 2，varchar属于可变长度，在mysql底层用2个字节标识可变长度

-- ref
-- 指明当前表所参照的字段
create index teacherid_index on class(teacherid);
explain
	select * from class c, teacher t
	where c.TeacherId = t.Tid 
	and t.Tname  = '张三';

-- rows
-- 被索引优化查询的数据行数（实际通过索引而查询到的数据行数）
create index teacherid_index on class(teacherid);
explain
	select * from class c, teacher t
	where c.TeacherId = t.Tid 
	and t.Tname  = '张三';

-- extra
-- 表示其他的一些说明

-- using filesort
-- 针对单索引
-- 表明当前的SQL性能消耗较大
-- 表示进行了一次额外的排序，常见于order by语句中
drop table if exists test1;
create table test1
(
	a char(5),
	b char(5),
	c char(5),
	index a_index(a),
	index b_index(b),
	index c_index(c)
)engine=innodb default charset=utf8;
explain select * from test1 where a='' order by a;
explain select * from test1 where a='' order by b;
-- 对于单索引，如果排序和查找是同一个字段，则不会出现using filesort，反之则会出现。所以where哪些字段就order by哪些字段
-- 针对复合索引
-- 不可跨列（最佳左前缀）
drop index a_index on test1;
drop index b_index on test1;
drop index c_index on test1;
create index a_b_c_index on test1(a,b,c);
-- 使用了a，但没有使用b，跨列
explain select * from test1 where a='' order by c; -- using filesort
-- 使用了b，但没有使用a，跨列
explain select * from test1 where b='' order by c; -- using filesort
-- 使用了a,b，没有跨列
explain select * from test1 where a='' order by b;

-- using temporary
-- 表示当前SQL性能消耗较大，是由于使用到了临时表，一般出现在group by中
explain select tid from teacher where tid in ('t_1001','t_1003') group by tid;
explain select tgender from teacher where Tname in ('张三','李四') group by tgender;
-- 查询哪个字段就按照哪个字段分组，否则就会出现using temporary
explain select tname,TGender from teacher where tname = '张三' and TGender = 'male' group by tname,TGender;
explain select tname,TGender,TAge from teacher where tname = '张三' and TGender = 'male' group by TAge;

-- using index
-- 索引覆盖，表示不用读取源表，只利用索引获取数据，不需要回源表查询
-- 只要使用到的列，全部出现在索引中，就是索引覆盖
drop index a_b_c_index on test1;
create index a_b_index on test1(a,b);
explain select a,c from test1 where a='' or c='';
explain select a,b from test1 where a='' and b='';
explain select a,b from test1 where a='' or b='';
explain select a,b from test1;
-- 如果用到了using index时，会对possible_keys和key造成影响
-- 如果没有where，则索引只出现在key中
-- 如果有where，则索引出现在possible_keys和key中

-- using where
-- 表示需要回表查询，既在索引中进行了查询，又回到了源表进行了查询
drop index a_b_index on test1;
create index a_index on test1(a);
explain select a,c from test1 where a='' and c='';

-- impossible where
-- 当where子句永远为false时，会出现
explain select a from test1 where a='a' and a='b';

-- using join buffer
-- 表示mysql引擎使用了连接缓存，即mysql底层改动了SQL

-- 四、优化
-- 复合索引顺序和使用顺序一致，且对于复合索引不要跨列使用
drop table if exists test1;
create table test1
(
	a int(3) not null,
	b int(3) not null,
	c int(3) not null,
	d int(3) not null
)engine=innodb default charset=utf8;
create index a_b_c_index on test1(a,b,c);
explain select c from test1 where c=1 and b=2 and a=1; -- 不推荐
explain select c from test1 where a=1 and c=3 group by c; -- 跨列不推荐
explain select c from test1 where a=1 and b=2 and c=3;

-- 单表优化
explain
	select tid from teacher t 
	where tage in (40, 45, 50) and tgender='male'
	order by tage desc;
-- 添加索引时，要根据mysql解析顺序添加索引
-- from->on->join->where->group by->having->select dinstinct->order by->limit
create index tage_tgender_tid on teacher(tage,tgender,tid);
explain
	select tid from teacher t 
	where tage in (40, 45, 50) and tgender='male'
	order by tage desc;
-- 使用in有时候会导致索引失效，所以可将in字段放到最后
-- 创建新索引时，最好删除之前的废弃索引，否则索引之间有时会产生干扰
drop index tage_tgender_tid on teacher;
create index tgender_tage_tid on teacher(tgender, tage, tid);
explain
	select tid from teacher t 
	where tgender='male' and  tage in (40, 45, 50)
	order by tage desc;
-- 最佳左前缀，保持索引的定义和使用的顺序一致性
-- 索引需逐步优化，且每次创建新索引，根据情况删除之前的废弃索引
-- 将in的范围查询放到where条件的最后，防止失效
explain
	select tid from teacher t 
	where tgender='male' and  tage = 40
	order by tage desc;
drop index tgender_tage_tid on teacher;
	
-- 两表优化
show index from teacher
alter table teacher drop primary key;
explain 
	select * from class c
	left join teacher t 
	on c.TeacherId = t.Tid 
	where t.Tname = '张三';
-- 对于表连接，小表驱动大表，索引建立在经常使用的字段上
-- 当编写on时，将数据量小的表放左边
-- 一般情况下，左连接给左表加索引，右连接给右表加索引，其他表不需要加索引
show index from class;
create index teacherid_index on class(teacherid);
explain 
	select * from class c
	left join teacher t 
	on c.TeacherId = t.Tid 
	where t.Tname = '张三';
show index from teacher;
create index tname_index on teacher(tname);
explain 
	select * from class c
	left join teacher t 
	on c.TeacherId = t.Tid 
	where t.Tname = '张三';

drop index tname_index on teacher;
alter table teacher add primary key(tid);
	
-- 三表优化
-- 优化原则同两表一致

-- 五、避免索引失效
-- 复合索引：不要跨列或者无序使用（最佳左前缀）、尽量全索引匹配，建立几个索引就使用几个索引
-- 不要在索引上进行任何计算操作（计算、函数、类型转换）
show index from class;
explain select * from class where TeacherId = 't_1001';
explain select * from class where substr(TeacherId,1)= 't';
-- 索引不能使用!=、<>、is null、is not null，否则自身以及右侧所有全部失效。复合索引中如果有>，则自身和右侧索引失效
-- like不要以'%'开头，否则索引失效。如果一定要使用，尽量使用索引覆盖
explain select * from teacher where Tid like '%_100%';
explain select * from teacher where Tid like 't_100%';
explain select tid from teacher where Tid like '%_100%'; -- 索引覆盖
-- 尽量不要使用类型转换（显示、隐式），否则索引失效
explain select * from class where TeacherId = 't_1001';
explain select * from class where TeacherId = 1001;
-- 尽量不要使用or，否则索引失效，会让自身以及左右两侧索引都失效
-- exists和in优化
-- 如果主查询的数据量大，则使用in关键字，效率高
-- 如果子查询的数据量大，则使用exists关键字，效率高
-- order by优化
-- 选择使用单路排序和双路排序，调整buffer的容量大小
set max_length_for_sort_data = 1024 -- （字节数）
-- 避免使用select *