import 'dart:async';
import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_file_service.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';

class ClientTokenSectionCoordinator {
  ClientTokenSectionCoordinator({
    required this.controller,
    this.scrollController,
  });

  final ClientTokenSectionController controller;
  final ScrollController? scrollController;

  static String formErrorMessage(AppLocalizations l10n, ClientTokenFormErrorKey? key) {
    return switch (key) {
      ClientTokenFormErrorKey.globalPermissionRequired => l10n.ctErrorGlobalPermissionRequired,
      ClientTokenFormErrorKey.ruleOrGlobalPermissionsRequired => l10n.ctErrorRuleOrGlobalPermissionsRequired,
      ClientTokenFormErrorKey.payloadInvalidJson => l10n.ctErrorPayloadInvalidJson,
      ClientTokenFormErrorKey.payloadMustBeJsonObject => l10n.ctErrorPayloadMustBeJsonObject,
      ClientTokenFormErrorKey.payloadDatabaseMustBeString => l10n.ctErrorPayloadDatabaseMustBeString,
      ClientTokenFormErrorKey.payloadDatabaseCannotBeEmpty => l10n.ctErrorPayloadDatabaseCannotBeEmpty,
      null => '',
    };
  }

  static String statusFilterLabel(AppLocalizations l10n, ClientTokenStatusFilter value) {
    return switch (value) {
      ClientTokenStatusFilter.all => l10n.ctFilterStatusAll,
      ClientTokenStatusFilter.active => l10n.ctFilterStatusActive,
      ClientTokenStatusFilter.revoked => l10n.ctFilterStatusRevoked,
    };
  }

  static String sortFilterLabel(AppLocalizations l10n, ClientTokenSortOption value) {
    return switch (value) {
      ClientTokenSortOption.newest => l10n.ctSortNewest,
      ClientTokenSortOption.oldest => l10n.ctSortOldest,
      ClientTokenSortOption.clientAsc => l10n.ctSortClientAsc,
      ClientTokenSortOption.clientDesc => l10n.ctSortClientDesc,
    };
  }

  Future<void> initializeTokenListState(ClientTokenProvider provider) async {
    final restored = controller.restoreListPreferences();
    if (restored != null) {
      controller.applyRestoredListPreferences(restored);
    }
    if (!provider.hasLoaded) {
      await provider.loadTokens(query: controller.buildListQuery());
    }
  }

  Future<void> openAddRuleModal(BuildContext context) async {
    if (controller.isGlobalScopeMode) {
      return;
    }
    final result = await showClientTokenRuleDialog(
      context: context,
      existingRules: List.unmodifiable(controller.rules),
    );
    if (!context.mounted || result == null) {
      return;
    }

    controller.mergeRules(result);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        controller.notifyCreateTokenDialogChanged();
      }
    });
  }

  Future<void> openEditRuleModal(BuildContext context, int index) async {
    final result = await showClientTokenRuleDialog(
      context: context,
      initialRule: controller.rules[index],
      existingRules: List.unmodifiable(controller.rules),
    );
    if (!context.mounted || result == null) {
      return;
    }

    controller.rules[index] = result.first;
    controller.notifyCreateTokenDialogChanged();
  }

  Future<void> handleImportRulesFromSection(BuildContext context) async {
    if (!context.mounted || controller.isImportingRules || controller.isGlobalScopeMode) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;

    try {
      final picked = await controller.pickRulesImportFile();
      if (picked == null || picked.files.isEmpty) {
        return;
      }
      final filePath = picked.files.single.path;
      if (filePath == null) {
        return;
      }

      controller.setImportingRules(true);

      final outcome = await controller.importRulesFromPath(filePath);
      if (!context.mounted) {
        return;
      }

      switch (outcome) {
        case ClientTokenRuleImportEmpty():
          SettingsFeedback.showError(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesErrorEmpty,
          );
        case ClientTokenRuleImportTooLarge():
          SettingsFeedback.showError(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesErrorFileTooLarge,
          );
        case ClientTokenRuleImportInvalidFormat(:final line, :final content):
          SettingsFeedback.showError(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesErrorInvalidFormat(line, content),
          );
        case ClientTokenRuleImportReadFailure(:final error, :final stackTrace):
          developer.log('Failed to import rules', name: 'client_token_section', error: error, stackTrace: stackTrace);
          SettingsFeedback.showError(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesErrorEmpty,
          );
        case ClientTokenRuleImportLoaded(:final drafts):
          controller.mergeRules(drafts);
          controller.notifyCreateTokenDialogChanged();
          SettingsFeedback.showSuccess(
            context: context,
            title: l10n.ctButtonImportRules,
            message: l10n.ctImportRulesSuccess(drafts.length),
          );
      }
    } on Exception catch (e, st) {
      developer.log('Rule import picker failed', name: 'client_token_section', error: e, stackTrace: st);
      if (context.mounted) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonImportRules,
          message: l10n.ctImportRulesErrorReadFailed,
        );
      }
    } finally {
      if (context.mounted) {
        controller.setImportingRules(false);
      }
    }
  }

  Future<void> handleExportRules(BuildContext context) async {
    if (controller.rules.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;

    final tokenName = controller.nameController.text.trim();
    final defaultFileName = tokenName.isNotEmpty
        ? '${tokenName.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_').replaceAll(RegExp(r'_+$'), '')}.txt'
        : l10n.ctExportRulesDefaultFileName;

    try {
      final savePath = await controller.pickRulesExportPath(defaultFileName);
      if (savePath == null) {
        return;
      }
      await controller.exportRulesToPath(savePath);
    } on Exception catch (e, st) {
      developer.log(
        'Failed to export rules',
        name: 'client_token_section',
        error: e,
        stackTrace: st,
      );
      if (context.mounted) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.ctButtonExportRules,
          message: l10n.ctExportRulesError,
        );
      }
    }
  }

  Future<void> handleSubmitToken(BuildContext context, ClientTokenProvider provider) async {
    controller.clearFormError();
    controller.notifyCreateTokenDialogChanged();

    final navigator = Navigator.of(context, rootNavigator: true);
    provider.clearError();
    provider.clearLastCreatedToken();

    final request = controller.buildSubmitRequest();
    if (request == null) {
      return;
    }

    final previousOffset = currentScrollOffset();
    final currentEditingTokenId = controller.editingTokenId;
    final isSuccess = currentEditingTokenId == null
        ? await provider.createToken(
            request,
            refreshTokens: false,
          )
        : await provider.updateToken(
            currentEditingTokenId,
            request,
            refreshTokens: false,
            expectedVersion: controller.editingTokenVersion,
          );

    if (isSuccess && context.mounted) {
      if (controller.autoRefreshAfterCreate) {
        await refreshTokensPreservingPosition(context, provider, previousOffset);
      }
      if (!context.mounted) {
        return;
      }
      controller.clearFormError();
      controller.notifyCreateTokenDialogChanged();
      if (provider.error.isEmpty) {
        final outcome = provider.lastUpdateOutcome;
        final rotatedTokenValue = provider.lastCreatedToken;
        controller.clearTokenDraftForm();
        navigator.pop();
        if (currentEditingTokenId != null) {
          showEditOutcomeFeedback(
            context: context,
            outcome: outcome,
            rotatedTokenValue: rotatedTokenValue,
          );
        }
      }
    }
  }

  void showEditOutcomeFeedback({
    required BuildContext context,
    required ClientTokenUpdateOutcome? outcome,
    required String? rotatedTokenValue,
  }) {
    if (!context.mounted || outcome == null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    switch (outcome) {
      case ClientTokenUpdateOutcome.unchanged:
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctMsgTokenNoChanges),
            onClose: close,
          ),
        );
        return;
      case ClientTokenUpdateOutcome.metadataOnly:
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctMsgTokenMetadataUpdated),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
        return;
      case ClientTokenUpdateOutcome.rotated:
        if (rotatedTokenValue == null || rotatedTokenValue.isEmpty) {
          return;
        }
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctMsgTokenRotated),
            content: SelectableText(rotatedTokenValue),
            severity: InfoBarSeverity.success,
            onClose: close,
            action: FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: rotatedTokenValue));
                close();
              },
              child: Text(l10n.ctButtonCopyToken),
            ),
          ),
        );
        return;
    }
  }

  Future<void> clearTokenFilters(ClientTokenProvider provider) async {
    controller.clearTokenFilters();
    await controller.saveListPreferences();
    await reloadTokensForCurrentFilters(provider);
  }

  double? currentScrollOffset() {
    final controller = scrollController;
    if (controller == null || !controller.hasClients) {
      return null;
    }
    return controller.offset;
  }

  Future<void> refreshTokensPreservingPosition(
    BuildContext context,
    ClientTokenProvider provider,
    double? previousOffset,
  ) async {
    final refreshed = await provider.loadTokens(
      silent: true,
      query: controller.buildListQuery(),
    );
    if (!refreshed || previousOffset == null || !context.mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scroll = scrollController;
      if (scroll == null || !scroll.hasClients) {
        return;
      }
      final clampedOffset = previousOffset.clamp(
        scroll.position.minScrollExtent,
        scroll.position.maxScrollExtent,
      );
      scroll.jumpTo(clampedOffset);
    });
  }

  Future<void> handleCopyToken(
    BuildContext context,
    ClientTokenProvider provider,
    ClientTokenSummary token,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await provider.getTokenSecret(token.id);
    if (!context.mounted) {
      return;
    }

    result.fold(
      (lookup) {
        final tokenValue = lookup.tokenValue;
        if (!lookup.isAvailable) {
          displayInfoBar(
            context,
            builder: (context, close) => InfoBar(
              title: Text(l10n.ctInfoClientTokenUnavailable),
              severity: InfoBarSeverity.warning,
            ),
          );
          return;
        }

        Clipboard.setData(ClipboardData(text: tokenValue!));
        provider.recordCopiedToken(
          tokenId: token.id,
          clientId: token.clientId,
        );
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctInfoClientTokenCopied),
            severity: InfoBarSeverity.success,
          ),
        );
      },
      (failure) {
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.ctInfoClientTokenLoadFailed),
            content: SelectableText(failure.toDisplayMessage()),
            severity: InfoBarSeverity.error,
          ),
        );
      },
    );
  }

  Future<void> handleRevoke(
    BuildContext context,
    ClientTokenProvider provider,
    ClientTokenSummary token,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await SettingsFeedback.showConfirmation(
      context: context,
      title: l10n.ctConfirmRevokeTitle,
      message: l10n.ctConfirmRevokeMessage,
      confirmText: l10n.ctButtonRevoke,
    );
    if (!context.mounted || !confirmed) {
      return;
    }
    await provider.revokeToken(token.id);
    if (!context.mounted) {
      return;
    }
    if (provider.error.isNotEmpty) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: provider.error,
        onConfirm: () => provider.clearError(),
      );
    }
  }

  Future<void> handleDelete(
    BuildContext context,
    ClientTokenProvider provider,
    ClientTokenSummary token,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await SettingsFeedback.showConfirmation(
      context: context,
      title: l10n.ctConfirmDeleteTitle,
      message: l10n.ctConfirmDeleteMessage,
      confirmText: l10n.ctButtonDelete,
    );
    if (!context.mounted || !confirmed) {
      return;
    }
    await provider.deleteToken(token.id);
    if (!context.mounted) {
      return;
    }
    if (provider.error.isNotEmpty) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: provider.error,
        onConfirm: () => provider.clearError(),
      );
    }
  }

  Future<void> reloadTokensForCurrentFilters(ClientTokenProvider provider) async {
    await provider.loadTokens(
      silent: true,
      query: controller.buildListQuery(),
    );
  }
}
