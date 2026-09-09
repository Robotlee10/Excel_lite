-- ==============================================================================
-- MASTER SUPABASE POS DATABASE INITIALIZATION SCRIPT WITH RLS
-- ==============================================================================

-- 1. ENUMS FOR STRICT DATA TYPES
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('cashier', 'manager', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer', 'split');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM ('completed', 'refunded', 'voided');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE stock_movement_type AS ENUM ('sale', 'restock', 'adjustment', 'return');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- 2. USERS / CASHIERS TABLE
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    pin_hash VARCHAR(255) NOT NULL,
    role user_role DEFAULT 'cashier',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


-- 3. CATEGORIES & PRODUCTS
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    barcode VARCHAR(64) UNIQUE,
    name VARCHAR(150) NOT NULL,
    category_id INT REFERENCES categories(id) ON DELETE SET NULL,
    price NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    cost_price NUMERIC(12, 2) NOT NULL CHECK (cost_price >= 0),
    stock_quantity INT NOT NULL DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


-- 4. ORDERS (TRANSACTION HEADERS)
CREATE TABLE IF NOT EXISTS orders (
    id BIGSERIAL PRIMARY KEY,
    client_uuid UUID UNIQUE, -- Ensures idempotent offline syncing
    receipt_number VARCHAR(50) UNIQUE NOT NULL,
    cashier_id INT REFERENCES users(id) ON DELETE RESTRICT,
    status order_status DEFAULT 'completed',
    subtotal NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    tax_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    discount_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    grand_total NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    payment_method payment_method NOT NULL DEFAULT 'cash',
    amount_paid NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    change_given NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


-- 5. ORDER ITEMS (LINE ITEMS IN CART)
CREATE TABLE IF NOT EXISTS order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL,
    subtotal NUMERIC(12, 2) NOT NULL
);


-- 6. AUDIT LOG: TRANSACTION VOIDS & CANCELLATIONS
CREATE TABLE IF NOT EXISTS transaction_voids (
    id SERIAL PRIMARY KEY,
    client_uuid UUID UNIQUE NOT NULL, -- Prevents duplicate void syncing
    receipt_number VARCHAR(50),
    item_name VARCHAR(255) NOT NULL,
    category VARCHAR(100) DEFAULT 'General',
    quantity NUMERIC(10,2) NOT NULL,
    price NUMERIC(12, 2) NOT NULL,
    grand_total NUMERIC(12, 2) NOT NULL,
    cashier_name VARCHAR(100) DEFAULT 'Admin',
    receipt_printed BOOLEAN DEFAULT FALSE,
    voided_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


-- 7. STOCK TRACKING & AUDIT LOG
CREATE TABLE IF NOT EXISTS stock_movements (
    id BIGSERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id) ON DELETE CASCADE,
    movement_type stock_movement_type NOT NULL,
    quantity_change INT NOT NULL,
    reference_id BIGINT,
    user_id INT REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


-- ==============================================================================
-- INDEXES FOR HIGH-PERFORMANCE SEARCH & SYNCING
-- ==============================================================================
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode) WHERE is_active IS TRUE;
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_client_uuid ON orders(client_uuid);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_voids_cashier ON transaction_voids(cashier_name);
CREATE INDEX IF NOT EXISTS idx_voids_client_uuid ON transaction_voids(client_uuid);


-- ==============================================================================
-- TRIGGERS & AUTOMATED INVENTORY DEDUCTION
-- ==============================================================================
CREATE OR REPLACE FUNCTION deduct_inventory_on_order()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE products 
    SET stock_quantity = stock_quantity - NEW.quantity
    WHERE id = NEW.product_id;

    INSERT INTO stock_movements (product_id, movement_type, quantity_change, reference_id)
    VALUES (NEW.product_id, 'sale', -NEW.quantity, NEW.order_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_deduct_stock ON order_items;
CREATE TRIGGER trigger_deduct_stock
AFTER INSERT ON order_items
FOR EACH ROW
EXECUTE FUNCTION deduct_inventory_on_order();


-- ==============================================================================
-- DEFAULT SEED DATA FOR NEW DEPLOYMENTS
-- ==============================================================================
INSERT INTO users (id, full_name, pin_hash, role)
VALUES (1, 'Admin Cashier', '1234', 'admin')
ON CONFLICT (id) DO NOTHING;

INSERT INTO categories (id, name, description) VALUES 
(1, 'General', 'General store inventory'),
(2, 'Groceries', 'Food and household consumables'),
(3, 'Electronics', 'Gadgets and electronic items')
ON CONFLICT (id) DO NOTHING;


-- ==============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

-- 1. ENABLE RLS ON ALL TABLES
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaction_voids ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;


-- 2. PUBLIC / ANON ACCESS POLICIES (FRONTEND CATALOG READS)
DROP POLICY IF EXISTS "Allow public read access to active products" ON products;
CREATE POLICY "Allow public read access to active products" 
ON products FOR SELECT 
USING (is_active = TRUE);

DROP POLICY IF EXISTS "Allow public read access to categories" ON categories;
CREATE POLICY "Allow public read access to categories" 
ON categories FOR SELECT 
USING (TRUE);


-- 3. SERVICE ROLE POLICIES (FULL BACKEND ACCESS FOR FASTAPI)
DROP POLICY IF EXISTS "Allow full access to service_role on orders" ON orders;
CREATE POLICY "Allow full access to service_role on orders"
ON orders FOR ALL TO service_role
USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow full access to service_role on order_items" ON order_items;
CREATE POLICY "Allow full access to service_role on order_items"
ON order_items FOR ALL TO service_role
USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow full access to service_role on transaction_voids" ON transaction_voids;
CREATE POLICY "Allow full access to service_role on transaction_voids"
ON transaction_voids FOR ALL TO service_role
USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow full access to service_role on stock_movements" ON stock_movements;
CREATE POLICY "Allow full access to service_role on stock_movements"
ON stock_movements FOR ALL TO service_role
USING (TRUE) WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Allow full access to service_role on users" ON users;
CREATE POLICY "Allow full access to service_role on users"
ON users FOR ALL TO service_role
USING (TRUE) WITH CHECK (TRUE);