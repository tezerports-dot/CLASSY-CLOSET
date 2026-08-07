import '../../../../core/services/retail_store.dart';

class CustomersRepository {
  const CustomersRepository(this._store);

  final RetailStore _store;

  List<CustomerRecord> get cachedCustomers => List.unmodifiable(_store.customers);
  Future<void> addCustomer(CustomerRecord customer) => _store.addCustomer(customer);
  Future<void> refresh() => _store.refresh();
}
