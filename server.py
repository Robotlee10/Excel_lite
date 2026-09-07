from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import os
import psycopg2

app = FastAPI(title="POS Sync Backend")

# --- FIXED CORS MIDDLEWARE CONFIGURATION ---
# Note: Explicit origins are required when allow_credentials=True
origins = [
    "https://excel.robotlee.xyz",
    "http://excel.robotlee.xyz",
    "http://localhost:3000",
    "http://127.0.0.1:5500",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# -------------------------------------------

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_NAME = os.getenv("DB_NAME", "pos_db")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "postgres")

def get_db():
    conn = psycopg2.connect(
        host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS
    )
    try:
        yield conn
    finally:
        conn.close()

from typing import List, Union

class OrderItemSchema(BaseModel):
    product_id: int
    quantity: Union[int, float]  # Accepts both integer and decimal quantities
    unit_price: float
    subtotal: float

class SyncOrderSchema(BaseModel):
    client_uuid: str
    receipt_number: str
    cashier_id: int
    payment_method: str
    subtotal: float
    tax_amount: float
    discount_amount: float = 0.0
    grand_total: float
    amount_paid: float
    change_given: float = 0.0
    created_at: str
    items: List[OrderItemSchema]

@app.get("/")
def read_root():
    return {"status": "online", "message": "POS Sync Backend Engine Active"}

@app.post("/api/v1/sync/orders")
def sync_orders(orders: List[SyncOrderSchema], db_conn=Depends(get_db)):
    synced_uuids = []
    
    with db_conn.cursor() as cursor:
        for order in orders:
            try:
                cursor.execute("""
                    INSERT INTO orders (
                        client_uuid, receipt_number, cashier_id, payment_method,
                        subtotal, tax_amount, discount_amount, grand_total,
                        amount_paid, change_given, created_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (client_uuid) DO NOTHING
                    RETURNING id;
                """, (
                    order.client_uuid, order.receipt_number, order.cashier_id,
                    order.payment_method, order.subtotal, order.tax_amount,
                    order.discount_amount, order.grand_total, order.amount_paid,
                    order.change_given, order.created_at
                ))
                
                result = cursor.fetchone()
                
                if result:
                    order_id = result[0]
                    for item in order.items:
                        cursor.execute("""
                            INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal)
                            VALUES (%s, %s, %s, %s, %s);
                        """, (order_id, item.product_id, item.quantity, item.unit_price, item.subtotal))
                
                synced_uuids.append(order.client_uuid)
                
            except Exception as e:
                db_conn.rollback()
                raise HTTPException(status_code=500, detail=f"Sync failed on {order.client_uuid}: {str(e)}")

        db_conn.commit()

    return {"status": "success", "synced_uuids": synced_uuids}