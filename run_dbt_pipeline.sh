#!/bin/bash

cd ~/Documents/code/dbt_course/der_sp

echo "============================================"
echo "  Starting dbt build workflow..."
echo "  Project: der_sp"
echo "============================================"

LOGFILE="logs/dbt_build_$(date +%Y%m%d_%H%M%S).log"

echo "Writing output to $LOGFILE"

dbt seed --target seed >> "$LOGFILE" 2>&1
dbt run --target dev >> "$LOGFILE" 2>&1
dbt test --target dev >> "$LOGFILE" 2>&1
dbt snapshot --target snapshot >> "$LOGFILE" 2>&1

echo "============================================"
echo "  dbt build finished."
echo "  Log file: $LOGFILE"
echo "  Exit code: $?"
echo "============================================"