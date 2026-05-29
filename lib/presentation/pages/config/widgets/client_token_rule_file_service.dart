import 'dart:io';

import 'package:plug_agente/presentation/pages/config/widgets/client_token_rule_dialog.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_rules_grid.dart';

/// Outcome of importing token rules from a `.txt` file.
///
/// Each variant maps to a distinct, user-facing message in the UI, keeping
/// the file IO and strict parsing out of the widget while letting the
/// caller own localization and feedback.
sealed class ClientTokenRuleImportOutcome {
  const ClientTokenRuleImportOutcome();
}

/// The file was empty or produced no valid rules.
final class ClientTokenRuleImportEmpty extends ClientTokenRuleImportOutcome {
  const ClientTokenRuleImportEmpty();
}

/// The file exceeded [maxRuleImportFileSizeBytes].
final class ClientTokenRuleImportTooLarge extends ClientTokenRuleImportOutcome {
  const ClientTokenRuleImportTooLarge();
}

/// A line did not match the strict `resource;type;effect;permissions` format.
final class ClientTokenRuleImportInvalidFormat extends ClientTokenRuleImportOutcome {
  const ClientTokenRuleImportInvalidFormat({required this.line, required this.content});

  final int line;
  final String content;
}

/// The file could not be read or decoded.
final class ClientTokenRuleImportReadFailure extends ClientTokenRuleImportOutcome {
  const ClientTokenRuleImportReadFailure(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;
}

/// The file parsed into [drafts] without errors.
final class ClientTokenRuleImportLoaded extends ClientTokenRuleImportOutcome {
  const ClientTokenRuleImportLoaded(this.drafts);

  final List<ClientTokenRuleDraft> drafts;
}

/// Reads and writes the section-level token rule `.txt` files.
///
/// Encapsulates the file IO, size limit, strict parsing and serialization so
/// the section widget keeps only file-picker selection and UI feedback.
class ClientTokenRuleFileService {
  const ClientTokenRuleFileService();

  Future<ClientTokenRuleImportOutcome> importFromFile(String path) async {
    try {
      final file = File(path);
      final size = await file.length();
      if (size == 0) {
        return const ClientTokenRuleImportEmpty();
      }
      if (size > maxRuleImportFileSizeBytes) {
        return const ClientTokenRuleImportTooLarge();
      }

      final content = await file.readAsString();
      final result = parseTokenRulesStrict(content);

      if (result.drafts.isEmpty) {
        return const ClientTokenRuleImportEmpty();
      }
      if (result.hasErrors) {
        final firstError = result.errors.first;
        return ClientTokenRuleImportInvalidFormat(
          line: firstError.line,
          content: firstError.content,
        );
      }
      return ClientTokenRuleImportLoaded(result.drafts);
    } on Object catch (error, stackTrace) {
      return ClientTokenRuleImportReadFailure(error, stackTrace);
    }
  }

  /// Serializes [rules] into the strict `resource;type;effect;permissions`
  /// line format consumed by [importFromFile].
  String serializeRules(List<ClientTokenRuleDraft> rules) {
    return rules
        .map((rule) {
          final perms = [
            if (rule.canRead) 'read',
            if (rule.canUpdate) 'update',
            if (rule.canDelete) 'delete',
            if (rule.canDdl) 'ddl',
          ].join(',');
          return '${rule.resource};${rule.resourceType.name};${rule.effect.name};$perms';
        })
        .join('\n');
  }

  Future<void> exportToFile(String path, List<ClientTokenRuleDraft> rules) {
    return File(path).writeAsString(serializeRules(rules));
  }
}
