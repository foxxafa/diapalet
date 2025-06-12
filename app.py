from flask import Flask, request, jsonify, abort
from flask_cors import CORS
from datetime import datetime
import os
import mysql.connector as mysql
from contextlib import contextmanager

# -----------------------------------------------------------------------------
# Basic configuration
# -----------------------------------------------------------------------------
app = Flask(__name__)
CORS(app)

# -----------------------------------------------------------------------------
# DB helper
# -----------------------------------------------------------------------------
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
    except mysql.Error as err:
        conn.rollback()
        print(f"Database transaction failed: {err}")
        # In a real app, you'd want more robust error handling/logging
        raise
    else:
        conn.commit()
    finally:
        cur.close()
        conn.close()

# -----------------------------------------------------------------------------
# Simple query helpers
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
# Stock helper (The heart of inventory management)
# -----------------------------------------------------------------------------
def upsert_stock(cur, urun_id: int, location_id: int, qty_change: float, pallet_barcode: str | None):
    """
    Core function to adjust stock levels. Can handle positive (add) and
    negative (subtract) quantity changes. Ensures transactions.
    A new pallet is created implicitly when a pallet_barcode is used for the
    first time for a given item and location.
    """
    # Use IS NULL safe comparison for pallet_barcode
    pallet_clause = "pallet_barcode = %s" if pallet_barcode else "pallet_barcode IS NULL"
    params = [urun_id, location_id]
    if pallet_barcode:
        params.append(pallet_barcode)

    cur.execute(
        f"SELECT id, quantity FROM inventory_stock WHERE urun_id = %s AND location_id = %s AND {pallet_clause}",
        tuple(params)
    )
    stock = cur.fetchone()

    if stock:
        new_qty = (stock["quantity"] or 0) + qty_change
        if new_qty > 0.001:  # Use a small epsilon for float comparison
            cur.execute(
                "UPDATE inventory_stock SET quantity = %s, updated_at = NOW() WHERE id = %s",
                (new_qty, stock["id"])
            )
        else:
            # If quantity is zero or less, remove the stock record
            cur.execute("DELETE FROM inventory_stock WHERE id = %s", (stock["id"],))
    elif qty_change > 0:
        cur.execute(
            """
            INSERT INTO inventory_stock
                  (urun_id, location_id, quantity, pallet_barcode, updated_at)
            VALUES (%s, %s, %s, %s, NOW())
            """,
            (urun_id, location_id, qty_change, pallet_barcode)
        )
    # If qty_change is negative and no stock exists, do nothing (or raise error)
    # Current implementation silently ignores subtraction from non-existent stock.

# -----------------------------------------------------------------------------
# API v1 – Master Data & UI Support Endpoints
# -----------------------------------------------------------------------------
@app.route("/v1/locations", methods=["GET"])
def get_locations():
    return jsonify(query_all("SELECT id, name, code FROM locations WHERE is_active = 1 ORDER BY name"))

@app.route("/v1/products/dropdown", methods=["GET"])
def get_products_for_dropdown():
    return jsonify(query_all("SELECT UrunId AS id, UrunAdi AS name, StokKodu AS code FROM urunler WHERE aktif = 1 ORDER BY UrunAdi"))

@app.route("/v1/purchase-orders", methods=["GET"])
def get_open_purchase_orders():
    return jsonify(query_all("SELECT id, po_id, tarih FROM satin_alma_siparis_fis WHERE status = 0 ORDER BY tarih DESC"))

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
# API v1 - Goods Receipt Endpoints
# -----------------------------------------------------------------------------
def _create_goods_receipt(data: dict):
    header = data.get("header", {})
    items = data.get("items", [])
    if not header or not items:
        return {"error": "Invalid payload: Missing header or items"}, 400

    # Assume MAL KABUL location has ID 1
    mal_kabul_location_id = 1 

    try:
        with get_db() as (conn, cur):
            # 1. Create goods_receipt header
            cur.execute(
                """
                INSERT INTO goods_receipts (siparis_id, invoice_number, employee_id, receipt_date, created_at)
                VALUES (%s, %s, %s, %s, NOW())
                """,
                (header.get("siparis_id"), header.get("invoice_number"), header.get("employee_id"), header.get("receipt_date") or datetime.utcnow())
            )
            receipt_id = cur.lastrowid

            # 2. Insert items and update stock for each item
            for item in items:
                cur.execute(
                    """
                    INSERT INTO goods_receipt_items (receipt_id, urun_id, quantity_received, pallet_barcode)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (receipt_id, item["urun_id"], item["quantity"], item.get("pallet_barcode"))
                )
                # Add received items to stock at the "MAL KABUL" location
                upsert_stock(cur, item["urun_id"], mal_kabul_location_id, item["quantity"], item.get("pallet_barcode"))

            # 3. Update the original purchase order status to 'completed' (status=1)
            if header.get("siparis_id"):
                cur.execute(
                    "UPDATE satin_alma_siparis_fis SET status = 1, updated_at = NOW() WHERE id = %s",
                    (header["siparis_id"],)
                )
            
        return {"receipt_id": receipt_id, "status": "success"}, 201

    except mysql.Error as err:
        return {"error": f"Database error: {err}"}, 500
    except Exception as e:
        return {"error": f"An unexpected error occurred: {e}"}, 500


@app.route("/v1/goods-receipts", methods=["POST"])
def post_goods_receipt():
    data = request.get_json(force=True)
    result, status_code = _create_goods_receipt(data)
    return jsonify(result), status_code


# -----------------------------------------------------------------------------
# API v1 - Transfer Endpoints
# -----------------------------------------------------------------------------
def _create_transfer(data: dict):
    header = data.get("header", {})
    items = data.get("items", [])
    if not header or not items:
        return {"error": "Invalid payload: Missing header or items"}, 400

    op_type = header.get("operation_type") # 'pallet_transfer', 'box_transfer', 'box_from_pallet'
    src_loc_id = header.get("source_location_id")
    dst_loc_id = header.get("target_location_id")
    
    try:
        with get_db() as (conn, cur):
            # Log the parent transfer operation first (optional but good practice)
            # This part can be enhanced to create a single transfer header record if needed.

            for item in items:
                urun_id = item["product_id"]
                qty = item["quantity"]
                pallet_bc = item.get("pallet_id") # pallet_id from payload corresponds to pallet_barcode

                # Log every single item transfer for traceability
                cur.execute(
                    """
                    INSERT INTO inventory_transfers
                        (urun_id, from_location_id, to_location_id, quantity, pallet_barcode, employee_id, transfer_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (urun_id, src_loc_id, dst_loc_id, qty, pallet_bc, header.get("employee_id"), header.get("transfer_date") or datetime.utcnow())
                )

                if op_type == "pallet_transfer":
                    # For a full pallet transfer, we find all items on that pallet at the source and move them.
                    # The `items` payload should reflect all items on the pallet.
                    upsert_stock(cur, urun_id, src_loc_id, -qty, pallet_bc) # Decrease from source
                    upsert_stock(cur, urun_id, dst_loc_id, qty, pallet_bc)  # Increase at destination
                
                elif op_type == "box_from_pallet":
                    # Moving a specific quantity of a product *out* of a pallet to a new location as boxes
                    upsert_stock(cur, urun_id, src_loc_id, -qty, pallet_bc) # Decrease from pallet at source
                    upsert_stock(cur, urun_id, dst_loc_id, qty, None) # Increase as loose boxes at destination
                
                else: # op_type == "box_transfer" (or default)
                    # Moving loose boxes (non-palletized stock)
                    upsert_stock(cur, urun_id, src_loc_id, -qty, None) # Decrease from source (no pallet)
                    upsert_stock(cur, urun_id, dst_loc_id, qty, None)  # Increase at destination (no pallet)

        return {"status": "success"}, 200

    except mysql.Error as err:
        return {"error": f"Database error: {err}"}, 500
    except Exception as e:
        return {"error": f"An unexpected error occurred: {e}"}, 500


@app.route("/v1/transfers", methods=["POST"])
def post_transfer():
    data = request.get_json(force=True)
    result, status_code = _create_transfer(data)
    return jsonify(result), status_code

# -----------------------------------------------------------------------------
# API v1 - Container/Stock Query Endpoints
# -----------------------------------------------------------------------------
@app.route("/v1/containers/<int:location_id>/ids", methods=["GET"])
def get_container_ids(location_id):
    mode = request.args.get("mode", "pallet").strip()
    
    if mode == "pallet":
        # Return distinct pallet barcodes for the given location
        rows = query_all(
            "SELECT DISTINCT pallet_barcode AS id FROM inventory_stock WHERE location_id = %s AND pallet_barcode IS NOT NULL",
            (location_id,)
        )
        return jsonify([r["id"] for r in rows if r["id"]])
    else:  # box mode
        # Return products that exist as loose boxes for the given location
        rows = query_all(
            """
            SELECT s.urun_id  AS productId, u.UrunAdi AS productName,
                   u.StokKodu AS productCode, SUM(s.quantity) AS quantity
            FROM inventory_stock s
            JOIN urunler u ON u.UrunId = s.urun_id
            WHERE s.location_id = %s AND s.pallet_barcode IS NULL
            GROUP BY s.urun_id, u.UrunAdi, u.StokKodu
            """,
            (location_id,)
        )
        return jsonify(rows)

@app.route("/v1/containers/<string:pallet_barcode>/contents", methods=["GET"])
def get_container_contents(pallet_barcode):
    # This endpoint assumes pallet_barcode is globally unique, or we can add location_id
    rows = query_all(
        """
        SELECT u.UrunAdi AS productName, s.urun_id AS productId, s.quantity
        FROM inventory_stock s
        JOIN urunler u ON u.UrunId = s.urun_id
        WHERE s.pallet_barcode = %s
        """,
        (pallet_barcode,),
    )
    return jsonify(rows)


# -----------------------------------------------------------------------------
# Device Sync Endpoints (/api/sync)
# -----------------------------------------------------------------------------
@app.route("/api/sync/upload", methods=["POST"])
def sync_upload():
    payload = request.get_json(force=True)
    operations = payload.get("operations", [])
    results = []

    for op in operations:
        op_type = op.get("type")
        op_data = op.get("data", {})
        
        try:
            if op_type == "goods_receipt":
                result, _ = _create_goods_receipt(op_data)
                results.append({"operation": op, "result": result})
            elif op_type in ("pallet_transfer", "box_transfer", "box_from_pallet"):
                result, _ = _create_transfer(op_data)
                results.append({"operation": op, "result": result})
            else:
                results.append({"operation": op, "result": {"error": "Unknown operation type"}})
        except Exception as e:
            results.append({"operation": op, "result": {"error": str(e)}})
            # Continue processing other operations
            continue

    return jsonify({"success": True, "results": results}), 200

# This endpoint now includes the new inventory and goods receipt tables
@app.route("/api/sync/download", methods=["POST"])
def sync_download():
    payload = request.get_json(force=True)
    last_sync_iso = payload.get("last_sync")
    
    try:
        last_sync_dt = datetime.fromisoformat(last_sync_iso.replace("Z", "+00:00")) if last_sync_iso else None
    except (ValueError, TypeError):
        last_sync_dt = None

    def _get_updates(table, time_cols, all_time_cols_are_not_null=True):
        if not last_sync_dt:
            return query_all(f"SELECT * FROM {table}")
        
        # Use COALESCE for nullable timestamp columns
        if not all_time_cols_are_not_null:
            time_cols = [f"COALESCE({col}, '1970-01-01')" for col in time_cols]
            
        where_clause = " OR ".join([f"{col} >= %s" for col in time_cols])
        params = tuple([last_sync_dt] * len(time_cols))
        return query_all(f"SELECT * FROM {table} WHERE {where_clause}", params)

    try:
        # Fetch all data, client will handle conflicts/updates
        # This is a simplified full-table sync for required tables
        data = {
            "locations": query_all("SELECT * FROM locations"),
            "urunler": query_all("SELECT *, UrunId as id, StokKodu as code, UrunAdi as name, aktif as is_active FROM urunler"),
            "satin_alma_siparis_fis": query_all("SELECT * FROM satin_alma_siparis_fis"),
            "satin_alma_siparis_fis_satir": query_all("SELECT * FROM satin_alma_siparis_fis_satir"),
            
            # Inventory state is critical, always send the full picture
            "inventory_stock": query_all("SELECT * FROM inventory_stock"),
            
            # For logs, we can send incrementally
            "goods_receipts": _get_updates('goods_receipts', ['created_at']),
            "goods_receipt_items": query_all("SELECT * FROM goods_receipt_items"), # Send all items for simplicity
            "inventory_transfers": _get_updates('inventory_transfers', ['created_at']),
            "employees": _get_updates('employees', ['created_at', 'updated_at'], all_time_cols_are_not_null=False)
        }
        
        # Convert datetime objects to ISO 8601 strings for JSON compatibility
        for table_name, records in data.items():
            for record in records:
                for key, value in record.items():
                    if isinstance(value, datetime):
                        record[key] = value.isoformat()

        return jsonify({"success": True, "data": data, "timestamp": datetime.utcnow().isoformat()}), 200

    except mysql.Error as err:
        return jsonify({"success": False, "error": f"Database download failed: {err}"}), 500
    except Exception as e:
        return jsonify({"success": False, "error": f"An unexpected error occurred: {e}"}), 500

# -----------------------------------------------------------------------------
# Start the app
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
