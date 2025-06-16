from flask import Flask, request, jsonify, abort
from flask_cors import CORS
from datetime import datetime
import os
import mysql.connector as mysql
from contextlib import contextmanager
from decimal import Decimal, InvalidOperation

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
    """
    pallet_clause = "pallet_barcode = %s" if pallet_barcode else "pallet_barcode IS NULL"
    params = [urun_id, location_id]
    if pallet_barcode:
        params.append(pallet_barcode)

    cur.execute(
        f"SELECT id, quantity FROM inventory_stock WHERE urun_id = %s AND location_id = %s AND {pallet_clause}",
        tuple(params)
    )
    stock = cur.fetchone()

    qty_change_decimal = Decimal(str(qty_change))

    if stock:
        current_stock_qty = stock.get("quantity") or Decimal('0')
        new_qty = current_stock_qty + qty_change_decimal

        if new_qty > Decimal('0.001'):
            cur.execute(
                "UPDATE inventory_stock SET quantity = %s, updated_at = NOW() WHERE id = %s",
                (new_qty, stock["id"])
            )
        else:
            cur.execute("DELETE FROM inventory_stock WHERE id = %s", (stock["id"],))

    elif qty_change_decimal > 0:
        cur.execute(
            """
            INSERT INTO inventory_stock
                  (urun_id, location_id, quantity, pallet_barcode, updated_at)
            VALUES (%s, %s, %s, %s, NOW())
            """,
            (urun_id, location_id, qty_change_decimal, pallet_barcode)
        )


# -----------------------------------------------------------------------------
# Business Logic Helpers
# -----------------------------------------------------------------------------
def _check_and_update_po_status(cur, siparis_id: int):
    """
    Checks if all items in a purchase order have been fully received.
    If so, updates the purchase order status to 'completed' (1).
    """
    if not siparis_id:
        return

    cur.execute(
        "SELECT urun_id, miktar FROM satin_alma_siparis_fis_satir WHERE siparis_id = %s",
        (siparis_id,)
    )
    ordered_items = cur.fetchall()
    if not ordered_items:
        return

    cur.execute(
        """
        SELECT gri.urun_id, SUM(gri.quantity_received) as total_received
        FROM goods_receipt_items gri
        JOIN goods_receipts gr ON gr.id = gri.receipt_id
        WHERE gr.siparis_id = %s
        GROUP BY gri.urun_id
        """,
        (siparis_id,)
    )
    received_totals_list = cur.fetchall()
    received_totals = {item['urun_id']: item['total_received'] for item in received_totals_list}

    all_items_completed = True
    for item in ordered_items:
        ordered_qty = item['miktar']
        received_qty = received_totals.get(item['urun_id'], Decimal('0'))

        if received_qty < ordered_qty:
            all_items_completed = False
            break

    if all_items_completed:
        print(f"Sipariş ID {siparis_id} tamamlandı. Durum güncelleniyor.")
        cur.execute(
            "UPDATE satin_alma_siparis_fis SET status = 1, updated_at = NOW() WHERE id = %s",
            (siparis_id,)
        )
    else:
        print(f"Sipariş ID {siparis_id} henüz tamamlanmadı. Durum değiştirilmedi.")


# -----------------------------------------------------------------------------
# API v1 – Master Data & UI Support Endpoints
# -----------------------------------------------------------------------------
@app.route("/v1/locations", methods=["GET"])
def get_locations():
    return jsonify(query_all("SELECT id, name, code FROM locations WHERE is_active = 1 ORDER BY name"))


@app.route("/v1/products/dropdown", methods=["GET"])
def get_products_for_dropdown():
    return jsonify(query_all(
        "SELECT UrunId AS id, UrunAdi AS name, StokKodu AS code, Barcode1 AS barcode1 FROM urunler WHERE aktif = 1 ORDER BY UrunAdi"))


@app.route("/v1/purchase-orders", methods=["GET"])
def get_open_purchase_orders():
    return jsonify(
        query_all("SELECT id, po_id, tarih FROM satin_alma_siparis_fis WHERE status = 0 ORDER BY tarih DESC"))


@app.route("/v1/purchase-orders/<int:order_id>/items", methods=["GET"])
def get_purchase_order_items(order_id):
    sql = """
        SELECT
            s.id,
            s.urun_id AS productId,
            s.miktar AS expectedQuantity,
            s.birim AS unit,
            u.UrunAdi AS productName,
            u.StokKodu AS stockCode,
            u.Barcode1 AS barcode1,
            u.aktif as isActive,
            COALESCE(received.total_received, 0) AS receivedQuantity
        FROM satin_alma_siparis_fis_satir s
        JOIN urunler u ON u.UrunId = s.urun_id
        LEFT JOIN (
            SELECT gri.urun_id, SUM(gri.quantity_received) as total_received
            FROM goods_receipt_items gri
            JOIN goods_receipts gr ON gr.id = gri.receipt_id
            WHERE gr.siparis_id = %s
            GROUP BY gri.urun_id
        ) AS received ON received.urun_id = s.urun_id
        WHERE s.siparis_id = %s;
    """
    items = query_all(sql, (order_id, order_id))

    results = []
    for item in items:
        results.append({
            "id": item["id"],
            "orderId": order_id,
            "productId": item["productId"],
            "expectedQuantity": item["expectedQuantity"],
            "receivedQuantity": item["receivedQuantity"],
            "unit": item["unit"],
            "product": {
                "id": item["productId"],
                "name": item["productName"],
                "stockCode": item["stockCode"],
                "barcode1": item["barcode1"],
                "isActive": item["isActive"] == 1,
            }
        })

    return jsonify(results)


# -----------------------------------------------------------------------------
# API v1 - Goods Receipt Endpoints
# -----------------------------------------------------------------------------
def _create_goods_receipt(data: dict):
    header = data.get("header", {})
    items = data.get("items", [])
    if not header or not items:
        return {"error": "Invalid payload: Missing header or items"}, 400

    mal_kabul_location_id = 1
    siparis_id = header.get("siparis_id")

    try:
        with get_db() as (conn, cur):
            cur.execute(
                """
                INSERT INTO goods_receipts (siparis_id, invoice_number, employee_id, receipt_date, created_at)
                VALUES (%s, %s, %s, %s, NOW())
                """,
                (siparis_id, header.get("invoice_number"), header.get("employee_id"),
                 header.get("receipt_date") or datetime.utcnow())
            )
            receipt_id = cur.lastrowid

            for item in items:
                cur.execute(
                    """
                    INSERT INTO goods_receipt_items (receipt_id, urun_id, quantity_received, pallet_barcode)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (receipt_id, item["urun_id"], item["quantity"], item.get("pallet_barcode"))
                )
                upsert_stock(cur, item["urun_id"], mal_kabul_location_id, item["quantity"], item.get("pallet_barcode"))

            if siparis_id:
                _check_and_update_po_status(cur, siparis_id)

        return {"receipt_id": receipt_id, "status": "success"}, 201

    except mysql.Error as err:
        print(f"Goods Receipt DB Error: {err}")
        return {"error": f"Database error: {err}"}, 500
    except Exception as e:
        print(f"Goods Receipt Unexpected Error: {e}")
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

    op_type = header.get("operation_type")
    src_loc_id = header.get("source_location_id")
    dst_loc_id = header.get("target_location_id")

    try:
        with get_db() as (conn, cur):
            for item in items:
                urun_id = item["product_id"]
                qty = item["quantity"]
                pallet_bc = item.get("pallet_id")

                cur.execute(
                    """
                    INSERT INTO inventory_transfers
                        (urun_id, from_location_id, to_location_id, quantity, pallet_barcode, employee_id, transfer_date)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (urun_id, src_loc_id, dst_loc_id, qty, pallet_bc, header.get("employee_id"),
                     header.get("transfer_date") or datetime.utcnow())
                )

                if op_type == "pallet_transfer":
                    upsert_stock(cur, urun_id, src_loc_id, -qty, pallet_bc)
                    upsert_stock(cur, urun_id, dst_loc_id, qty, pallet_bc)
                elif op_type == "box_from_pallet":
                    upsert_stock(cur, urun_id, src_loc_id, -qty, pallet_bc)
                    upsert_stock(cur, urun_id, dst_loc_id, qty, None)
                else:  # Covers 'box_transfer'
                    upsert_stock(cur, urun_id, src_loc_id, -qty, None)
                    upsert_stock(cur, urun_id, dst_loc_id, qty, None)

        return {"status": "success"}, 200

    except mysql.Error as err:
        print(f"Transfer DB Error: {err}")
        return {"error": f"Database error: {err}"}, 500
    except Exception as e:
        print(f"Transfer Unexpected Error: {e}")
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
        rows = query_all(
            "SELECT DISTINCT pallet_barcode AS id FROM inventory_stock WHERE location_id = %s AND pallet_barcode IS NOT NULL",
            (location_id,)
        )
        return jsonify([r["id"] for r in rows if r["id"]])
    else:
        rows = query_all(
            """
            SELECT
                s.urun_id AS productId,
                u.UrunAdi AS productName,
                u.StokKodu AS productCode,
                u.Barcode1 AS barcode1,
                SUM(s.quantity) AS quantity
            FROM inventory_stock s
            JOIN urunler u ON u.UrunId = s.urun_id
            WHERE s.location_id = %s AND s.pallet_barcode IS NULL
            GROUP BY s.urun_id, u.UrunAdi, u.StokKodu, u.Barcode1
            """,
            (location_id,)
        )
        return jsonify(rows)


@app.route("/v1/containers/<string:pallet_barcode>/contents", methods=["GET"])
def get_container_contents(pallet_barcode):
    rows = query_all(
        """
        SELECT u.UrunAdi AS productName, s.urun_id AS productId, s.quantity, u.StokKodu as productCode
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
            if op_type == "goodsReceipt":
                result, _ = _create_goods_receipt(op_data)
                results.append({"operation": op, "result": result})

            elif op_type == "inventoryTransfer":
                result, _ = _create_transfer(op_data)
                results.append({"operation": op, "result": result})

            else:
                results.append({"operation": op, "result": {"error": f"Unknown main operation type: {op_type}"}})

        except Exception as e:
            print(f"Error processing operation {op}: {e}")
            results.append({"operation": op, "result": {"error": str(e)}})
            continue

    return jsonify({"success": True, "results": results}), 200


@app.route("/api/sync/download", methods=["POST"])
def sync_download():
    payload = request.get_json() or {}
    last_sync_ts = payload.get("last_sync_timestamp")
    print(f"Delta sync request received. Last sync timestamp: {last_sync_ts}")

    data = {}

    try:
        # Zaman damgası olan tablolar için delta (değişen) sorguları
        if last_sync_ts:
            data["locations"] = query_all("SELECT * FROM locations WHERE updated_at > %s", (last_sync_ts,))
            data["urunler"] = query_all("SELECT * FROM urunler WHERE updated_at > %s", (last_sync_ts,))
            data["employees"] = query_all("SELECT * FROM employees WHERE updated_at > %s", (last_sync_ts,))
            data["satin_alma_siparis_fis"] = query_all("SELECT * FROM satin_alma_siparis_fis WHERE updated_at > %s",
                                                       (last_sync_ts,))
            data["inventory_stock"] = query_all("SELECT * FROM inventory_stock WHERE updated_at > %s", (last_sync_ts,))
            # 'created_at' kullanılan ve güncellenmeyen tablolar
            data["goods_receipts"] = query_all("SELECT * FROM goods_receipts WHERE created_at > %s", (last_sync_ts,))
            data["inventory_transfers"] = query_all("SELECT * FROM inventory_transfers WHERE created_at > %s",
                                                    (last_sync_ts,))

            # Zaman damgası olmayan, join gerektiren tablolar
            data["satin_alma_siparis_fis_satir"] = query_all("""
                SELECT s.* FROM satin_alma_siparis_fis_satir s
                JOIN satin_alma_siparis_fis f ON s.siparis_id = f.id
                WHERE f.updated_at > %s
            """, (last_sync_ts,))
            data["goods_receipt_items"] = query_all("""
                SELECT i.* FROM goods_receipt_items i
                JOIN goods_receipts h ON i.receipt_id = h.id
                WHERE h.created_at > %s
            """, (last_sync_ts,))

        # İlk senkronizasyon (full sync)
        else:
            print("Full sync request received.")
            data["locations"] = query_all("SELECT * FROM locations")
            data["urunler"] = query_all("SELECT * FROM urunler")
            data["employees"] = query_all("SELECT * FROM employees")
            data["satin_alma_siparis_fis"] = query_all("SELECT * FROM satin_alma_siparis_fis")
            data["satin_alma_siparis_fis_satir"] = query_all("SELECT * FROM satin_alma_siparis_fis_satir")
            data["goods_receipts"] = query_all("SELECT * FROM goods_receipts")
            data["goods_receipt_items"] = query_all("SELECT * FROM goods_receipt_items")
            data["inventory_stock"] = query_all("SELECT * FROM inventory_stock")
            data["inventory_transfers"] = query_all("SELECT * FROM inventory_transfers")

        # Tarih/saat ve ondalık sayıları string'e çevir
        for table_name, records in data.items():
            for record in records:
                for key, value in record.items():
                    if isinstance(value, datetime):
                        record[key] = value.isoformat()
                    elif isinstance(value, Decimal):
                        record[key] = str(value)

        return jsonify({"success": True, "data": data, "timestamp": datetime.utcnow().isoformat()}), 200

    except mysql.Error as err:
        return jsonify({"success": False, "error": f"Database download failed: {err}"}), 500
    except Exception as e:
        return jsonify({"success": False, "error": f"An unexpected error occurred: {e}"}), 500


# -----------------------------------------------------------------------------
# Health Check Endpoint
# -----------------------------------------------------------------------------
@app.route("/health", methods=["GET"])
def health_check():
    """A simple endpoint to check if the server is running."""
    return jsonify({"status": "ok", "message": "Server is running"}), 200


# -----------------------------------------------------------------------------
# Start the app
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
