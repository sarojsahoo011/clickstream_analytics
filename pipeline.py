"""Python 3.10+, standard library only. File arrival replay; SQLite local reference."""
import argparse,csv,datetime as dt,json,sqlite3
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def read_csv(name):
 with (ROOT/'sources'/name).open() as f: return list(csv.DictReader(f))
def run(cutoff,db=None):
 db=Path(db) if db else ROOT/'world.sqlite'
 c=sqlite3.connect(db);c.row_factory=sqlite3.Row
 c.executescript((ROOT/'sql/schema.sql').read_text())
 old={ (r['source_system'],r['event_id']):dict(r) for r in c.execute('SELECT * FROM silver_event') }
 for path in sorted((ROOT/'sources/events').glob('*.jsonl')):
  for line,raw in enumerate(path.read_text().splitlines(),1):
   e=json.loads(raw)
   if e['received_timestamp']<=cutoff:
    c.execute('INSERT OR IGNORE INTO bronze_event VALUES(?,?,?,?)',(path.name,line,raw,e['received_timestamp']))
 c.commit()
 defs={(r['product_id'],r['event_name']):r for r in read_csv('event_definitions.csv')}
 users={r['user_id']:r for r in read_csv('users.csv')};sites={r['site_id']:r for r in read_csv('sites.csv')}
 products={r['product_id'] for r in read_csv('products.csv')}
 links=[r for r in read_csv('identities.csv') if r['learned_at']<=cutoff]
 c.execute('DELETE FROM quarantine');c.execute('DELETE FROM silver_event')
 for row in c.execute('SELECT * FROM bronze_event ORDER BY received_at,file_name,line_number').fetchall():
  e=json.loads(row['payload']);reason=None
  try:
   for k in ['source_system','event_id','event_timestamp','received_timestamp','product_id','site_id','event_name']:
    if not e.get(k): raise ValueError('missing '+k)
   for k in ['event_timestamp','received_timestamp']:
    if not e[k].endswith('Z'): raise ValueError('timestamp must use UTC Z')
    dt.datetime.fromisoformat(e[k].replace('Z','+00:00'))
   if e['schema_version']!=1: raise ValueError('unsupported schema version')
   if (e['product_id'],e['event_name']) not in defs: raise ValueError('unknown event contract')
   if e['site_id'] not in sites or e['product_id'] not in products: raise ValueError('unknown dimension')
   if e['event_timestamp']>e['received_timestamp']: raise ValueError('future event timestamp')
   if e.get('user_id') and e['user_id'] not in users: raise ValueError('unknown user')
  except (ValueError,KeyError,TypeError) as ex: reason=str(ex)
  if reason:
   c.execute('INSERT INTO quarantine VALUES(?,?,?,?)',(row['file_name'],row['line_number'],reason,row['payload']));continue
  user=e.get('user_id')
  if not user:
   matches={l['user_id'] for l in links if l['anonymous_id']==e.get('anonymous_id') and l['valid_from']<=e['event_timestamp']<l['valid_to']}
   if len(matches)==1: user=matches.pop()
  d=defs[e['product_id'],e['event_name']]
  c.execute('INSERT OR IGNORE INTO silver_event VALUES('+','.join('?'*16)+')',(
   e['source_system'],e['event_id'],e['event_timestamp'],e['received_timestamp'],e['event_timestamp'][:10],
   user,e.get('anonymous_id'),e['product_id'],e['site_id'],e['event_name'],d['feature_id'],int(d['is_eligible']),
   e['is_bot'],int(users.get(user,{}).get('is_internal',0)),d['definition_version'],json.dumps(e['properties'])))
 new={(r['source_system'],r['event_id']):dict(r) for r in c.execute('SELECT * FROM silver_event')}
 touched=set()
 for key in old.keys()|new.keys():
  if old.get(key)!=new.get(key):
   for item in [old.get(key),new.get(key)]:
    if item: touched.add(item['event_date'])
 for day in touched: c.execute('INSERT OR IGNORE INTO refresh_queue VALUES(?,?,?)',(cutoff,day,'event_or_identity_change'))
 c.execute('DROP TABLE IF EXISTS dim_site');c.execute('CREATE TABLE dim_site(site_id TEXT PRIMARY KEY,organization_id TEXT,plan TEXT)')
 c.executemany('INSERT INTO dim_site VALUES(:site_id,:organization_id,:plan)',sites.values())
 c.commit()
 # Executescript commits before executing: explicitly wrap mart publication in one transaction.
 c.executescript('BEGIN;\n'+(ROOT/'sql/marts.sql').read_text()+'\nCOMMIT;')
 stats=[c.execute('SELECT COUNT(*) FROM '+t).fetchone()[0] for t in ['bronze_event','silver_event','quarantine']]
 c.execute('INSERT OR REPLACE INTO pipeline_run VALUES(?,?,?,?,?,?)',(cutoff,cutoff,*stats,'success'));c.commit()
 out=ROOT/'reports'/cutoff[:10];out.mkdir(parents=True,exist_ok=True)
 for block in (ROOT/'sql/executive.sql').read_text().split('-- name: ')[1:]:
  name,sql=block.split('\n',1);rows=c.execute(sql).fetchall()
  with (out/(name+'.csv')).open('w',newline='') as f:
   w=csv.writer(f);w.writerow([x[0] for x in c.execute(sql).description]);w.writerows(rows)
 print(json.dumps(dict(cutoff=cutoff,bronze=stats[0],silver=stats[1],quarantine=stats[2],affected_dates=len(touched))))
 c.close();return stats
if __name__=='__main__':
 a=argparse.ArgumentParser();a.add_argument('--cutoff',default='2026-11-10T00:00:00Z');a.add_argument('--db');args=a.parse_args();run(args.cutoff,args.db)
