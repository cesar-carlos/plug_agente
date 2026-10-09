import 'dart:developer' as developer;

import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Persisted client-token list UI preferences (filters + auto-refresh flag).
typedef ClientTokenListPreferencesData = ({
  String clientFilter,
  ClientTokenStatusFilter statusFilter,
  ClientTokenSortOption sortOption,
  bool autoRefreshAfterCreate,
  int pageSize,
});

/// Keys for persisting the client-token list filters in [IAppSettingsStore].
abstract final class ClientTokenListPreferenceKeys {
  static const String clientFilter = 'client_token_list_client_filter';
  static const String statusFilter = 'client_token_list_status_filter';
  static const String sortFilter = 'client_token_list_sort_filter';
  static const String autoRefreshAfterCreate = 'client_token_auto_refresh_after_create';
  static const String pageSize = 'client_token_list_page_size';
}

/// Restores and persists the client-token list filters and auto-refresh flag.
///
/// Extracted from `ClientTokenSection` so the widget no longer reaches into
/// `IAppSettingsStore` directly and the storage mapping is unit-testable.
class ClientTokenListPreferences {
  ClientTokenListPreferences(this._resolveStore);

  final IAppSettingsStore? Function() _resolveStore;
  domain.ConfigurationFailure? lastFailure;

  /// Reads the persisted preferences, or `null` when no store is available
  /// (so the caller keeps its current defaults). Read failures are logged and
  /// also yield `null`.
  ClientTokenListPreferencesData? restore() {
    lastFailure = null;
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
        pageSize: _validPageSize(store.getInt(ClientTokenListPreferenceKeys.pageSize)),
      );
    } on Exception catch (error, stackTrace) {
      lastFailure = domain.ConfigurationFailure.withContext(
        message: 'Não foi possível restaurar as preferências da lista de tokens.',
        cause: error,
        context: const {'operation': 'restore_client_token_preferences'},
      );
      developer.log(
        'Failed to restore client token preferences',
        name: 'client_token_list_preferences',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<Result<void>> save(ClientTokenListPreferencesData data) async {
    lastFailure = null;
    final store = _resolveStore();
    if (store == null) {
      return const Success(unit);
    }
    try {
      await store.setValues({
        ClientTokenListPreferenceKeys.clientFilter: data.clientFilter.trim(),
        ClientTokenListPreferenceKeys.statusFilter: _statusFilterToStorage(data.statusFilter),
        ClientTokenListPreferenceKeys.sortFilter: _sortOptionToStorage(data.sortOption),
        ClientTokenListPreferenceKeys.autoRefreshAfterCreate: data.autoRefreshAfterCreate,
        ClientTokenListPreferenceKeys.pageSize: _validPageSize(data.pageSize),
      });
      return const Success(unit);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to save client token preferences',
        name: 'client_token_list_preferences',
        error: error,
        stackTrace: stackTrace,
      );
      final failure = domain.ConfigurationFailure.withContext(
        message: 'Não foi possível salvar as preferências da lista de tokens.',
        cause: error,
        context: const {'operation': 'save_client_token_preferences'},
      );
      lastFailure = failure;
      return Failure(failure);
    }
  }

  static int _validPageSize(int? value) =>
      ClientTokenListQuery.supportedPageSizes.contains(value) ? value! : ClientTokenListQuery.defaultPageSize;

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
