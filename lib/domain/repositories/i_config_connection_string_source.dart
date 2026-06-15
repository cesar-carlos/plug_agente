import 'package:plug_agente/domain/entities/config.dart';

abstract interface class IConfigConnectionStringSource {
  String generateConnectionString(Config config);

  String generateConnectionStringForPersistence(Config config);
}
