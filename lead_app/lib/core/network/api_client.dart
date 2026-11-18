import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._init();
  late final Dio dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _token;
  VoidCallback? onSessionExpired;

  String? get token => _token;

  void setToken(String? token) {
    _token = token;
  }

  ApiClient._init() {
    dio = Dio(
      BaseOptions(
        baseUrl: '${AppConstants.defaultBaseUrl}${AppConstants.apiPrefix}',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();

          // In release mode, ALWAYS use the official production URL (api.tirvona.com)
          if (kReleaseMode) {
            options.baseUrl =
                '${AppConstants.defaultBaseUrl}${AppConstants.apiPrefix}';
          } else {
            // In debug mode, allow custom server URL override from SharedPreferences
            final customUrl = prefs.getString(AppConstants.serverUrlKey);
            if (customUrl != null && customUrl.trim().isNotEmpty) {
              final cleaned = customUrl.trim().replaceAll(RegExp(r'/+$'), '');
              options.baseUrl = '$cleaned${AppConstants.apiPrefix}';
            }
          }

          var t = _token;
          if (t == null || t.isEmpty) {
            t = await _storage.read(key: AppConstants.tokenKey);
            if (t == null || t.isEmpty) {
              t = prefs.getString(AppConstants.tokenKey);
            }
            _token = t;
          }

          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401) {
            _token = null;
            await _storage.delete(key: AppConstants.tokenKey);
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(AppConstants.tokenKey);
            onSessionExpired?.call();
          }
          return handler.next(e);
        },
      ),
    );
  }

  Future<void> updateBaseUrl(String newUrl) async {
    final cleaned = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    dio.options.baseUrl = '$cleaned${AppConstants.apiPrefix}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.serverUrlKey, cleaned);
  }

  Future<String> getBaseUrl() async {
    if (kReleaseMode) {
      return AppConstants.defaultBaseUrl;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.serverUrlKey) ??
        AppConstants.defaultBaseUrl;
  }
}
