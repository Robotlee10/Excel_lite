# Excel Lite POS Sync System

A lightweight offline-first Point of Sale system designed for barcode-driven sales, local queueing, and safe server synchronization. The app stores pending sales in the browser with IndexedDB, retries when the internet is unavailable, and synchronizes completed orders to PostgreSQL when connectivity is restored.

## Overview

This project combines:
- A browser-based POS interface for item entry and receipt printing
- Local offline transaction storage using IndexedDB
- A FastAPI backend for receiving synced order batches
- PostgreSQL tables for products, users, orders, and stock movement tracking
- Idempotent sync logic using client_uuid to avoid duplicate inserts
- Automatic inventory deduction when order items are inserted

## Project Structure

- `index.html` – Frontend POS UI with barcode scanning, local queue, receipt print, and offline sync logic
- `server.py` – FastAPI API that exposes product data and accepts synced order payloads
- `schema.sql` – PostgreSQL schema, tables, indexes, and stock deduction trigger
- `sync.js` – Standalone browser sync helper for queueing and background syncing
- `requirements.txt` – Python dependencies for the backend
- `README.md` – Project documentation

## Key Features

- Offline sales capture with IndexedDB persistence
- Automatic retry when the browser goes offline or the backend is unavailable
- Idempotent synchronization through unique `client_uuid` values
- Product catalog loading from the backend with local caching
- Barcode input and camera-based scanning support
- Thermal receipt print layout for selected transactions
- CSV export and local transaction queue management
- PostgreSQL stock quantity reduction on each inserted order item
- Stock audit trail via `stock_movements`

## Architecture

### Frontend
The browser app is a single-page POS interface. It:
- stores sales in IndexedDB under the `orders` object store
- marks entries as `synced` when a batch has been accepted by the server
- keeps a queue of unsynced transactions while offline
- auto-attempts sync when the device reconnects or after a polling interval

### Backend
The FastAPI app provides:
- `GET /` for basic health status
- `GET /api/v1/products` to fetch products keyed by barcode
- `POST /api/v1/sync/orders` to receive a list of unsynced orders and insert them atomically

### Database
The PostgreSQL schema includes:
- `users` with cashier roles
- `categories` and `products`
- `orders` and `order_items`
- `stock_movements` for inventory audit
- a trigger that subtracts `stock_quantity` when an order item is inserted

## Requirements

- Python 3.10+
- PostgreSQL database server
- Modern browser with IndexedDB support
- Optional: PostgreSQL client such as psql

## Setup

### 1. Create PostgreSQL database

```bash
psql -U postgres -d postgres -c "CREATE DATABASE pos_db;"
```

### 2. Apply the database schema

```bash
psql -U postgres -d pos_db -f schema.sql
```

If your local PostgreSQL credential differs from the defaults, update the database connection values in `server.py` or pass them as environment variables.

### 3. Install Python dependencies

```bash
pip install -r requirements.txt
```

### 4. Start the backend

```bash
uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

### 5. Open the frontend

Serve the project folder with a static web server, or open `index.html` directly in a browser if your environment allows it. For a local static host, a common option is:

```bash
python -m http.server 5500
```

Then visit:

```text
http://localhost:5500
```

## Environment Variables

The backend reads the following environment variables:

- `DB_HOST` – PostgreSQL host, default: `localhost`
- `DB_NAME` – database name, default: `pos_db`
- `DB_USER` – PostgreSQL user, default: `postgres`
- `DB_PASS` – PostgreSQL password, default: `postgres`

Example:

```bash
set DB_HOST=localhost
set DB_NAME=pos_db
set DB_USER=postgres
set DB_PASS=postgres
```

On Linux/macOS use:

```bash
export DB_HOST=localhost
export DB_NAME=pos_db
export DB_USER=postgres
export DB_PASS=postgres
```

## API Behavior

### Product catalog

```http
GET /api/v1/products
```

Returns a barcode-indexed product dictionary:

```json
{
  "123456789": {
    "product_id": 1,
    "name": "Rice",
    "category": "Groceries",
    "price": 1500.0
  }
}
```

### Order sync

```http
POST /api/v1/sync/orders
```

Accepts a JSON array of order records with items. Each record is inserted with `ON CONFLICT (client_uuid) DO NOTHING`, which makes synchronization idempotent.

## Offline Sync Flow

1. The cashier adds items in the browser.
2. Each sale is queued in IndexedDB under the local `orders` store.
3. The browser flags unsynced orders and retries when online.
4. `syncOfflineOrders()` sends queued records to the FastAPI endpoint.
5. The server writes orders and line items into PostgreSQL.
6. The browser marks each synced order as complete in IndexedDB.

## Database Schema Highlights

### `orders`
Stores the transaction header:
- `client_uuid` – unique idempotency key
- `receipt_number` – unique receipt identifier
- `cashier_id` – related cashier
- `payment_method` – cash, card, transfer, split
- `subtotal`, `tax_amount`, `discount_amount`, `grand_total`
- `amount_paid`, `change_given`
- `created_at`

### `order_items`
Stores product line items:
- `order_id`
- `product_id`
- `quantity`
- `unit_price`
- `subtotal`

### `stock_movements`
Tracks stock changes generated by the inventory trigger for each order item.

## Important Notes

- The frontend uses `crypto.randomUUID()` for local order identifiers.
- The app depends on the backend being reachable for catalog refresh and sync.
- Product data is cached in localStorage to reduce API calls during offline use.
- This project is a practical prototype and should be hardened before production deployment with authentication, validation, audit logs, and secure configuration management.

## Deployment Considerations

For deployment, the frontend can be served as a static site and the backend can run behind a production ASGI server such as Uvicorn or Gunicorn. Database credentials should be managed as environment variables, not hardcoded in source files.

## Useful Commands

```bash
# install dependencies
pip install -r requirements.txt

# run backend
uvicorn server:app --reload --host 0.0.0.0 --port 8000

# import schema
psql -U postgres -d pos_db -f schema.sql
```

## License

This project is provided as-is for learning and local development purposes.