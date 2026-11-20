import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user_model.dart';
import '../constants/api_endpoints.dart';
import '../constants/app_constants.dart';
import '../network/api_client.dart';
import 'tracking_service.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<LeadUser> login(String phone, String password) async {
    try {
      final response = await _apiClient.dio.post(
        ApiEndpoints.login,
        data: {'phone': phone.trim(), 'password': password},
      );

      final body = response.data;
      final data = body['data'] ?? body;
      final token = data['token']?.toString();
      final agentData = data['agent'] ?? data['user'] ?? data;

      if (token == null || token.isEmpty) {
        throw Exception('Invalid token returned by server');
      }

      final user = LeadUser.fromJson(Map<String, dynamic>.from(agentData));

      // Persist auth token in memory, secure storage, and shared preferences
      ApiClient.instance.setToken(token);
      await _storage.write(key: AppConstants.tokenKey, value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.tokenKey, token);
      await prefs.setString(AppConstants.userKey, jsonEncode(user.toJson()));

      return user;
    } on DioException catch (e) {
      final msg = e.response?.data?['message'];
      if (msg != null) {
        if (msg is List) {
          throw Exception(msg.join(', '));
        }
        throw Exception(msg.toString());
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception(
          'Unable to connect to server. Please check your internet connection or server host.',
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception(
            'Unable to connect to server. Please check your internet connection or server host.');
      }
      throw Exception('Login failed: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String phone,
    String? email,
    required String password,
    required String state,
    required String district,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        ApiEndpoints.register,
        data: {
          'name': name.trim(),
          'phone': phone.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          'password': password,
          'state': state.trim(),
          'district': district.trim(),
        },
      );

      final body = response.data;
      return Map<String, dynamic>.from(body is Map ? body : {});
    } on DioException catch (e) {
      final msg = e.response?.data?['message'];
      if (msg != null) {
        if (msg is List) {
          throw Exception(msg.join(', '));
        }
        throw Exception(msg.toString());
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception(
          'Unable to connect to server. Please check your internet connection or server host.',
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception(
            'Unable to connect to server. Please check your internet connection or server host.');
      }
      throw Exception('Registration failed: ${e.message}');
    }
  }

  Future<LeadUser?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppConstants.userKey);
    if (raw != null) {
      try {
        return LeadUser.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    return null;
  }

  Future<String?> getToken() async {
    if (ApiClient.instance.token != null &&
        ApiClient.instance.token!.isNotEmpty) {
      return ApiClient.instance.token;
    }
    final stored = await _storage.read(key: AppConstants.tokenKey);
    if (stored != null && stored.isNotEmpty) {
      ApiClient.instance.setToken(stored);
      return stored;
    }
    final prefs = await SharedPreferences.getInstance();
    final prefToken = prefs.getString(AppConstants.tokenKey);
    if (prefToken != null && prefToken.isNotEmpty) {
      ApiClient.instance.setToken(prefToken);
      return prefToken;
    }
    return null;
  }

  Future<LeadUser?> fetchProfile() async {
    try {
      final response = await _apiClient.dio.get(ApiEndpoints.me);
      final body = response.data;
      final data = body['data'] ?? body;
      final user = LeadUser.fromJson(Map<String, dynamic>.from(data));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.userKey, jsonEncode(user.toJson()));
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<LeadUser> updateProfile({
    required String name,
    String? email,
    String? phone,
  }) async {
    try {
      final response = await _apiClient.dio.put(
        ApiEndpoints.me,
        data: {
          'name': name.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      );

      final body = response.data;
      final data = body['data'] ?? body;
      final user = LeadUser.fromJson(Map<String, dynamic>.from(data));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.userKey, jsonEncode(user.toJson()));
      return user;
    } on DioException catch (e) {
      final msg = e.response?.data?['message'];
      if (msg != null) {
        if (msg is List) throw Exception(msg.join(', '));
        throw Exception(msg.toString());
      }
      throw Exception('Failed to update profile: ${e.message}');
    }
  }

  Future<void> logout() async {
    // While the token is still valid: stop GPS, send queued route points,
    // and clear the queue so another account never uploads them.
    await TrackingService.instance.beforeLogout();
    ApiClient.instance.setToken(null);
    await _storage.delete(key: AppConstants.tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);
    await prefs.remove('tirvona_today_attendance_cache');
    await prefs.remove('tirvona_tracked_distance_km');
    await prefs.remove('tirvona_tracked_distance_date');
    await prefs.remove('tirvona_tracked_halts');
  }
}
