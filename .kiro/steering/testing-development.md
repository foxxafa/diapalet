# Test ve Geliştirme Rehberi - Diapalet

## Test Stratejisi

### Test Piramidi
1. **Unit Tests**: İş mantığı ve utility fonksiyonları
2. **Widget Tests**: UI bileşenleri ve etkileşimler
3. **Integration Tests**: End-to-end senaryolar

### Test Klasör Yapısı
```
test/
├── unit/
│   ├── core/
│   └── features/
├── widget/
│   ├── core/
│   └── features/
└── integration/
    └── scenarios/
```

## Unit Testing

### Repository Tests
```dart
group('GoodsReceivingRepository', () {
  test('should return purchase orders when online', () async {
    // Arrange
    when(mockNetworkInfo.isConnected).thenAnswer((_) async => true);

    // Act
    final result = await repository.getPurchaseOrders();

    // Assert
    expect(result.isRight(), true);
  });
});
```

### ViewModel Tests
```dart
group('GoodsReceivingViewModel', () {
  test('should emit loading then success states', () async {
    // Test state management
    expectLater(
      viewModel.stream,
      emitsInOrder([LoadingState(), SuccessState(data)]),
    );

    await viewModel.loadPurchaseOrders();
  });
});
```

## Widget Testing

### Screen Tests
```dart
testWidgets('should display purchase orders list', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: GoodsReceivingScreen(),
    ),
  );

  expect(find.byType(ListView), findsOneWidget);
  expect(find.text('Purchase Orders'), findsOneWidget);
});
```

### Mock Setup
```dart
class MockGoodsReceivingRepository extends Mock
    implements GoodsReceivingRepository {}

class MockSyncService extends Mock implements SyncService {}
```

## Development Workflow

### Git Workflow
- **main**: Production ready kod
- **develop**: Development branch
- **feature/**: Yeni özellikler
- **hotfix/**: Acil düzeltmeler

### Commit Messages
```
feat: add QR code scanning for goods receiving
fix: resolve offline sync issue
docs: update API documentation
test: add unit tests for inventory transfer
```

### Code Review Checklist
- [ ] Kod standartlarına uygun
- [ ] Unit testler yazılmış
- [ ] Error handling yapılmış
- [ ] Localization uygulanmış
- [ ] Performance optimizasyonu
- [ ] Accessibility kontrolleri

## Debugging

### Debug Tools
- Flutter Inspector
- Dio Interceptor (network logs)
- SQLite browser (database inspection)
- Provider DevTools

### Logging
```dart
// Debug logging
if (kDebugMode) {
  print('Debug: $message');
}

// Error logging
logger.error('Error occurred', error: e, stackTrace: stackTrace);
```

## Performance

### Optimization Tips
- ListView.builder kullan (büyük listeler için)
- Image caching uygula
- Unnecessary rebuilds'i önle
- Database query'leri optimize et
- Memory leaks'i kontrol et

### Monitoring
- App startup time
- Frame rendering performance
- Memory usage
- Network request times
- Database query performance