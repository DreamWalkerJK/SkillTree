show databases;

use bookdb_pre;

show tables;

select count(*) from book; -- 10014701

-- 设置并发线程数，默认值为4
-- 1
set local innodb_parallel_read_threads=1;
select count(*) from book; -- 13.87s

-- 2
set local innodb_parallel_read_threads=2;
select count(*) from book; -- 13.94s

-- 4 DEFAULT
set local innodb_parallel_read_threads=default;
select count(*) from book; -- 7.36s

-- 8
set local innodb_parallel_read_threads=8;
select count(*) from book; -- 4.11s

-- 16
set local innodb_parallel_read_threads=16;
select count(*) from book; -- 3.80s

-- 32
set local innodb_parallel_read_threads=32;
select count(*) from book; -- 3.99s

-- 64
set local innodb_parallel_read_threads=64;
select count(*) from book; -- 3.98s