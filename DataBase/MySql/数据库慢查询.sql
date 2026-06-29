-- 数据库慢查询
-- 一、深度分页
-- 查询第5000000-5000020数据，先查前5000020条再抛弃前5000000条数据
select SId,SName from student limit 5000000,20;
-- 优化：
-- 1、适用于主键自增的情况，且每次需要记录maxId值
-- 通过走主键索引，直接链接到100000处取10条数据
-- select SId,SName from student where SId > maxId limit 100000,10;
-- 2、子查询in|inner join，先根据where条件分页查出一页，外层查询只需要查询这一页的数据
-- 通过减少回表的记录数提高查询效率
-- select * from student where SId in (select SId from student where 条件 limit 100000,10 );
-- 针对主键索引不是自增，使用order by 进行排序解决，查询模板：
-- select * from table_name
-- where 条件 and id order by id limit offset, rows
-- 3、ElasticSearch
-- from+size浅分页：（数据量较小，10000以内）
-- 类似关系型数据库中的limit，from分页起始位置，size表示每页获取的数据条数，适用于10000-50000条数据，默认是10000条限制
-- scroll深分页：（数据量大，后台批处理任务（数据迁移）、一次性进行批量数据的导出、查询海量结果集的数据）
-- 类似关系型数据库中的cursor游标，每次返回一个scroll_id，再通过scroll_id获取下一页，无法跳页
-- 首次查询会生成缓存快照，每一个scroll_id不仅会占用大量资源且会生成历史快照，后续数据变化无法及时体现在查询结果
-- 减少了查询和排序的次数，有效降低查询和存储的性能损耗，需要注意设定期望的过期时间，以降低维持游标查询窗口所消耗的资源
-- 不建议用于实时请求，比如数据导出，适合一次性批量查询或非实时数据的分页查询
-- search after分页：（数据量大，用户实时、高并发查询）
-- 根据上一页的最后一条数据来确定下一页的位置，因为依赖于上一页的最后一条数据，所以无法跳页
-- 采用记录作为游标，为了找到每一页的最后一条数据，每个doc必须有一个全局唯一值，推荐用_uid
-- 相比于scroll分页优点是可以实时体现数据的变化，解决了查询快照导致的查询结果延迟问题
-- 无状态分页查询，数据的变更能够即使的反映在查询结果中，且不用维护scroll_id和快照，节省资源
-- 不适合大幅度跳页查询

-- 二、未加索引
-- 聚集索引使用：列经常被分组排序、返回某范围内的数据、小数目的不同值、外键列、主键列
-- 频繁更新的列或者频繁修改索引列并不适合使用
-- 聚集索引（主键）和非聚集索引的区别：
-- 1、
-- 聚集索引可以查到所需要的数据
-- 非聚集索引可以查到数据对应的主键值，再使用主键值通过聚集索引查找到数据
-- 2、聚集索引一个表只能有一个，而非聚集可以有多个
-- 3、聚集索引存储记录是物理上连续存在，物理存储按照索引排序，是一种索引组织结构，索引的键值逻辑顺序决定了表数据行的物理存储顺序；
-- 非聚集是逻辑上的连续物理存储不连续，普通索引，仅仅对数据列创建对应的索引，不影响整个表的物理存储顺序。
-- 4、聚集索引是索引结构和数据一起存放的索引，索引的叶节点就是数据节点；
-- 非聚集是索引结构和数据分开存放，索引的叶节点是索引节点指针指向对应的数据块。
-- 优缺点：
-- 聚集索引插入数据时速度慢（在物理存储的排序上找到位置再插入），查询要比非聚集要快

-- 查看某张表的索引
show create table student;
-- 加索引的alter操作可能引起锁表，注意使用时间
-- create index index_name on table_name(columu_name)
-- 添加主键索引
-- alter table table_name add primary key(column_name);
-- 添加唯一索引
-- alter table table_name add unique(column_name);
-- 添加普通索引
-- alter table table_name add index index_name (column_name);
-- 添加全文索引
-- alter table table_name add fulltext(column_name);
-- 添加多列索引
-- alter table table_name add index index_name (column_name, column_name1,...);

-- 三、索引失效
-- 1、添加索引的字段区分性差
-- 字段唯一性差、频繁更新、大量为空少数有值
-- 2、索引字段在or中，除非or中的条件都是索引字段
-- 3、like '%xxx'
-- 4、索引字段发生了隐式转换
-- 如索引字段为varchar类型，但是却没有加单引号，直接where column_name=xxx
-- 5、联合索引（多个普通字段组合在一起创建的索引）不满足最左匹配原则（按照最左优先的方式进行索引的匹配）
-- 即联合索引（a,b,c），查询where a=1 以a开头的走索引，其他不走 
-- 6、where条件中，索引字段有计算或使用了函数
-- 7、is not null不走索引，is null走索引

-- 强制使用索引
-- select * from table_name force index(column_name) where 

-- 四、Join过多或者子查询过多
-- 不建议使用子查询，可以改成join来优化，但join关联表也不应该过多
-- join在数据量较小时在内存中做的，匹配量小或者join_buffer设置的比较大，速度尚可
-- join在数据量较大时，mysql会采用在硬盘上创建临时表的方式进行多张表的关联匹配

-- 五、in 中的元素过多
-- 代码层面做限制、元素分组或者引入多线程

-- 六、数据量过大