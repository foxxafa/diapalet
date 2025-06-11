from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime
import os
import mysql.connector as mysql
from contextlib import contextmanager

# -----------------------------------------------------------------------------
# Basic configuration – use environment variables for sensitive information
# -----------------------------------------------------------------------------
app = Flask(__name__)
CORS(app)

@contextmanager
def get_db():
    """Provides a transactional database connection and cursor."""
    conn = mysql.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        user=os.environ.get("DB_USER", "root"),
        password=os.environ.get("DB_PASSWORD", "123456"),
        database=os.environ.get("DB_NAME", "diapalet_test"),
    )
    cur = conn.cursor(dictionary=True)
    try:
        yield conn, cur
        conn.commit()
    except mysql.Error as err:
        conn.rollback()
        # In a real app, you'd want to log this error.
        print(f"Database transaction failed: {err}")
        # Re-raise the exception to be handled by the caller or Flask's error handler
        raise
    finally:
        cur.close()
        conn.close()

# -----------------------------------------------------------------------------
# Helper utilities
# -----------------------------------------------------------------------------

def query_one(sql: str, params: tuple = ()):
    with get_db() as (_, cur):
        cur.execute(sql, params)
        return cur.fetchone()

def query_all(sql: str, params: tuple = ()):
    with get_db() as (_, cur):
        cur.execute(sql, params)
        return cur.fetchall()

def execute(sql: str, params: tuple = ()):
    with get_db() as (conn, cur):
        cur.execute(sql, params)
        return cur.lastrowid

# -----------------------------------------------------------------------------
# API v1 – master data
# -----------------------------------------------------------------------------

def _get_all_locations():
    return query_all(
        "SELECT id, name, code FROM locations WHERE is_active = 1 ORDER BY name"
    )

@app.route("/v1/locations", methods=["GET"])
def get_locations():
    return jsonify(_get_all_locations())

@app.route("/v1/locations/source", methods=["GET"])
def get_source_locations():
    return jsonify(_get_all_locations())

@app.route("/v1/locations/target", methods=["GET"])
def get_target_locations():
    return jsonify(_get_all_locations())

@app.route("/v1/products/dropdown", methods=["GET"])
def get_products_for_dropdown():
    rows = query_all("SELECT UrunId AS id, UrunAdi AS name, StokKodu AS code FROM urunler WHERE aktif = 1 ORDER BY UrunAdi")
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
        SELECT s.id, u.UrunAdi AS productName, s.urun_id AS productId,
               s.miktar AS orderedQuantity, s.birim AS unit
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

def _create_goods_receipt(data):
    header = data.get("header")
    items = data.get("items", [])
    if not header or not items:
        return {"error": "Invalid payload"}, 400

    employee_id = header.get("employee_id")
    siparis_id = header.get("siparis_id")
    invoice_number = header.get("invoice_number")
    receipt_date = header.get("receipt_date") or datetime.utcnow().isoformat()

    try:
        with get_db() as (conn, cur):
            # Insert header
            cur.execute(
                """
                INSERT INTO goods_receipts (siparis_id, invoice_number, employee_id, receipt_date, created_at)
                VALUES (%s, %s, %s, %s, NOW())
                """,
                (siparis_id, invoice_number, employee_id, receipt_date),
            )
            receipt_id = cur.lastrowid

            # Insert items and update stock
            for item in items:
                urun_id = item["urun_id"]
                qty = item.get("quantity", 0)
                pallet_barcode = item.get("pallet_barcode")
                cur.execute(
                    """
                    INSERT INTO goods_receipt_items (receipt_id, urun_id, quantity_received, pallet_barcode)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (receipt_id, urun_id, qty, pallet_barcode),
                )
                # MAL KABUL location id is assumed to be 1
                upsert_stock(cur, urun_id, 1, qty, pallet_barcode)

            # If an order is associated, update its status
            if siparis_id:
                if invoice_number:
                    cur.execute(
                        "UPDATE satin_alma_siparis_fis SET status = 1, invoice = %s, updated_at = NOW() WHERE id = %s",
                        (invoice_number, siparis_id)
                    )
                else:
                    cur.execute(
                        "UPDATE satin_alma_siparis_fis SET status = 1, updated_at = NOW() WHERE id = %s",
                        (siparis_id,)
                    )
        return {"receipt_id": receipt_id}, 201
    except mysql.Error as err:
        # The error is already printed by the context manager
        return {"error": f"Database error occurred."}, 500

@app.route("/v1/goods-receipts", methods=["POST"])
def post_goods_receipt():
    data = request.get_json(force=True)
    result, status_code = _create_goods_receipt(data)
    return jsonify(result), status_code

# -----------------------------------------------------------------------------
# Pallet Operations (Placeholder)
# -----------------------------------------------------------------------------

@app.route("/v1/pallets", methods=["POST"])
def create_pallet():
    return jsonify({"status": "ok", "pallet_id": f"PALLET_{datetime.utcnow().timestamp()}"}), 201

@app.route("/v1/pallets/<string:pallet_id>/items", methods=["POST"])
def add_items_to_pallet(pallet_id):
    return jsonify({"status": "ok"}), 200

# -----------------------------------------------------------------------------
# Transfer operations (box or pallet)
# -----------------------------------------------------------------------------

def _create_transfer(data):
    header = data.get("header")
    items = data.get("items", [])
    if not header or not items:
        return {"error": "Invalid payload"}, 400

    operation_type = header.get("operation_type")
    src_id = header.get("source_location_id") # Changed from name to ID
    dst_id = header.get("target_location_id") # Changed from name to ID
    pallet_barcode = header.get("pallet_id")
    employee_id = header.get("employee_id")
    transfer_date = header.get("transfer_date") or datetime.utcnow().isoformat()

    if not src_id or not dst_id:
         return {"error": "Invalid source/target location ID"}, 400

    try:
        with get_db() as (conn, cur):
            if operation_type in ("pallet", "pallet_transfer"):
                cur.execute(
                    "UPDATE inventory_stock SET location_id = %s, updated_at = NOW() WHERE location_id = %s AND pallet_barcode = %s",
                    (dst_id, src_id, pallet_barcode),
                )
                # Log transfer for each item on the pallet
                for item in items:
                    cur.execute(
                        """
                        INSERT INTO inventory_transfers (urun_id, from_location_id, to_location_id, quantity, pallet_barcode, employee_id, transfer_date)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """,
                        (item["product_id"], src_id, dst_id, item["quantity"], pallet_barcode, employee_id, transfer_date),
                    )
            else: # Box transfer
                for item in items:
                    urun_id = item["product_id"]
                    qty = item["quantity"]
                    cur.execute(
                        """
                        INSERT INTO inventory_transfers (urun_id, from_location_id, to_location_id, quantity, pallet_barcode, employee_id, transfer_date)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """,
                        (urun_id, src_id, dst_id, qty, None, employee_id, transfer_date),
                    )
                    upsert_stock(cur, urun_id, src_id, -qty, None)
                    upsert_stock(cur, urun_id, dst_id, qty, None)
        return {"status": "success"}, 200
    except mysql.Error as err:
        return {"error": "Database error occurred."}, 500

@app.route("/v1/transfers", methods=["POST"])
def post_transfer():
    data = request.get_json(force=True)
    result, status_code = _create_transfer(data)
    return jsonify(result), status_code

# -----------------------------------------------------------------------------
# Helper to update stock (now requires a cursor)
# -----------------------------------------------------------------------------

def upsert_stock(cur, urun_id: int, location_id: int, qty: float, pallet_barcode: str | None):
    """Insert/update stock row using a provided cursor to support transactions."""
    if pallet_barcode is None:
        cur.execute(
            "SELECT id, quantity FROM inventory_stock WHERE urun_id = %s AND location_id = %s AND pallet_barcode IS NULL",
            (urun_id, location_id),
        )
    else:
        cur.execute(
            "SELECT id, quantity FROM inventory_stock WHERE urun_id = %s AND location_id = %s AND pallet_barcode = %s",
            (urun_id, location_id, pallet_barcode),
        )
    row = cur.fetchone()

    if row:
        new_qty = (row["quantity"] or 0) + qty
        if new_qty <= 0:
            cur.execute("DELETE FROM inventory_stock WHERE id = %s", (row["id"],))
        else:
            cur.execute("UPDATE inventory_stock SET quantity = %s, updated_at = NOW() WHERE id = %s", (new_qty, row["id"]))
    elif qty > 0:
        cur.execute(
            "INSERT INTO inventory_stock (urun_id, location_id, quantity, pallet_barcode, updated_at) VALUES (%s, %s, %s, %s, NOW())",
            (urun_id, location_id, qty, pallet_barcode),
        )

# -----------------------------------------------------------------------------
# Device Sync endpoints
# -----------------------------------------------------------------------------

@app.route("/api/register_device", methods=["POST"])
def register_device():
    device_id = request.get_json(force=True).get("device_id")
    return jsonify({"device_id": device_id, "status": "registered"}), 200

@app.route("/api/sync/upload", methods=["POST"])
def sync_upload():
    # This function now correctly uses the transactional _create functions
    payload = request.get_json(force=True)
    operations = payload.get("operations", [])
    for op in operations:
        op_type = op.get("operation_type")
        data = op.get("operationData", {})
        try:
            if op_type == "goods_receipt":
                _create_goods_receipt({
                    "header": {
                        "invoice_number": data.get("invoice_number"),
                        "receipt_date": data.get("receipt_date"),
                        "employee_id": data.get("employee_id", 1),
                        "siparis_id": data.get("siparis_id")
                    },
                    "items": data.get("items", [])
                })
            elif op_type in ("pallet_transfer", "box_transfer"):
                _create_transfer({
                    "header": {
                        "operation_type": op_type,
                        "source_location_id": data.get("source_location_id"),
                        "target_location_id": data.get("target_location_id"),
                        "pallet_id": data.get("pallet_id"),
                        "transfer_date": data.get("transfer_date"),
                        "employee_id": data.get("employee_id", 1)
                    },
                    "items": data.get("items", [])
                })
        except Exception as e:
            # In a real app, log this failure and perhaps store it for retry
            print(f"Failed to process uploaded operation: {op_type}, error: {e}")
            continue # Continue to next operation
    return jsonify({"success": True}), 200

@app.route("/api/sync/download", methods=["POST"])
def sync_download():
    payload = request.get_json(force=True)
    last_sync_iso = payload.get("last_sync")
    try:
        last_sync_dt = datetime.fromisoformat(last_sync_iso.replace("Z", "+00:00")) if last_sync_iso else None
    except (ValueError, TypeError):
        last_sync_dt = None

    def _build_inc_clause(columns: list[str]):
        if not last_sync_dt or not columns: return "", ()
        conds = [f"{col} >= %s" for col in columns]
        return " WHERE " + " OR ".join(conds), tuple([last_sync_dt] * len(conds))

    def _fetch(sql: str, params: tuple = ()):
        return query_all(sql, params)

    try:
        inc_clause_ts, inc_params_ts = _build_inc_clause(["created_at", "updated_at"])
        inc_clause_up, inc_params_up = _build_inc_clause(["updated_at"])
        inc_clause_cr, inc_params_cr = _build_inc_clause(["created_at"])
        inc_clause_dt, inc_params_dt = _build_inc_clause(["transfer_date"])

        employees = _fetch(f"SELECT id, first_name, last_name, role, is_active, created_at, updated_at FROM employees {inc_clause_ts}", inc_params_ts)
        products = _fetch(f"SELECT UrunId AS id, StokKodu AS code, UrunAdi AS name, aktif AS is_active, created_at, updated_at FROM urunler {inc_clause_ts}", inc_params_ts)
        locations = _fetch(f"SELECT id, name, code, is_active, latitude, longitude, address, description, created_at, updated_at FROM locations {inc_clause_ts}", inc_params_ts)
        
        purchase_orders = _fetch(f"SELECT id, po_id, tarih, status, notlar, user, created_at, updated_at, gun, lokasyon_id, invoice, delivery FROM satin_alma_siparis_fis {inc_clause_ts}", inc_params_ts)
        purchase_order_items = _fetch("SELECT id, siparis_id, urun_id, miktar, birim FROM satin_alma_siparis_fis_satir") # No timestamp, full sync
        
        # NOTE: Excluded `created_at` as client DB doesn't have it.
        goods_receipts = _fetch(f"SELECT id, siparis_id, invoice_number, employee_id, receipt_date FROM goods_receipts {inc_clause_cr}", inc_params_cr)
        
        if last_sync_dt and goods_receipts:
            receipt_ids = [r["id"] for r in goods_receipts]
            placeholders = ",".join(["%s"] * len(receipt_ids))
            goods_receipt_items = _fetch(f"SELECT id, receipt_id, urun_id, quantity_received, pallet_barcode FROM goods_receipt_items WHERE receipt_id IN ({placeholders})", tuple(receipt_ids))
        else:
            goods_receipt_items = _fetch("SELECT id, receipt_id, urun_id, quantity_received, pallet_barcode FROM goods_receipt_items")
        
        inventory_stock = _fetch(f"SELECT id, urun_id, location_id, quantity, pallet_barcode, updated_at FROM inventory_stock {inc_clause_up}", inc_params_up)
        inventory_transfers = _fetch(f"SELECT id, urun_id, from_location_id, to_location_id, quantity, pallet_barcode, employee_id, transfer_date FROM inventory_transfers {inc_clause_dt}", inc_params_dt)

        # Using singular keys to match client-side table names
        data = {
            "employee": employees,
            "product": products,
            "location": locations,
            "purchase_order": purchase_orders,
            "purchase_order_item": purchase_order_items,
            "goods_receipt": goods_receipts,
            "goods_receipt_item": goods_receipt_items,
            "inventory_stock": inventory_stock,
            "inventory_transfer": inventory_transfers,
        }
        return jsonify({"success": True, "data": data}), 200
    except mysql.Error as err:
        return jsonify({"success": False, "error": "Database download failed."}), 500

# -----------------------------------------------------------------------------
# Container/Pallet Endpoints
# -----------------------------------------------------------------------------

@app.route("/v1/containers/<string:location>/ids", methods=["GET"])
def get_container_ids(location):
    mode = request.args.get("mode", "pallet").strip()
    loc_row = query_one("SELECT id FROM locations WHERE name = %s", (location,))
    if not loc_row:
        return jsonify({"error": "Location not found"}), 404
    loc_id = loc_row["id"]

    if mode == "pallet":
        rows = query_all(
            "SELECT DISTINCT pallet_barcode AS id FROM inventory_stock WHERE location_id = %s AND pallet_barcode IS NOT NULL",
            (loc_id,),
        )
        return jsonify([str(r["id"]) for r in rows])
    else:  # Box mode returns full item details now
        rows = query_all(
            """
            SELECT s.urun_id AS productId, u.UrunAdi AS productName, u.StokKodu as productCode, SUM(s.quantity) AS quantity
            FROM inventory_stock s
            JOIN urunler u ON u.UrunId = s.urun_id
            WHERE s.location_id = %s AND s.pallet_barcode IS NULL
            GROUP BY s.urun_id, u.UrunAdi, u.StokKodu
            """,
            (loc_id,),
        )
        return jsonify(rows)

@app.route("/v1/containers/<string:container_id>/contents", methods=["GET"])
def get_container_contents(container_id):
    # This endpoint is now primarily for pallets. Box contents are fetched via get_container_ids.
    mode = request.args.get("mode", "pallet").strip()
    if mode != "pallet":
        return jsonify([]) # Or return an error, but returning empty is safer for the client.

    rows = query_all(
        """
        SELECT u.UrunAdi AS productName, s.urun_id AS productId, s.quantity
        FROM inventory_stock s
        JOIN urunler u ON u.UrunId = s.urun_id
        WHERE s.pallet_barcode = %s
        """,
        (container_id,),
    )
    return jsonify(rows)

# -----------------------------------------------------------------------------
# Start the app
# -----------------------------------------------------------------------------

if __name__ == "__main__":
    # Use 0.0.0.0 to make it accessible on your local network
    app.run(host="0.0.0.0", port=5000, debug=True)