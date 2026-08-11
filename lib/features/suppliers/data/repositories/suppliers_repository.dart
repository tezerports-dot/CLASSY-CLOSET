import '../../../../core/services/retail_store.dart';

class SuppliersRepository {
  const SuppliersRepository(this._store);

  final RetailStore _store;

  List<SupplierRecord> get cachedSuppliers =>
      List.unmodifiable(_store.suppliers);
  Future<void> refresh() => _store.refresh();
}
