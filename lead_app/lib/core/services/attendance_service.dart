import 'package:dio/dio.dart';

import '../../models/attendance_model.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';

class AttendanceService {
  final ApiClient _apiClient = ApiClient.instance;

  Future<AttendanceModel> getTodayStatus() async {
    try {
      final response = await _apiClient.dio.get(ApiEndpoints.todayAttendance);
      final body = response.data;
      final data = body['data'] ?? body;
      if (data == null) return AttendanceModel();
      return AttendanceModel.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return AttendanceModel();
    }
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
      return AttendanceModel.fromJson(Map<String, dynamic>.from(record));
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
        ApiEndpoints.checkOut,
        data: payload,
      );
      final body = response.data;
      final data = body['data'] ?? body;
      final record = data['record'] ?? data;
      return AttendanceModel.fromJson(Map<String, dynamic>.from(record));
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
