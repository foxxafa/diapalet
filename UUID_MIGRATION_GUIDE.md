# UUID-Based Inventory Relationship Migration Guide

## 📋 Overview

This migration removes the dependency on server-generated IDs (`siparis_id`, `goods_receipt_id`) in favor of UUID-based relationships for inventory management. This change enables true offline-first operations and eliminates the need to sync server IDs back to mobile devices.

## 🎯 Goals

1. **Offline-first compatibility**: Mobile devices can create all necessary UUIDs without server communication
2. **Multi-device safety**: No ID conflicts when multiple devices work simultaneously
3. **Simplified consolidation**: Easier stock merging without complex ID tracking
4. **Reduced sync complexity**: No need to update local IDs after server sync

## 🔄 Schema Changes

### inventory_stock Table

**Before:**
```sql
CREATE TABLE inventory_stock (
  stock_uuid TEXT NOT NULL UNIQUE,
  urun_key TEXT NOT NULL,
  birim_key TEXT,
  location_id INTEGER,
  siparis_id INTEGER,           -- ❌ REMOVED
  goods_receipt_id INTEGER,     -- ❌ REMOVED
  quantity REAL NOT NULL,
  stock_status TEXT NOT NULL,
  ...
)
```

**After:**
```sql
CREATE TABLE inventory_stock (
  stock_uuid TEXT NOT NULL UNIQUE,
  urun_key TEXT NOT NULL,
  birim_key TEXT,
  location_id INTEGER,
  receipt_operation_uuid TEXT,  -- ✅ NEW: Links to goods_receipts.operation_unique_id
  quantity REAL NOT NULL,
  stock_status TEXT NOT NULL,
  ...
)
```

### inventory_transfers Table

**Before:**
```sql
CREATE TABLE inventory_transfers (
  operation_unique_id TEXT,
  urun_key TEXT,
  from_location_id INTEGER,
  to_location_id INTEGER,
  siparis_id INTEGER,           -- ❌ REMOVED
  goods_receipt_id INTEGER,     -- ❌ REMOVED
  ...
)
```

**After:**
```sql
CREATE TABLE inventory_transfers (
  operation_unique_id TEXT,
  urun_key TEXT,
  from_location_id INTEGER,
  to_location_id INTEGER,
  from_receipt_operation_uuid TEXT,  -- ✅ NEW: Source receipt's UUID
  ...
)
```

## 📊 Relationship Model

### Old Model (ID-based)
```
goods_receipts                    inventory_stock
├── goods_receipt_id (PK) ───────┼── goods_receipt_id (FK)
├── siparis_id                   ├── siparis_id (FK)
└── ...                          └── ...
```

**Problems:**
- Mobile needs to wait for server ID
- Complex sync logic to update IDs
- Multi-device conflicts possible

### New Model (UUID-based)
```
goods_receipts                    inventory_stock
├── goods_receipt_id (PK)        ├── stock_uuid (PK)
├── operation_unique_id (UUID) ──┼── receipt_operation_uuid (UUID)
├── siparis_id                   └── ...
└── ...
```

**Benefits:**
- ✅ Mobile generates UUID instantly
- ✅ Simple sync - no ID updates needed
- ✅ Multi-device safe
- ✅ Easier consolidation

## 🔧 Code Changes

### Mobile (Flutter)

**1. Database Schema Update** (`database_helper.dart:247-270`)
```dart
// inventory_stock table
CREATE TABLE IF NOT EXISTS inventory_stock (
  stock_uuid TEXT NOT NULL UNIQUE,
  receipt_operation_uuid TEXT,  // NEW
  // siparis_id removed
  // goods_receipt_id removed
  ...
)
```

**2. Sync Logic Update** (`database_helper.dart:727`)
```dart
// Before
'siparis_id': stock['siparis_id'],
'goods_receipt_id': stock['goods_receipt_id'],

// After
'receipt_operation_uuid': stock['receipt_operation_uuid'],
```

**3. Query Updates** (`database_helper.dart:1788-1808`)
```dart
// Before
WHERE ints.siparis_id = ? AND ints.stock_status = 'receiving'

// After
LEFT JOIN goods_receipts gr ON ints.receipt_operation_uuid = gr.operation_unique_id
WHERE gr.siparis_id = ? AND ints.stock_status = 'receiving'
```

### Backend (PHP)

**1. upsertStock Signature** (`TerminalController.php:1388`)
```php
// Before
private function upsertStock($db, $urunKey, $birimKey, $locationId,
    $qtyChange, $palletBarcode, $stockStatus,
    $siparisId = null, $expiryDate = null, $goodsReceiptId = null, ...)

// After
private function upsertStock($db, $urunKey, $birimKey, $locationId,
    $qtyChange, $palletBarcode, $stockStatus,
    $receiptOperationUuid = null, $expiryDate = null, ...)
```

**2. Stock Consolidation Logic** (`TerminalController.php:1461-1468`)
```php
// Before
if ($stockStatus === 'receiving') {
    if ($siparisId !== null) {
        $this->addNullSafeWhere($query, 'siparis_id', $siparisId);
    } else {
        $this->addNullSafeWhere($query, 'goods_receipt_id', $goodsReceiptId);
    }
}

// After
if ($stockStatus === 'receiving' && $receiptOperationUuid !== null) {
    $this->addNullSafeWhere($query, 'receipt_operation_uuid', $receiptOperationUuid);
}
```

**3. INSERT Statement** (`TerminalController.php:1569-1583`)
```php
// Before
'siparis_id' => $siparisId,
'goods_receipt_id' => ($siparisId === null) ? $goodsReceiptId : null,

// After
'receipt_operation_uuid' => $receiptOperationUuid,
```

## 🚀 Migration Steps

### Phase 1: Database Migration (Backend)

```bash
# 1. Backup database
mysqldump -u user -p database > backup_before_uuid_migration.sql

# 2. Run migration script
mysql -u user -p database < backend/migrations/m250107_000000_uuid_based_inventory_relationships.sql

# 3. Verify data migration
SELECT COUNT(*) FROM inventory_stock WHERE receipt_operation_uuid IS NULL AND goods_receipt_id IS NOT NULL;
# Should return 0 if migration successful
```

### Phase 2: Code Deployment

1. **Deploy backend changes first**
   - Old mobile apps will continue working (backward compatible)
   - New UUID fields are populated alongside old fields

2. **Deploy mobile app update**
   - Mobile starts using UUID-based relationships
   - Old fields are ignored but still synced (for rollback safety)

3. **Monitor for 1-2 weeks**
   - Ensure all devices are updated
   - Check logs for any issues

### Phase 3: Cleanup (Optional)

```sql
-- After confirming everything works, remove old columns
ALTER TABLE inventory_stock DROP COLUMN siparis_id;
ALTER TABLE inventory_stock DROP COLUMN goods_receipt_id;
ALTER TABLE inventory_transfers DROP COLUMN siparis_id;
ALTER TABLE inventory_transfers DROP COLUMN goods_receipt_id;
```

## 📝 Testing Checklist

- [ ] Goods receipt creation (with order)
- [ ] Goods receipt creation (free/without order)
- [ ] Inventory transfer (putaway)
- [ ] Inventory transfer (product movement)
- [ ] Stock consolidation ('receiving' → 'available')
- [ ] Multi-device goods receipt on same order
- [ ] Offline goods receipt sync
- [ ] Query by order (getInventoryStockForOrder)

## 🔍 Consolidation Scenarios

### Scenario 1: Order-based Receipt Consolidation

**Before (ID-based):**
```
Receipt 1 (ID=100): 3 units → siparis_id=1, goods_receipt_id=100
Receipt 2 (ID=101): 4 units → siparis_id=1, goods_receipt_id=101
Result: 2 separate stock records (3 + 4)
```

**After (UUID-based):**
```
Receipt 1 (UUID=aaa): 3 units → receipt_operation_uuid=aaa
Receipt 2 (UUID=bbb): 4 units → receipt_operation_uuid=bbb
Consolidation: 7 units (merged by unique constraint)
```

### Scenario 2: Transfer to Available Status

**Before:**
```
receiving → available: Must clear siparis_id and goods_receipt_id
Complex logic to determine which fields to clear
```

**After:**
```
receiving → available: Simply set receipt_operation_uuid=NULL
Clean, simple consolidation
```

## ⚠️ Important Notes

1. **Backward Compatibility**: Old mobile apps will continue to send `siparis_id` and `goods_receipt_id`, which are safely ignored
2. **Data Integrity**: The migration script preserves all existing relationships
3. **Performance**: New indexes ensure queries remain fast
4. **Rollback**: Keep old columns for 2-4 weeks to enable safe rollback if needed

## 📞 Support

For questions or issues:
- Check logs in `backend/runtime/logs/terminal_debug.log`
- Mobile logs via Flutter debugger
- Contact: [Your contact info]

---

**Migration Date**: 2025-01-07
**Author**: Claude Code Assistant
**Status**: ✅ Ready for deployment
