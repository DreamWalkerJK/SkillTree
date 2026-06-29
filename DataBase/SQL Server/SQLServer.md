# <center>SQL Server</center>

### <a id="1">1.with(nolock)</a>  
适合的场景：  
- 基础数据表  
- 历史数据表  
- 业务允许脏读情况出现涉及的表
- 数据量超大的表，出于性能考虑，而允许脏读  

当执行类似以下类似的语句时：  
> begin transaction  
> alter table student add address varchar(256);  

用with(nolock)会话也会被阻塞  

### <a id="2">2.回滚</a>  
SQL Server中的DDL语句可以回滚