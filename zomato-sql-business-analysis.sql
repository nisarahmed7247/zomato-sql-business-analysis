create database Zomato;
use zomato;
select * from orders;
--Q1Calculate total delivered revenue and monthly revenue trend.

select round(sum(order_amount),2) as total_revenue from orders where order_status="delivered";
select date_format(order_timestamp, '%Y-%m') as Order_month, sum(order_amount) as monthly_revenue, sum(sum(order_amount)) over() as total_revenue from orders where order_status='delivered'
group by date_format(order_timestamp, '%Y-%m')
order by order_month;

--Q2For each city, calculate total delivered revenue, AOV, active customers, and revenue contribution. Then identify cities with above-average active customers but below-average revenue contribution.

create view city_performance as with city_revenue as (select c.city, sum(o.order_amount) as city_revenue, sum(sum(o.order_amount)) over() as total_revenue, avg(o.order_amount) as AOV, count(distinct(c.customer_id)) as active_customers, round((sum(o.order_amount)/sum(sum(o.order_amount)) over())*100,2) as revenue_contribution from orders o inner join customers c on o.customer_id=c.customer_id where order_status='delivered'
group by city)
select city, city_revenue, total_revenue, AOV, active_customers, revenue_contribution from city_revenue where active_customers>(select avg(active_customers) from city_revenue) and revenue_contribution<(select avg(revenue_contribution) from city_revenue);
select * from city_performance;

--Q3Within each city, identify the top 3 restaurants by delivered revenue. For each selected restaurant, show its city, revenue, number of delivered orders, AOV, and its percentage contribution to that citys revenue.


create view  top_restaurants_by_city as select restaurant_id, restaurant_name, city, revenue, city_revenue, round((revenue/city_revenue)*100,2) as revenue_contribution, delivered_orders, round(AOV,2) as AOV from (select city, r.restaurant_id, restaurant_name, count(order_id) as delivered_orders, avg(order_amount) as AOV, sum(sum(order_amount)) over(partition by city) as city_revenue, sum(order_amount) as revenue, dense_rank() over(partition by city order by sum(order_amount) desc) as ranking from restaurants r inner join orders o on r.restaurant_id=o.restaurant_id where order_status='delivered'
group by city, restaurant_name, r.restaurant_id)as CR
where ranking<=3;
select * from  top_restaurants_by_city;

--Q4Calculate month-over-month revenue growth for delivered orders. For each month, show monthly revenue, previous month revenue, and MoM growth percentage.

create view monthly_revenue_mom as with monthly_revenue as (select date_format(order_timestamp, '%Y-%m') as order_Month, round(sum(order_amount),2) as monthly_revenue , round(lag(sum(order_amount)) over(order by date_format(order_timestamp, '%Y-%m') ),2) as previous_revenue from orders
where order_status='delivered'
group by date_format(order_timestamp, '%Y-%m'))
select Order_month, monthly_revenue, previous_revenue, round(((monthly_revenue-Previous_revenue)/previous_revenue)*100,2) as MoM from monthly_revenue;
select * from monthly_revenue_mom;

--Q5Identify the restaurants that collectively generate the first 80% of total delivered revenue. For each restaurant, show its revenue, revenue contribution %, and cumulative revenue contribution %.

create view restaurant_revenue_80pct as with Restaurant_revenue as (select r.restaurant_id, restaurant_name, sum(order_amount) as revenue, sum(sum(order_amount)) over() as total_revenue from restaurants r inner join orders o on r.restaurant_id=o.restaurant_id where order_status='delivered'
group by r.restaurant_id, restaurant_name),

cummulative_revenue as (select restaurant_id, restaurant_name, revenue, total_revenue, round((revenue/total_revenue)*100,2) as revenue_contribution, sum(revenue) over(order by revenue desc, restaurant_id rows between unbounded preceding and current row) as cummulative_revenue from restaurant_revenue),

Final as (select restaurant_id, restaurant_name, round(revenue,2) as revenue, revenue_contribution, round((cummulative_revenue/total_revenue)*100,2) as cummulative_revenue_contribution, lag(round((cummulative_revenue/total_revenue)*100,2)) over(order by revenue desc, restaurant_id) as previous_crc from cummulative_revenue)

select restaurant_id, restaurant_name, revenue, revenue_contribution, cummulative_revenue_contribution from final
where previous_crc<=80 or previous_crc IS NULL;
select * from restaurant_revenue_80pct;

with customer_spending as (select c.customer_id, customer_name, sum(order_amount) as total_spending, count(order_id) as delivered_orders, avg(order_amount) as AOV, sum(sum(order_amount)) over() as total_revenue, row_number() over(order by sum(order_amount) desc) as ranking from customers c inner join orders o on c.customer_id=o.customer_id where order_status='delivered'
group by c.customer_id, customer_name)

select customer_id, customer_name, round(total_spending,2) as total_spending, delivered_orders, round(AOV,2) as AOV, round((total_spending/total_revenue)*100,2) as revenue_contribution from customer_spending
where ranking<=10;

--Q7.Segment customers into Low, Medium, and High-value groups based on their total delivered spending using spending thresholds derived from the average customer spending. Then calculate the number of customers, total revenue, average spending, and revenue contribution for each segment.

create view segment_revenue as with customer_spending as (select c.customer_id, customer_name, sum(order_amount) as total_spending from customers c inner join orders o on c.customer_id=o.customer_id
where order_status='delivered'
group by c.customer_id, customer_name),

customer_segment as (select customer_id, customer_name, total_spending, sum(total_spending) over() as total_revenue, case when
total_spending>(1.5*(select avg(total_spending) from customer_spending)) then 'High'
when total_spending>=(0.5*(select avg(total_spending) from customer_spending)) then 'Medium'
else 'Low' end as Segment from customer_spending)

select segment, count(customer_id) as total_customers, round(sum(total_spending),2) as segment_revenue, round(avg(total_spending),2) as average_spending, round((sum(total_spending)/Max(total_revenue))*100,2) as revenue_contribution from customer_segment
group by segment;
select * from segment_revenue;

--Q8.Compare repeat customers with one-time customers. For each group, calculate the number of customers, total delivered revenue, average customer spending, average number of delivered orders per customer, and revenue contribution.

create view customer_type_analysis as with customer_grouping as (select c.customer_id, customer_name, sum(order_amount) as total_spending, count(order_id) as total_orders, case
when count(order_id)>1 then 'Repeat Customer'
else 'One Time Customer' end as customer_group from customers c inner join orders o on c.customer_id=o.customer_id where order_status='delivered'
group by c.customer_id, customer_name)
select customer_group, count(customer_id) as total_customers, round(sum(total_spending),2) as group_revenue, round(avg(total_spending),2) as avg_customer_spending, round(avg(total_orders),2) as Avg_Orders_per_Customer, round((sum(total_spending)/sum(sum(total_spending)) over ())*100,2) as revenue_contribution from customer_grouping
group by customer_group;
select * from customer_type_analysis;

--Q9.For each customer acquisition channel, among customers who have placed at least one delivered order, calculate the number of active customers, repeat-customer rate, average customer spending, and average number of delivered orders per customer. Compare the channels to understand differences in customer retention and engagement.

create view customer_acquisition_analysis as with channel_revenue as (select Acquisition_channel, c.customer_id, 1 as active_customer, sum(order_amount) as customer_spending, count(order_id) as delivered_orders from customers c inner join orders o on c.customer_id=o.customer_id where order_status='delivered'
group by acquisition_channel, c.customer_id),
repeat_customers as (select acquisition_channel, sum(active_customer) as total_customers, avg(customer_spending) as avg_customer_spending, avg(delivered_orders) as avg_customer_order, sum(case when delivered_orders>1 then 1
else 0 end) as repeat_customers from channel_revenue
group by acquisition_channel)
select acquisition_channel, total_customers, round((repeat_customers/total_customers)*100,2) as repeat_customer_rate, Round(avg_customer_spending,2) as avg_customer_spending, round(avg_customer_order,2) as avg_customer_order from repeat_customers;
select * from customer_acquisition_analysis;

--Q10.Identify what percentage of total delivered revenue is generated by the top 10%, 20%, and 30% of customers ranked by spending.

create view customer_revenue_concentration as with customer_ranking as (select c.customer_id, sum(order_amount) as customer_spending, count(c.customer_id) over() as total_customers, sum(sum(order_amount)) over () as total_revenue, row_number() over(order by sum(order_amount) desc, c.customer_id) as ranking from customers c inner join orders o on c.customer_id=o.customer_id
where order_status='delivered'
group by c.customer_id)
select round((sum(case
when ranking<=(0.1*total_customers) then customer_spending
else 0 end)/max(total_revenue))*100,2) as top_10_revenue_contribution,
round((sum(case when ranking<=(0.2*total_customers) then customer_spending
else 0 end)/Max(total_revenue))*100,2) as top_20_revenue_contribution,
round((sum(case when ranking<=(0.3*total_customers) then customer_spending
else 0 end)/max(total_revenue))*100,2) as top_30_revenue_contribution from customer_ranking;
select * from customer_revenue_concentration;

--Q11.For each restaurant, compare its delivered order volume and revenue against the average restaurant in the same city. Identify restaurants that have above-city-average order volume but below-city-average revenue.

Create view restaurant_city_performance as with restaurant_revenue as (select r.restaurant_id, restaurant_name, city,  count(order_id) as order_volume, avg(count(order_id)) over (partition by city) as avg_city_order_volume, sum(order_amount) as revenue, avg(sum(order_amount)) over (partition by city) as avg_city_revenue from restaurants r inner join orders o on r.restaurant_id=o.restaurant_id
where order_status='delivered'
group by r.restaurant_id, restaurant_name, city)
select restaurant_id, Restaurant_name, city, order_volume, round(avg_city_order_volume,2) as avg_city_order_volume, round(revenue,2) as revenue, round(avg_city_revenue,2) as avg_city_revenue from restaurant_revenue
where order_volume>avg_city_order_volume and revenue<avg_city_revenue;
select * from restaurant_city_performance;

--Q12.For each cuisine, calculate total delivered orders, total delivered revenue, AOV, and average restaurant rating. Then identify cuisines whose revenue is above the overall average cuisine revenue but whose average restaurant rating is below the overall average cuisine rating.

Create view cuisine_performance as with restaurant_level as ( select r.restaurant_id, r.restaurant_name, r.cuisine, r.avg_rating, count(o.order_id) AS delivered_orders, sum(o.order_amount) AS revenue from restaurants r inner join orders o on r.restaurant_id = o.restaurant_id
Where o.order_status = 'delivered'
group by r.restaurant_id, r.restaurant_name, r.cuisine, r.avg_rating),

cuisine_rating as ( select cuisine, sum(delivered_orders) as delivered_order_volume, round(sum(revenue), 2) as revenue, round(avg(avg_rating), 2) as average_restaurant_rating, round(sum(revenue) / sum(delivered_orders), 2) as AOV from restaurant_level
group by cuisine),

cuisine_benchmarks as (select cuisine, delivered_order_volume, revenue, average_restaurant_rating, AOV, avg(revenue) over () as avg_revenue, avg(average_restaurant_rating) over () as avg_rating from cuisine_rating)

select cuisine, delivered_order_volume, round(revenue, 2) as revenue, AOV, round(average_restaurant_rating, 2) as average_restaurant_rating from cuisine_benchmarks
where revenue > avg_revenue and average_restaurant_rating < avg_rating;
select * from cuisine_performance;

--Q13.Identify restaurants whose delivered revenue is above the average revenue of restaurants in their city, but whose average restaurant rating is below the average rating of restaurants in their city. For each restaurant, show its revenue, city-average revenue, restaurant rating, and city-average rating.

create view restaurant_city_rating_performance as with restaurant_rating as (select r.restaurant_id, restaurant_name, city, round(sum(order_amount),2) as revenue, round(avg(sum(order_amount)) over (partition by city),2) as city_avg_revenue, avg_rating, round(avg(avg_rating) over (partition by city),2) as city_avg_rating from restaurants r inner join orders o on r.restaurant_id=o.restaurant_id
where order_status='delivered'
group by r.restaurant_id, restaurant_name, city, avg_rating)
select restaurant_id, restaurant_name, city, revenue, city_avg_revenue, avg_rating, city_avg_rating from restaurant_rating
where revenue>city_avg_revenue and avg_rating<city_avg_rating;
select * from restaurant_city_rating_performance;

--Q14.For each restaurant, calculate the number of unique customers who placed delivered orders, total delivered orders, and average orders per customer. Then identify restaurants where the average orders per customer is above the overall average across restaurants.


create view restaurant_customer_order_analysis as with restaurant_volume as (select r.restaurant_id, restaurant_name, count(distinct(c.customer_id)) as unique_customers,  count(order_id) as total_delivered_orders, (count(order_id)/count(distinct(c.customer_id))) as avg_order_per_customer, avg((count(order_id)/count(distinct(c.customer_id)))) over () as overall_avg from restaurants r inner join orders o on r.restaurant_id=o.restaurant_id inner join customers c on o.customer_id=c.customer_id
where order_status='delivered'
group by r.restaurant_id, restaurant_name)
select restaurant_id, restaurant_name, unique_customers, total_delivered_orders, round(avg_order_per_customer,2) as avg_order_per_customer from restaurant_volume
where avg_order_per_customer>overall_avg;
select * from restaurant_customer_order_analysis;

--Q15.For each cuisine, calculate the total delivered orders, total delivered revenue, unique customers who placed delivered orders, and average order value (AOV). Then identify cuisines that have above-average delivered order volume but below-average AOV across cuisines.

create view cuisine_demand_analysis as with cuisine_analysis as (select cuisine, count(order_id) as delivered_orders, round(avg(count(order_id)) over(),2) as avg_delivered_volume, round(sum(order_amount),2) as delivered_revenue, count(distinct(c.customer_id)) as unique_customers, round(avg(order_amount),2) as AOV, round(avg(avg(order_amount)) over (),2) as avg_AOV from restaurants r inner join orders o on r.restaurant_id=o.restaurant_id inner join customers c on o.customer_id=c.customer_id
group by cuisine)
select cuisine, delivered_orders, delivered_revenue, unique_customers, AOV from cuisine_analysis
where delivered_orders>avg_delivered_volume and AOV<avg_AOV;
select * from cuisine_demand_analysis;

--Q16.For each discount band, calculate delivered orders, revenue, total discount, average discount per order, and AOV. Identify bands with above-average discount per order but below-average AOV across discount bands.

create view discount_band_analysis as with discount_orders as (select order_id, discount_amount, order_amount, case
when discount_amount>100 then 'High Discount'
when discount_amount>50 then 'Medium Discount'
when discount_amount>0 then 'Low Discount'
else 'No Discount' end as Discount_Band from orders where order_status='delivered'),
discount_avg as (select discount_band, count(order_id) as delivered_orders, round(sum(order_amount),2) as total_delivered_revenue, round(sum(discount_amount),2) as total_discount_amount, round((sum(discount_amount)/count(order_id)),2) as avg_discount_per_order, round(avg(sum(discount_amount)/count(order_id)) over (),2) as overall_avg_discount, round(avg(order_amount),2) as AOV, round(avg(avg(order_amount)) over (),2) as avg_AOV from discount_orders
group by discount_band)

select discount_band, delivered_orders, total_delivered_revenue, total_discount_amount,avg_discount_per_order, AOV from discount_avg
where avg_discount_per_order>overall_avg_discount and AOV<avg_AOV;
select * from discount_band_analysis;

--Q17.For each order status, calculate the number of orders, total order value, average order value, and average discount amount. Also calculate each status percentage of total orders and percentage of total order value.

create view order_status_analysis as with order_status_analysis as (select order_status, count(order_id) as total_orders, round(sum(count(order_id)) over (),2) as overall_orders, round(sum(order_amount),2) as total_order_value, round(sum(sum(order_amount)) over (),2) as overall_order_value, round(avg(order_amount),2) as AOV, round(avg(discount_amount),2) as avg_discount_amount from orders
group by order_status)
select order_status, total_orders, total_order_value, AOV, avg_discount_amount, round((total_orders/overall_orders)*100,2) as order_volume_contribution, round((total_order_value/overall_order_value)*100,2) as order_value_contribution from order_status_analysis;
select * from order_status_analysis;

--Q18.For each city, calculate total, delivered, cancelled, and refunded orders, along with cancellation and refund rates. Identify cities with both rates above their respective overall city averages.

create view city_order_status_analysis as with city_analysis as (select city, count(order_id) as total_orders, sum(case when order_status='delivered' then 1
else 0 end) as delivered_orders, sum(case when order_status='cancelled' then 1
else 0 end) as cancelled_orders, sum(case when order_status='refunded' then 1
else 0 end) as refunded_orders from customers c inner join orders o on c.customer_id=o.customer_id
group by city),
city_order_status as (select city, delivered_orders, cancelled_orders, refunded_orders, total_orders, round((cancelled_orders/total_orders)*100,2) as cancellation_rate, round((refunded_orders/total_orders)*100,2) as refund_rate, round(avg((cancelled_orders/total_orders)*100) over (),2) as overall_cancellation_rate, round(avg((refunded_orders/total_orders)*100) over(),2) as overall_refund_rate from city_analysis)
select city, delivered_orders, cancelled_orders, refunded_orders, total_orders, cancellation_rate, refund_rate from city_order_status
where cancellation_rate>overall_cancellation_rate and refund_rate>Overall_refund_rate;
select * from city_order_status_analysis;

--Q19.For each delivery-fee band, calculate delivered orders, delivered revenue, average delivery fee, and AOV. Identify bands with above-average delivery fee but below-average AOV.
Bands: Free = ₹0; Low = >₹0–₹30; Medium = >₹30–₹60; High = >₹60.

create view delivery_fee_analysis as with delivery_fee_band as (select case 
when delivery_fee>60 then 'High'
when delivery_fee>30 then 'Medium'
when delivery_fee>0 then 'Low'
else 'Free' end as Delivery_Fee_Band, order_id, order_amount, delivery_fee from orders where order_status='delivered'),

delivery_fee_band2 as (select delivery_fee_band, count(order_id) as delivered_orders, round(sum(order_amount),2) as delivered_revenue, avg(delivery_fee) as avg_delivery_fee, avg(order_amount) as AOV, avg(avg(delivery_fee)) over () as overall_avg_delivery_fee, avg(avg(order_amount)) over () as overall_AOV from delivery_fee_band
group by delivery_fee_band)

select delivery_fee_band, delivered_orders, delivered_revenue, round(avg_delivery_fee,2) as avg_delivery_fee, round(AOV,2) as AOV from delivery_fee_band2
where avg_delivery_fee>overall_avg_delivery_fee and AOV<overall_AOV;
select * from delivery_fee_analysis;

--Q20.For each payment mode, calculate delivered orders, delivered revenue, AOV, and revenue contribution. Identify payment modes with above-average AOV but below-average revenue contribution.

create view Payment_Mode_Performance as with payment_mode_analysis as (select payment_mode, count(order_id) as delivered_orders, round(sum(order_amount),2) as delivered_revenue, round(avg(order_amount),2) as AOV, round(sum(sum(order_amount)) over (),2) as overall_revenue, round(avg(avg(order_amount)) over (),2) as overall_AOV from orders
where order_status='delivered'
group by payment_mode),

payment_mode_analysis2 as (select payment_mode, delivered_orders, delivered_revenue, AOV, overall_AOV, round((delivered_revenue/overall_revenue)*100,2) as revenue_contribution, round(avg((delivered_revenue/overall_revenue)*100) over (),2) as avg_RC from payment_mode_analysis)

select payment_mode, delivered_orders, delivered_revenue, AOV, revenue_contribution from payment_mode_analysis2
where AOV>Overall_AOV and revenue_contribution< avg_RC;
select * from Payment_Mode_Performance;

--Q21.Compare 2024 vs 2025 monthly delivered orders and revenue, calculate growth rates, and identify months where revenue increased but orders declined.

create view Monthly_Growth_Drivers as with monthly_analysis as (select month(order_timestamp) as order_Month_number, monthname(order_timestamp) as Order_Month, sum(case
when year(order_timestamp)=2024 then 1
else 0 end) as 2024_Orders, sum(case when year(order_timestamp)=2025 then 1
else 0 end) as 2025_Orders, round(sum(case
when year(order_timestamp)=2024 then order_amount
else 0 end),2) as 2024_Revenue, round(sum(case
when year(order_timestamp)=2025 then order_amount
else 0 end),2) as 2025_Revenue from orders
where order_status='delivered'
group by monthname(order_timestamp), month(order_timestamp)),

monthly_analysis2 as (select order_month_number, order_month, 2024_orders, 2025_orders, round(((2025_orders-2024_orders)/2024_orders)*100,2) as order_growth_pct, 2024_revenue, 2025_revenue, round(((2025_revenue-2024_revenue)/2024_revenue)*100,2) as revenue_growth_pct from monthly_analysis
Where 2024_orders > 0 and 2024_revenue > 0)

select order_month, 2024_orders, 2025_orders, order_growth_pct, 2024_revenue, 2025_revenue, revenue_growth_pct from monthly_analysis2
where revenue_growth_pct>0 and order_growth_pct<0
order by order_month_number;
select * from Monthly_Growth_Drivers;

--Q22.For each city, compare 2024 vs 2025 delivered revenue and orders. Calculate revenue growth % and order growth %. Identify cities where revenue grew but orders declined.

create view city_yearly_growth_analysis as with City_Yearly_Analysis as (select city, sum(case
when year(order_timestamp)=2024 then 1
else 0 end) as 2024_Orders, sum(case when year(order_timestamp)=2025 then 1
else 0 end) as 2025_Orders, round(sum(case
when year(order_timestamp)=2024 then order_amount
else 0 end),2) as 2024_Revenue, round(sum(case
when year(order_timestamp)=2025 then order_amount
else 0 end),2) as 2025_Revenue from orders o inner join customers c on o.customer_id=c.customer_id
where order_status='delivered'
group by city),

city_yearly_analysis2 as (select city, 2024_orders, 2025_orders, round(((2025_orders-2024_orders)/2024_orders)*100,2) as order_growth_pct, 2024_revenue, 2025_revenue, round(((2025_revenue-2024_revenue)/2024_revenue)*100,2) as revenue_growth_pct from city_yearly_analysis
Where 2024_orders > 0 and 2024_revenue > 0)

select city, 2024_orders, 2025_orders, order_growth_pct, 2024_revenue, 2025_revenue, revenue_growth_pct from city_yearly_analysis2
where revenue_growth_pct>0 and order_growth_pct<0;
select * from city_yearly_growth_analysis;

--Q23.For each city, calculate 2024 and 2025 active customers and delivered revenue, along with their growth %. Identify cities where revenue increased but active customers declined.

create view city_customer_growth_analysis as with City_customer_Analysis as (select city, round(sum(case
when year(order_timestamp)=2024 and order_status='delivered' then order_amount
else 0 end),2) as 2024_Revenue, round(sum(case
when year(order_timestamp)=2025 and order_status='delivered' then order_amount
else 0 end),2) as 2025_Revenue, count(distinct((case
when year(order_timestamp)=2024 then c.customer_id end))) as 2024_active_customers, count(distinct((case
when year(order_timestamp)=2025 then c.customer_id end))) as 2025_active_customers from orders o inner join customers c on o.customer_id=c.customer_id
group by city),

city_customer_analysis2 as (select city, 2024_active_customers, 2025_active_customers, round(((2025_active_customers-2024_active_customers)/2024_active_customers)*100,2) as Active_customer_growth_Pct, 2024_revenue, 2025_revenue, round(((2025_revenue-2024_revenue)/2024_revenue)*100,2) as revenue_growth_pct from city_customer_analysis
Where 2024_active_customers > 0
      and 2024_revenue > 0)

select city, 2024_active_customers, 2025_active_customers, active_customer_growth_pct, 2024_revenue, 2025_revenue, revenue_growth_pct from city_customer_analysis2
where revenue_growth_pct>0 and active_customer_growth_pct<0;
select * from city_customer_growth_analysis;

--Q24.For each restaurant, compare 2024 vs 2025 delivered revenue and calculate revenue growth %. Identify restaurants with more than 20% revenue decline in 2025.

create view restaurant_revenue_growth_analysis as with restaurant_yearly_analysis as (select r.restaurant_id, restaurant_name, round(sum(case
when year(order_timestamp)=2024 and order_status='delivered' then order_amount
else 0 end),2) as 2024_Revenue, round(sum(case
when year(order_timestamp)=2025 and order_status='delivered' then order_amount
else 0 end),2) as 2025_Revenue from orders o inner join restaurants r on o.restaurant_id=r.restaurant_id
group by r.restaurant_id, restaurant_name),

restaurant_yearly_analysis2 as (select restaurant_id, restaurant_name, 2024_revenue, 2025_revenue, round(((2025_revenue-2024_revenue)/2024_revenue)*100,2) as revenue_growth_pct from restaurant_yearly_analysis
where 2024_revenue>0)

select restaurant_id, restaurant_name, 2024_revenue, 2025_revenue, revenue_growth_pct from restaurant_yearly_analysis2
where revenue_growth_pct<-20;
select * from restaurant_revenue_growth_analysis;

--Q25.For each cuisine, compare 2024 vs 2025 delivered revenue and calculate growth %. Identify cuisines with growth above 10% and rank them by growth.

create view cuisine_revenue_growth_analysis as with cuisine_yearly_analysis as (select cuisine, round(sum(case
when year(order_timestamp)=2024 and order_status='delivered' then order_amount
else 0 end),2) as 2024_Revenue, round(sum(case
when year(order_timestamp)=2025 and order_status='delivered' then order_amount
else 0 end),2) as 2025_Revenue from orders o inner join restaurants r on o.restaurant_id=r.restaurant_id
group by cuisine),

cuisine_yearly_analysis2 as (select cuisine, 2024_revenue, 2025_revenue, round(((2025_revenue-2024_revenue)/2024_revenue)*100,2) as revenue_growth_pct from cuisine_yearly_analysis
where 2024_revenue>0)

select cuisine, 2024_revenue, 2025_revenue, revenue_growth_pct, dense_rank() over(order by revenue_growth_pct desc) as ranking from cuisine_yearly_analysis2
where revenue_growth_pct>10;
select * from cuisine_revenue_growth_analysis;


