import 'package:plug_agente/application/validation/input_validators.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';

const int maxRuleImportFileSizeBytes = 512 * 1024;

const Set<String> _validTypes = {'table', 'view'};
const Set<String> _validEffects = {'allow', 'deny'};
const Set<String> _validPermissions = {'read', 'update', 'delete', 'ddl'};

class TokenRuleImportLineError {
  const TokenRuleImportLineError(this.line, this.content);

  final int line;
  final String content;
}

class TokenRuleImportResult {
  const TokenRuleImportResult({required this.drafts, required this.errors});

  final List<ClientTokenRuleDraft> drafts;
  final List<TokenRuleImportLineError> errors;

  bool get hasErrors => errors.isNotEmpty;
}

TokenRuleImportResult parseTokenRulesStrict(String content) {
  return _parseRules(
    content,
    defaultType: DatabaseResourceType.table,
    defaultEffect: ClientTokenRuleEffect.allow,
    defaultCanRead: false,
    defaultCanUpdate: false,
    defaultCanDelete: false,
    defaultCanDdl: false,
    strictFormat: true,
  );
}

TokenRuleImportResult parseTokenRulesFlexible(
  String content, {
  required DatabaseResourceType defaultType,
  required ClientTokenRuleEffect defaultEffect,
  required bool defaultCanRead,
  required bool defaultCanUpdate,
  required bool defaultCanDelete,
  required bool defaultCanDdl,
}) {
  return _parseRules(
    content,
    defaultType: defaultType,
    defaultEffect: defaultEffect,
    defaultCanRead: defaultCanRead,
    defaultCanUpdate: defaultCanUpdate,
    defaultCanDelete: defaultCanDelete,
    defaultCanDdl: defaultCanDdl,
  );
}

TokenRuleImportResult _parseRules(
  String content, {
  required DatabaseResourceType defaultType,
  required ClientTokenRuleEffect defaultEffect,
  required bool defaultCanRead,
  required bool defaultCanUpdate,
  required bool defaultCanDelete,
  required bool defaultCanDdl,
  bool strictFormat = false,
}) {
  final drafts = <ClientTokenRuleDraft>[];
  final errors = <TokenRuleImportLineError>[];

  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final rawLine = lines[i].trim();
    if (rawLine.isEmpty) continue;

    final lineNumber = i + 1;
    final parts = rawLine.split(';').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) continue;

    if (parts.length == 4 &&
        _validTypes.contains(parts[1].toLowerCase()) &&
        _validEffects.contains(parts[2].toLowerCase()) &&
        _isValidPermissionField(parts[3])) {
      final resourceResult = InputValidators.tableResource(parts[0]);
      if (resourceResult.isError()) {
        errors.add(TokenRuleImportLineError(lineNumber, rawLine));
        continue;
      }
      final type = parts[1].toLowerCase() == 'table' ? DatabaseResourceType.table : DatabaseResourceType.view;
      final effect = parts[2].toLowerCase() == 'allow' ? ClientTokenRuleEffect.allow : ClientTokenRuleEffect.deny;
      final perms = _parsePermissions(parts[3]);
      drafts.add(
        ClientTokenRuleDraft(
          resource: resourceResult.getOrNull()!,
          resourceType: type,
          effect: effect,
          canRead: perms.canRead,
          canUpdate: perms.canUpdate,
          canDelete: perms.canDelete,
          canDdl: perms.canDdl,
        ),
      );
      continue;
    }

    if (strictFormat) {
      errors.add(TokenRuleImportLineError(lineNumber, rawLine));
      continue;
    }

    var addedFromLine = 0;
    var lineHasError = false;
    for (final part in parts) {
      final resourceResult = InputValidators.tableResource(part);
      if (resourceResult.isError()) {
        errors.add(TokenRuleImportLineError(lineNumber, part));
        lineHasError = true;
        break;
      }
      drafts.add(
        ClientTokenRuleDraft(
          resource: resourceResult.getOrNull()!,
          resourceType: defaultType,
          effect: defaultEffect,
          canRead: defaultCanRead,
          canUpdate: defaultCanUpdate,
          canDelete: defaultCanDelete,
          canDdl: defaultCanDdl,
        ),
      );
      addedFromLine++;
    }
    if (lineHasError && addedFromLine > 0) {
      drafts.removeRange(drafts.length - addedFromLine, drafts.length);
    }
  }

  return TokenRuleImportResult(drafts: drafts, errors: errors);
}

bool _isValidPermissionField(String field) {
  final tokens = field.toLowerCase().split(',').map((t) => t.trim()).where((t) => t.isNotEmpty);
  return tokens.isNotEmpty && tokens.every(_validPermissions.contains);
}

({bool canRead, bool canUpdate, bool canDelete, bool canDdl}) _parsePermissions(String field) {
  final tokens = field.toLowerCase().split(',').map((t) => t.trim()).toSet();
  return (
    canRead: tokens.contains('read'),
    canUpdate: tokens.contains('update'),
    canDelete: tokens.contains('delete'),
    canDdl: tokens.contains('ddl'),
  );
}
