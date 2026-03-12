import 'package:plug_agente/domain/entities/token_audit_event.dart';

abstract class ITokenAuditStore {
  Future<void> record(TokenAuditEvent event);
}
