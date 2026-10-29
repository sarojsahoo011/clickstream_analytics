# Data dictionary and modeling notes

## Source event to derived column

| Silver column | Source / derivation | Meaning |
|---|---|---|
| source_system, event_id | Envelope | Composite immutable event key |
| event_timestamp | Envelope | Action time, UTC |
| received_timestamp | Collector envelope | Arrival time, UTC |
| event_date | First 10 characters of canonical event timestamp | Activity calendar date |
| user_id | Authenticated ID, otherwise verified identity bridge | Canonical account or NULL |
| anonymous_id | Envelope | Browser anonymous identity |
| product_id, site_id | Envelope, validated | Product and tenant context |
| event_name | Envelope, validated against registry | Action contract |
| feature_id | Event definitions | Stable feature grouping |
| is_eligible | Event definitions v1 | Whether action qualifies for activity |
| is_bot | Envelope (demo) | Automation flag; production needs trusted detection |
| is_internal | User snapshot | Employee/test exclusion |
| definition_version | Event definition | v1 only in this package |
| properties | Source JSON | Product-specific attributes |

platform and schema_version are retained in Bronze; schema_version is validated but neither is materialized in Silver. Add them as typed Silver columns for device/platform reporting. There is no independent ingested_timestamp in this demo; received_timestamp is the replay clock. Production should preserve event, collection, lake ingestion, and processing timestamps separately.

## Gold measures

eligible_event_count counts eligible deduplicated events; first_activity_at/last_activity_at are event timestamps. Gold daily rows exist only for active combinations, not for every user/calendar-day pair. Missing rows mean no known qualifying activity, which can also reflect upstream incompleteness. Join a date spine for explicit zeros after completeness checks.

active_days is the number of user/product/day rows in a month (sites already collapsed). The version is always v1; if several versions coexist, count distinct dates within the intended definition rather than summing versioned memberships blindly.

Session observed_span_seconds is time between first and last event. A one-event session has zero observed span; this does not mean zero time spent. No DAU/MAU ratios are precomputed. Compute the ratio from separately defined distinct-user windows.

## Dimension relationships

users.user_id 1 → many silver_event.user_id (nullable on events)
products.product_id 1 → many silver_event.product_id
sites.site_id 1 → many silver_event.site_id
sites.organization_id groups sites into customer organizations
(product_id,event_name) in event_definitions 1 → many Silver events, v1 only
identities.anonymous_id + validity interval maps anonymous events to users as of learned time

User, site and contract snapshots are static. A historical change to is_internal, site organization or eligibility would otherwise rewrite history. A production model must choose event-time SCD2 semantics versus intentionally restated current semantics and preserve the chosen definition snapshot per release.
