#!/bin/sh
mysql -h localhost -u root -P 3306 -phello987 << EOF

DROP DATABASE IF EXISTS dev;
create database dev;
use dev;




create table retail_transactions(
tran_id INT,
tran_date DATE,
store_id INT,
store_city varchar(50),
store_state char(2),
quantity INT,
total FLOAT);


insert into retail_transactions values(1,'2019-03-17',1,'CHICAGO','IL',5,106.25);
insert into retail_transactions values(2,'2019-03-16',2,'NEW YORK','NY',6,116.25);
insert into retail_transactions values(3,'2019-03-15',3,'SPRINGFIELD','IL',7,126.25);
insert into retail_transactions values(4,'2019-03-17',4,'SAN FRANCISCO','CA',8,136.25);
insert into retail_transactions values(5,'2019-03-11',1,'CHICAGO','IL',9,146.25);
insert into retail_transactions values(6,'2019-03-18',1,'CHICAGO','IL',10,156.25);
insert into retail_transactions values(7,'2019-03-14',2,'NEW YORK','NY',11,166.25);
insert into retail_transactions values(8,'2019-03-11',1,'CHICAGO','IL',12,176.25);
insert into retail_transactions values(9,'2019-03-10',4,'SAN FRANCISCO','CA',13,186.25);
insert into retail_transactions values(10,'2019-03-13',1,'CHICAGO','IL',14,196.25);
insert into retail_transactions values(11,'2019-03-14',5,'CHICAGO','IL',15,106.25);
insert into retail_transactions values(12,'2019-03-15',6,'CHICAGO','IL',16,116.25);
insert into retail_transactions values(13,'2019-03-16',7,'CHICAGO','IL',17,126.25);
insert into retail_transactions values(14,'2019-03-16',7,'CHICAGO','IL',17,126.25);


EOF
