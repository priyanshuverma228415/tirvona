import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/attendance_model.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';

class AttendanceService {
  final ApiClient _apiClient = ApiClient.instance;
  static const String _todayAttendanceCacheKey = 'tirvona_today_attendance_cache';

  Future<void> saveLocalTodayStatus(AttendanceModel model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final map = model.toJson();
      map['cacheDate'] = todayStr;
      await prefs.setString(_todayAttendanceCacheKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<AttendanceModel?> getLocalTodayStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_todayAttendanceCacheKey);
      if (str == null || str.isEmpty) return null;
      final map = jsonDecode(str) as Map<String, dynamic>;
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (map['cacheDate'] == todayStr) {
        return AttendanceModel.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  Future<AttendanceModel> getTodayStatus() async {
    try {
      final response = await _apiClient.dio.get(ApiEndpoints.todayAttendance);
      final body = response.data;
      final data = body['data'] ?? body;
      if (data != null && data is Map) {
        final model = AttendanceModel.fromJson(Map<String, dynamic>.from(data));
        if (model.checkedIn || model.checkedOut) {
          await saveLocalTodayStatus(model);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_todayAttendanceCacheKey);
        }
        return model;
      }
    } catch (e) {
      debugPrint('[AttendanceService] getTodayStatus remote error: $e');
    }

    // Fallback to locally cached status for today
    final cached = await getLocalTodayStatus();
    if (cached != null) {
      return cached;
    }

    return AttendanceModel();
  }

  Future<AttendanceModel> checkIn({
    required double lat,
    required double lng,
    double? accuracy,
    String? address,
    String? notes,
  }) async {
    try {
      final coords = <String, dynamic>{'lat': lat, 'lng': lng};
      if (accuracy != null) {
        coords['accuracy'] = accuracy;
      }
      final payload = <String, dynamic>{'coords': coords};
      if (address != null && address.isNotEmpty) {
        payload['address'] = address;
      }
      payload['notes'] = (notes != null && notes.trim().isNotEmpty)
          ? notes.trim()
          : 'Field shift check-in';

      final response = await _apiClient.dio.post(
        ApiEndpoints.checkIn,
        data: payload,
      );
      final body = response.data;
      final data = body['data'] ?? body;
      final record = data['record'] ?? data;
      final model = AttendanceModel.fromJson(Map<String, dynamic>.from(record));
      await saveLocalTodayStatus(model);
      return model;
    } on DioException catch (e) {
      final msg = e.response?.data?['message'];
      if (msg is List) {
        throw Exception(msg.join(', '));
      }
      if (msg != null && msg.toString().isNotEmpty) {
        throw Exception(msg.toString());
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception('Server unreachable. Please check backend is running.');
      }
      throw Exception(e.message ?? 'Check-in failed');
    }
  }

  Future<AttendanceModel> checkOut({
    required double lat,
    required double lng,
    double? accuracy,
    String? address,
    String? notes,
    double? distanceKm,
  }) async {
    try {
      final coords = <String, dynamic>{'lat': lat, 'lng': lng};
      if (accuracy != null) {
        coords['accuracy'] = accuracy;
      }
      final payload = <String, dynamic>{'coords': coords};
      if (address != null && address.isNotEmpty) {
        payload['address'] = address;
      }
      if (distanceKm != null && distanceKm > 0) {
        payload['distanceKm'] = distanceKm;
        payload['totalDistanceKm'] = distanceKm;
      }
      payload['notes'] = (notes != null && notes.trim().isNotEmpty)
          ? notes.trim()
          : 'Field shift check-out';

      final response = await _apiClient.dio.post(
        ApiEndpoints.checkOut,
        data: payload,
      );
      final body = response.data;
      final data = body['data'] ?? body;
      final record = data['record'] ?? data;
      final model = AttendanceModel.fromJson(Map<String, dynamic>.from(record));
      await saveLocalTodayStatus(model);
      return model;
    } on DioException catch (e) {
      final msg = e.response?.data?['message'];
      if (msg is List) {
        throw Exception(msg.join(', '));
      }
      if (msg != null && msg.toString().isNotEmpty) {
        throw Exception(msg.toString());
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception('Server unreachable. Please check backend is running.');
      }
      throw Exception(e.message ?? 'Check-out failed');
    }
  }

  Future<Map<String, dynamic>> getHistoryData() async {
    try {
      final response = await _apiClient.dio.get(ApiEndpoints.attendanceHistory);
      final body = response.data;
      final data = body['data'] ?? body;
      final rawRecords =
          data['records'] ?? data['items'] ?? (data is List ? data : []);
      final summary = data['summary'] as Map<String, dynamic>? ?? {};
      final records = (rawRecords as List)
          .map(
            (item) => AttendanceModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      return {'summary': summary, 'records': records};
    } catch (_) {
      return {'summary': <String, dynamic>{}, 'records': <AttendanceModel>[]};
    }
  }

  Future<List<AttendanceModel>> getHistory() async {
    final res = await getHistoryData();
    return res['records'] as List<AttendanceModel>;
  }
}
