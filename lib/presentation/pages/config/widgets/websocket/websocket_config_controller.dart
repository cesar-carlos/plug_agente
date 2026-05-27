import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/presentation/pages/config/config_form_controller.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:result_dart/result_dart.dart';

/// Sealed outcomes of a [WebSocketConfigController] orchestration call.
///
/// Splitting validation outcomes (missing url/agent/credentials, login
/// required, save failed) from a generic [Failure] keeps the UI responsible
/// for translating each case into the right localized feedback while the
/// controller stays free of `BuildContext`/`AppLocalizations` dependencies.
sealed class WebSocketActionOutcome {
  const WebSocketActionOutcome();
}

class WebSocketActionSuccess extends WebSocketActionOutcome {
  const WebSocketActionSuccess();
}

class WebSocketActionAlreadyBusy extends WebSocketActionOutcome {
  const WebSocketActionAlreadyBusy();
}

class WebSocketActionMissingServerUrl extends WebSocketActionOutcome {
  const WebSocketActionMissingServerUrl();
}

class WebSocketActionMissingAgentId extends WebSocketActionOutcome {
  const WebSocketActionMissingAgentId();
}

class WebSocketActionMissingCredentials extends WebSocketActionOutcome {
  const WebSocketActionMissingCredentials();
}

class WebSocketActionLoginRequired extends WebSocketActionOutcome {
  const WebSocketActionLoginRequired();
}

class WebSocketActionSaveFailed extends WebSocketActionOutcome {
  const WebSocketActionSaveFailed(this.failure);

  /// Raw exception produced by [ConfigProvider.saveConfig]. Typed as [Exception]
  /// to match `result_dart`'s default failure type. The concrete value is
  /// always a [Failure] (`domain/errors/failures.dart`), so consumers can
  /// safely call `toDisplayMessage()` (extension on [Object]) to render it.
  final Exception failure;
}

/// Coordinates the WebSocket connection page actions (login/logout, connect/
/// disconnect, persist) so the widget tree only renders state and surfaces
/// feedback. Concentrating orchestration here keeps presentation widgets
/// focused on layout and removes `Navigator`/`SettingsFeedback` calls from
/// the side-effecting flows.
class WebSocketConfigController {
  WebSocketConfigController({
    required ConfigProvider configProvider,
    required AuthProvider authProvider,
    required ConnectionProvider connectionProvider,
    required ConfigFormController formController,
  }) : _configProvider = configProvider,
       _authProvider = authProvider,
       _connectionProvider = connectionProvider,
       _formController = formController;

  final ConfigProvider _configProvider;
  final AuthProvider _authProvider;
  final ConnectionProvider _connectionProvider;
  final ConfigFormController _formController;

  Future<WebSocketActionOutcome> loginOrLogout() async {
    final currentConfigId = _configProvider.currentConfig?.id;
    if (_authProvider.isAuthenticatedForConfig(currentConfigId)) {
      await _connectionProvider.disconnect();
      await _authProvider.logout(
        configId: currentConfigId,
        clearStoredSession: true,
      );
      return const WebSocketActionSuccess();
    }

    final serverUrl = normalizeServerUrl(
      _formController.serverUrlController.text,
    );
    if (serverUrl.isEmpty) {
      return const WebSocketActionMissingServerUrl();
    }

    final agentId = _formController.agentIdController.text.trim();
    if (agentId.isEmpty) {
      return const WebSocketActionMissingAgentId();
    }

    final username = _formController.authUsernameController.text;
    final password = _formController.authPasswordController.text;
    if (username.isEmpty || password.isEmpty) {
      return const WebSocketActionMissingCredentials();
    }

    final saveResult = await _persistFormToConfig();
    return saveResult.fold(
      (savedConfig) async {
        await _authProvider.login(
          configId: savedConfig.id,
          serverUrl: savedConfig.serverUrl.trim(),
          credentials: AuthCredentials(
            username: username.trim(),
            password: password.trim(),
            agentId: savedConfig.agentId.trim(),
          ),
        );
        return const WebSocketActionSuccess();
      },
      (failure) async => WebSocketActionSaveFailed(failure),
    );
  }

  Future<WebSocketActionOutcome> connectOrDisconnect() async {
    final status = _connectionProvider.status;
    final isBusy =
        status == ConnectionStatus.connecting ||
        status == ConnectionStatus.negotiating ||
        status == ConnectionStatus.reconnecting;
    if (isBusy) {
      return const WebSocketActionAlreadyBusy();
    }

    if (_connectionProvider.isConnected) {
      await _connectionProvider.disconnect();
      return const WebSocketActionSuccess();
    }

    final serverUrl = normalizeServerUrl(
      _formController.serverUrlController.text,
    );
    final agentId = _formController.agentIdController.text.trim();
    if (serverUrl.isEmpty) {
      return const WebSocketActionMissingServerUrl();
    }
    if (agentId.isEmpty) {
      return const WebSocketActionMissingAgentId();
    }

    final saveResult = await _persistFormToConfig();
    return saveResult.fold(
      (savedConfig) async {
        final token = _authProvider.tokenForConfig(savedConfig.id)?.token.trim();
        if (!_authProvider.isAuthenticatedForConfig(savedConfig.id) ||
            token == null ||
            token.isEmpty) {
          return const WebSocketActionLoginRequired();
        }
        await _connectionProvider.connect(
          savedConfig.serverUrl.trim(),
          savedConfig.agentId.trim(),
          configId: savedConfig.id,
          authToken: token,
        );
        return const WebSocketActionSuccess();
      },
      (failure) async => WebSocketActionSaveFailed(failure),
    );
  }

  Future<Result<Config>> persistCurrentConfig() {
    return _persistFormToConfig();
  }

  Future<Result<Config>> _persistFormToConfig() {
    _formController.updateAllFieldsToProvider(_configProvider);
    return _configProvider.saveConfig();
  }
}
