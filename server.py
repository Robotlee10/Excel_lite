from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict
from typing import List, Optional, Union, Any
import os
import psycopg2

app = FastAPI(title="POS Sync Backend")

# --- CORS MIDDLEWARE ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://excel.robotlee.xyz",
        "http://excel.robotlee.xyz",
        "http://localhost:3000",
        "http://127.0.0.1:5500",
        "*"
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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

class OrderItemSchema(BaseModel):
    model_config = ConfigDict(extra='ignore')  # Ignore unexpected fields
    product_id: Optional[int] = 1
    quantity: Union[float, int]
    unit_price: float
    subtotal: float

class SyncOrderSchema(BaseModel):
    model_config = ConfigDict(extra='ignore')  # Ignore unexpected fields
    client_uuid: str
    receipt_number: str
    cashier_id: Optional[int] = 1
    payment_method: Optional[str] = "cash"
    subtotal: float
    tax_amount: Optional[float] = 0.0
    discount_amount: Optional[float] = 0.0
    grand_total: float
    amount_paid: Optional[float] = 0.0
    change_given: Optional[float] = 0.0
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
                    order.client_uuid, order.receipt_number, order.cashier_id or 1,
                    order.payment_method or 'cash', order.subtotal, order.tax_amount or 0.0,
                    order.discount_amount or 0.0, order.grand_total, order.amount_paid or order.grand_total,
                    order.change_given or 0.0, order.created_at
                ))
                
                result = cursor.fetchone()
                
                if result:
                    order_id = result[0]
                    for item in order.items:
                        cursor.execute("""
                            INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal)
                            VALUES (%s, %s, %s, %s, %s);
                        """, (order_id, item.product_id or 1, item.quantity, item.unit_price, item.subtotal))
                
                synced_uuids.append(order.client_uuid)
                
            except Exception as e:
                db_conn.rollback()
                raise HTTPException(status_code=500, detail=f"Sync failed on {order.client_uuid}: {str(e)}")

        db_conn.commit()

    return {"status": "success", "synced_uuids": synced_uuids}