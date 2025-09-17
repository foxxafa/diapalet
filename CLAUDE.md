# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RowHub WMS is a comprehensive warehouse management system with:
- **Frontend**: Flutter app (mobile-first design)
- **Backend**: PHP with Yii2 framework
- **Database**: SQLite (local) + MySQL/PostgreSQL (server)
- **Architecture**: Clean Architecture with Repository pattern

## Development Commands

### Flutter Frontend
```bash
# Install dependencies
flutter pub get

# Run the application
flutter run

# Analyze code for issues
flutter analyze

# Run tests
flutter test

# Build for production
flutter build apk
flutter build ios
```

### Backend (PHP/Yii2)
```bash
# Install PHP dependencies
cd backend && composer install

# Run database migrations
php yii migrate

# Start development server (if needed)
php -S localhost:8000 -t web/
```

## Architecture Overview

### Flutter App Structure (lib/)
```
lib/
├── core/                    # Shared utilities and services
│   ├── constants/          # App constants and enums
│   ├── local/              # SQLite database management
│   ├── network/            # API configuration and networking
│   ├── services/           # Business services (PDF, barcode, etc.)
│   ├── sync/               # Offline/online synchronization
│   ├── theme/              # App theming and styling
│   └── widgets/            # Reusable UI components
├── features/               # Feature-based modules
│   ├── auth/               # Authentication
│   ├── goods_receiving/    # QR-based goods receiving
│   ├── inventory_transfer/ # Stock movement between locations
│   ├── inventory_inquiry/  # Stock status and queries
│   └── pending_operations/ # Offline operations management
└── main.dart              # App entry point with dependency injection
```

### Clean Architecture Pattern
Each feature follows Clean Architecture with:
- **data/repositories/**: Repository implementations with local/remote data sources
- **domain/repositories/**: Repository interfaces
- **domain/entities/**: Business entities
- **presentation/**: UI screens and view models

### Backend Structure (backend/)
```
backend/
├── controllers/        # API endpoints and request handling
├── models/            # Database models and business logic
├── config/            # Application configuration
├── migrations/        # Database schema migrations
└── components/        # Reusable backend components
```

## Key Technologies & Dependencies

### State Management
- **Provider pattern**: Primary state management
- **ChangeNotifier**: For reactive view models
- Global providers setup in `main.dart`

### Database & Persistence
- **SQLite**: Local database via `sqflite` package
- **DatabaseHelper**: Singleton database management (`lib/core/local/database_helper.dart`)
- **Offline-first**: Operations work without connectivity

### Networking
- **Dio**: HTTP client with interceptors
- **ApiConfig**: Centralized API configuration (`lib/core/network/api_config.dart`)
- **Auto-sync**: Background synchronization when online

### Core Features
- **QR/Barcode scanning**: `mobile_scanner` package
- **Internationalization**: `easy_localization` for Turkish/English
- **PDF generation**: For reports and labels
- **Intent handling**: Barcode scanner integration

## Development Guidelines

### Code Organization
- Follow existing feature-based folder structure
- Use Clean Architecture layers consistently
- Implement Repository pattern for data access
- Keep view models focused and testable

### Database Operations
- Use `DatabaseHelper.instance` for all SQLite operations
- Implement proper transaction handling for data consistency
- Follow existing table naming conventions in `database_constants.dart`

### API Integration
- Use configured Dio instance from `ApiConfig`
- Implement proper error handling with `NetworkInfo`
- Support offline operations with sync queue

### Testing
- Test files should mirror the lib/ structure
- Use repository mocks for unit testing
- Test offline/online scenarios for sync operations

## Custom Lint Rules

The project uses custom analysis options in `analysis_options.yaml`:
- `prefer_const_declarations: false` - Due to database constants system
- `prefer_interpolation_to_compose_strings: false` - Performance considerations
- `use_build_context_synchronously: false` - Mounted checks are implemented manually

## Sync & Offline Operations

The app supports full offline functionality:
- **PendingOperation**: Queue system for offline actions
- **SyncService**: Handles background synchronization
- **Conflict resolution**: Smart merging of offline/online data changes
- Operations are queued locally and synced when connectivity returns