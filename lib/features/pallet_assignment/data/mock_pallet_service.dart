import '../domain/pallet_repository.dart';

class MockPalletService implements PalletRepository {
  @override
  List<String> getPalletList() {
    return ['Palet #1', 'Palet #2', 'Palet #3'];
  }
}
