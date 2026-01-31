import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  UpdateService(this._updateUrl, this._dio);
  final String _updateUrl;
  final Dio _dio;

  Future<bool> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await _dio.get<Map<String, dynamic>>(
        '$_updateUrl/check',
        queryParameters: {'currentVersion': currentVersion},
      );

      if (response.statusCode != 200) {
        return false;
      }

      final data = response.data;
      if (data == null) return false;
      final isUpdateAvailable = data['updateAvailable'] as bool? ?? false;

      if (isUpdateAvailable) {
        // TODO(team): Implementar atualização automática quando AutoUpdater API
        // estiver disponível. AutoUpdater requer configuração específica do Windows.
        // AutoUpdater requer configuração específica do Windows
        // final autoUpdater = AutoUpdater();
        // autoUpdater.setFeedURL(_updateUrl);
        // await autoUpdater.checkForUpdates();
      }

      return isUpdateAvailable;
    } on Exception {
      return false;
    }
  }
}
