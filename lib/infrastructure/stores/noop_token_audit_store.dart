import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';

class NoopTokenAuditStore implements ITokenAuditStore {
  @override
  Future<void> record(TokenAuditEvent event) async {}
}
