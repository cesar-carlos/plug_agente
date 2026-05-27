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

class AgentProfileAddressSection extends StatefulWidget {
  const AgentProfileAddressSection({
    required this.controller,
    required this.l10n,
    required this.isLookingUpCep,
    required this.canLookup,
    required this.onLookupCep,
    super.key,
  });

  final AgentProfileFormController controller;
  final AppLocalizations l10n;
  final ValueListenable<bool> isLookingUpCep;
  final ValueListenable<bool> canLookup;
  final VoidCallback onLookupCep;

  @override
  State<AgentProfileAddressSection> createState() => _AgentProfileAddressSectionState();
}

class _AgentProfileAddressSectionState extends State<AgentProfileAddressSection> {
  late FieldSpec _postalCodeSpec;
  late FieldSpec _stateSpec;

  @override
  void initState() {
    super.initState();
    _rebuildSpecs();
  }

  @override
  void didUpdateWidget(covariant AgentProfileAddressSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.l10n, widget.l10n)) {
      _rebuildSpecs();
    }
  }

  void _rebuildSpecs() {
    _postalCodeSpec = AppFieldSpecs.cep(widget.l10n);
    _stateSpec = AppFieldSpecs.state(widget.l10n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    return AgentProfileSection(
      title: l10n.agentProfileSectionAddress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveFieldActionRow(
            field: AppTextField(
              label: l10n.agentProfileFieldPostalCode,
              controller: widget.controller.postalCodeController,
              fieldSpec: _postalCodeSpec,
              textInputAction: TextInputAction.next,
              validator: (value) => requiredWithSpecValidator(
                l10n,
                l10n.agentProfileFieldPostalCode,
                _postalCodeSpec,
                value,
              ),
            ),
            action: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[widget.isLookingUpCep, widget.canLookup]),
              builder: (context, _) {
                final loading = widget.isLookingUpCep.value;
                final enabled = widget.canLookup.value && !loading;
                return AppButton(
                  label: l10n.agentProfileActionLookupCep,
                  isPrimary: false,
                  isLoading: loading,
                  onPressed: enabled ? widget.onLookupCep : null,
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ResponsiveFieldRow(
            flexes: const [3, 1],
            children: [
              AppTextField(
                label: l10n.agentProfileFieldStreet,
                controller: widget.controller.streetController,
                textInputAction: TextInputAction.next,
                validator: (value) => requiredFieldValidator(
                  l10n,
                  l10n.agentProfileFieldStreet,
                  value,
                ),
              ),
              AppTextField(
                label: l10n.agentProfileFieldNumber,
                controller: widget.controller.addressNumberController,
                textInputAction: TextInputAction.next,
                validator: (value) => requiredFieldValidator(
                  l10n,
                  l10n.agentProfileFieldNumber,
                  value,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ResponsiveFieldRow(
            flexes: const [2, 2, 1],
            children: [
              AppTextField(
                label: l10n.agentProfileFieldDistrict,
                controller: widget.controller.districtController,
                textInputAction: TextInputAction.next,
                validator: (value) => requiredFieldValidator(
                  l10n,
                  l10n.agentProfileFieldDistrict,
                  value,
                ),
              ),
              AppTextField(
                label: l10n.agentProfileFieldCity,
                controller: widget.controller.cityController,
                textInputAction: TextInputAction.next,
                validator: (value) => requiredFieldValidator(
                  l10n,
                  l10n.agentProfileFieldCity,
                  value,
                ),
              ),
              AppTextField(
                label: l10n.agentProfileFieldState,
                controller: widget.controller.stateController,
                fieldSpec: _stateSpec,
                textInputAction: TextInputAction.next,
                validator: (value) => requiredWithSpecValidator(
                  l10n,
                  l10n.agentProfileFieldState,
                  _stateSpec,
                  value,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
