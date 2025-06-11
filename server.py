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
        password=os.environ.get("DB_PASSWORD", "123456"),
        database=os.environ.get("DB_NAME", "diapalet_test"),
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

def _create_goods_receipt(data):
    header = data.get("header")
    items = data.get("items", [])

    if not header or not items:
        return {"error": "Invalid payload"}, 400

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

    # If an order is associated, update its status to 'closed' (1)
    # and set the invoice number if provided.
    if siparis_id:
        # Assuming status=1 means 'closed/completed'
        if invoice_number:
            execute(
                "UPDATE satin_alma_siparis_fis SET status = 1, invoice = %s WHERE id = %s",
                (invoice_number, siparis_id)
            )
        else:
            execute(
                "UPDATE satin_alma_siparis_fis SET status = 1 WHERE id = %s",
                (siparis_id,)
            )

    return {"receipt_id": receipt_id}, 201


@app.route("/v1/goods-receipts", methods=["POST"])
def post_goods_receipt():
    data = request.get_json(force=True)
    result, status_code = _create_goods_receipt(data)
    return jsonify(result), status_code


# -----------------------------------------------------------------------------
# Pallet Operations
# -----------------------------------------------------------------------------

@app.route("/v1/pallets", methods=["POST"])
def create_pallet():
    # Bu endpoint için henüz bir işlevsellik tanımlanmamış.
    # Gerekirse, veritabanına yeni bir palet eklemek için kod ekleyebilirsiniz.
    return jsonify({"status": "ok", "pallet_id": f"PALLET_{datetime.utcnow().timestamp()}"}), 201


@app.route("/v1/pallets/<string:pallet_id>/items", methods=["POST"])
def add_items_to_pallet(pallet_id):
    # Bu endpoint için henüz bir işlevsellik tanımlanmamış.
    # Gerekirse, belirli bir palete ürün eklemek için kod ekleyebilirsiniz.
    return jsonify({"status": "ok"}), 200

# -----------------------------------------------------------------------------
# Transfer operations (box or pallet)
# -----------------------------------------------------------------------------

def _create_transfer(data):
    header = data.get("header")
    items = data.get("items", [])

    if not header or not items:
        return {"error": "Invalid payload"}, 400

    operation_type  = header.get("operation_type")  # pallet or box
    src_name        = header.get("source_location")
    dst_name        = header.get("target_location")
    pallet_barcode  = header.get("pallet_id")  # Palet barkodu veya None (kutu akışı)
    employee_id     = header.get("employee_id")
    transfer_date   = header.get("transfer_date") or datetime.utcnow().isoformat()

    # Map location names to IDs
    src = query_one("SELECT id FROM locations WHERE name = %s", (src_name,))
    dst = query_one("SELECT id FROM locations WHERE name = %s", (dst_name,))
    if not src or not dst:
        return {"error": "Invalid source/target location"}, 400

    # ------------------------------------------------------------------
    # PALET TRANSFERİ – paletin tamamını bir lokasyondan diğerine taşı
    # ------------------------------------------------------------------
    if operation_type in ("pallet", "pallet_transfer"):
        # 1) Stok tablosunda ilgili paletin tüm satırlarının lokasyonunu güncelle
        conn = get_db_connection()
        cur  = conn.cursor()
        cur.execute(
            """
            UPDATE inventory_stock
            SET location_id = %s, updated_at = NOW()
            WHERE location_id = %s AND pallet_barcode = %s
            """,
            (dst["id"], src["id"], pallet_barcode),
        )
        conn.commit()
        cur.close()
        conn.close()

        # 2) Her ürün için transfer hareketi kaydet (raporlama için)
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
        return {"status": "success"}, 200

    # ------------------------------------------------------------------
    # KUTU TRANSFERİ – belirli miktar kutuyu taşı
    # ------------------------------------------------------------------
    for item in items:
        urun_id = item["product_id"]
        qty     = item["quantity"]
        # Hareket kaydı
        execute(
            """
            INSERT INTO inventory_transfers (urun_id, from_location_id, to_location_id, quantity, pallet_barcode, employee_id, transfer_date)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (urun_id, src["id"], dst["id"], qty, pallet_barcode, employee_id, transfer_date),
        )
        # Stok güncelle – kaynak azalt, hedef artır
        upsert_stock(urun_id, src["id"], -qty, None)  # kutu akışında pallet_barcode yok
        upsert_stock(urun_id, dst["id"],  qty, None)

    return {"status": "success"}, 200


@app.route("/v1/transfers", methods=["POST"])
def post_transfer():
    data = request.get_json(force=True)
    result, status_code = _create_transfer(data)
    return jsonify(result), status_code


# -----------------------------------------------------------------------------
# Helper to update stock (insert or increment)
# -----------------------------------------------------------------------------

def upsert_stock(urun_id: int, location_id: int, qty: float, pallet_barcode: str | None):
    """Insert / update stock row.

    * Mevcut kayıt varsa, miktarı arttır/azalt.
    * Yeni miktar 0 veya altına düşerse kayıt silinir.
    * Kayıt yoksa ve qty > 0 ise yeni kayıt oluşturulur.
    """
    conn = get_db_connection()
    cur  = conn.cursor(dictionary=True)

    # Sorgu, pallet_barcode NULL / NOT NULL durumuna göre farklılık gösterir
    if pallet_barcode is None:
        cur.execute(
            """
            SELECT id, quantity FROM inventory_stock
            WHERE urun_id = %s AND location_id = %s AND pallet_barcode IS NULL
            """,
            (urun_id, location_id),
        )
    else:
        cur.execute(
            """
            SELECT id, quantity FROM inventory_stock
            WHERE urun_id = %s AND location_id = %s AND pallet_barcode = %s
            """,
            (urun_id, location_id, pallet_barcode),
        )

    row = cur.fetchone()

    if row:
        new_qty = (row["quantity"] or 0) + qty
        if new_qty <= 0:
            # Miktar 0 veya negatif olduysa satırı sil
            cur.execute("DELETE FROM inventory_stock WHERE id = %s", (row["id"],))
        else:
            cur.execute(
                """
                UPDATE inventory_stock
                SET quantity = %s, updated_at = NOW()
                WHERE id = %s
                """,
                (new_qty, row["id"]),
            )
    else:
        # Kayıt yoksa ve pozitif miktar ekleniyorsa yeni satır oluştur
        if qty > 0:
            cur.execute(
                """
                INSERT INTO inventory_stock (urun_id, location_id, quantity, pallet_barcode)
                VALUES (%s, %s, %s, %s)
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
        data = op.get("operationData", {})

        if op_type == "goods_receipt":
            # Gelen veriyi _create_goods_receipt'in beklediği formata dönüştür
            formatted_data = {
                "header": {
                    "invoice_number": data.get("invoice_number"),
                    "receipt_date": data.get("receipt_date"),
                    # employee_id ve siparis_id gibi eksik bilgiler mobil taraftan eklenmeli
                    # veya burada varsayılan değerler atanmalıdır.
                    "employee_id": data.get("employee_id", 1),
                    "siparis_id": data.get("siparis_id")
                },
                "items": [
                    {
                        "urun_id": item.get("product_id"),
                        "quantity": item.get("quantity"),
                        "pallet_barcode": item.get("pallet_id")
                    } for item in data.get("items", [])
                ]
            }
            _create_goods_receipt(formatted_data)

        elif op_type in ("pallet_transfer", "box_transfer"):
            # Gelen veriyi _create_transfer'in beklediği formata dönüştür
            formatted_data = {
                "header": {
                    "operation_type": op_type,
                    "source_location": data.get("source_location"),
                    "target_location": data.get("target_location"),
                    "pallet_id": data.get("pallet_id"),
                    "transfer_date": data.get("transfer_date"),
                    # employee_id mobil taraftan eklenmeli veya varsayılan atanmalı
                    "employee_id": data.get("employee_id", 1)
                },
                "items": [
                    {
                        "product_id": item.get("product_id"),
                        "quantity": item.get("quantity")
                    } for item in data.get("items", [])
                ]
            }
            _create_transfer(formatted_data)
        else:
            continue
    return jsonify({"success": True}), 200


@app.route("/api/sync/download", methods=["POST"])
def sync_download():
    payload = request.get_json(force=True)

    # Optional incremental sync timestamp (ISO 8601 string). If provided, only
    # rows created/updated after this timestamp will be returned *for tables
    # that have such columns*; otherwise, the whole table is returned.
    last_sync_iso = payload.get("last_sync")
    try:
        last_sync_dt = (
            datetime.fromisoformat(last_sync_iso.replace("Z", "+00:00")) if last_sync_iso else None
        )
    except Exception:
        last_sync_dt = None

    def _build_inc_clause(columns: list[str]):
        """Return sql clause and params respecting available timestamp columns."""
        if not last_sync_dt or not columns:
            return "", ()
        cond_parts = [f"{col} >= %s" for col in columns]
        return " WHERE " + " OR ".join(cond_parts), tuple([last_sync_dt] * len(columns))

    def _fetch(sql: str, params: tuple = ()):  # tiny helper for brevity
        return query_all(sql, params)

    # ---------------------------- MASTER DATA ---------------------------------
    inc_clause, inc_params = _build_inc_clause(["created_at", "updated_at"])
    products = _fetch(
        f"""
        SELECT UrunId AS id,
               StokKodu AS code,
               UrunAdi AS name,
               aktif    AS is_active,
               created_at, updated_at
        FROM urunler""" + inc_clause,
        inc_params,
    )

    inc_clause, inc_params = _build_inc_clause(["created_at", "updated_at"])
    locations = _fetch(
        f"""
        SELECT id, name, code, is_active, latitude, longitude, address, description,
               created_at, updated_at
        FROM locations""" + inc_clause,
        inc_params,
    )

    # -------------------------- TRANSACTIONAL DATA ----------------------------
    # satin_alma_siparis_fis (has created_at/updated_at)
    inc_clause, inc_params = _build_inc_clause(["created_at", "updated_at"])
    purchase_orders = _fetch(
        "SELECT * FROM satin_alma_siparis_fis" + inc_clause,
        inc_params,
    )

    # satin_alma_siparis_fis_satir (no timestamps) -> always full
    purchase_order_items = _fetch("SELECT * FROM satin_alma_siparis_fis_satir")

    # goods_receipts (has created_at)
    inc_clause, inc_params = _build_inc_clause(["created_at"])
    goods_receipts = _fetch(
        "SELECT * FROM goods_receipts" + inc_clause,
        inc_params,
    )

    # goods_receipt_items (no timestamps) – link via goods_receipts inc
    if last_sync_dt:
        # fetch items where their parent receipt is in the incremental set
        receipt_ids = [r["id"] for r in goods_receipts]
        if receipt_ids:
            placeholders = ",".join(["%s"] * len(receipt_ids))
            goods_receipt_items = _fetch(
                f"SELECT * FROM goods_receipt_items WHERE receipt_id IN ({placeholders})",
                tuple(receipt_ids),
            )
        else:
            goods_receipt_items = []
    else:
        goods_receipt_items = _fetch("SELECT * FROM goods_receipt_items")

    # inventory_stock (has updated_at)
    inc_clause, inc_params = _build_inc_clause(["updated_at"])
    inventory_stock = _fetch("SELECT * FROM inventory_stock" + inc_clause, inc_params)

    # ------------------------------ RESPONSE ----------------------------------
    data = {
        "products": products,
        "locations": locations,
        "purchase_orders": purchase_orders,
        "purchase_order_items": purchase_order_items,
        "goods_receipts": goods_receipts,
        "goods_receipt_items": goods_receipt_items,
        "inventory_stock": inventory_stock,
    }

    return jsonify({"success": True, "data": data}), 200

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
    else:  # box flow, return product IDs as container IDs
        rows = query_all(
            "SELECT DISTINCT urun_id AS id FROM inventory_stock WHERE location_id = %s AND pallet_barcode IS NULL",
            (loc_id,),
        )
    return jsonify([str(r["id"]) for r in rows])


@app.route("/v1/containers/<string:container_id>/contents", methods=["GET"])
def get_container_contents(container_id):
    mode = request.args.get("mode", "pallet").strip()
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