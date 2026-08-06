import 'package:get_it/get_it.dart';

import '../../core/database/app_database.dart';
import '../../core/services/retail_store.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  if (!getIt.isRegistered<AppDatabase>()) {
    getIt.registerLazySingleton<AppDatabase>(AppDatabase.new);
  }
  if (!getIt.isRegistered<RetailStore>()) {
    getIt.registerLazySingleton<RetailStore>(RetailStore.new);
  }
}
