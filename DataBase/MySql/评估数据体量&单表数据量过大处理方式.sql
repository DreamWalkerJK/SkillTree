-- 从表容量、磁盘空间评估数据体量
-- 一、表容量
-- OLTP表单表<=2000w，总大小<=15G，访问量单表<=1600/s
-- 查询表的行数据总数
select count(1) from student;
select count(*) from student;

-- 数据量过大时可使用
show table status like 'student'

-- 二、磁盘空间
-- 数据量占磁盘使用率<=70%
-- 查看指定数据库容量大小
select 
table_schema as '数据库',
table_name as '表',
table_rows as '记录数',
truncate(data_length/1024/1024, 2) as '数据容量（MB）',
truncate(index_length/1024/1024, 2) as '索引容量（MB）'
from information_schema.tables t
order by data_length desc, index_length desc;
-- 查看单个数据库容量大小
select 
table_schema as '数据库',
table_name as '表',
table_rows as '记录数',
truncate(data_length/1024/1024, 2) as '数据容量（MB）',
truncate(index_length/1024/1024, 2) as '索引容量（MB）'
from information_schema.tables t
where table_schema = 'test'
order by data_length desc, index_length desc;

-- 三、单表数据量过大，查询变慢，如何解决？
-- InnoDB存储引擎最小存储单元是页，大小为16k
-- 1、数据表分区（不适合千万级以上的）
-- 分区是指将一个表的数据按照条件分布到不同的文件，还是指向同一张表，只是数据分散到了不同的文件
-- 表分区可以在区间内查询对应的数据，降低查询范围，并且索引分区也可以进一步提高命中率，提升查询效率
-- 查看数据表是否支持分区
show variables like '%partition%';
-- 2、数据库分表
-- a、分表后单表数据量降低，B+树高度变低，查询的磁盘IO变少，所以可以提升效率
-- b、解决由于数据量过大而导致数据库性能降低的问题，将原来独立的数据库拆分成若干数据库组成，
-- 将数据大表拆分成若干数据表组成，使得单一数据库、单一数据表的数据量变小，从而达到提升数据库性能的目的。
-- c、分表：水平分表和垂直分表
-- 水平分表：数据表行的拆分，把数据按照某些规则拆分成多张表或者多个库来存放，分为库内表和分库。
-- 进行水平拆分后的表要去掉auto_increment自增长，id可以用一个id增长临时表获得。
-- 垂直分表：列的拆分，根据表之间的相关性进行拆分。
-- d、方案
-- 取模方案：将数据均匀的分布到各个表中
-- range范围方案：以范围进行拆分数据
-- hash取模和range方案结合：对表数取模，再根据range范围
-- 3、冷热归档
-- 过程：
-- 创建归档表，原则上要与原表保持一致
-- 归档表数据的初始化
-- 业务增量数据处理过程（旧数据迁移）
-- 数据获取（获取热数据）
