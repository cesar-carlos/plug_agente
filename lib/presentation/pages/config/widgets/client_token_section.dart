import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_row.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

class ClientTokenSection extends StatefulWidget {
  const ClientTokenSection({super.key});

  @override
  State<ClientTokenSection> createState() => _ClientTokenSectionState();
}

class _ClientTokenSectionState extends State<ClientTokenSection> {
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _agentIdController = TextEditingController();
  final TextEditingController _payloadController = TextEditingController();
  final List<_RuleDraft> _rules = <_RuleDraft>[];

  bool _allTables = false;
  bool _allViews = false;
  bool _allPermissions = false;
  String _formError = '';

  @override
  void initState() {
    super.initState();
    _addRule();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final provider = context.read<ClientTokenProvider>();
      if (!provider.hasLoaded) {
        provider.loadTokens(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _agentIdController.dispose();
    _payloadController.dispose();
    for (final rule in _rules) {
      rule.dispose();
    }
    super.dispose();
  }

  void _addRule() {
    setState(() {
      _rules.add(_RuleDraft());
    });
  }

  void _removeRule(int index) {
    if (_rules.length <= 1) {
      return;
    }
    setState(() {
      final removed = _rules.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _handleCreateToken() async {
    setState(() {
      _formError = '';
    });

    final provider = context.read<ClientTokenProvider>();
    provider.clearError();
    provider.clearLastCreatedToken();

    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      setState(() {
        _formError = 'Informe o client_id para criar o token.';
      });
      return;
    }

    final payloadResult = _parsePayload();
    if (payloadResult == null) {
      return;
    }

    final rules = _buildRules();
    if (!_allPermissions && rules.isEmpty) {
      setState(() {
        _formError =
            'Adicione ao menos uma regra valida ou marque all_permissions.';
      });
      return;
    }

    final request = ClientTokenCreateRequest(
      clientId: clientId,
      agentId: _agentIdController.text.trim().isEmpty
          ? null
          : _agentIdController.text.trim(),
      payload: payloadResult,
      allTables: _allTables,
      allViews: _allViews,
      allPermissions: _allPermissions,
      rules: rules,
    );

    final created = await provider.createToken(request);
    if (created && mounted) {
      setState(() {
        _formError = '';
      });
    }
  }

  Map<String, dynamic>? _parsePayload() {
    final rawPayload = _payloadController.text.trim();
    if (rawPayload.isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      setState(() {
        _formError = 'Payload deve ser um objeto JSON valido.';
      });
      return null;
    } on FormatException {
      setState(() {
        _formError = 'Payload JSON invalido.';
      });
      return null;
    }
  }

  List<ClientTokenRule> _buildRules() {
    final rules = <ClientTokenRule>[];
    for (final draft in _rules) {
      final resource = draft.resourceController.text.trim();
      if (resource.isEmpty) {
        continue;
      }
      final hasAnyPermission =
          draft.canRead || draft.canUpdate || draft.canDelete;
      if (!hasAnyPermission) {
        continue;
      }
      rules.add(
        ClientTokenRule(
          resource: DatabaseResource(
            resourceType: draft.resourceType,
            name: resource,
          ),
          permissions: ClientPermissionSet(
            canRead: draft.canRead,
            canUpdate: draft.canUpdate,
            canDelete: draft.canDelete,
          ),
          effect: draft.effect,
        ),
      );
    }
    return rules;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientTokenProvider>(
      builder: (context, provider, _) {
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsSectionTitle(title: 'Client Token Authorization'),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Client ID',
                controller: _clientIdController,
                hint: 'client-acme',
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Agent ID (opcional)',
                controller: _agentIdController,
                hint: 'agent-01',
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Payload JSON (opcional)',
                controller: _payloadController,
                hint: '{"display_name":"Acme ERP","env":"production"}',
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  _FlagCheckbox(
                    label: 'all_tables',
                    value: _allTables,
                    onChanged: (value) {
                      setState(() {
                        _allTables = value;
                      });
                    },
                  ),
                  _FlagCheckbox(
                    label: 'all_views',
                    value: _allViews,
                    onChanged: (value) {
                      setState(() {
                        _allViews = value;
                      });
                    },
                  ),
                  _FlagCheckbox(
                    label: 'all_permissions',
                    value: _allPermissions,
                    onChanged: (value) {
                      setState(() {
                        _allPermissions = value;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const Expanded(
                    child: SettingsSectionTitle(title: 'Regras por recurso'),
                  ),
                  AppButton(
                    label: 'Adicionar regra',
                    isPrimary: false,
                    icon: FluentIcons.add,
                    onPressed: _addRule,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Column(
                children: List<Widget>.generate(
                  _rules.length,
                  (index) {
                    final rule = _rules[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == _rules.length - 1 ? 0 : AppSpacing.md,
                      ),
                      child: ClientTokenRuleRow(
                        title: 'Regra ${index + 1}',
                        resourceController: rule.resourceController,
                        resourceType: rule.resourceType,
                        effect: rule.effect,
                        canRead: rule.canRead,
                        canUpdate: rule.canUpdate,
                        canDelete: rule.canDelete,
                        onResourceTypeChanged: (value) {
                          setState(() {
                            rule.resourceType = value;
                          });
                        },
                        onEffectChanged: (value) {
                          setState(() {
                            rule.effect = value;
                          });
                        },
                        onReadChanged: (value) {
                          setState(() {
                            rule.canRead = value;
                          });
                        },
                        onUpdateChanged: (value) {
                          setState(() {
                            rule.canUpdate = value;
                          });
                        },
                        onDeleteChanged: (value) {
                          setState(() {
                            rule.canDelete = value;
                          });
                        },
                        onRemove: () => _removeRule(index),
                      ),
                    );
                  },
                ),
              ),
              if (_formError.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _ErrorSurface(message: _formError),
              ],
              if (provider.error.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _ErrorSurface(message: provider.error),
              ],
              if (provider.lastCreatedToken != null) ...[
                const SizedBox(height: AppSpacing.md),
                _CreatedTokenSurface(
                  token: provider.lastCreatedToken!,
                  onDismiss: provider.clearLastCreatedToken,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  AppButton(
                    label: 'Criar token',
                    icon: FluentIcons.add_friend,
                    isLoading: provider.isCreating,
                    onPressed: _handleCreateToken,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppButton(
                    label: 'Atualizar lista',
                    icon: FluentIcons.refresh,
                    isPrimary: false,
                    isLoading: provider.isLoading,
                    onPressed: () => provider.loadTokens(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const SettingsSectionTitle(title: 'Tokens cadastrados'),
              const SizedBox(height: AppSpacing.md),
              if (provider.tokens.isEmpty && !provider.isLoading)
                const Text('Nenhum token encontrado.'),
              if (provider.tokens.isNotEmpty)
                Column(
                  children: provider.tokens.map((token) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _TokenSummaryTile(
                        tokenId: token.id,
                        clientId: token.clientId,
                        createdAt: token.createdAt,
                        isRevoked: token.isRevoked,
                        isRevoking: provider.isRevoking,
                        onRevoke: token.isRevoked
                            ? null
                            : () => provider.revokeToken(token.id),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FlagCheckbox extends StatelessWidget {
  const _FlagCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      checked: value,
      onChanged: (isChecked) => onChanged(isChecked ?? false),
      content: Text(label),
    );
  }
}

class _ErrorSurface extends StatelessWidget {
  const _ErrorSurface({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: SelectableText(
        message,
        style: TextStyle(
          color: Colors.red.normal,
        ),
      ),
    );
  }
}

class _CreatedTokenSurface extends StatelessWidget {
  const _CreatedTokenSurface({
    required this.token,
    required this.onDismiss,
  });

  final String token;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Token criado com sucesso (copie e guarde agora):',
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.clear),
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(token),
        ],
      ),
    );
  }
}

class _TokenSummaryTile extends StatelessWidget {
  const _TokenSummaryTile({
    required this.tokenId,
    required this.clientId,
    required this.createdAt,
    required this.isRevoked,
    required this.isRevoking,
    this.onRevoke,
  });

  final String tokenId;
  final String clientId;
  final DateTime createdAt;
  final bool isRevoked;
  final bool isRevoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('Client: $clientId'),
                const SizedBox(height: AppSpacing.xs),
                SelectableText('ID: $tokenId'),
                const SizedBox(height: AppSpacing.xs),
                Text('Criado em: ${createdAt.toLocal().toIso8601String()}'),
                const SizedBox(height: AppSpacing.xs),
                Text('Status: ${isRevoked ? "revogado" : "ativo"}'),
              ],
            ),
          ),
          AppButton(
            label: isRevoked ? 'Revogado' : 'Revogar',
            isPrimary: false,
            isLoading: isRevoking,
            onPressed: onRevoke,
          ),
        ],
      ),
    );
  }
}

class _RuleDraft {
  _RuleDraft()
    : resourceController = TextEditingController(),
      resourceType = DatabaseResourceType.table,
      effect = ClientTokenRuleEffect.allow,
      canRead = true,
      canUpdate = false,
      canDelete = false;

  final TextEditingController resourceController;
  DatabaseResourceType resourceType;
  ClientTokenRuleEffect effect;
  bool canRead;
  bool canUpdate;
  bool canDelete;

  void dispose() {
    resourceController.dispose();
  }
}
