import 'package:get_it/get_it.dart';

import '../../core/database/app_database.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/printer_service.dart';
import '../../core/services/retail_store.dart';
import '../../features/auth/data/repositories/auth_repository.dart';
import '../../features/customers/data/repositories/customers_repository.dart';
import '../../features/pos/data/repositories/pos_repository.dart';
import '../../features/products/data/repositories/products_repository.dart';
import '../../features/suppliers/data/repositories/suppliers_repository.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  if (!getIt.isRegistered<AppDatabase>()) {
    getIt.registerLazySingleton<AppDatabase>(AppDatabase.new);
  }
  if (!getIt.isRegistered<RetailStore>()) {
    getIt.registerLazySingleton<RetailStore>(
      () => RetailStore(getIt<AppDatabase>()),
    );
  }
  if (!getIt.isRegistered<BackupService>()) {
    getIt.registerLazySingleton<BackupService>(
      () => BackupService(getIt<AppDatabase>()),
    );
  }
  if (!getIt.isRegistered<PrinterService>()) {
    getIt.registerLazySingleton<PrinterService>(PrinterService.new);
  }
  if (!getIt.isRegistered<AuthRepository>()) {
    getIt.registerLazySingleton<AuthRepository>(
      () => AuthRepository(getIt<RetailStore>()),
    );
  }
  if (!getIt.isRegistered<ProductsRepository>()) {
    getIt.registerLazySingleton<ProductsRepository>(
      () => ProductsRepository(getIt<RetailStore>()),
    );
  }
  if (!getIt.isRegistered<CustomersRepository>()) {
    getIt.registerLazySingleton<CustomersRepository>(
      () => CustomersRepository(getIt<RetailStore>()),
    );
  }
  if (!getIt.isRegistered<SuppliersRepository>()) {
    getIt.registerLazySingleton<SuppliersRepository>(
      () => SuppliersRepository(getIt<RetailStore>()),
    );
  }
  if (!getIt.isRegistered<PosRepository>()) {
    getIt.registerLazySingleton<PosRepository>(
      () => PosRepository(getIt<RetailStore>()),
    );
  }
  await getIt<RetailStore>().initialize();
}
