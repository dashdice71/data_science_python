---------------------------------------------------------------------------------------------------------------------------------------
-- Data Ingestion and Processing - Case Study
-- By: Anmol Parida
---------------------------------------------------------------------------------------------------------------------------------------

-- Dropping the tables
drop table nyc_taxi_data;
drop table nyc_taxi_data_year_month_partitioned;
drop table nyc_taxi_data_year_month_partitioned_orc;

---------------------------------------------------------------------------------------------------------------------------------------
-- Table Creation
---------------------------------------------------------------------------------------------------------------------------------------

-- IMPORTANT: BEFORE CREATING ANY TABLE, MAKE SURE YOU RUN THIS COMMAND 
ADD JAR /opt/cloudera/parcels/CDH/lib/hive/lib/hive-hcatalog-core-1.1.0-cdh5.11.2.jar;

-- CREATE EXTERNAL TABLE 
CREATE EXTERNAL TABLE IF NOT EXISTS nyc_taxi_data(
`vendorid` int,
`tpep_pickup_datetime` timestamp,
`tpep_dropoff_datetime` timestamp, 
`passenger_count` int,
`trip_distance` double,
`ratecodeid` int,
`store_and_fwd_flag` string,
`pulocationid` int,
`dolocationid` int,
`payment_type` int,
`fare_amount` double,
`extra` double,
`mta_tax` double,
`tip_amount` double,
`tolls_amount` double,
`improvement_surcharge` double,
`total_amount` double)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/common_folder/nyc_taxi_data'
TBLPROPERTIES ("skip.header.line.count"="1");

-- RUN QUERY ON THIS TABLE 
select * from nyc_taxi_data limit 10;


---------------------------------------------------------------------------------------------------------------------------------------
-- Basic Data Quality Checks
---------------------------------------------------------------------------------------------------------------------------------------
-- How many records has each TPEP provider provided? Write a query that summarises the number of records of each provider.
-- The data provided is for months November and December only. Check whether the data is consistent, and if not, identify the data quality issues. Mention all data quality issues in comments.
-- You might have encountered unusual or erroneous rows in the dataset. Can you conclude which vendor is doing a bad job in providing the records using different columns of the dataset? Summarise your conclusions based on every column where these errors are present. 
-- For example,  There are unusual passenger count, i.e. 0 which is unusual.

-- [Quality Check] How many records has each TPEP provider provided? Write a query that summarises the number of records of each provider.

select vendorid, count(*) as TripsByVendor
from nyc_taxi_data
group by vendorid;

--  	vendorid	tripsbyvendor
--  	2	        647183
--  	1	        527386

--------- [ Quality Check ] ---------

select year(tpep_pickup_datetime) as yr, count(*) as trip_count
from nyc_taxi_data
group by year(tpep_pickup_datetime);

--  	yr	    trip_count
-- 1	2008	2
-- 2	2018	4
-- 3	2003	1
-- 4	2009	1
-- 5	2017	1174561

-- INSTRUCTION  : As per thr assignment, we ONLY consider the data of yellow taxis for November and December of the year 2017.
-- INFERENCE    : We have inconsistent data as we have trips record with year 2003,2008,2009,2018 as well

--------- [ Quality Check ] ---------

select month(tpep_pickup_datetime) as mnth, count(*) as trip_count
from nyc_taxi_data
where year(tpep_pickup_datetime) = '2017'
group by month(tpep_pickup_datetime);

--  	mnth	trip_count
-- 1	10	    6
-- 2	12	    594255
-- 3	11	    580300

-- INSTRUCTION  : As per thr assignment, we ONLY consider the data of yellow taxis for November and December of the year 2017.
-- INFERENCE    : After filterig with only year as 2017, We have inconsistent data as we have trips record with month October of 2017

--------- [ Quality Check ] ---------

select count(*) 
from nyc_taxi_data
where extra not in (0,0.5,1); --  4856

-- INSTRUCTION  : From the Data Dictionary, Miscellaneous extras and surcharges. Currently, this only includes the $0.50 and $1 rush hour and overnight charges.
-- INFERENCE    : There are 4856 records which does not fall in (0,0.5,1)

--------- [ Quality Check ] ---------

select count(*) 
from nyc_taxi_data
where mta_tax not in (0,0.5); --  548

-- INSTRUCTION  : From the Data Dictionary, $0.50 MTA tax that is automatically triggered based on the metered rate in use.
-- INFERENCE    : There are 548 records which does not fall in (0,0.5)

--------- [ Quality Check ] ---------

select count(*) 
from nyc_taxi_data
where tip_amount <= 0; --  417839

select count(*) 
from nyc_taxi_data
where tip_amount > 0; --  756730
 
-- INSTRUCTION  : From the Data Dictionary, Tip amount – This field is automatically populated for credit card tips. **Cash tips are not included**.
-- INFERENCE    : There are 5756730 valid tip amount and 417839 invalid tips.

--------- [ Quality Check ] ---------

select count(*) 
from nyc_taxi_data
where trip_distance  0; --  1167167 (Valid)

select count(*) 
from nyc_taxi_data
where trip_distance = 0; -- 7402 (Valid - considering this is on road process, no booking and cancellation fee)

select count(*) 
from nyc_taxi_data
where trip_distance < 0; --  0 (Invalid)

select vendorid, count(*) 
from nyc_taxi_data
where trip_distance <= 0
group by vendorid;

--  	vendorid	_c1
-- 1	2	        3185
-- 2	1	        4217
 
-- INSTRUCTION  : From the Data Dictionary, he elapsed trip distance in miles reported by the taximeter. >> can be zero or more
-- INFERENCE    : There are (1167167+7402) valid  distance, considering the zero distance are the ones that got cancelled.
--              : Both the vendors have made wrong entries, Vendor 1 has around 1000 more incorrect records compared to Vendor 2.

--------- [ Quality Check ] ---------

select passenger_count, count(*) 
from nyc_taxi_data
group by passenger_count;

--  	passenger_count	_c1
-- 1	0	6824
-- 6	1	827499
-- 2	2	176872
-- 7	3	50693
-- 3	4	24951
-- 8	5	54568
-- 4	6	33146
-- 9	7	12
-- 5	8	3
-- 10	9	1

--------- [ Quality Check - Question ] ---------

-- Can you conclude which vendor is doing a bad job in providing the records using different columns of the dataset? 
-- Summarise your conclusions based on every column where these errors are present.

select vendorid, count(*) from nyc_taxi_data
where NOT(
year(tpep_pickup_datetime)=2017 
and month(tpep_pickup_datetime) in (11,12) 
and (year(tpep_dropoff_datetime)=2017 or tpep_dropoff_datetime<UNIX_TIMESTAMP('2018-01-02','yyyy-MM-dd')) 
and total_amount >= 0
and improvement_surcharge >= 0
and tolls_amount >= 0
and trip_distance >= 0
and ratecodeid in (1,2,3,4,5,6)
and store_and_fwd_flag in ('Y','N') 
and payment_type in (1,2,3,4,5,6) 
and fare_amount >= 0 
and extra in (0,0.5,1) 
and tpep_pickup_datetime <= tpep_dropoff_datetime
and mta_tax in (0,0.5) 
and (tip_amount<=0 or payment_type =1) 
and (passenger_count!=0 or trip_distance<=0))
group by vendorid;

--  	vendorid	_c1
--      2	        3328
--  	1	        8606

-- [Answer] <Overall Consideration> Values NOT in condition - Vendor 1 is doing a bad job in providing the records using different columns of the dataset 


---------------------------------------------------------------------------------------------------------------------------------------
-- Before answering the below questions, you need to create a clean, ORC partitioned table for analysis. Remove all the erroneous rows.
---------------------------------------------------------------------------------------------------------------------------------------

-- PARTITION THE DATA  
-- IMPORTANT: BEFORE PARTITIONING ANY TABLE, MAKE SURE YOU RUN THESE COMMANDS 
SET hive.exec.max.dynamic.partitions=100000;
SET hive.exec.max.dynamic.partitions.pernode=100000;


-- First drop the table 
drop table nyc_taxi_data_year_month_partitioned;

-- Then create external table
create external table if not exists nyc_taxi_data_year_month_partitioned(
`vendorid` int,
`tpep_pickup_datetime` timestamp,
`tpep_dropoff_datetime` timestamp, 
`passenger_count` int,
`trip_distance` double,
`ratecodeid` int,
`store_and_fwd_flag` string,
`pulocationid` int,
`dolocationid` int,
`payment_type` int,
`fare_amount` double,
`extra` double,
`mta_tax` double,
`tip_amount` double,
`tolls_amount` double,
`improvement_surcharge` double,
`total_amount` double) partitioned by (yr int, mnth int)
location '/user/hive/warehouse/Anmol_Parida/nyc_taxi_data_year_month_partitioned';


-- insert overwrite : after selecting the correct records
insert overwrite table nyc_taxi_data_year_month_partitioned partition(yr, mnth) 
select *, year(tpep_pickup_datetime) as yr, month(tpep_pickup_datetime) as mnth 
from nyc_taxi_data
where year(tpep_pickup_datetime)=2017 
and month(tpep_pickup_datetime) in (11,12) 
and (year(tpep_dropoff_datetime)=2017 or tpep_dropoff_datetime<UNIX_TIMESTAMP('2018-01-02','yyyy-MM-dd')) 
and total_amount >= 0
and improvement_surcharge >= 0
and tolls_amount >= 0
and trip_distance >= 0
and ratecodeid in (1,2,3,4,5,6)
and store_and_fwd_flag in ('Y','N') 
and payment_type in (1,2,3,4,5,6) 
and fare_amount >= 0 
and extra in (0,0.5,1) 
and tpep_pickup_datetime <= tpep_dropoff_datetime
and mta_tax in (0,0.5) 
and (tip_amount<=0 or payment_type =1) 
and (passenger_count!=0 or trip_distance<=0);

-- Checking if the data has been pouplated in the table 
select yr, count(*) 
from nyc_taxi_data_year_month_partitioned
group by yr;

select count(*) from nyc_taxi_data_year_month_partitioned; -- < Expected: 1162635, Actual: 1162635 >


-- ORC FILE FORMAT: This format improves query performance 

--  Drop the table 
drop table nyc_taxi_data_year_month_partitioned_orc;


-- First, create ORC table 
create external table if not exists nyc_taxi_data_year_month_partitioned_orc(
`vendorid` int,
`tpep_pickup_datetime` timestamp,
`tpep_dropoff_datetime` timestamp, 
`passenger_count` int,
`trip_distance` double,
`ratecodeid` int,
`store_and_fwd_flag` string,
`pulocationid` int,
`dolocationid` int,
`payment_type` int,
`fare_amount` double,
`extra` double,
`mta_tax` double,
`tip_amount` double,
`tolls_amount` double,
`improvement_surcharge` double,
`total_amount` double) partitioned by (yr int, mnth int)
stored as orc location '/user/hive/warehouse/Anmol_Parida/nyc_taxi_data_year_month_partitioned_orc'
tblproperties ("orc.compress"="SNAPPY");

-- Then, write data from partition table into ORC table 
insert overwrite table nyc_taxi_data_year_month_partitioned_orc partition(yr , mnth)
select * from nyc_taxi_data_year_month_partitioned;

-- Checking if the data has been pouplated in the table 
select yr, count(*) 
from nyc_taxi_data_year_month_partitioned
group by yr;

select count(*) from nyc_taxi_data_year_month_partitioned; -- < Expected: 1162635, Actual: 1162635 >



---------------------------------------------------------------------------------------------------------------------------------------
-- Analysis-I
---------------------------------------------------------------------------------------------------------------------------------------

-- [Question 1] Compare the overall average fare per trip for November and December.

select mnth, avg(fare_amount) as avgFareForMonth
from nyc_taxi_data_year_month_partitioned_orc
group by mnth;

-- mnth	avgfareformonth
-- 11	12.960085507274076
-- 12	12.756421086820422

-- [Question 2] Explore the ‘number of passengers per trip’ - how many trips are made by each level of ‘Passenger_count’? Do most people travel solo or with other people?

select passenger_count, count(*) as aggregate_passenger_count
from nyc_taxi_data_year_month_partitioned_orc
group by passenger_count;

-- passenger_count	aggregate_passenger_count
-- 0	102
-- 1	824133
-- 2	175856
-- 3	50427
-- 4	24825
-- 5	54279
-- 6	32997
-- 7	12
-- 8	3
-- 9	1

-- [Question 3] Which is the most preferred mode of payment?

select Payment_type, count(*) as count_payment_type
from nyc_taxi_data_year_month_partitioned_orc
group by Payment_type;

-- payment_type	count_payment_type
-- 1	782601
-- 2	372819 
-- 3	5738
-- 4	1477

-- [Answer] Credit Card is the most prefered mode of payment.


-- [Question 4] What is the average tip paid per trip? 
-- Compare the average tip with the 25th, 50th and 75th percentiles and comment whether the ‘average tip’ is a representative statistic (of the central tendency) of ‘tip amount paid’. 
-- Hint: You may use percentile_approx(DOUBLE col, p): Returns an approximate pth percentile of a numeric column (including floating point types) in the group.

select  percentile_approx(Tip_amount, 0.25) as P25, 
        percentile_approx(Tip_amount, 0.50) as P50,
        percentile_approx(Tip_amount, 0.60) as P60,
        percentile_approx(Tip_amount, 0.65) as P65,
        percentile_approx(Tip_amount, 0.75) as P75,
        avg(Tip_amount) as avg_Tip_amount
from nyc_taxi_data_year_month_partitioned_orc;

-- p25	p50	                p60                 p65                 p75	                avg_tip_amount
-- 0	1.352687465025182	1.7552831251760728	1.9918238929914251  2.4477915571616298	1.8323452072236657

-- [Answer] The average tip amount lies between 60th and the 65th perccentile


-- [Question 5] Explore the ‘Extra’ (charge) variable - what fraction of total trips have an extra charge is levied?

select count(*)
from nyc_taxi_data_year_month_partitioned_orc
where extra > 0; -- Charged = 534986

select count(*)
from nyc_taxi_data_year_month_partitioned_orc
where extra = 0 ; -- Not Charged = 627649

select count(*)
from nyc_taxi_data_year_month_partitioned_orc; -- 1162635

-- [Answer] 
-- fraction of total trips where extra charge is levied       :(627649/1162635) = 0.5398 ~ Almost 54%
-- fraction of total trips where extra charge is NOT levied   :(534986/1162635) = 0.4601 ~ Almost 64%


---------------------------------------------------------------------------------------------------------------------------------------
-- Analysis-II
---------------------------------------------------------------------------------------------------------------------------------------

-- [Question 1] 
-- What is the correlation between the number of passengers on any given trip, and the tip paid per trip? 
-- Do multiple travellers tip more compared to solo travellers? Hint: Use CORR(Col_1, Col_2)

select corr(Passenger_count,Tip_amount)
from nyc_taxi_data_year_month_partitioned_orc;

-- [Answer] -0.00501373999946902 : Indicates that there is negligible correlation between the Passenger_count and Tip_amount

-- [Question 2]
-- Segregate the data into five segments of ‘tip paid’: [0-5), [5-10), [10-15) , [15-20) and >=20. 
-- Calculate the percentage share of each bucket(i.e. the fraction of trips falling in each bucket).

select tip_paid, count(tip_paid) as bucket_count, round(count(tip_paid) * 100 / sum(count(tip_paid)) OVER(),2) as percent_tip_paid
from
(
    SELECT tip_amount, 
    CASE
        WHEN tip_amount >= 0 and tip_amount < 5 Then '0_5'
        WHEN tip_amount >= 5 and tip_amount < 10 Then '5_10'
        WHEN tip_amount >= 10 and tip_amount < 15 Then '10_15'
        WHEN tip_amount >= 15 and tip_amount < 20 Then '15_20'
        ELSE '20_above'
    END AS tip_paid
    FROM nyc_taxi_data_year_month_partitioned_orc
) a1
group by tip_paid;

--  	tip_paid	bucket_count	percent_tip_paid
-- 5	0_5	        1073410	        92.33
-- 1	5_10	    65489	        5.63
-- 4	10_15	    20216	        1.74
-- 3	15_20	    2319	        0.2
-- 2	20_above	1201	        0.1


-- [Question 3] 
-- Which month has a greater average ‘speed’ - November or December? Note that the variable ‘speed’ will have to be derived from other metrics. 
-- Hint: You have columns for distance and time.

-- Approach 1 (Considring 0 trip distance and 0 trip time)
SELECT mnth, round(avg(trip_distance/(unix_timestamp(tpep_dropoff_datetime) -  unix_timestamp(tpep_pickup_datetime))) * 3600,2) as Speed
from nyc_taxi_data_year_month_partitioned_orc
group by mnth;

--  	mnth	speed
-- 1	11	    10.95
-- 2	12	    11.05

-- PREFERRED Approach 2 (Removing 0 trip distance and 0 trip time)
SELECT mnth, round(avg(trip_distance/(unix_timestamp(tpep_dropoff_datetime) -  unix_timestamp(tpep_pickup_datetime))) * 3600,2) as Speed
from nyc_taxi_data_year_month_partitioned_orc
where trip_distance !=0 
and unix_timestamp(tpep_dropoff_datetime) -  unix_timestamp(tpep_pickup_datetime) != 0
group by mnth;

--  	mnth	speed
-- 1	11	    10.97
-- 2	12	    11.07

-- [Answer] December Month has higher avergae Speed  11.07 mph over November having 10.97 mph


-- [Question 4] 
-- Analyse the average speed of the most happening days of the year, i.e. 31st December (New year’s eve) and 25th December (Christmas) and compare it with the overall average. 

SELECT round(avg(trip_distance/(unix_timestamp(tpep_dropoff_datetime) -  unix_timestamp(tpep_pickup_datetime))) * 3600,2) as Overall_Aevrgae_Speed
from nyc_taxi_data_year_month_partitioned_orc
where trip_distance !=0 
and unix_timestamp(tpep_dropoff_datetime) -  unix_timestamp(tpep_pickup_datetime) != 0;

--- Overall_Average_Speed = 11.02 mph

SELECT round(avg(trip_distance/(unix_timestamp(tpep_dropoff_datetime) -  unix_timestamp(tpep_pickup_datetime))) * 3600,2) as Overall_Aevrgae_Speed
from nyc_taxi_data_year_month_partitioned_orc
where trip_distance !=0 
and unix_timestamp(tpep_dropoff_datetime) -  unix_timestamp(tpep_pickup_datetime) != 0
and mnth = 12
and day(tpep_pickup_datetime) = 25;

--- Dec25_Average_Speed = 15.27 mph

SELECT round(avg(trip_distance/(unix_timestamp(tpep_dropoff_datetime) -  unix_timestamp(tpep_pickup_datetime))) * 3600,2) as Overall_Aevrgae_Speed
from nyc_taxi_data_year_month_partitioned_orc
where trip_distance !=0 
and unix_timestamp(tpep_dropoff_datetime) -  unix_timestamp(tpep_pickup_datetime) != 0
and mnth = 12
and day(tpep_pickup_datetime) = 31;

--- Dec31_Average_Speeds = 13.25 mph

-- [Answer] Overall_Average_Speed(11.02 mph) < Dec31_Average_Speed(13.25 mph) <  Dec25_Average_Speed(15.27 mph)



-- <<<<<<<<<< End >>>>>>>>>>>>>>