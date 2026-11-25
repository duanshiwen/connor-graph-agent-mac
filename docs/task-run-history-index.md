# Task run history reads

`tasks/task-run-history.jsonl` remains the complete authoritative audit log. Task refreshes read the most recent records through a disposable SQLite index alongside that file, with separate indexes for global and per-task history. Neither source records nor duplicate run IDs are removed. Ordering remains startedAt descending, finishedAt descending (nil sorts last), then source order for ties.

The index stores source identity, size and nanosecond modification/change times. A changed source is rebuilt in bounded chunks; normal repository appends update source and index under a SQLite write transaction. Invalid JSON lines are skipped as before. A final record without a newline is separated before the next append. If the index is unavailable or corrupt, reads use the original JSONL path and appends continue writing the authoritative log. The index can be deleted while the app is stopped.

The initial index build processes the existing log once. Subsequent unchanged reads decode only the requested limit, rather than repeatedly parsing the full log during calendar/task refreshes.
