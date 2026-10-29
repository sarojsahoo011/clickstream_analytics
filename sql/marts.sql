DROP TABLE IF EXISTS gold_user_product_site_day;
CREATE TABLE gold_user_product_site_day AS
SELECT event_date,user_id,product_id,site_id,definition_version,
 COUNT(*) eligible_event_count,MIN(event_timestamp) first_activity_at,MAX(event_timestamp) last_activity_at
FROM silver_event WHERE user_id IS NOT NULL AND is_eligible=1 AND is_bot=0 AND is_internal=0
GROUP BY event_date,user_id,product_id,site_id,definition_version;
DROP TABLE IF EXISTS gold_user_product_day;
CREATE TABLE gold_user_product_day AS
SELECT event_date,user_id,product_id,definition_version,SUM(eligible_event_count) eligible_event_count,
 MIN(first_activity_at) first_activity_at,MAX(last_activity_at) last_activity_at
FROM gold_user_product_site_day GROUP BY event_date,user_id,product_id,definition_version;
DROP TABLE IF EXISTS gold_user_feature_day;
CREATE TABLE gold_user_feature_day AS
SELECT event_date,user_id,product_id,feature_id,COUNT(*) eligible_event_count
FROM silver_event WHERE user_id IS NOT NULL AND is_eligible=1 AND is_bot=0 AND is_internal=0
GROUP BY event_date,user_id,product_id,feature_id;
DROP TABLE IF EXISTS gold_user_product_month;
CREATE TABLE gold_user_product_month AS
SELECT substr(event_date,1,7) activity_month,user_id,product_id,definition_version,
 COUNT(*) active_days,SUM(eligible_event_count) eligible_event_count
FROM gold_user_product_day GROUP BY substr(event_date,1,7),user_id,product_id,definition_version;
DROP TABLE IF EXISTS silver_session;
CREATE TABLE silver_session AS
WITH previous AS (
 SELECT *,LAG(event_timestamp) OVER(PARTITION BY user_id,product_id,site_id ORDER BY event_timestamp,event_id) previous_at
 FROM silver_event WHERE user_id IS NOT NULL AND is_eligible=1 AND is_bot=0 AND is_internal=0
), marks AS (
 SELECT *,CASE WHEN previous_at IS NULL OR (julianday(event_timestamp)-julianday(previous_at))*86400>1800.001 THEN 1 ELSE 0 END new_session FROM previous
), numbered AS (
 SELECT *,SUM(new_session) OVER(PARTITION BY user_id,product_id,site_id ORDER BY event_timestamp,event_id ROWS UNBOUNDED PRECEDING) session_number FROM marks
)
SELECT user_id,product_id,site_id,session_number,MIN(event_timestamp) start_at,MAX(event_timestamp) end_at,
 COUNT(*) event_count,(julianday(MAX(event_timestamp))-julianday(MIN(event_timestamp)))*86400 observed_span_seconds
FROM numbered GROUP BY user_id,product_id,site_id,session_number;
