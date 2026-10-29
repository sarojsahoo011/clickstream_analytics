-- name: product_mau
SELECT activity_month,product_id,COUNT(DISTINCT user_id) mau,SUM(eligible_event_count) events,
 ROUND(AVG(active_days),2) avg_active_days FROM gold_user_product_month GROUP BY 1,2;
-- name: company_and_cross_product_mau
WITH users AS (SELECT activity_month,user_id,COUNT(DISTINCT product_id) products FROM gold_user_product_month GROUP BY 1,2)
SELECT activity_month,COUNT(*) company_mau,SUM(CASE WHEN products>=2 THEN 1 ELSE 0 END) cross_product_mau,
 ROUND(100.0*SUM(CASE WHEN products>=2 THEN 1 ELSE 0 END)/COUNT(*),2) cross_product_pct FROM users GROUP BY 1;
-- name: monthly_retention
WITH pairs AS (
 SELECT a.activity_month,a.product_id,a.user_id,MAX(CASE WHEN b.user_id IS NOT NULL THEN 1 ELSE 0 END) retained
 FROM gold_user_product_month a LEFT JOIN gold_user_product_month b ON a.user_id=b.user_id AND a.product_id=b.product_id
 AND b.activity_month=strftime('%Y-%m',date(a.activity_month||'-01','+1 month')) GROUP BY 1,2,3
) SELECT activity_month,product_id,COUNT(*) cohort_users,SUM(retained) retained_users,
 ROUND(100.0*SUM(retained)/COUNT(*),2) retention_pct FROM pairs
WHERE activity_month='2026-09' GROUP BY 1,2;
-- name: feature_adoption
WITH numerator AS (SELECT substr(event_date,1,7) month,product_id,feature_id,COUNT(DISTINCT user_id) users FROM gold_user_feature_day GROUP BY 1,2,3),
denominator AS (SELECT activity_month,product_id,COUNT(DISTINCT user_id) mau FROM gold_user_product_month GROUP BY 1,2)
SELECT n.*,d.mau,ROUND(100.0*n.users/d.mau,2) adoption_pct FROM numerator n JOIN denominator d ON n.month=d.activity_month AND n.product_id=d.product_id;
-- name: organization_activity
SELECT d.event_date,s.organization_id,COUNT(DISTINCT d.user_id) active_users,SUM(d.eligible_event_count) events
FROM gold_user_product_site_day d JOIN dim_site s ON d.site_id=s.site_id GROUP BY 1,2;
-- name: ordered_creation_funnel
-- Same user, product, site; creation strictly after view and within 24h. Not a session funnel.
WITH starts AS (SELECT user_id,product_id,site_id,MIN(event_timestamp) view_at FROM silver_event
WHERE event_name='page_view' AND is_eligible=1 AND is_bot=0 AND is_internal=0 AND user_id IS NOT NULL
AND event_date BETWEEN '2026-10-01' AND '2026-10-30' GROUP BY 1,2,3),
converted AS (SELECT s.*,MAX(CASE WHEN e.event_id IS NOT NULL THEN 1 ELSE 0 END) converted FROM starts s LEFT JOIN silver_event e
ON s.user_id=e.user_id AND s.product_id=e.product_id AND s.site_id=e.site_id AND e.event_name='content_created'
AND e.is_eligible=1 AND e.is_bot=0 AND e.is_internal=0 AND e.event_timestamp>s.view_at
AND julianday(e.event_timestamp)-julianday(s.view_at)<=1 GROUP BY s.user_id,s.product_id,s.site_id,s.view_at)
SELECT product_id,COUNT(*) user_site_entries,SUM(converted) conversions,ROUND(100.0*SUM(converted)/COUNT(*),2) conversion_pct FROM converted GROUP BY 1;
-- name: data_health
SELECT event_date,COUNT(*) events,SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) unattributed,
 SUM(CASE WHEN julianday(received_timestamp)-julianday(event_timestamp)>1 THEN 1 ELSE 0 END) over_24h_late FROM silver_event GROUP BY 1;
