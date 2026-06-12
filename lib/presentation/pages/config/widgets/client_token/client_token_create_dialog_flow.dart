import 'dart:math' show max, min;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_content.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_footer.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_create_dialog_shell.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_coordinator.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:provider/provider.dart';

Future<void> showClientTokenCreateDialog({
  required BuildContext context,
  required ClientTokenSectionController controller,
  required ClientTokenSectionCoordinator coordinator,
  required ClientTokenProvider provider,
  ClientTokenSummary? baseToken,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final isEditingToken = baseToken != null;

  controller.loadTokenIntoForm(baseToken);
  provider.clearError();
  provider.clearLastCreatedToken();
  provider.clearLastUpdateOutcome();

  controller.attachDialogControllerListeners();
  controller.markCreateTokenDialogOpen(true);
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: l10n.ctDialogDismissCreateToken,
      barrierColor: Colors.black.withValues(
        alpha: createTokenBarrierOpacity,
      ),
      pageBuilder: (_, primaryAnimation, secondaryAnimation) {
        return ValueListenableBuilder<int>(
          valueListenable: controller.createTokenDialogRevision,
          builder: (dialogContext, revision, child) {
            final mediaQuery = MediaQuery.of(dialogContext);
            final availableHeight =
                (mediaQuery.size.height - mediaQuery.padding.vertical - mediaQuery.viewInsets.bottom).clamp(
                  0.0,
                  double.infinity,
                );
            final availableWidth = mediaQuery.size.width - (createTokenDialogHorizontalMargin * 2);
            final dialogWidth = availableWidth.clamp(
              420.0,
              createTokenDialogMaxWidth,
            );
            final factorHeight = availableHeight * createTokenDialogHeightFactor;
            final minPreferredOuter = min(
              createTokenDialogMinPreferredOuterHeight,
              availableHeight,
            );
            final dialogOuterMaxHeight = max(factorHeight, minPreferredOuter);
            final isCompact = dialogWidth < createTokenDialogCompactWidthBreakpoint;
            final theme = FluentTheme.of(dialogContext);
            final dialogL10n = AppLocalizations.of(dialogContext)!;
            final formError = ClientTokenSectionCoordinator.formErrorMessage(
              dialogL10n,
              controller.formErrorKey,
            );

            return ChangeNotifierProvider<ClientTokenProvider>.value(
              value: provider,
              child: ClientTokenCreateDialogShell(
                navigatorContext: dialogContext,
                agentFocusNode: controller.createTokenDialogAgentFocusNode,
                dialogWidth: dialogWidth,
                dialogOuterMaxHeight: dialogOuterMaxHeight,
                theme: theme,
                isEditingToken: isEditingToken,
                body: (context, tokenProvider) {
                  final hasChanges = controller.hasFormChanges();
                  final policyChanged = controller.hasPolicyChanges();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClientTokenCreateDialogContent(
                          isCompact: isCompact,
                          isEditingToken: isEditingToken,
                          policyChanged: policyChanged,
                          hasFormChanges: hasChanges,
                          agentFocusNode: controller.createTokenDialogAgentFocusNode,
                          nameController: controller.nameController,
                          clientIdController: controller.clientIdController,
                          agentIdController: controller.agentIdController,
                          payloadController: controller.payloadController,
                          rules: controller.rules,
                          allTables: controller.allTables,
                          allViews: controller.allViews,
                          globalCanRead: controller.globalCanRead,
                          globalCanUpdate: controller.globalCanUpdate,
                          globalCanDelete: controller.globalCanDelete,
                          globalCanDdl: controller.globalCanDdl,
                          formError: formError,
                          providerError: tokenProvider.error,
                          lastCreatedToken: tokenProvider.lastCreatedToken,
                          onToggleAllTables: (value) {
                            controller.allTables = value;
                            controller.notifyCreateTokenDialogChanged();
                          },
                          onToggleAllViews: (value) {
                            controller.allViews = value;
                            controller.notifyCreateTokenDialogChanged();
                          },
                          onToggleGlobalRead: (value) {
                            controller.globalCanRead = value;
                            controller.notifyCreateTokenDialogChanged();
                          },
                          onToggleGlobalUpdate: (value) {
                            controller.globalCanUpdate = value;
                            controller.notifyCreateTokenDialogChanged();
                          },
                          onToggleGlobalDelete: (value) {
                            controller.globalCanDelete = value;
                            controller.notifyCreateTokenDialogChanged();
                          },
                          onToggleGlobalDdl: (value) {
                            controller.globalCanDdl = value;
                            controller.notifyCreateTokenDialogChanged();
                          },
                          onAddRule: () => coordinator.openAddRuleModal(dialogContext),
                          onExportRules: () => coordinator.handleExportRules(dialogContext),
                          onImportRules: () => coordinator.handleImportRulesFromSection(dialogContext),
                          isImportingRules: controller.isImportingRules,
                          onEditRule: (index) => coordinator.openEditRuleModal(dialogContext, index),
                          onDeleteRule: controller.removeRule,
                          onDismissCreatedToken: tokenProvider.clearLastCreatedToken,
                          onFieldSubmitted: () => coordinator.handleSubmitToken(dialogContext, tokenProvider),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ClientTokenCreateDialogFooter(
                        isCreating: tokenProvider.isCreating,
                        canSubmit: hasChanges,
                        submitLabel: isEditingToken
                            ? AppLocalizations.of(dialogContext)!.ctButtonSaveTokenChanges
                            : AppLocalizations.of(dialogContext)!.ctButtonCreateToken,
                        onCancel: () => Navigator.of(dialogContext).pop(),
                        onSubmit: () => coordinator.handleSubmitToken(dialogContext, tokenProvider),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: curved.drive(
              Tween(begin: createTokenScaleStart, end: 1),
            ),
            child: child,
          ),
        );
      },
    );
  } finally {
    controller.markCreateTokenDialogOpen(false);
    controller.detachDialogControllerListeners();
  }
}
