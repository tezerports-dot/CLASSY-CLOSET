import '../../../../core/services/retail_store.dart';

class ProductsRepository {
  const ProductsRepository(this._store);

  final RetailStore _store;

  List<ProductRecord> get cachedProducts => List.unmodifiable(_store.products);
  Future<void> addProduct(ProductRecord product) => _store.addProduct(product);
  Future<void> refresh() => _store.refresh();
}
