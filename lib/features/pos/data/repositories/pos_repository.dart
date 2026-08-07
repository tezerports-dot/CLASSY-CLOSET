import '../../../../core/services/retail_store.dart';

class PosRepository {
  const PosRepository(this._store);

  final RetailStore _store;

  List<CartLine> get cart => List.unmodifiable(_store.cart);
  void addToCart(ProductRecord product) => _store.addToCart(product);
  void removeFromCart(CartLine line) => _store.removeFromCart(line);
  Future<SaleRecord> checkout({CustomerRecord? customer, required double paid}) => _store.checkout(customer: customer, paid: paid);
}
