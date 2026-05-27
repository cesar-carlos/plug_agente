import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_form_controller.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_section.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_validators.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/responsive_field_row.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/form/app_field_specs.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/form/field_spec.dart';

class AgentProfileIdentitySection extends StatefulWidget {
  const AgentProfileIdentitySection({
    required this.controller,
    required this.l10n,
    required this.isLookingUpCnpj,
    required this.canLookup,
    required this.onLookupCnpj,
    super.key,
  });

  final AgentProfileFormController controller;
  final AppLocalizations l10n;
  final ValueListenable<bool> isLookingUpCnpj;
  final ValueListenable<bool> canLookup;
  final VoidCallback onLookupCnpj;

  @override
  State<AgentProfileIdentitySection> createState() => _AgentProfileIdentitySectionState();
}

class _AgentProfileIdentitySectionState extends State<AgentProfileIdentitySection> {
  // FieldSpecs are stable for the lifetime of an [AppLocalizations] instance,
  // so we memoize them and only rebuild when the locale changes.
  late FieldSpec _documentSpec;

  @override
  void initState() {
    super.initState();
    _documentSpec = AppFieldSpecs.document(widget.l10n);
  }

  @override
  void didUpdateWidget(covariant AgentProfileIdentitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.l10n, widget.l10n)) {
      _documentSpec = AppFieldSpecs.document(widget.l10n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return AgentProfileSection(
      title: l10n.agentProfileSectionIdentity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveFieldRow(
            children: [
              AppTextField(
                label: l10n.agentProfileFieldName,
                controller: widget.controller.nameController,
                textInputAction: TextInputAction.next,
                validator: (value) => requiredFieldValidator(
                  l10n,
                  l10n.agentProfileFieldName,
                  value,
                ),
              ),
              AppTextField(
                label: l10n.agentProfileFieldTradeName,
                controller: widget.controller.tradeNameController,
                textInputAction: TextInputAction.next,
                validator: (value) => requiredFieldValidator(
                  l10n,
                  l10n.agentProfileFieldTradeName,
                  value,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ResponsiveFieldActionRow(
            field: AppTextField(
              label: l10n.agentProfileFieldDocument,
              controller: widget.controller.documentController,
              fieldSpec: _documentSpec,
              textInputAction: TextInputAction.next,
              validator: (value) => requiredWithSpecValidator(
                l10n,
                l10n.agentProfileFieldDocument,
                _documentSpec,
                value,
              ),
            ),
            action: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[widget.isLookingUpCnpj, widget.canLookup]),
              builder: (context, _) {
                final loading = widget.isLookingUpCnpj.value;
                final enabled = widget.canLookup.value && !loading;
                return AppButton(
                  label: l10n.agentProfileActionLookupCnpj,
                  isPrimary: false,
                  isLoading: loading,
                  onPressed: enabled ? widget.onLookupCnpj : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
