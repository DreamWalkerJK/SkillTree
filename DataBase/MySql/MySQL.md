# <center>Mysql 笔记</center>

### 登录操作  
登录  
> mysql -u python -p

### 用户操作（需要有root权限）  
查看当前用户  
> select current_user;  

或者  

> select user();

添加用户  
> create user 'demo'@'localhost' identified by '123456';  

删除用户  
> drop user if exists 'demo'@'localhost';  

修改  
修改用户名  
> rename user 'demo'@'localhost' to 'test'@'localhost';  

修改用户密码  
> alter user 'test'@'localhost' identified by '666666';  

查询用户
> select user,host from mysql.user;  
 
### 权限操作（需要有root权限）  
查看用户权限  
> show grants for 'test'@'localhost';  
-- USAGE 只允许登录  
-- ALL 允许做任何事，和root一样  

添加用户权限  
将某张表的所有权限都给用户  
> grant all on test.scores to 'test'@'localhost';  

将root权限赋给用户  
> grant all privileges on *.* to 'test'@'localhost' with option;  

撤销权限  
> revoke all on test.scores from 'test'@'localhost';  

刷新系统权限表   
> flush privileges;

### 数据库操作  
新增数据库  
> create database demo charset=utf8;  

删除数据库  
> drop database if exists demo;  

查看所有数据库  
> show databases;  

查看创建数据库的语句   
> show create database demo;  

使用数据库  
> use demo;  

### 数据表操作  
创建表    
> create table students(  
&emsp;   id int unsigned not null auto_increment primary key commit '主键ID',  
&emsp;   name varchar(50) not null,  
&emsp;   age tinyint unsigned not null,  
&emsp;   gender enum('male','female') default 'male',  
&emsp;   classId int unsigned not null  
)engine=InnoDB default charset=utf8;  

删除表   
> drop table if exists students; -- DDL语句不可回滚  

修改表  
添加字段  
> alter table students add birth datetime;  

修改字段   
> alter table students modify birth date;  

修改字段名  
> alter table students change birth birthday date default '1900-01-01';  

删除字段  
> alter table students drop classId;  

查询表
查看表创建语句  
> show create table students;  

查看表字段信息  
> desc students;  

### 数据操作  
新增表数据  
> insert into students values(0, 'tom', 18, 'male', 2);  

删除表数据  
> truncate students; -- DDL语句不可回滚，会重置表的自增值  
> delete from students; --DML语句  

修改表数据  
> update students set name='jerry' where id=0;  

查询表数据
> select * from students;  

### 索引操作  
创建索引  
> create index index_name on students(name);  
删除索引  
> drop index index_name on students;    
查看索引  
> show index from students;  

### 视图操作  
创建视图  
> create view partStu as 
    select name, age, gender 
    from students;

删除视图  
> drop view if exists partStu;   

### 事务操作  
事务特性：（ACID）
- Atomicity：原子性，整个事务中的操作要么全部成功，要么全部失败    
- Consistency： 一致性，数据库总是从一个一致性的状态转换到另一个一致性的状态    
- Isolation： 隔离性，一个事务所做的修改在最终提交前，对其他事务是不可见的  
- Durability：持久性，一旦事务提交，则其所作的修改会永久保存到数据库  

开启事务  
> begin;  
> start transaction;  

提交事务  
> commit;  

回滚事务  
> rollback;  

### 其它操作  
查看执行计划  
> show profiles;  

显示数据库版本  
> select version();  

显示当前时间  
> select now();