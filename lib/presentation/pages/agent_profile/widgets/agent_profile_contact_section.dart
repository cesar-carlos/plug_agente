import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_form_controller.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_section.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_validators.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/responsive_field_row.dart';
import 'package:plug_agente/shared/widgets/common/form/app_field_specs.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/form/field_spec.dart';

class AgentProfileContactSection extends StatefulWidget {
  const AgentProfileContactSection({
    required this.controller,
    required this.l10n,
    super.key,
  });

  final AgentProfileFormController controller;
  final AppLocalizations l10n;

  @override
  State<AgentProfileContactSection> createState() => _AgentProfileContactSectionState();
}

class _AgentProfileContactSectionState extends State<AgentProfileContactSection> {
  late FieldSpec _phoneSpec;
  late FieldSpec _mobileSpec;
  late FieldSpec _emailSpec;

  @override
  void initState() {
    super.initState();
    _rebuildSpecs();
  }

  @override
  void didUpdateWidget(covariant AgentProfileContactSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.l10n, widget.l10n)) {
      _rebuildSpecs();
    }
  }

  void _rebuildSpecs() {
    _phoneSpec = AppFieldSpecs.phone(widget.l10n);
    _mobileSpec = AppFieldSpecs.mobile(widget.l10n);
    _emailSpec = AppFieldSpecs.email(widget.l10n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return AgentProfileSection(
      title: l10n.agentProfileSectionContact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveFieldRow(
            children: [
              AppTextField(
                label: l10n.agentProfileFieldPhone,
                controller: widget.controller.phoneController,
                fieldSpec: _phoneSpec,
                textInputAction: TextInputAction.next,
              ),
              AppTextField(
                label: l10n.agentProfileFieldMobile,
                controller: widget.controller.mobileController,
                fieldSpec: _mobileSpec,
                textInputAction: TextInputAction.next,
                validator: (value) => requiredWithSpecValidator(
                  l10n,
                  l10n.agentProfileFieldMobile,
                  _mobileSpec,
                  value,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: l10n.agentProfileFieldEmail,
            controller: widget.controller.emailController,
            fieldSpec: _emailSpec,
            textInputAction: TextInputAction.next,
            validator: (value) => requiredWithSpecValidator(
              l10n,
              l10n.agentProfileFieldEmail,
              _emailSpec,
              value,
            ),
          ),
        ],
      ),
    );
  }
}
