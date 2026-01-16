import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';

class UpdateService {
  final String _updateUrl;
  final Dio _dio;

  UpdateService(this._updateUrl, this._dio);

  Future<bool> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      final response = await _dio.get(
        '$_updateUrl/check',
        queryParameters: {'currentVersion': currentVersion},
      );
      
      if (response.statusCode != 200) {
        return false;
      }

      final data = response.data as Map<String, dynamic>;
      final isUpdateAvailable = data['updateAvailable'] as bool? ?? false;
      
      if (isUpdateAvailable) {
        // TODO: Implementar atualização automática quando AutoUpdater API estiver disponível
        // AutoUpdater requer configuração específica do Windows
        // final autoUpdater = AutoUpdater();
        // autoUpdater.setFeedURL(_updateUrl);
        // await autoUpdater.checkForUpdates();
      }
      
      return isUpdateAvailable;
    } catch (e) {
      return false;
    }
  }
}