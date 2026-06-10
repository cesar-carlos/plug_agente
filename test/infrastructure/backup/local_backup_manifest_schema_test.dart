import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';

void main() {
  late JsonSchema manifestSchema;

  setUpAll(() {
    final schemaFile = File('docs/backup/local_backup_manifest.schema.json');
    manifestSchema = JsonSchema.create(jsonDecode(schemaFile.readAsStringSync()) as Map<String, dynamic>);
  });

  test('default export manifest validates against schema', () {
    final manifest = <String, dynamic>{
      'formatVersion': 1,
      'createdAt': DateTime.utc(2026, 6, 10, 12).toIso8601String(),
      'appVersion': '1.8.4',
      'platform': 'windows',
      'installationId': '11111111-1111-1111-1111-111111111111',
      'odbcSecretsIncluded': false,
      'secureStorageSecretsIncluded': false,
    };

    expect(manifestSchema.validate(manifest).isValid, isTrue);
  });

  test('opt-in secrets manifest validates against schema', () {
    final manifest = <String, dynamic>{
      'formatVersion': 1,
      'createdAt': DateTime.utc(2026, 6, 10, 12).toIso8601String(),
      'appVersion': '1.8.4',
      'platform': 'windows',
      'installationId': '11111111-1111-1111-1111-111111111111',
      'odbcSecretsIncluded': true,
      'secureStorageSecretsIncluded': true,
      'secureStorageSecretsBlobVersion': 1,
      'secureStorageSecretsEntryCount': 3,
    };

    expect(manifestSchema.validate(manifest).isValid, isTrue);
  });
}
