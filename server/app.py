from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime
import os
import mysql.connector as mysql

# -----------------------------------------------------------------------------
# Basic configuration – use environment variables for sensitive information
# -----------------------------------------------------------------------------

def get_db_connection():
    return mysql.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        user=os.environ.get("DB_USER", "root"),
        password=os.environ.get("DB_PASSWORD", "password"),
        database=os.environ.get("DB_NAME", "rowhub"),
        autocommit=True,
    )

app = Flask(__name__)
CORS(app)

# -----------------------------------------------------------------------------
# Helper utilities
# -----------------------------------------------------------------------------

def query_one(sql: str, params: tuple = ()):  # Expect only one row
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute(sql, params)
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row


def query_all(sql: str, params: tuple = ()):
    conn = get_db_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute(sql, params)
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows


def execute(sql: str, params: tuple = ()):  # Insert / update / delete
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute(sql, params)
    last_id = cur.lastrowid
    cur.close()
    conn.close()
    return last_id

# -----------------------------------------------------------------------------
# API v1 – master data
# -----------------------------------------------------------------------------

@app.route("/v1/locations", methods=["GET"])
def get_locations():
    rows = query_all(
        "SELECT id, name, code FROM locations WHERE is_active = 1 ORDER BY name"
    )
    return jsonify(rows)


@app.route("/v1/products/dropdown", methods=["GET"])
def get_products_for_dropdown():
    rows = query_all(
        "SELECT UrunId AS id, UrunAdi AS name, StokKodu AS code FROM urunler WHERE aktif = 1 ORDER BY UrunAdi"
    )
    return jsonify(rows)


# -----------------------------------------------------------------------------
# Purchase orders (open == status = 0)
# -----------------------------------------------------------------------------

@app.route("/v1/purchase-orders", methods=["GET"])
def get_open_purchase_orders():
    orders = query_all(
        """
        SELECT id, po_id AS purchaseOrderNumber, tarih AS orderDate, status
        FROM satin_alma_siparis_fis
        WHERE status = 0
        ORDER BY tarih DESC
        """
    )
    return jsonify(orders)


@app.route("/v1/purchase-orders/<int:order_id>/items", methods=["GET"])
def get_purchase_order_items(order_id):
    items = query_all(
        """
        SELECT s.id AS id,
               u.UrunAdi AS productName,
               s.urun_id AS productId,
               s.miktar    AS orderedQuantity,
               s.birim     AS unit
        FROM satin_alma_siparis_fis_satir s
        JOIN urunler u ON u.UrunId = s.urun_id
        WHERE s.siparis_id = %s
        """,
        (order_id,),
    )
    return jsonify(items)

# -----------------------------------------------------------------------------
# Goods receipt
# -----------------------------------------------------------------------------

@app.route("/v1/goods-receipts", methods=["POST"])
def post_goods_receipt():
    data = request.get_json(force=True)
    header = data.get("header")
    items = data.get("items", [])

    if not header or not items:
        return jsonify({"error": "Invalid payload"}), 400

    employee_id = header.get("employee_id")
    siparis_id = header.get("siparis_id")
    invoice_number = header.get("invoice_number")
    receipt_date = header.get("receipt_date") or datetime.utcnow().isoformat()

    # Insert header
    receipt_id = execute(
        """
        INSERT INTO goods_receipts (siparis_id, invoice_number, employee_id, receipt_date)
        VALUES (%s, %s, %s, %s)
        """,
        (siparis_id, invoice_number, employee_id, receipt_date),
    )

    # Insert items and update stock
    for item in items:
        urun_id = item["urun_id"]
        qty     = item.get("quantity", 0)
        pallet_barcode = item.get("pallet_barcode")
        execute(
            """
            INSERT INTO goods_receipt_items (receipt_id, urun_id, quantity_received, pallet_barcode)
            VALUES (%s, %s, %s, %s)
            """,
            (receipt_id, urun_id, qty, pallet_barcode),
        )
        # MAL KABUL location id assumed to be 1
        upsert_stock(urun_id, 1, qty, pallet_barcode)

    return jsonify({"receipt_id": receipt_id}), 201


# -----------------------------------------------------------------------------
# Transfer operations (box or pallet)
# -----------------------------------------------------------------------------

@app.route("/v1/transfers", methods=["POST"])
def post_transfer():
    data = request.get_json(force=True)
    header = data.get("header")
    items = data.get("items", [])

    if not header or not items:
        return jsonify({"error": "Invalid payload"}), 400

    operation_type  = header.get("operation_type")  # pallet or box
    src_name        = header.get("source_location")
    dst_name        = header.get("target_location")
    pallet_barcode  = header.get("pallet_id")
    employee_id     = header.get("employee_id")
    transfer_date   = header.get("transfer_date") or datetime.utcnow().isoformat()

    # Map location names to IDs
    src = query_one("SELECT id FROM locations WHERE name = %s", (src_name,))
    dst = query_one("SELECT id FROM locations WHERE name = %s", (dst_name,))
    if not src or not dst:
        return jsonify({"error": "Invalid source/target location"}), 400

    transfer_id = execute(
        """
        INSERT INTO inventory_transfers (urun_id, from_location_id, to_location_id, quantity, pallet_barcode, employee_id, transfer_date)
        VALUES (0, %s, %s, 0, %s, %s, %s)
        """,
        (src["id"], dst["id"], pallet_barcode, employee_id, transfer_date),
    )

    # Insert detail lines & adjust stock
    for item in items:
        urun_id = item["product_id"]
        qty     = item["quantity"]
        execute(
            """
            INSERT INTO inventory_transfers (urun_id, from_location_id, to_location_id, quantity, pallet_barcode, employee_id, transfer_date)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (urun_id, src["id"], dst["id"], qty, pallet_barcode, employee_id, transfer_date),
        )
        upsert_stock(urun_id, src["id"], -qty, pallet_barcode)
        upsert_stock(urun_id, dst["id"],  qty, pallet_barcode)

    return jsonify({"transfer_id": transfer_id}), 200


# -----------------------------------------------------------------------------
# Helper to update stock (insert or increment)
# -----------------------------------------------------------------------------

def upsert_stock(urun_id: int, location_id: int, qty: float, pallet_barcode: str | None):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO inventory_stock (urun_id, location_id, quantity, pallet_barcode)
        VALUES (%s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE quantity = quantity + VALUES(quantity), updated_at = NOW()
        """,
        (urun_id, location_id, qty, pallet_barcode),
    )
    conn.commit()
    cur.close()
    conn.close()

# -----------------------------------------------------------------------------
# Device Registration & Sync endpoints
# -----------------------------------------------------------------------------

@app.route("/api/register_device", methods=["POST"])
def register_device():
    payload = request.get_json(force=True)
    device_id = payload.get("device_id")
    # Here you would store device info to a table (devices). For brevity, we just echo success.
    return jsonify({"device_id": device_id, "status": "registered"}), 200


@app.route("/api/sync/upload", methods=["POST"])
def sync_upload():
    payload = request.get_json(force=True)
    operations = payload.get("operations", [])
    for op in operations:
        op_type = op.get("operation_type")
        if op_type == "goods_receipt":
            # Reuse post_goods_receipt logic by delegating
            post_goods_receipt()
        elif op_type in ("pallet_transfer", "box_transfer"):
            post_transfer()
        else:
            continue
    return jsonify({"success": True}), 200


@app.route("/api/sync/download", methods=["POST"])
def sync_download():
    payload = request.get_json(force=True)
    # For simplicity always return full master data
    products = query_all(
        "SELECT UrunId AS id, UrunAdi AS name, StokKodu AS code FROM urunler WHERE aktif = 1"
    )
    locations = query_all(
        "SELECT name FROM locations WHERE is_active = 1"
    )
    return jsonify({"success": True, "data": {"products": products, "locations": locations}}), 200

@app.route("/v1/containers/<string:location>/ids", methods=["GET"])
def get_container_ids(location):
    mode = request.args.get("mode", "pallet")
    loc_row = query_one("SELECT id FROM locations WHERE name = %s", (location,))
    if not loc_row:
        return jsonify({"error": "Location not found"}), 404
    loc_id = loc_row["id"]
    if mode == "pallet":
        rows = query_all(
            "SELECT DISTINCT pallet_barcode AS id FROM inventory_stock WHERE location_id = %s AND pallet_barcode IS NOT NULL",
            (loc_id,),
        )
    else:  # box flow, return product IDs as container IDs
        rows = query_all(
            "SELECT DISTINCT urun_id AS id FROM inventory_stock WHERE location_id = %s AND pallet_barcode IS NULL",
            (loc_id,),
        )
    return jsonify([r["id"] for r in rows])


@app.route("/v1/containers/<string:container_id>/contents", methods=["GET"])
def get_container_contents(container_id):
    mode = request.args.get("mode", "pallet")
    if mode == "pallet":
        rows = query_all(
            """
            SELECT u.UrunAdi AS productName, s.urun_id AS productId, s.quantity
            FROM inventory_stock s
            JOIN urunler u ON u.UrunId = s.urun_id
            WHERE s.pallet_barcode = %s
            """,
            (container_id,),
        )
    else:  # box mode (container_id is product id) – return total at each location
        rows = query_all(
            """
            SELECT u.UrunAdi AS productName, s.location_id, l.name AS locationName, s.quantity
            FROM inventory_stock s
            JOIN urunler u ON u.UrunId = s.urun_id
            JOIN locations l ON l.id = s.location_id
            WHERE s.urun_id = %s AND s.pallet_barcode IS NULL
            """,
            (container_id,),
        )
    return jsonify(rows)

# -----------------------------------------------------------------------------
# Start the app (only for local dev)
# -----------------------------------------------------------------------------

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True) 