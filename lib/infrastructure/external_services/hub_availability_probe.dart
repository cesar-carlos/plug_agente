import 'package:dio/dio.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/repositories/i_hub_availability_probe.dart';
import 'package:plug_agente/infrastructure/external_services/dio_factory.dart';

class HubAvailabilityProbe implements IHubAvailabilityProbe {
  HubAvailabilityProbe({
    Dio? dio,
    String probePath = AppConstants.defaultHubAvailabilityProbePath,
  }) : _dio =
           dio ??
           DioFactory.createDio(
             requestTimeout: const Duration(seconds: AppConstants.hubAvailabilityProbeTimeoutSeconds),
           ),
       _probePath = probePath;

  final Dio _dio;
  final String _probePath;

  @override
  Future<bool> isServerReachable(String serverUrl) async {
    final targetUrl = joinServerUrlAndPath(serverUrl, _probePath);
    try {
      final response = await _dio.get<void>(targetUrl);
      return response.statusCode != null;
    } on DioException catch (error) {
      // Any HTTP response means host is reachable (even 401/403/404).
      if (error.response != null) {
        return true;
      }
      return false;
    } on Exception {
      return false;
    }
  }
}
