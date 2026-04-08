part of 'client_token_section.dart';

const _createTokenDialogMaxWidth = 1120.0;
const _createTokenDialogHorizontalMargin = 40.0;
const _createTokenDialogHeightFactor = 0.84;
const _createTokenDialogMinPreferredOuterHeight = 400.0;
const _createTokenDialogCompactWidthBreakpoint = 780.0;
const _createTokenBarrierOpacity = 0.4;
const _createTokenScaleStart = 0.95;

class _CreateTokenDialogShell extends StatefulWidget {
  const _CreateTokenDialogShell({
    required this.navigatorContext,
    required this.agentFocusNode,
    required this.dialogWidth,
    required this.dialogOuterMaxHeight,
    required this.theme,
    required this.isEditingToken,
    required this.body,
  });

  final BuildContext navigatorContext;
  final FocusNode agentFocusNode;
  final double dialogWidth;
  final double dialogOuterMaxHeight;
  final FluentThemeData theme;
  final bool isEditingToken;
  final Widget Function(BuildContext context, ClientTokenProvider provider) body;

  @override
  State<_CreateTokenDialogShell> createState() => _CreateTokenDialogShellState();
}

class _CreateTokenDialogShellState extends State<_CreateTokenDialogShell> {
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
