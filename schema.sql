-- 1. ENUMS FOR STRICT DATA TYPES
CREATE TYPE user_role AS ENUM ('cashier', 'manager', 'admin');
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer', 'split');
CREATE TYPE order_status AS ENUM ('completed', 'refunded', 'voided');
CREATE TYPE stock_movement_type AS ENUM ('sale', 'restock', 'adjustment', 'return');

-- 2. USERS / CASHIERS TABLE
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    pin_hash VARCHAR(255) NOT NULL,
    role user_role DEFAULT 'cashier',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. CATEGORIES & PRODUCTS
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

CREATE TABLE products (
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
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    client_uuid UUID UNIQUE, -- Ensures idempotent offline syncing
    receipt_number VARCHAR(50) UNIQUE NOT NULL,
    cashier_id INT REFERENCES users(id) ON DELETE RESTRICT,
    status order_status DEFAULT 'completed',
    subtotal NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    tax_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    discount_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    grand_total NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    payment_method payment_method NOT NULL,
    amount_paid NUMERIC(12, 2) NOT NULL,
    change_given NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. ORDER ITEMS (LINE ITEMS IN CART)
CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    product_id INT REFERENCES products(id) ON DELETE RESTRICT,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL,
    subtotal NUMERIC(12, 2) NOT NULL
);

-- 6. STOCK TRACKING & AUDIT LOG
CREATE TABLE stock_movements (
    id BIGSERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id) ON DELETE CASCADE,
    movement_type stock_movement_type NOT NULL,
    quantity_change INT NOT NULL,
    reference_id BIGINT,
    user_id INT REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- INDEXES
CREATE INDEX idx_products_barcode ON products(barcode) WHERE is_active IS TRUE;
CREATE INDEX idx_orders_created_at ON orders(created_at);
CREATE INDEX idx_orders_client_uuid ON orders(client_uuid);
CREATE INDEX idx_order_items_order ON order_items(order_id);

-- AUTOMATED INVENTORY DEDUCTION TRIGGER
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

CREATE TRIGGER trigger_deduct_stock
AFTER INSERT ON order_items
FOR EACH ROW
EXECUTE FUNCTION deduct_inventory_on_order();