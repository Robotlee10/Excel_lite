# POS Sync System

An offline-first Point of Sale (POS) core engine featuring idempotent database synchronization and automatic PostgreSQL stock tracking.

## Components
- `schema.sql`: PostgreSQL relational structure, indexes, and automatic stock reduction trigger.
- `server.py`: FastAPI server for processing offline batch synchronization payloads.
- `sync.js`: Client-side IndexedDB worker script managing offline order queueing and auto-syncing.

## Quickstart

### Database Setup
```bash
psql -U postgres -d pos_db -f schema.sql