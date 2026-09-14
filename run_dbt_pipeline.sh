#!/bin/bash

cd ~/Documents/code/dbt_course/der_sp || exit 1
mkdir -p logs

echo "============================================"
echo "  Starting dbt build workflow..."
echo "  Project: der_sp"
echo "============================================"

LOGFILE="logs/dbt_build_$(date +%Y%m%d_%H%M%S).log"

echo "Writing output to $LOGFILE"

fail() {
    echo "  FAILED: $1"
    echo "  --- last 20 lines of $LOGFILE ---"
    tail -20 "$LOGFILE"
    exit 1
}

# dbt_packages/ is gitignored and dbt clean wipes it, so a fresh clone needs this first.
dbt deps >> "$LOGFILE" 2>&1 || fail "dbt deps"

dbt seed --target seed >> "$LOGFILE" 2>&1 || fail "dbt seed --target seed"
dbt run --target prod >> "$LOGFILE" 2>&1 || fail "dbt run --target prod"

# Abort before the snapshot: snapshots are append-only history, so persisting SCD
# rows built from rejected data is painful to undo.
dbt test --target prod >> "$LOGFILE" 2>&1 || fail "dbt test --target prod"
dbt snapshot --target snapshot >> "$LOGFILE" 2>&1 || fail "dbt snapshot --target snapshot"

echo "============================================"
echo "  dbt build finished successfully."
echo "  Log file: $LOGFILE"
echo "============================================"
