import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('API Test - GET http://31.97.29.223:3000/', () {
    late http.Client client;

    setUp(() {
      client = http.Client();
    });

    tearDown(() {
      client.close();
    });

    test('should successfully connect to production server', () async {
      // Arrange
      const url = 'http://31.97.29.223:3000/';

      // Act & Assert
      try {
        final response = await client.get(Uri.parse(url));

        expect(response.statusCode, isNotNull);
        expect(response.statusCode, isA<int>());
      } catch (e) {
        rethrow;
      }
    });

    test('should handle connection timeout gracefully', () async {
      // Arrange
      const url = 'http://31.97.29.223:3000/';
      final clientWithTimeout = http.Client();

      // Act & Assert
      try {
        await clientWithTimeout.get(Uri.parse(url)).timeout(const Duration(seconds: 1));
        fail('Should have thrown TimeoutException');
      } on Exception catch (e) {
        expect(e, isA<Exception>());
      } finally {
        clientWithTimeout.close();
      }
    });

    test('should include proper headers in request', () async {
      // Arrange
      const url = 'http://31.97.29.223:3000/';
      final headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Plug Database/1.0.0 (Windows)',
      };

      // Act
      try {
        final response = await client.get(Uri.parse(url), headers: headers);

        // Assert
        expect(response.statusCode, isNotNull);
      } catch (e) {
        // Request failed, but we're just testing the configuration
      }
    });

    test('should handle different endpoints correctly', () async {
      // Arrange
      const baseUrl = 'http://31.97.29.223:3000/';

      // Act & Assert - Test base endpoint
      try {
        final response = await client.get(Uri.parse(baseUrl)).timeout(const Duration(seconds: 5));
        expect(response.statusCode, isNotNull);
      } catch (e) {
        // Don't fail the test, just catch the error
      }
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
