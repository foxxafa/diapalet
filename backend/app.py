#!/usr/bin/env python3
# backend/app.py
from flask import Flask, request, jsonify
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error
import json
from datetime import datetime
import os
from typing import Dict, List, Any
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', 3306)),
    'user': os.getenv('DB_USER', 'root'),
    'password': os.getenv('DB_PASSWORD', ''),
    'database': os.getenv('DB_NAME', 'rowhub'),
    'charset': 'utf8mb4',
    'collation': 'utf8mb4_turkish_ci'
}

def get_db_connection():
    """Create database connection"""
    try:
        connection = mysql.connector.connect(**DB_CONFIG)
        return connection
    except Error as e:
        logger.error(f"Database connection error: {e}")
        return None

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

@app.route('/api/register_device', methods=['POST'])
def register_device():
    """Register a mobile device"""
    try:
        data = request.get_json()
        device_id = data.get('device_id')
        device_name = data.get('device_name', '')
        platform = data.get('platform', 'android')
        app_version = data.get('app_version', '1.0.0')
        
        if not device_id:
            return jsonify({'error': 'device_id is required'}), 400
            
        connection = get_db_connection()
        if not connection:
            return jsonify({'error': 'Database connection failed'}), 500
            
        cursor = connection.cursor()
        
        # Insert or update device registration
        query = """
        INSERT INTO mobile_devices (device_id, device_name, platform, app_version)
        VALUES (%s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
        device_name = VALUES(device_name),
        platform = VALUES(platform),
        app_version = VALUES(app_version),
        is_active = 1
        """
        
        cursor.execute(query, (device_id, device_name, platform, app_version))
        connection.commit()
        
        return jsonify({'success': True, 'message': 'Device registered successfully'})
        
    except Exception as e:
        logger.error(f"Error registering device: {e}")
        return jsonify({'error': 'Internal server error'}), 500
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/api/sync/upload', methods=['POST'])
def upload_pending_operations():
    """Upload pending operations from mobile device"""
    try:
        data = request.get_json()
        device_id = data.get('device_id')
        operations = data.get('operations', [])
        
        if not device_id:
            return jsonify({'error': 'device_id is required'}), 400
            
        if not operations:
            return jsonify({'success': True, 'message': 'No operations to sync'})
            
        connection = get_db_connection()
        if not connection:
            return jsonify({'error': 'Database connection failed'}), 500
            
        cursor = connection.cursor()
        
        # Start sync log
        sync_log_query = """
        INSERT INTO sync_log (device_id, sync_type, operations_count)
        VALUES (%s, 'manual', %s)
        """
        cursor.execute(sync_log_query, (device_id, len(operations)))
        sync_log_id = cursor.lastrowid
        
        success_count = 0
        failed_count = 0
        failed_operations = []
        
        for operation in operations:
            try:
                # Process each operation
                result = process_operation(cursor, device_id, operation)
                if result['success']:
                    success_count += 1
                else:
                    failed_count += 1
                    failed_operations.append({
                        'operation': operation,
                        'error': result['error']
                    })
            except Exception as e:
                failed_count += 1
                failed_operations.append({
                    'operation': operation,
                    'error': str(e)
                })
        
        # Update sync log
        update_sync_log_query = """
        UPDATE sync_log 
        SET success_count = %s, failed_count = %s, sync_completed_at = NOW(), 
            status = %s, error_details = %s
        WHERE id = %s
        """
        
        status = 'completed' if failed_count == 0 else 'failed'
        error_details = json.dumps(failed_operations) if failed_operations else None
        
        cursor.execute(update_sync_log_query, 
                      (success_count, failed_count, status, error_details, sync_log_id))
        
        # Update device last sync time
        cursor.execute("""
        UPDATE mobile_devices SET last_sync_at = NOW() WHERE device_id = %s
        """, (device_id,))
        
        connection.commit()
        
        return jsonify({
            'success': True,
            'sync_log_id': sync_log_id,
            'success_count': success_count,
            'failed_count': failed_count,
            'failed_operations': failed_operations
        })
        
    except Exception as e:
        logger.error(f"Error uploading operations: {e}")
        return jsonify({'error': 'Internal server error'}), 500
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

def process_operation(cursor, device_id: str, operation: Dict[str, Any]) -> Dict[str, Any]:
    """Process a single operation"""
    try:
        operation_type = operation.get('operation_type')
        operation_data = operation.get('operation_data', {})
        
        if operation_type == 'goods_receipt':
            return process_goods_receipt(cursor, operation_data)
        elif operation_type == 'pallet_transfer':
            return process_pallet_transfer(cursor, operation_data)
        elif operation_type == 'box_transfer':
            return process_box_transfer(cursor, operation_data)
        else:
            return {'success': False, 'error': f'Unknown operation type: {operation_type}'}
            
    except Exception as e:
        logger.error(f"Error processing operation: {e}")
        return {'success': False, 'error': str(e)}

def process_goods_receipt(cursor, data: Dict[str, Any]) -> Dict[str, Any]:
    """Process goods receipt operation"""
    try:
        # Insert into goods receipt tables
        # This is a simplified example - adjust based on your actual schema
        
        external_id = data.get('external_id')
        invoice_number = data.get('invoice_number')
        receipt_date = data.get('receipt_date')
        items = data.get('items', [])
        
        # Example: Insert into a goods_receipt_sync table or your main tables
        # Adjust this based on your actual schema
        query = """
        INSERT INTO pending_operations (device_id, operation_type, operation_data, status)
        VALUES (%s, 'goods_receipt', %s, 'completed')
        """
        
        cursor.execute(query, (data.get('device_id', ''), json.dumps(data)))
        
        return {'success': True}
        
    except Exception as e:
        return {'success': False, 'error': str(e)}

def process_pallet_transfer(cursor, data: Dict[str, Any]) -> Dict[str, Any]:
    """Process pallet transfer operation"""
    try:
        # Process pallet transfer logic
        query = """
        INSERT INTO pending_operations (device_id, operation_type, operation_data, status)
        VALUES (%s, 'pallet_transfer', %s, 'completed')
        """
        
        cursor.execute(query, (data.get('device_id', ''), json.dumps(data)))
        
        return {'success': True}
        
    except Exception as e:
        return {'success': False, 'error': str(e)}

def process_box_transfer(cursor, data: Dict[str, Any]) -> Dict[str, Any]:
    """Process box transfer operation"""
    try:
        # Process box transfer logic
        query = """
        INSERT INTO pending_operations (device_id, operation_type, operation_data, status)
        VALUES (%s, 'box_transfer', %s, 'completed')
        """
        
        cursor.execute(query, (data.get('device_id', ''), json.dumps(data)))
        
        return {'success': True}
        
    except Exception as e:
        return {'success': False, 'error': str(e)}

@app.route('/api/sync/download', methods=['POST'])
def download_master_data():
    """Download master data for offline use"""
    try:
        data = request.get_json()
        device_id = data.get('device_id')
        last_sync = data.get('last_sync_timestamp')
        
        if not device_id:
            return jsonify({'error': 'device_id is required'}), 400
            
        connection = get_db_connection()
        if not connection:
            return jsonify({'error': 'Database connection failed'}), 500
            
        cursor = connection.cursor(dictionary=True)
        
        # Get master data
        master_data = {}
        
        # Get products
        cursor.execute("SELECT UrunId as id, StokKodu as code, UrunAdi as name FROM urunler WHERE aktif = 1")
        master_data['products'] = cursor.fetchall()
        
        # Get locations
        cursor.execute("SELECT id, name, code FROM locations WHERE is_active = 1")
        master_data['locations'] = cursor.fetchall()
        
        # Add timestamp
        master_data['sync_timestamp'] = datetime.now().isoformat()
        
        return jsonify({
            'success': True,
            'data': master_data
        })
        
    except Exception as e:
        logger.error(f"Error downloading master data: {e}")
        return jsonify({'error': 'Internal server error'}), 500
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/api/sync/status/<device_id>', methods=['GET'])
def get_sync_status(device_id):
    """Get sync status for a device"""
    try:
        connection = get_db_connection()
        if not connection:
            return jsonify({'error': 'Database connection failed'}), 500
            
        cursor = connection.cursor(dictionary=True)
        
        # Get latest sync log
        cursor.execute("""
        SELECT * FROM sync_log 
        WHERE device_id = %s 
        ORDER BY sync_started_at DESC 
        LIMIT 1
        """, (device_id,))
        
        sync_log = cursor.fetchone()
        
        # Get pending operations count
        cursor.execute("""
        SELECT COUNT(*) as pending_count 
        FROM pending_operations 
        WHERE device_id = %s AND status = 'pending'
        """, (device_id,))
        
        pending_result = cursor.fetchone()
        pending_count = pending_result['pending_count'] if pending_result else 0
        
        return jsonify({
            'success': True,
            'latest_sync': sync_log,
            'pending_operations': pending_count
        })
        
    except Exception as e:
        logger.error(f"Error getting sync status: {e}")
        return jsonify({'error': 'Internal server error'}), 500
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000) 