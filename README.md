# RowHub DWMS

**Digital Warehouse Management System**

A comprehensive Flutter-based warehouse management application that streamlines warehouse operations through QR/Barcode scanning technology.

## Features

### 📦 Goods Receiving
- **Order-based receiving**: Receive goods against purchase orders with automatic validation
- **Free receiving**: Accept goods without predefined orders using delivery note numbers
- **QR/Barcode scanning**: Quick product identification and quantity entry
- **Expiry date tracking**: Monitor product shelf life and expiration dates
- **Pallet management**: Support for both pallet and individual item receiving

### 📍 Inventory Transfer & Put-away
- **Location-based transfers**: Move inventory between warehouse locations/shelves
- **Put-away operations**: Transfer received goods from receiving area to storage locations
- **Flexible modes**: Support both pallet-level and item-level transfers
- **Real-time stock updates**: Automatic inventory adjustments with each operation

### 📊 Stock Management
- **Real-time inventory tracking**: Live stock levels across all locations
- **FIFO logic**: First-in-first-out stock rotation for expiring products
- **Multi-location support**: Manage inventory across multiple warehouse zones
- **Stock status tracking**: Monitor items through receiving, available, and transfer states

### 🔄 Offline/Online Synchronization
- **Offline capability**: Continue operations even without internet connectivity
- **Auto-sync**: Automatic data synchronization when connection is restored
- **Conflict resolution**: Smart handling of data conflicts during sync

### 📱 Mobile-First Design
- **Responsive UI**: Optimized for handheld devices and scanners
- **Touch-friendly controls**: Large buttons and intuitive navigation
- **Dark/Light themes**: Comfortable viewing in various lighting conditions
- **Multilingual support**: Turkish and English language options

## Technology Stack

- **Frontend**: Flutter (Dart)
- **Backend**: PHP with Yii2 framework
- **Database**: SQLite (local) + MySQL/PostgreSQL (server)
- **Architecture**: Clean Architecture with Repository pattern
- **State Management**: Provider pattern
- **Local Storage**: SQLite with CRUD operations
- **Networking**: HTTP REST APIs with Dio client

## Getting Started

### Prerequisites
- Flutter SDK (>=3.8.0)
- Dart SDK
- Android/iOS development environment
- Backend server setup (optional for offline testing)

### Installation

1. Clone the repository
```bash
git clone <repository-url>
cd rowhub-dwms
```

2. Install dependencies
```bash
flutter pub get
```

3. Run the application
```bash
flutter run
```

## Usage

1. **Login**: Authenticate with your warehouse credentials
2. **Goods Receiving**: Scan QR codes to receive incoming shipments
3. **Put-away**: Transfer received goods to storage locations
4. **Stock Transfer**: Move inventory between locations as needed
5. **Sync**: Data automatically syncs with server when online

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is proprietary software. All rights reserved.
