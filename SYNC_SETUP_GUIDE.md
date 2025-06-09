# Flutter Offline Synchronization Setup Guide

This guide explains how to set up and use the complete offline synchronization system for the Diapalet Flutter app with Flask backend.

## Architecture Overview

The system implements a robust offline-first architecture with the following components:

- **Flutter Mobile App**: Works offline by default, queues operations when disconnected
- **Local SQLite Database**: Stores all data locally with sync status tracking
- **Background Sync Service**: Automatically syncs every 30 seconds when online
- **Flask Backend API**: Handles sync requests and stores data in MySQL
- **Pending Operations Screen**: Manual sync interface for users

## Database Setup

### 1. Apply Sync Tables to Existing Database

Execute the SQL script to add synchronization tables to your existing rowhub database:

```bash
mysql -u your_username -p rowhub < sync_tables.sql
```

This adds the following tables:
- `pending_operations` - Stores pending operations from mobile devices
- `sync_log` - Tracks synchronization history
- `mobile_devices` - Manages registered mobile devices

### 2. Configure Database Connection

Update the Flask backend database configuration in `backend/app.py` or use environment variables:

```bash
export DB_HOST=localhost
export DB_PORT=3306
export DB_USER=root
export DB_PASSWORD=your_password
export DB_NAME=rowhub
```

## Backend Setup

### 1. Install Python Dependencies

```bash
cd backend
pip install -r requirements.txt
```

### 2. Run Flask Server

```bash
python app.py
```

The server will start on `http://localhost:5000`

### 3. Test API Health

```bash
curl http://localhost:5000/health
```

## Flutter App Setup

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Update Server URL

Edit `lib/core/sync/sync_service.dart` and change the base URL:

```dart
static const String baseUrl = 'http://your-server-ip:5000';
```

For local testing with Android emulator, use:
```dart
static const String baseUrl = 'http://10.0.2.2:5000';
```

For iOS simulator:
```dart
static const String baseUrl = 'http://localhost:5000';
```

### 3. Run the App

```bash
flutter run
```

## How It Works

### Online Mode

1. **Automatic Registration**: Device registers automatically with the backend on first connection
2. **Real-time Sync**: Operations are sent to the server immediately when performed
3. **Background Sync**: Every 30 seconds, the app checks for pending operations and syncs them
4. **Master Data Download**: Product and location data is synchronized from the server

### Offline Mode

1. **Local Storage**: All operations are saved to local SQLite database
2. **Sync Status Tracking**: Operations are marked with `synced = 0` when offline
3. **Queue Building**: Operations accumulate in the pending operations queue
4. **Auto-sync on Reconnection**: When connection is restored, background sync automatically uploads pending operations

### Manual Sync

1. **Pending Operations Screen**: Navigate from Home → "Bekleyen İşlemler" / "Pending Operations"
2. **View Pending**: See all operations waiting to be synchronized
3. **Manual Sync**: Press the sync button to force immediate synchronization
4. **Status Monitoring**: Real-time status updates show sync progress

## API Endpoints

The Flask backend provides these endpoints:

- `GET /health` - Health check
- `POST /api/register_device` - Register a mobile device
- `POST /api/sync/upload` - Upload pending operations
- `POST /api/sync/download` - Download master data
- `GET /api/sync/status/<device_id>` - Get sync status

## Testing the Flow

### 1. Setup Test Environment

1. Start MySQL database with rowhub schema
2. Apply sync tables: `mysql -u root -p rowhub < sync_tables.sql`
3. Start Flask backend: `python backend/app.py`
4. Start Flutter app: `flutter run`

### 2. Test Online Flow

1. Ensure device has internet connection
2. Perform goods receiving or pallet transfer operations
3. Check backend database to verify operations are saved
4. Monitor sync status in Pending Operations screen

### 3. Test Offline Flow

1. Disable internet connection on device
2. Perform several operations (goods receiving, transfers)
3. Navigate to Pending Operations screen - should show queued operations
4. Re-enable internet connection
5. Either wait for automatic sync (30 seconds) or press manual sync button
6. Verify operations appear in backend database

### 4. Test Error Handling

1. Stop Flask backend server
2. Try to sync - should show error status
3. Restart backend
4. Sync should resume automatically

## Customization

### Sync Interval

Change background sync frequency in `lib/core/sync/sync_service.dart`:

```dart
static const Duration syncInterval = Duration(seconds: 30);
```

### Server URL per Environment

Create different configurations for development, staging, and production:

```dart
class SyncConfig {
  static const String baseUrl = String.fromEnvironment(
    'SYNC_SERVER_URL',
    defaultValue: 'http://localhost:5000',
  );
}
```

### Add New Operation Types

1. Update the backend `process_operation` function in `app.py`
2. Add new operation type handling in Flutter `SyncService._getPendingOperations`
3. Update the `PendingOperation.displayTitle` for UI display

## Troubleshooting

### Common Issues

1. **Connection Refused**
   - Check if Flask server is running
   - Verify server URL in Flutter app
   - For Android emulator, use `10.0.2.2` instead of `localhost`

2. **Database Connection Error**
   - Verify MySQL is running
   - Check database credentials in Flask config
   - Ensure rowhub database exists

3. **Sync Not Working**
   - Check network connectivity
   - View logs in Flutter debug console
   - Check Flask server logs for errors

4. **Operations Not Appearing**
   - Verify operations are saved locally in SQLite
   - Check `synced` column values in local database
   - Monitor backend database for received operations

### Debug Mode

Enable verbose logging by setting debug mode in `sync_service.dart`:

```dart
debugPrint('Sync operation: $operation');
```

### Database Inspection

View local SQLite data:
```bash
# Find the database file
flutter packages pub run sqflite:sqflite_dev_tools

# Or use a SQLite browser to inspect:
# Android: /data/data/com.example.diapalet/databases/app_main_database.db
```

## Production Deployment

### Backend Deployment

1. Use a production WSGI server like Gunicorn:
```bash
pip install gunicorn
gunicorn -w 4 -b 0.0.0.0:5000 app:app
```

2. Set up environment variables for production database
3. Use HTTPS with SSL certificates
4. Set up monitoring and logging

### Mobile App

1. Update server URL to production endpoint
2. Build release APK/iOS app
3. Test thoroughly on actual devices
4. Consider implementing certificate pinning for security

This completes the setup guide for the offline synchronization system. The system provides robust offline capabilities while maintaining data integrity and user experience. 