import 'dart:developer' as developer;

import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';

/// Persisted client-token list UI preferences (filters + auto-refresh flag).
typedef ClientTokenListPreferencesData = ({
  String clientFilter,
  ClientTokenStatusFilter statusFilter,
  ClientTokenSortOption sortOption,
  bool autoRefreshAfterCreate,
});

/// Keys for persisting the client-token list filters in [IAppSettingsStore].
abstract final class ClientTokenListPreferenceKeys {
  static const String clientFilter = 'client_token_list_client_filter';
  static const String statusFilter = 'client_token_list_status_filter';
  static const String sortFilter = 'client_token_list_sort_filter';
  static const String autoRefreshAfterCreate = 'client_token_auto_refresh_after_create';
}

/// Restores and persists the client-token list filters and auto-refresh flag.
///
/// Extracted from `ClientTokenSection` so the widget no longer reaches into
/// `IAppSettingsStore` directly and the storage mapping is unit-testable.
class ClientTokenListPreferences {
  const ClientTokenListPreferences(this._resolveStore);

  final IAppSettingsStore? Function() _resolveStore;

  /// Reads the persisted preferences, or `null` when no store is available
  /// (so the caller keeps its current defaults). Read failures are logged and
  /// also yield `null`.
  ClientTokenListPreferencesData? restore() {
    final store = _resolveStore();
    if (store == null) {
      return null;
    }
    try {
      return (
        clientFilter: store.getString(ClientTokenListPreferenceKeys.clientFilter) ?? '',
        statusFilter: _statusFilterFromStorage(store.getString(ClientTokenListPreferenceKeys.statusFilter)),
        sortOption: _sortOptionFromStorage(store.getString(ClientTokenListPreferenceKeys.sortFilter)),
        autoRefreshAfterCreate: store.getBool(ClientTokenListPreferenceKeys.autoRefreshAfterCreate) ?? true,
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to restore client token preferences',
        name: 'client_token_list_preferences',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> save(ClientTokenListPreferencesData data) async {
    final store = _resolveStore();
    if (store == null) {
      return;
    }
    try {
      await store.setString(ClientTokenListPreferenceKeys.clientFilter, data.clientFilter.trim());
      await store.setString(ClientTokenListPreferenceKeys.statusFilter, _statusFilterToStorage(data.statusFilter));
      await store.setString(ClientTokenListPreferenceKeys.sortFilter, _sortOptionToStorage(data.sortOption));
      await store.setBool(ClientTokenListPreferenceKeys.autoRefreshAfterCreate, data.autoRefreshAfterCreate);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to save client token preferences',
        name: 'client_token_list_preferences',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static String _statusFilterToStorage(ClientTokenStatusFilter value) {
    return switch (value) {
      ClientTokenStatusFilter.all => 'all',
      ClientTokenStatusFilter.active => 'active',
      ClientTokenStatusFilter.revoked => 'revoked',
    };
  }

  static ClientTokenStatusFilter _statusFilterFromStorage(String? value) {
    return switch (value) {
      'active' => ClientTokenStatusFilter.active,
      'revoked' => ClientTokenStatusFilter.revoked,
      _ => ClientTokenStatusFilter.all,
    };
  }

  static String _sortOptionToStorage(ClientTokenSortOption value) {
    return switch (value) {
      ClientTokenSortOption.newest => 'newest',
      ClientTokenSortOption.oldest => 'oldest',
      ClientTokenSortOption.clientAsc => 'client_asc',
      ClientTokenSortOption.clientDesc => 'client_desc',
    };
  }

  static ClientTokenSortOption _sortOptionFromStorage(String? value) {
    return switch (value) {
      'oldest' => ClientTokenSortOption.oldest,
      'client_asc' => ClientTokenSortOption.clientAsc,
      'client_desc' => ClientTokenSortOption.clientDesc,
      _ => ClientTokenSortOption.newest,
    };
  }
}
