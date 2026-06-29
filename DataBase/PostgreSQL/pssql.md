server、Database、Post默认不输入
输入Username和口令

## 一、数据库操作

#### 创建数据库

```sql
create database testdb;
```

#### 查看数据库

```sql
\l
```

#### 删除数据库

```sql
drop database testdb;
```

## 二、表操作

#### 新增表

```sql
create table public.class(
	cid int not null,
	cname varchar(50) not null,
	constraint class_pkey primary key(cid)
)
with(
	OIDS = FALSE
);
comment on table public.class
	is '班级表';
```

```sql
create table public.student(
	sid int primary key,
	sname varchar(50) not null,
	sage int,
	cid int
)
with(
	OIDS=FALSE
);
comment on table public.student
	is '学生表';
```

#### 删除表

```sql
drop table public.test1;
```

## 三、模式（架构）Schema操作

#### 创建

```sql
create schema myschema;
```

#### 删除

```sql
drop schema myschema;
```

## 四、数据查询操作

#### 增

```sql
insert into public.class(cid, cname)
	values(1001, 'zhangsan');
```

#### 查

```sql
select * from public.class;
```

#### 更新

```sql
update public.class set cname='lisi'
	where cid=1001;
```

#### 删除

```sql
delete from public.class
	where cid=1001;
```

#### 升序/降序

```sql
select cid,cname from public.class
	order by cname asc;
select cid,cname from public.class
	order by cname desc;
```

#### 分组group by

```sql
select cname,count(cname) from public.class
group by cname;
```

#### having子句(与group by组合)用于选择满足某些条件的特定行

```sql
select cname from public.class
group by cname having count(cname)>=2
```

表示显示名称数量大于等于2的记录

#### 条件查询 where

AND 条件
OR 条件
AND & OR 条件
NOT 条件

```sql
select * from public.class
where cname is not null;
```

LIKE 条件
IN 条件

```sql
select * from public.class
where cid in (1001, 1003);
```

NOT IN 条件

```sql
select * from public.class
where cid not in (1001, 1003);
```

BETWEEN 条件（1001~1010）

```sql
select * from public.class
where cid between 1001 and 1010;
```

## 五、连接

#### 内连接(INNER JOIN) 左右两张表都匹配的数据 交集

```sql
select sid,sname,sage,cname
from public.student as s
inner join public.class as c
on s.cid=c.cid;
```

#### 外连接

#### 左外连接(LEFT OUTER JOIN) 包含左表有，右表没有的数据 左表+交集

```sql
select sid,sname,sage,cname
from public.student as s
left join public.class as c
on s.cid=c.cid;
```

#### 右外连接(RIGHT OUTER JOIN) 包含左表没有，右表有的数据 右表+交集

```sql
select sid,sname,sage,cname
from public.student as s
right join public.class as c
on s.cid=c.cid;
```

#### 全连接(FULL OUTER JOIN) 包含左右表没有的数据 左表+交集+右表

```sql
select sid,sname,sage,cname
from public.student as s
full join public.class as c
on s.cid=c.cid;
```

#### 跨连接(CROSS JOIN) 笛卡尔积 左表5数据 * 右表10数据 = 50数据

```sql
select sid,sname,sage,cname
from public.student as s
cross join public.class as c
```

## 六、高级

### 视图

视图(VIEW)是一个伪表，它不是物理表，而是作为普通表选择查询。
视图也可以表示连接的表。
它可以包含表的所有行或来自一个或多个表的所选行。

```sql
create view current_student as
select sid,sname,sage
from public.student;

select * from current_student;

drop view current_student;
```

### 存储过程

 PostgreSQL函数或存储过程是存储在数据库服务器上
并可以使用SQL界面调用的一组SQL和过程语句(声明，分配，循环，控制流程等)。
它有助于您执行通常在数据库中的单个函数中进行多次查询和往返操作的操作。

#### 语法

```sql
CREATE [OR REPLACE] FUNCTION function_name (arguments)   
RETURNS return_datatype AS $variable_name$  
  DECLARE  
    declaration;  
    [...]  
  BEGIN  
    < function_body >  
    [...]  
    RETURN { variable_name | value }  
  END; LANGUAGE plpgsql;
```

#### 参数说明

function_name：指定函数的名称。
[OR REPLACE]：是可选的，它允许您修改/替换现有函数。
RETURN：它指定要从函数返回的数据类型。它可以是基础，复合或域类型，或者也可以引用表列的类型。
function_body：function_body包含可执行部分。
plpgsql：它指定实现该函数的语言的名称。

```sql
create or replace function tatalStudentRecords()
returns integer as $total$
declare
	total integer;
begin
	select count(*) into total from public.student;
	return total;
end;
$total$ language plpgsql

select tatalStudentRecords();
drop function tatalStudentRecords;
```

### 触发器

触发器是一组动作或数据库回调函数，
它们在指定的表上执行指定的数据库事件(即，INSERT，UPDATE，DELETE或TRUNCATE语句)时自动运行。
触发器用于验证输入数据，执行业务规则，保持审计跟踪等。
1）PostgreSQL在以下情况下执行/调用触发器：在尝试操作之前(在检查约束并尝试INSERT，UPDATE或DELETE之前)。
或者在操作完成后(在检查约束并且INSERT，UPDATE或DELETE完成后)。
或者不是操作(在视图中INSERT，UPDATE或DELETE的情况下)
2）对于操作修改的每一行，都会调用一个标记为FOR EACH ROWS的触发器。 另一方面，标记为FOR EACH STATEMENT的触发器只对任何给定的操作执行一次，而不管它修改多少行。
3）您可以为同一事件定义同一类型的多个触发器，但条件是按名称按字母顺序触发。
4）当与它们相关联的表被删除时，触发器被自动删除。

```sql
create or replace function autoDeleteStudent()
	returns trigger as $example_trigger$
begin
	delete from student 
	where public.student.cid = old.cid;
	return old;
end;
$example_trigger$ language plpgsql;

create trigger delete_Class_Student_trigger 
after delete on Class
for each row
execute procedure autoDeleteStudent();

delete from public.class
where cid=1004;

select * from public.student;
select * from public.class;
```

### 别名

用于为列或表提供临时名称

```sql
select s.* from public.student as s;
```

### 索引

索引是用于加速从数据库检索数据的特殊查找表。
数据库索引类似于书的索引(目录)。 
索引为出现在索引列中的每个值创建一个条目。
1）索引使用SELECT查询和WHERE子句加速数据输出，但是会减慢使用INSERT和UPDATE语句输入的数据。
2）您可以在不影响数据的情况下创建或删除索引。
3）可以通过使用CREATE INDEX语句创建索引，指定创建索引的索引名称和表或列名称。
4）还可以创建一个唯一索引，类似于唯一约束，该索引防止列或列的组合上有一个索引重复的项。
PostgreSQL中有几种索引类型，如B-tree，Hash，GiST，SP-GiST和GIN等。
每种索引类型根据不同的查询使用不同的算法。 默认情况下，CREATE INDEX命令使用B树索引。

#### 单列索引

```sql
create index class_index on public.class(cname);
```

#### 多列索引

```sql
create index student_index 
on public.student(sname,sage);
```

#### 唯一索引

创建唯一索引以获取数据的完整性并提高性能。
它不允许向表中插入重复的值，或者在原来表中有相同记录的列上也不能创建索引。

```sql
create unique index unique_student_index
on public.student(sid);

drop index class_index;
drop index student_index;
drop index unique_student_index;
```

#### 避免使用索引的时刻

应该避免在小表上使用索引。
不要为具有频繁，大批量更新或插入操作的表创建索引。
索引不应用于包含大量NULL值的列。
不要在经常操作(修改)的列上创建索引。

### Union

UNION子句/运算符用于组合两个或多个SELECT语句的结果，而不返回任何重复的行。
要使用UNION，每个SELECT必须具有相同的列数，相同数量的列表达式，
相同的数据类型，并且具有相同的顺序，但不一定要相同。

#### 不重复

```sql
select s.cid from public.student as s
union
select c.cid from public.class as c;
```

#### 重复

```sql
select s.cid from public.student as s
union all
select c.cid from public.class as c;
```

### alter

ALTER TABLE命令用于添加，删除或修改现有表中的列。

#### 增加列

```sql
ALTER TABLE table_name ADD column_name datatype;
```

#### 删除列

```sql
ALTER TABLE table_name DROP COLUMN column_name;
```

#### 更新列

```sql
ALTER TABLE table_name ALTER COLUMN column_name TYPE datatype;
```

#### 添加not null约束

```sql
ALTER TABLE table_name MODIFY column_name datatype NOT NULL;
```

#### 添加唯一约束ADD UNIQUE CONSTRAINT

```sql
ALTER TABLE table_name
ADD CONSTRAINT MyUniqueConstraint UNIQUE(column1, column2...);
```

#### 检查约束

```sql
ALTER TABLE table_name
ADD CONSTRAINT MyUniqueConstraint CHECK (CONDITION);
```

#### 添加主键ADD PRIMARY KEY

```sql
ALTER TABLE table_name
ADD CONSTRAINT MyPrimaryKey PRIMARY KEY (column1, column2...);
```

#### 从表中删除约束(DROP CONSTRAINT)

```sql
ALTER TABLE table_name
DROP CONSTRAINT MyUniqueConstraint;
```

#### 从表中删除主键约束(DROP PRIMARY KEY)约束

```sql
ALTER TABLE table_name
DROP CONSTRAINT MyPrimaryKey;
```

### TRUNCATE

TRUNCATE TABLE命令用于从现有表中删除完整的数据。
您也可以使用DROP TABLE命令删除完整的表，但会从数据库中删除完整的表结构，如果希望存储某些数据，则需要重新创建此表。
它和在每个表上使用DELETE语句具有相同的效果，但由于实际上并不扫描表，所以它的速度更快。 
此外，它会立即回收磁盘空间，而不需要后续的VACUUM操作。 这在大表上是最有用的。

```sql
TRUNCATE TABLE  table_name;
```

### 事务

事务是对数据库执行的工作单元。事务是以逻辑顺序完成的工作的单位或顺序，无论是用户手动的方式还是通过某种数据库程序自动执行。

#### 事务性质：

事务具有以下四个标准属性，一般是由首字母缩写词ACID简称：
原子性(Atomicity)：确保工作单位内的所有操作成功完成; 否则事务将在故障点中止，以前的操作回滚到其以前的状态。
一致性(Consistency)：确保数据库在成功提交的事务时正确更改状态。
隔离性(Isolation)：使事务能够独立运作并相互透明。
持久性(Durability)：确保在系统发生故障的情况下，提交的事务的结果或效果仍然存在。

#### 事务控制：

以下命令用于控制事务：
BEGIN TRANSACTION：开始事务。begin; or begin transaction; 
COMMIT：保存更改，或者您可以使用END TRANSACTION命令。commit; or end tracsaction;
ROLLBACK：回滚更改。rollback;
事务控制命令仅用于DML命令INSERT，UPDATE和DELETE。
创建表或删除它们时不能使用它们，因为这些操作会在数据库中自动提交。

```sql
begin transaction;
delete from public.student where sage<18;
rollback;

begin transaction;
delete from public.student where sage=5;
commit;

select * from public.student;
```

### SQL锁

锁或独占锁或写锁阻止用户修改行或整个表。 
在UPDATE和DELETE修改的行在事务的持续时间内被自动独占锁定。
这将阻止其他用户更改行，直到事务被提交或回退。
用户必须等待其他用户当他们都尝试修改同一行时。 
如果他们修改不同的行，不需要等待。 SELECT查询不必等待。
数据库自动执行锁定。 然而，在某些情况下，必须手动控制锁定。 
手动锁定可以通过使用LOCK命令完成。 它允许指定事务的锁类型和范围。

```sql
LOCK [ TABLE ]
name
 IN
lock_mode
```

name：要锁定的现有表的锁名称(可选模式限定)。 
如果在表名之前指定了ONLY，则仅该表被锁定 如果未指定ONLY，则表及其所有后代表(如果有)被锁定。
lock_mode：锁模式指定此锁与之冲突的锁。 
如果未指定锁定模式，则使用最严格的访问模式ACCESS EXCLUSIVE。 
可能的值是：ACCESS SHARE，ROW SHARE，ROW EXCLUSIVE，
SHARE UPDATE EXCLUSIVE，SHARE，SHARE ROW EXCLUSIVE，
EXCLUSIVE，ACCESS EXCLUSIVE

#### 死锁

当两个事务正在等待彼此完成操作时，可能会发生死锁。
虽然PostgreSQL可以检测到它们并使用ROLLBACK结束，但死锁仍然可能不方便。 
为了防止您的应用程序遇到此问题，请确保以这样的方式进行设计，以使其以相同的顺序锁定对象。

#### 咨询锁

PostgreSQL提供了创建具有应用程序定义含义的锁的方法。
这些称为咨询锁(劝告锁,英文为：advisory locks)。 
由于系统不强制使用它，因此应用程序正确使用它们。 咨询锁可用于锁定针对MVCC模型策略。
例如，咨询锁的常见用途是模拟所谓的“平面文件”数据管理系统的典型的悲观锁定策略。 
虽然存储在表中的标志可以用于相同的目的，但是建议锁更快，避免了表的膨胀，并且在会话结束时被服务器自动清除。

```sql
begin transaction;
lock table class in access exclusive mode;
rollback;/commit;
```

### 自动递增

```sql
CREATE TABLE tablename (
    colname SERIAL
);
```

### 权限

在数据库中创建对象时，都会为其分配所有者。 所有者通常是执行创建语句的用户。 
对于大多数类型的对象，初始状态是只有所有者(或超级用户)可以修改或删除对象。
要允许其他角色或用户使用它，必须授予权限或权限。

#### PostgreSQL中的不同类型的权限是：

SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,
CREATE,CONNECT,TEMPORARY,EXECUTE 和 USAGE。
根据对象的类型(表，函数等)，权限将应用于对象。 要为用户分配权限，使用GRANT命令。

#### GRANT的语法

GRANT命令的基本语法如下：

```sql
GRANT privilege [, ...]
ON object [, ...]
TO { PUBLIC | GROUP group | username }
SQL
```

privilege值可以是：SELECT，INSERT，UPDATE，DELETE，RULE，ALL。
object：要向其授予访问权限的对象的名称。 可能的对象是：表，视图，序列
PUBLIC：表示所有用户的简短形式。
GROUP group：授予权限的组。
username：授予权限的用户的名称。 PUBLIC是表示所有用户的简短形式。

```sql
CREATE USER manisha WITH PASSWORD 'password';
GRANT ALL ON COMPANY TO manisha;
```

#### REVOKE的语法

REVOKE命令的基本语法如下：

```sql
REVOKE privilege [, ...]
ON object [, ...]
FROM { PUBLIC | GROUP groupname | username }
SQL
```

privilege值可以是：SELECT，INSERT，UPDATE，DELETE，RULE，ALL。
object: 授予访问权限的对象的名称。 可能的对象是：表，视图，序列。
PUBLIC：表示所有用户的简短形式。
GROUP group：授予权限的组。
username：授予权限的用户的名称。 PUBLIC是表示所有用户的简短形式。

```sql
REVOKE ALL ON COMPANY FROM manisha;
DROP USER manisha;
```
