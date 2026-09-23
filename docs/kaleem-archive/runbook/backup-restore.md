# Backup & Restore Runbook

## Backup (automated daily via cron)

```bash
pg_dump -U kaleem kaleem | gzip > /backups/kaleem-$(date +%Y%m%d).sql.gz
```

## Restore

```bash
gunzip < /backups/kaleem-YYYYMMDD.sql.gz | psql -U kaleem kaleem
```

## Backup drill

Every 2 months, actually restore to a scratch database and verify data integrity.

### Drill log

(none yet — first drill after staging is live)
