# ... existing code ...
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
    pallet_barcode  = header.get("pallet_id")
    employee_id     = header.get("employee_id")
    transfer_date   = header.get("transfer_date") or datetime.utcnow().isoformat()

    # Map location names to IDs
    src = query_one("SELECT id FROM locations WHERE name = %s", (src_name,))
    dst = query_one("SELECT id FROM locations WHERE name = %s", (dst_name,))
    if not src or not dst:
        return {"error": "Invalid source/target location"}, 400

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
    
    return {"transfer_id": transfer_id}, 200

@app.route("/v1/transfers", methods=["POST"])
def post_transfer():
    data = request.get_json(force=True)
    result, status_code = _create_transfer(data)
    return jsonify(result), status_code


# ... existing code ...
@app.route("/api/sync/upload", methods=["POST"])
def sync_upload():
    payload = request.get_json(force=True)
    operations = payload.get("operations", [])
    for op in operations:
        op_type = op.get("operation_type")
        if op_type == "goods_receipt":
            _create_goods_receipt(op)
        elif op_type in ("pallet_transfer", "box_transfer"):
            _create_transfer(op)
        else:
            continue
    return jsonify({"success": True}), 200


@app.route("/api/sync/download", methods=["POST"])
# ... existing code ...

@app.route("/v1/purchase-orders/<int:order_id>/items", methods=["GET"])
def get_purchase_order_items(order_id):
# ... existing code ...
    )
    return jsonify(items)
