// The canonical implementation lives in domain/utils/log_sanitizer.dart so
// the domain layer can import it without a core dependency. This file
// re-exports it so all existing core/infrastructure/presentation consumers
// continue to work without changes.
export 'package:plug_agente/domain/utils/log_sanitizer.dart';
