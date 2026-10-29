# Clickstream Analytics: a complete reference implementation



## 1. The business world

There are 41 registered users, four sites belonging to four organizations, and three products. One user is internal. A user can operate across products and sites; organization is the customer account, site is the tenant/workspace. Site plan is static in this example. User registration is separate from activity: registered users do not automatically count as active.

September and October 2026 contain deterministic synthetic behavior. User 41 has only late-arriving activity. This deliberately makes late-event effects visible in MAU rather than merely increasing an already-active user’s event count. There are 5,462 received records, including a duplicate, one unknown event, an anonymous event, a bot event, and an event arriving 65 days late. Synthetic data illustrates mechanics, not realistic growth or seasonality.

## 2. Source files and contracts

| Source | Producer | Grain | Arrival pattern |
|---|---|---|---|
| sources/events/*.jsonl | Browser/backend SDK | One received event envelope per line | Files grouped by received UTC date |
| users.csv | Account service | One account | Static snapshot for this demo |
| sites.csv | Tenant service | One site | Static snapshot |
| products.csv | Product registry | One product | Static snapshot |
| event_definitions.csv | Product analytics owners | Product + event name, v1 | Controlled definition deployment |
| identities.csv | Verified login service | Anonymous ID + valid time interval | Includes learned_at, so links can arrive late |

Events contain source_system, event_id, event_timestamp, received_timestamp, user_id (nullable), anonymous_id, product_id, site_id, event_name, schema_version, is_bot, platform, and properties. Timestamps are canonical UTC strings with seconds and a Z suffix. Event time determines reporting date; received time controls arrival replay. A source must keep the same ID and immutable payload on retries. Event IDs are unique within source_system. In a production SDK contract, receipt time must be assigned by the collection service, not trusted from the client.

Properties retain object context. Do not send document bodies, message contents, tokens, or unnecessary PII into analytics. Consent enforcement belongs before collection; downstream suppression and deletion must also be supported.

Supported events: page_view (navigation), content_created (creation), content_shared (sharing), heartbeat (system). The first three qualify as activity; heartbeat does not. All events are valid in all three fictional products. Unknown events go to quarantine pending contract review.

## 3. End-to-end processing

**Collection → Bronze → Silver → Gold → executive reports.**

1. Read arrived records from JSONL files using received_timestamp <= the requested cutoff. Persist each source file + line once in bronze_event. Retain its complete JSON payload.
2. Validate required keys, timestamp parsing, UTC suffix, schema version, dimensions, event contract, and event-time ordering. Invalid records stay in Bronze and also appear in quarantine with a reason.
3. Deduplicate valid records by (source_system, event_id), taking the earliest received record. The fixture duplicate has the same payload. Production must detect conflicting payloads and alert rather than silently accepting the first.
4. Keep authenticated user_id. Otherwise apply an available verified anonymous mapping only if the event timestamp falls in [valid_from, valid_to). A mapping is available only after learned_at. Ambiguous mappings leave the event unattributed; production should additionally raise an identity-conflict signal.
5. Enrich events with feature and metric eligibility, internal user status, and definition version. Keep bots and internal events in Silver for inspection; exclude them from business marts.
6. Compare prior and rebuilt Silver rows. Record both old and new event dates for changed rows in refresh_queue. Identity corrections can therefore queue historical dates too.
7. Build tenant, user/product/day, feature/day, month, and session tables. Execute the reporting SQL and export CSVs.

The local implementation recomputes Silver and Gold from all accumulated Bronze records so its logic is easy to inspect. refresh_queue demonstrates change detection but does not drive incremental updates in this demo. It is an audit ledger of affected dates. It is not a production task queue with leases or retries.

## 4. Model and relationships

| Layer / table | Grain / logical unique key | Purpose |
|---|---|---|
| bronze_event | file_name + line_number | Immutable received records, including duplicate envelopes |
| quarantine | file_name + line_number per rebuild | Invalid source rows and reasons |
| silver_event | source_system + event_id | Deduplicated, standardized, enriched event |
| silver_session | user + product + site + session_number | Derived visit from eligible events |
| dim_site | site_id | Organization and plan context |
| gold_user_product_site_day | UTC date + user + product + site + definition_version | Tenant-aware activity |
| gold_user_product_day | UTC date + user + product + definition_version | Product activity with sites collapsed |
| gold_user_feature_day | UTC date + user + product + feature | Feature adoption |
| gold_user_product_month | calendar month + user + product + definition_version | Monthly active membership and active days |
| refresh_queue | run_id + event_date + reason | Changes requiring downstream refresh |
| pipeline_run | run_id (cutoff in demo) | Counts and success state |

Dimensions users, products, and event definitions are loaded from CSV into Python lookup maps. Identity mappings are also loaded from CSV, not persisted as a SQLite bridge table. Site is materialized because an executive query joins it. In a warehouse, materialize all of these as governed reference tables.

Join silver_event.site_id → dim_site.site_id, and user_id/product_id to their source dimensions. A user-to-site membership relationship is not inferred from account registration; activity identifies where the action occurred. Tenant-wide security still requires an authoritative membership table. Logical keys on CTAS Gold tables are documented, not physically enforced by SQLite constraints.

## 5. Metric definitions

All business metrics exclude bots, internal users, unknown users, and ineligible events. Anonymous events remain visible in Silver; verified later attribution can add them to Gold.

| Metric | Definition | Caution |
|---|---|---|
| DAU | Distinct eligible users on a UTC day | Never sum site DAUs for a product |
| Calendar-month MAU | Distinct eligible users within a UTC calendar month | Different from trailing 30-day MAU |
| Company MAU | Distinct users across all three products in the month | Never sum product MAUs |
| Cross-product MAU | Users active in at least two distinct products during a month | Products need not be used on the same day |
| Feature adoption | Monthly feature users / monthly product active users | Not a percentage of all registered or entitled users |
| Monthly retention | September product users active in the same product in October / September product users | Latest incomplete next month must not be presented as final |
| Active days | Distinct active UTC dates per user/product/month | Derived after collapsing sites |
| Funnel conversion | First qualifying October 1–30 view per user/product/site followed by create within 24 hours | Unit is user/product/site entry; not distinct people or sessions |

Sessions use eligible events, partitioned by user/product/site. A new session starts after a gap strictly greater than 30 minutes. Sessions can cross midnight. Session span is last event minus first event, not measured attention time. Local sequential session numbers can change after late events and must not be used as permanent external IDs. Platform/device boundaries and tab behavior are intentionally not modeled.

The funnel ends entry selection October 30 to allow a full next-day outcome window in October data. It uses the first entry only, not every repeated attempt. A page_view and content_created at the same timestamp do not count as ordered conversion.

## 6. Late arrivals and corrections

The key distinction: **ingest by arrival, report by event time**. Nothing is automatically discarded because it is old in this implementation.

| Scenario | Event time | Arrival / discovery | Correct effect |
|---|---|---|---|
| Normal event | Oct 31 | Seconds later | Update Oct 31 and October |
| late-boundary | Oct 31 23:55 UTC | Nov 3 23:55 UTC | Add u041 to October TeamDocs MAU, not November |
| anonymous-link | Oct 31 11:00 UTC | Event on Oct 31; link learned Nov 3 | Attribute historical event to u001; refresh October activity |
| late-very-old | Sep 2 | Nov 6 | Rebuild September PlanBoard membership and dependent retention |
| Duplicate retry | Sep 1 | Nov 4 | Bronze grows; Silver and activity counts stay unchanged |

A fixed three-day lookback alone misses the 65-day event and old identity correction. For production use a durable change ledger:

1. Persist every newly accepted or changed event with old/new event date and attribution keys. Upsert it into Silver on the composite event key.
2. Collect distinct affected dates and old/new user/product/site keys. Identity changes can expand this set beyond new-event dates.
3. Read **all eligible Silver events** for those dates, not just the late-event batch. Stage complete replacement partitions for day-level marts.
4. Replace affected date partitions atomically where practical. A MERGE must also delete stale rows that no longer exist in the corrected result. A plain upsert cannot remove an old identity’s activity.
5. Rebuild full affected calendar months from corrected daily tables. Refresh retention for affected cohort months and the preceding months whose return status depends on them.
6. For sessions, recompute the affected user/product/site event sequence. Late events can bridge sessions. For funnels, refresh the affected users and conversion windows, not only the arrival day.
7. Publish a consistent reporting release, record run IDs and per-mart completion, then acknowledge queue items. Retry unacknowledged work idempotently.

For a small MVP, rebuilding affected months is simpler than maintaining subtractive distinct counts. Do not increment MAU by the number of arriving users: first determine whether they already had qualifying activity in the month.

### Watermarks

A streaming watermark bounds state for stateful operations; it is not the source-file checkpoint and is not a blanket raw-data retention policy. If a streaming aggregate drops events outside its state horizon, the durable Bronze/Silver correction path must still repair the reporting tables. This demo uses batch replay with no streaming watermark, so it demonstrates the durable correction path directly.

### Publication policy

Proposed business policy: daily reports are provisional for seven days. Monthly reports carry a reporting_as_of timestamp, remain provisional for seven days after month-end, then are certified. Older corrections enter a controlled restatement workflow. The demo always recomputes historical truth and does not enforce certification locks. The 65-day case illustrates why older corrections still need a path. A certified report and latest-corrected report may be different versions, both with clear labels.

## 7. Executive reporting

Open Executive_Report.html for the before/after monthly metrics. SQL is in sql/executive.sql; results are under reports/<cutoff date>/. Each query is independently runnable in SQLite. Views include product MAU and active days, company and cross-product MAU, September-to-October retention, feature adoption, organization activity, a creation funnel, and daily data health.

Suggested executive layout: top row company MAU, cross-product penetration, product retention; next row product MAU trend and feature adoption; bottom row organization engagement and data freshness. Always display reporting period, as-of timestamp, metric definition version, and provisional/certified status. Adoption is behavioral use, not revenue. A revenue story needs billing/subscription facts at their own grain.

## 8. Production mapping: AWS + Databricks + dbt + Airflow

This is a proposed deployment design; no cloud resources are deployed by this package.

| Local component | Production counterpart |
|---|---|
| JSONL files grouped by received date | Collection endpoint → Kafka or object storage |
| bronze_event | Append-only Bronze Delta with ingestion metadata |
| CSV dimensions | CDC/snapshot ingestion from account, tenant, product services |
| Python validation + dedup | Incremental Spark transformations with quarantined invalid rows |
| Identity lookup | Governed identity bridge with valid time and learned time |
| Silver event table | Delta event fact with merge/change tracking strategy |
| sql/marts.sql | dbt models backed by affected-date/month refresh logic |
| refresh_queue | Durable work ledger with item states, retries and publication release ID |
| pipeline_run | Orchestration audit and monitoring tables |
| CSV reports | Semantic layer + BI dashboards |

Suggested schedule: ingest continuously or every 5 minutes; publish daily activity every 15–60 minutes; refresh monthly marts after daily partitions succeed; reconcile source-to-Bronze and Bronze-to-Silver daily. Airflow coordinates finite ingestion/transformation runs, queue claims, dbt builds, quality checks, and report release. A continuously running stream has a separate lifecycle. Use separate ingestion checkpoints per source, not one shared checkpoint.

Suggested task dependencies: ingest reference changes and events → standardize/resolve identities → calculate change set → refresh daily/feature/session models → refresh monthly/retention/funnel outputs → validate → publish release → acknowledge work. Reference changes must be versioned so reruns have reproducible definitions.

At scale, choose layout based on measured access patterns and data volume; do not partition by high-cardinality user ID. Keep long raw history separate from compact daily activity. Avoid blindly collecting the entire identity map into driver memory as this local implementation does.

## 9. Governance, quality and operations

Ownership: product engineers own event contracts and collector reliability; account service owns identities; data engineering owns ingestion and refresh; analytics owns activity definitions; security governs consent and access. Event changes require contract review before becoming metric-eligible.

Required checks: source manifest counts, ingestion completeness, duplicate and conflicting-payload rate, valid event contracts, missing identity percentage, dimension mapping failures, bot/internal exclusion, event delays, logical grain uniqueness, feature users <= product MAU, cross-product MAU <= company MAU, and distinct-user reconciliation between Silver and Gold. Expected fixture counts at final cutoff: Bronze 5,462; Silver 5,460; quarantine 1. One valid duplicate accounts for the remaining record.

The bundled checks verify the important edge cases and idempotency; they are not a complete production quality suite. Parsing invalid JSON lines and missing received_timestamp before Bronze are not covered by the reference loader: production must capture raw bytes and collector metadata before JSON parsing, dead-letter malformed envelopes, and monitor transport failures.

Retry policy: preserve raw records; rerun from durable checkpoints; quarantine bad rows; alert on volume anomalies and delayed sources. Do not publish partially refreshed executive datasets. The local script is single-writer and has no recovery coordinator: Silver commits before the Gold transaction, and CSV exports are written afterward. A failure can leave inconsistent layers. Production must stage versioned outputs and switch a release pointer only after all checks pass, then acknowledge queue work.

Privacy: restrict raw identifiers, keep a governed deletion/suppression list, and propagate account deletion and consent changes through raw retention, Silver, Gold, and exports as policy requires. Immutable-for-replay is an operational design goal, not an exception to deletion obligations. The demo has no live PII and does not implement consent or deletion workflows.

## 10. Scope and extensions

Implemented: source fixtures, persistent Bronze, row validation, quarantine, deduplication, delayed identity attribution, UTC activity, site-aware and site-collapsed daily marts, feature and monthly marts, sessionization, affected-date audit, executive queries, before/after reports, and repeatable checks.

Not implemented: actual Kafka/cloud ingestion, dbt project configuration, Airflow DAGs, streaming state, source CDC, dynamic SCD2 dimensions, versioned metric history, privacy deletion execution, production queue workers, conflict-payload detection, concurrency, atomic cross-layer publication, and warehouse deployment. Those are explicitly design guidance rather than runnable components.

Next extensions: add registration/activation cohort facts; version site plan history; add entitlement and subscriptions for paid conversion; introduce metric-version-specific eligibility mapping; add experiment exposures and assignments; implement surgical replacement from refresh_queue; and publish a governed semantic layer.
