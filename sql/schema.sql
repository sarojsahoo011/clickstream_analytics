PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS bronze_event (file_name TEXT,line_number INTEGER,payload TEXT,received_at TEXT, PRIMARY KEY(file_name,line_number));
CREATE TABLE IF NOT EXISTS quarantine (file_name TEXT,line_number INTEGER,reason TEXT,payload TEXT);
CREATE TABLE IF NOT EXISTS silver_event (
 source_system TEXT,event_id TEXT,event_timestamp TEXT,received_timestamp TEXT,event_date TEXT,
 user_id TEXT,anonymous_id TEXT,product_id TEXT,site_id TEXT,event_name TEXT,feature_id TEXT,
 is_eligible INTEGER,is_bot INTEGER,is_internal INTEGER,definition_version TEXT,properties TEXT,
 PRIMARY KEY(source_system,event_id));
CREATE TABLE IF NOT EXISTS refresh_queue (run_id TEXT,event_date TEXT,reason TEXT,PRIMARY KEY(run_id,event_date,reason));
CREATE TABLE IF NOT EXISTS pipeline_run (run_id TEXT PRIMARY KEY,cutoff TEXT,bronze_count INTEGER,silver_count INTEGER,quarantine_count INTEGER,status TEXT);
