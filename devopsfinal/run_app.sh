#!/bin/bash
# Small application script: reads its supporting source file and reports.
set -e
cd "$(dirname "$0")"
echo "=== App started: $(date) ==="
echo "Message : $(cat app/greeting.txt)"
echo "Commit  : $(git rev-parse --short HEAD 2>/dev/null || echo n/a)"
echo "=== App completed successfully ==="
