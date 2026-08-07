import '../../../../core/services/retail_store.dart';

/// Phase-1 local auth repository facade backed by Drift through [RetailStore].
///
/// This keeps the existing shell stable while the feature BLoCs are expanded in
/// later sessions.
class AuthRepository {
  const AuthRepository(this._store);

  final RetailStore _store;

  AppUser? get currentUser => _store.currentUser;
  bool get isAuthenticated => _store.isAuthenticated;

  Future<bool> login(String username, String password) => _store.login(username, password);
  Future<void> logout() => _store.logout();
}
