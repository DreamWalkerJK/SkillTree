drop database if exists test;
create database test;

use test;

show tables;

# EASY

/*511. Game Play Analysis I*/

drop table if exists Activity;

create table Activity(
	play_id int,
	device_id int,
	event_date date,
	games_played int,
	primary key(play_id, event_date)
);

select * from activity ;

alter table Activity change play_id player_id int;


insert into Activity(play_id, device_id, event_date, games_played)
values
(1,2,'2016-03-01',5),
(1,2,'2016-05-03',6),
(2,3,'2017-06-25',1),
(3,1,'2016-03-02',0),
(3,4,'2018-07-03',5);

select player_id , min(event_date) as first_login from Activity
group by player_id;

drop table Activity;

/*584. Find Customer Referee*/
drop table if exists Customer;

create table Customer(
	id int primary key,
	name varchar(50),
	referee_id int
);

select * from customer;

insert into Customer(id, name, referee_id)
values
(1,'Will',NULL),
(2,'Jane',NULL),
(3,'Alex',2),
(4,'Bill',NULL),
(5,'Zack',1),
(6,'Mark',2);

select name from customer 
where referee_id <> 2 or referee_id is null order by id;

select name from Customer 
where ifnull(referee_id, 0) <> 2; 

drop table Customer;

/*586. Customer Placing the Largest Number of Orders*/

drop table if exists Orders;

create table Orders
(
	order_number int primary key,
	customer_number int
);

select * from orders;

insert into orders(order_number, customer_number)
values
(1,1),
(2,2),
(3,3),
(4,3);

select customer_number
from orders group by customer_number order by count(order_number) desc limit 1;

drop table orders;

/*595. Big Countries*/
drop table if exists World;

create table world(
	name varchar(50) primary key,
	continent varchar(50),
	area int,
	population int,
	gdp bigint
);

select * from world;

insert into World(name, continent, area, population, gdp)
values
('Afghanistan','Asia',652230,25500100,20343000000),
('Albania','Europe',28748,2831741,2831741),
('Algeria','Africa',2381741,37100000,188681000000),
('Andorra','Europe',468,78115,3712000000),
('Angola','Africa',1246700,20609294,100990000000 );

select name, population, area from world 
where area>=3000000 or population>=25000000;

drop table world;

/*596. Classes More Than 5 Students*/
drop table if exists Courses;

create table Courses(
	student varchar(50),
	class varchar(50),
	primary key(student, class)
);

select * from Courses;

insert into Courses(student, class)
values
('A','Math'),
('B','English'),
('C','Math'),
('D','Biology'),
('E','Math'),
('F','Computer'),
('G','Math'),
('H','Math'),
('I','Math');

select class from courses 
group by class having count(student)>=5;

drop table courses;

/*607. Sales Person*/
drop table if exists salesperson;
drop table if exists company;
drop table if exists orders;

create table salesperson(
	sales_id int primary key,
	name varchar(50),
	salary int,
	commission_rate int,
	hire_date date
);

create table company(
	com_id int primary key,
	name varchar(50),
	city varchar(50)
);

create table orders
(
	order_id int primary key,
	order_date date,
	com_id int, 
	sales_id int,
	amount int
);

alter table orders add constraint fk_orders_com foreign key(com_id) references company(com_id);
alter table orders add constraint fk_orders_sales foreign key(sales_id) references salesperson(sales_id);

select * from salesperson;
select * from company ;
select * from orders;

insert into salesperson(sales_id, name, salary, commission_rate, hire_date)
values
(1,'John',10000,6,'2006-4-1'),
(2,'Amy',12000,6,'2010-5-1'),
(3,'Mark',65000,6,'2008-12-25'),
(4,'Pam',25000,6,'2005-1-1'),
(5,'Alex',5000,6,'2007-2-3');

insert into company (com_id, name ,city)
values
(1,'RED','Boston'),
(2,'ORANGE','New York'),
(3,'YELLOW','Bostpn'),
(4,'GREEN','Austin');

insert into orders(order_id,order_date,com_id,sales_id, amount)
values
(1,'2014-1-1',3,4,10000),
(2,'2014-2-1',4,5,5000),
(3,'2014-3-1',1,1,50000),
(4,'2014-4-1',1,4,25000);

select s.name from salesperson as s
where s.sales_id not in
(
	select o.sales_id from orders as o
	inner join company as c on o.com_id=c.com_id and c.name='RED'
)

alter table orders drop foreign key fk_orders_com;
alter table orders drop foreign key fk_orders_sales;
drop table orders;
drop table company ;
drop table salesperson ;

/*620. Not Boring Movies*/
select * from Cinema
where id % 2 = 1 and description <> 'boring'
order by rating desc;

/*1050. Actors and Directors Who Cooperated At Least Three Times*/
select actor_id, director_id from ActorDirector
group by actor_id, director_id having count(*)>=3;

/*1084. Sales Analysis III*/
select p.product_id, p.product_name from product as p
inner join 
(
    select s.product_id from Sales as s
    group by s.product_id 
    having min(sale_date)>='2019-01-01' and max(sale_date)<='2019-03-31'
) as temp on p.product_id=temp.product_id;

select p.product_id, p.product_name from product as p
inner join Sales as s
on p.product_id=s.product_id
group by s.product_id 
having min(s.sale_date)>='2019-01-01' and max(s.sale_date)<='2019-03-31';

/*1141. User Activity for the Past 30 Days I*/

select temp.activity_date as day, count(activity_date) as active_users from
(
select activity_date,  user_id from Activity
group by activity_date,user_id
having activity_date>'2019-06-27' and activity_date<='2019-07-27'
) as temp group by temp.activity_date;

select activity_date as day,  count(distinct user_id) as active_users from Activity
group by activity_date
having activity_date>date_sub('2019-07-27',interval 30 day) and activity_date<='2019-07-27';


/*1148. Article Views I*/
select distinct author_id as id from Views 
where author_id=viewer_id order by author_id asc;

/*1179. Reformat Department Table  行转列：case/if */
select id,
sum(if(month = 'Jan', revenue, null)) as Jan_Revenue,
sum(if(month = 'Feb', revenue, null)) as Feb_Revenue,
sum(if(month = 'Mar', revenue, null)) as Mar_Revenue,
sum(if(month = 'Apr', revenue, null)) as Apr_Revenue,
sum(if(month = 'May', revenue, null)) as May_Revenue,
sum(if(month = 'Jun', revenue, null)) as Jun_Revenue,
sum(if(month = 'Jul', revenue, null)) as Jul_Revenue,
sum(if(month = 'Aug', revenue, null)) as Aug_Revenue,
sum(if(month = 'Sep', revenue, null)) as Sep_Revenue,
sum(if(month = 'Oct', revenue, null)) as Oct_Revenue,
sum(if(month = 'Nov', revenue, null)) as Nov_Revenue,
sum(if(month = 'Dec', revenue, null)) as Dec_Revenue
from Department
group by id;

/*1407. Top Travellers*/
select u.name,
(
    case
    when sum(r.distance) is null then 0 
    else sum(r.distance) end
) 
    as travelled_distance 
from Users as u
left join Rides as r 
on u.id=r.user_id
group by r.user_id order by sum(r.distance) desc, u.name asc;

select u.name,
(
    case
    when r.distance is null then 0
    else r.distance end
) as travelled_distance
from Users as u
left join
(
    select temp.user_id, sum(temp.distance) as distance 
    from Rides as temp group by temp.user_id
) as r
on u.id = r.user_id
order by r.distance desc, u.name asc;

/*1484. Group Sold Products By The Date 行转列拼接：group_concat */
select sell_date,
count(distinct product) as num_sold,
group_concat(distinct product order by product separator ',') as products
from Activities
group by sell_date order by sell_date;

/*1527. Patients With a Condition*/
select patient_id, patient_name, conditions
from Patients
where conditions like 'DIAB1%' or conditions like '% DIAB1%';

/*1581. Customer Who Visited but Did Not Make Any Transactions*/
select v.customer_id,
count(v.customer_id) as count_no_trans
from
(
    select visit_id,customer_id from Visits
    where visit_id not in
    (
        select distinct t.visit_id from Transactions as t 
    )
) as v
group by v.customer_id;

select v.customer_id,
count(v.customer_id) as count_no_trans
from Visits as v
where v.visit_id not in
(
    select distinct t.visit_id from Transactions as t 
)
group by v.customer_id;

/*1587. Bank Account Summary II*/
select u.name,t.balance
from Users as u
inner join 
(
    select account,sum(amount) as balance from Transactions
    group by account
) as t
on u.account=t.account
where t.balance > 10000;

select u.name,sum(t.amount) as balance
from Users as u
inner join 
Transactions as t
on u.account=t.account group by t.account
having sum(t.amount) > 10000;

/*1667. Fix Names in a Table 
 * 大小写：upper()/lower() 
 * 截取字符串：left()/substring() 
 * 连接字符串：concat(str1, str2)
 * */
select user_id, 
concat(upper(left(name,1)), lower(substring(name, 2))) as name
from Users 
order by user_id;

/*1693. Daily Leads and Partners*/
select date_id, make_name,
count(distinct lead_id) as unique_leads,
count(distinct partner_id) as unique_partners
from DailySales
group by date_id, make_name;

/*1729. Find Followers Count*/
select user_id,
count(follower_id) as followers_count
from Followers
group by user_id 
order by user_id;

/*1741. Find Total Time Spent by Each Employee*/
select event_day as day, emp_id,
sum(out_time-in_time) as total_time
from Employees
group by event_day,emp_id;

/*1757. Recyclable and Low Fat Products*/
select product_id from Products
where low_fats='Y' and recyclable='Y';

/*1795. Rearrange Products Table 
 *列传行：
 *union：效率较union all 低，会去除重复和排序
 *union all*/
select product_id, 'store1' as store, store1 as price from Products where store1 is not null
union all
select product_id, 'store2' as store, store2 as price from Products where store2 is not null
union all
select product_id, 'store3' as store, store3 as price from Products where store3 is not null;

/*1873. Calculate Special Bonus*/
select employee_id, 
(
    case
    when employee_id % 2 = 1 and name not like 'M%'
    then salary
    else 0
    end
) as bonus
from Employees
order by employee_id;

/*1890. The Latest Login in 2020*/
select user_id, max(time_stamp) as last_stamp
from Logins
where time_stamp like '2020%'
group by user_id;

/*1965. Employees With Missing Information*/
select employee_id from Employees where employee_id not in
(
    select distinct employee_id from Salaries
)
union all
select employee_id from Salaries where employee_id not in
(
    select distinct employee_id from Employees
)
order by employee_id;


# Midium

/*178. Rank Scores 排名连续不跳过：dense_rank()*/
select Score,dense_rank() over(order by score desc) as 'rank'
from Scores;

/*184. Department Highest Salary*/
select d.name as Department, e.name as Employee, e.salary
from Employee as e,
(
    select temp.departmentId,max(temp.salary) as salary from Employee as temp
    group by temp.departmentId
) as e1,
Department as d
where e.departmentId = e1.departmentId and e.salary = e1.salary
and d.id = e1.departmentId;

/*608. Tree Node*/
select id,
(
    case 
        when p_id is null then 'Root'
        when p_id is not null and id in (select distinct temp.p_id from Tree as temp) then 'Inner'
        else 'Leaf'
    end
) as type
from Tree
order by id asc;

/*1158. Market Analysis I*/
select distinct u.user_id as buyer_id,u.join_date,
(
    case 
    when o.ordersCount is null then 0
    else o.ordersCount
    end
) as orders_in_2019
from Users as u
left join
(
    select buyer_id,count(buyer_id) as ordersCount
    from Orders where Year(order_date)='2019' group by buyer_id
) as o
on u.user_id=o.buyer_id;

/*1393. Capital Gain/Loss*/

select s.stock_name, sum(s.tempprice) as capital_gain_loss
from
(
    select stock_name,
    (
        case 
        when operation='Buy' then -1*price
        when operation='Sell' then price
        end
    ) as tempprice
    from Stocks
) as s group by s.stock_name;

/*180. Consecutive Numbers*/
drop table if exists Logs;

create table Logs(
	id int primary key,
	num int
);

insert into Logs(id, num)
values
(1,1),
(2,1),
(3,1),
(4,2),
(5,1),
(6,2),
(7,2);

select * from Logs;

drop table Logs;

select distinct num as ConsecutiveNums from 
(
	select l1.num,
	(
	    select l2.num from Logs as l2 where l2.id=l1.id+1 and l2.num=l1.num
	) as t1,
	(
	    select l3.num from Logs as l3 where l3.id=l1.id+2 and l3.num=l1.num
	) as t2 from Logs as l1
) as tempTable
where num=t1 and num=t2 and t1=t2;


select distinct Num as ConsecutiveNums
from Logs
where (Id + 1, Num) in (select * from Logs) 
and (Id + 2, Num) in (select * from Logs)


# Hard

/*185. Department Top Three Salaries*/
select d.name as Department, e.name as Employee, e.Salary from Employee as e
inner join Department as d
on e.departmentId = d.id
where 
(
    select count(distinct t.Salary) from Employee as t
    where t.departmentId=e.departmentId
    and t.salary > e.salary
) < 3
order by e.departmentId asc, e.salary desc;


/*262. Trips and Users*/
select t.request_at as Day,
round(count(t.status='cancelled_by_client' or t.status='cancelled_by_driver' or null)/count(t.status), 2) as 'Cancellation Rate'
from Trips as t
inner join Users as u
on (t.client_id = u.users_id and u.banned='No')
inner join Users as u1
on (t.driver_id = u1.users_id and u1.banned='No')
where t.request_at>='2013-10-01' and t.request_at <= '2013-10-03'
group by t.request_at;

/*601. Human Traffic of Stadium*/
select distinct a.* from Stadium as a,Stadium as b,Stadium as c
where ((a.id=b.id-1 and b.id+1=c.id)
or (a.id-1=b.id and a.id+1=c.id)
or (a.id-1=c.id and c.id-1=b.id))
and (a.people>=100 and b.people>=100 and c.people>=100)
order by a.visit_date;
