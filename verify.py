import sqlite3,tempfile
from pathlib import Path
from pipeline import run
with tempfile.TemporaryDirectory() as d:
 db=Path(d)/'test.sqlite'
 run('2026-11-01T00:00:00Z',db)
 c=sqlite3.connect(db)
 assert c.execute("SELECT COUNT(*) FROM silver_event WHERE event_id='late-boundary'").fetchone()[0]==0
 assert c.execute("SELECT user_id FROM silver_event WHERE event_id='anonymous-link'").fetchone()[0] is None
 c.close()
 run('2026-11-10T00:00:00Z',db)
 c=sqlite3.connect(db)
 assert c.execute("SELECT event_date FROM silver_event WHERE event_id='late-boundary'").fetchone()[0]=='2026-10-31'
 assert c.execute("SELECT user_id FROM silver_event WHERE event_id='anonymous-link'").fetchone()[0]=='u001'
 assert c.execute("SELECT COUNT(*) FROM gold_user_product_month WHERE user_id='u041' AND activity_month='2026-10'").fetchone()[0]==1
 assert c.execute("SELECT COUNT(*) FROM gold_user_product_day WHERE user_id='u040'").fetchone()[0]==0
 assert c.execute("SELECT COUNT(*) FROM quarantine WHERE reason='unknown event contract'").fetchone()[0]==1
 assert c.execute("SELECT COUNT(*) FROM silver_event WHERE event_id='late-very-old'").fetchone()[0]==1
 assert c.execute("SELECT COUNT(*) FROM bronze_event").fetchone()[0]-c.execute("SELECT COUNT(*) FROM silver_event").fetchone()[0]==2
 tables=['silver_event','gold_user_product_day','gold_user_product_site_day','gold_user_product_month','silver_session']
 before={t:c.execute('SELECT * FROM '+t+' ORDER BY 1,2,3').fetchall() for t in tables};c.close()
 run('2026-11-10T00:00:00Z',db);c=sqlite3.connect(db)
 assert all(before[t]==c.execute('SELECT * FROM '+t+' ORDER BY 1,2,3').fetchall() for t in tables)
 c.close()
print('PASS: late event, old backfill, identity correction, quarantine, deduplication, internal exclusion, and replay idempotency')
