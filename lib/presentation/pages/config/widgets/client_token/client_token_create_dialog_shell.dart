import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:provider/provider.dart';

const createTokenDialogMaxWidth = 1120.0;
const createTokenDialogHorizontalMargin = 40.0;
const createTokenDialogHeightFactor = 0.84;
const createTokenDialogMinPreferredOuterHeight = 400.0;
const createTokenDialogCompactWidthBreakpoint = 780.0;
const createTokenBarrierOpacity = 0.4;
const createTokenScaleStart = 0.95;

class ClientTokenCreateDialogShell extends StatefulWidget {
  const ClientTokenCreateDialogShell({
    required this.navigatorContext,
    required this.agentFocusNode,
    required this.dialogWidth,
    required this.dialogOuterMaxHeight,
    required this.theme,
    required this.isEditingToken,
    required this.body,
    super.key,
  });

  final BuildContext navigatorContext;
  final FocusNode agentFocusNode;
  final double dialogWidth;
  final double dialogOuterMaxHeight;
  final FluentThemeData theme;
  final bool isEditingToken;
  final Widget Function(BuildContext context, ClientTokenProvider provider) body;

  @override
  State<ClientTokenCreateDialogShell> createState() => _ClientTokenCreateDialogShellState();
}

class _ClientTokenCreateDialogShellState extends State<ClientTokenCreateDialogShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.agentFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isCreating = context.select<ClientTokenProvider, bool>(
      (ClientTokenProvider p) => p.isCreating,
    );
    return PopScope(
      canPop: !isCreating,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (isCreating) {
              return;
            }
            final navigator = Navigator.of(widget.navigatorContext);
            if (navigator.canPop()) {
              navigator.pop();
            }
          },
        },
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.dialogWidth,
                maxWidth: widget.dialogWidth,
                maxHeight: widget.dialogOuterMaxHeight,
              ),
              child: Semantics(
                namesRoute: true,
                label: widget.isEditingToken ? l10n.ctDialogEditTokenTitle : l10n.ctDialogCreateTokenTitle,
                child: Card(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  backgroundColor: widget.theme.resources.solidBackgroundFillColorBase,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isEditingToken ? l10n.ctDialogEditTokenTitle : l10n.ctDialogCreateTokenTitle,
                        style: context.sectionTitle,
                      ),
                      if (widget.isEditingToken) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: widget.theme.resources.subtleFillColorSecondary,
                            border: Border.all(
                              color: widget.theme.resources.controlStrokeColorDefault,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Text(l10n.ctEditUpdatesTokenHint),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Expanded(
                        child: Consumer<ClientTokenProvider>(
                          builder: (context, tokenProvider, _) {
                            return widget.body(context, tokenProvider);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
