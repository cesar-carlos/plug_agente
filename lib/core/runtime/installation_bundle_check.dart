import 'package:flutter/services.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ConfigurationFailure;
import 'package:result_dart/result_dart.dart';

Future<Result<Unit>> checkInstallationBundle(AssetBundle bundle) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    if (manifest.listAssets().isEmpty) {
      return Failure(ConfigurationFailure('The installed application asset manifest is empty.'));
    }
    await bundle.load('AssetManifest.bin');
    return const Success(unit);
  } on Object catch (error) {
    return Failure(
      ConfigurationFailure.withContext(
        message: 'The installed application assets could not be loaded.',
        cause: error,
        context: {'operation': 'installation_bundle_check'},
      ),
    );
  }
}
