#!/bin/bash
# Write probe: one INSERT every 200 ms, prints only state changes and how long each state lasted.
# Usage (inside pgclient): PGPASSWORD=... bash /tmp/loop.sh [host]   (times are UTC)
HOST=${1:-acid-demo}
prev=""; start=$(date +%s.%N)
echo "$(date +%T.%3N)  writing to $HOST every 200 ms"
while true; do
  err=$(psql "host=$HOST user=app_owner dbname=appdb sslmode=require connect_timeout=2" \
         -qc "INSERT INTO ticks DEFAULT VALUES" 2>&1 >/dev/null | head -1)
  if [ -z "$err" ]; then s="OK"; else s="FAIL: ${err:0:90}"; fi
  if [ "$s" != "$prev" ]; then
    now=$(date +%s.%N)
    [ -n "$prev" ] && echo "$(date +%T.%3N)    (previous state lasted $(awk "BEGIN{printf \"%.1f\", $now-$start}")s)"
    echo "$(date +%T.%3N)  $s"
    prev=$s; start=$now
  fi
  sleep 0.2
done
