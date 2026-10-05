import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/runtime/installation_bundle_check.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ConfigurationFailure;

class _ManifestBundle extends CachingAssetBundle {
  _ManifestBundle(this.manifest, {this.error});

  final Map<String, List<Map<String, String>>> manifest;
  final Error? error;

  @override
  Future<ByteData> load(String key) async {
    if (error case final error?) throw error;
    if (key != 'AssetManifest.bin') throw StateError('Unexpected asset: $key');
    return const StandardMessageCodec().encodeMessage(manifest)!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accepts an installed asset manifest through the Flutter asset channel', () async {
    final result = await checkInstallationBundle(
      _ManifestBundle({
        '.env': [
          {'asset': '.env'},
        ],
      }),
    );
    expect(result.isSuccess(), isTrue);
  });

  test('reports an empty manifest as a configuration failure', () async {
    final result = await checkInstallationBundle(_ManifestBundle({}));
    expect(result.exceptionOrNull(), isA<ConfigurationFailure>());
    expect((result.exceptionOrNull()! as ConfigurationFailure).message, contains('empty'));
  });

  test('preserves the asset loader failure without exposing it in the message', () async {
    final cause = StateError('private loader details');
    final result = await checkInstallationBundle(_ManifestBundle({}, error: cause));
    final failure = result.exceptionOrNull()! as ConfigurationFailure;
    expect(failure.cause, same(cause));
    expect(failure.context['operation'], 'installation_bundle_check');
    expect(failure.message, isNot(contains('private loader details')));
  });
}
