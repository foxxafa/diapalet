# Flask API Server for DiaPalet

## Setup

1. Create a virtualenv and install requirements

```bash
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

2. Export database credentials (or put in .env)

```bash
export DB_HOST=127.0.0.1
export DB_USER=root
export DB_PASSWORD=secret
export DB_NAME=rowhub
```

3. Run the server

```bash
python app.py
```

The server will listen on `http://0.0.0.0:5000`.

## Key Endpoints (prefix `/v1`)

| Method | Path | Description |
|--------|------|-------------|
| GET | /v1/locations | Active locations |
| GET | /v1/products/dropdown | Product list for dropdown |
| GET | /v1/purchase-orders | Open purchase orders |
| GET | /v1/purchase-orders/<order_id>/items | Items for a purchase order |
| POST | /v1/goods-receipts | Create goods receipt |
| POST | /v1/transfers | Create transfer (box or pallet) |
| GET | /v1/containers/<location>/ids | Container ids (pallets / products) |
| GET | /v1/containers/<id>/contents | Contents of container |

Sync endpoints (used by background sync):

| POST | /api/register_device |
| POST | /api/sync/upload |
| POST | /api/sync/download |
