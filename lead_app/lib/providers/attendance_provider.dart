import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../models/attendance_model.dart';
import '../core/services/attendance_service.dart';
import '../core/services/tracking_service.dart';

class AttendanceProvider extends ChangeNotifier {
  final AttendanceService _attendanceService = AttendanceService();

  AttendanceModel _todayStatus = AttendanceModel();
  List<AttendanceModel> _history = [];
  Map<String, dynamic> _historySummary = {};
  bool _isLoading = false;
  bool _isLoadingHistory = false;
  bool _isPunching = false;
  String? _errorMessage;

  AttendanceModel get todayStatus => _todayStatus;
  List<AttendanceModel> get history => _history;
  Map<String, dynamic> get historySummary => _historySummary;
  bool get isLoading => _isLoading;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isPunching => _isPunching;
  String? get errorMessage => _errorMessage;

  Future<void> loadHistory() async {
    _isLoadingHistory = true;
    notifyListeners();

    try {
      final res = await _attendanceService.getHistoryData();
      _history = (res['records'] as List<AttendanceModel>?) ?? [];
      _historySummary = (res['summary'] as Map<String, dynamic>?) ?? {};
    } catch (_) {}

    _isLoadingHistory = false;
    notifyListeners();
  }

  Future<void> loadTodayStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      _todayStatus = await _attendanceService.getTodayStatus();
      if (_todayStatus.isShiftActive) {
        TrackingService.instance.startTracking();
      } else {
        TrackingService.instance.stopTracking();
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> punchCheckIn({
    Position? position,
    String? notes,
    String? photoUrl,
  }) async {
    _isPunching = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final pos = position ?? await _getCurrentLocation();
      if (pos == null) {
        _errorMessage = 'Location is required to punch check-in. Please turn on device GPS.';
        _isPunching = false;
        notifyListeners();
        return false;
      }

      final result = await _attendanceService.checkIn(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        notes: notes,
      );

      // Explicit user punch: Shift is now active!
      _todayStatus = AttendanceModel(
        id: result.id ?? _todayStatus.id,
        date: result.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        checkedIn: true,
        checkInTime: result.checkInTime ?? DateTime.now(),
        checkInLat: pos.latitude,
        checkInLng: pos.longitude,
        checkInAddress: result.checkInAddress ?? 'Current Location Recorded via GPS',
        checkedOut: false,
        totalDistanceKm: result.totalDistanceKm,
        status: 'checked_in',
        notes: (notes != null && notes.trim().isNotEmpty) ? notes.trim() : 'Field shift check-in',
      );
      TrackingService.instance.startTracking();
      loadHistory();

      _isPunching = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isPunching = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> punchCheckOut({
    Position? position,
    String? notes,
    String? photoUrl,
  }) async {
    _isPunching = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final pos = position ?? await _getCurrentLocation();
      if (pos == null) {
        _errorMessage = 'Location is required to punch check-out. Please turn on device GPS.';
        _isPunching = false;
        notifyListeners();
        return false;
      }

      final result = await _attendanceService.checkOut(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        notes: notes,
      );

      // Explicit user check-out: Shift is completed!
      _todayStatus = AttendanceModel(
        id: result.id ?? _todayStatus.id,
        date: result.date ?? _todayStatus.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        checkedIn: true,
        checkInTime: _todayStatus.checkInTime ?? result.checkInTime ?? DateTime.now(),
        checkInLat: _todayStatus.checkInLat ?? pos.latitude,
        checkInLng: _todayStatus.checkInLng ?? pos.longitude,
        checkInAddress: _todayStatus.checkInAddress,
        checkedOut: true,
        checkOutTime: result.checkOutTime ?? DateTime.now(),
        checkOutLat: pos.latitude,
        checkOutLng: pos.longitude,
        checkOutAddress: result.checkOutAddress ?? 'Current Location Recorded via GPS',
        totalDistanceKm: result.totalDistanceKm ?? _todayStatus.totalDistanceKm,
        status: 'checked_out',
        notes: notes ?? 'Field shift check-out',
      );
      TrackingService.instance.stopTracking();
      loadHistory();

      _isPunching = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isPunching = false;
      notifyListeners();
      return false;
    }
  }

  Future<Position?> _getCurrentLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return await Geolocator.getLastKnownPosition();
    }
  }
}
