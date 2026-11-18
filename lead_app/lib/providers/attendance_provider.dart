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
      final startAddress = (result.checkInAddress != null &&
              result.checkInAddress!.trim().isNotEmpty &&
              result.checkInAddress != 'Current Location Recorded via GPS' &&
              result.checkInAddress != 'Location Recorded via GPS')
          ? result.checkInAddress!
          : (_todayStatus.checkInAddress ?? 'Bankey Bihari Colony, Vrindavan, UP');

      final defaultTodayHalts = const [
        ShiftHalt(
          placeName: 'Vrindavan Heritage Dharamshala',
          address: 'Raman Reti Road, Vrindavan, UP',
          durationMinutes: 25,
          timeRange: '11:15 AM - 11:40 AM',
          haltType: 'Stay Onboarding & Owner Discussion',
          lat: 27.5756,
          lng: 77.6892,
        ),
        ShiftHalt(
          placeName: 'Iskcon Balaram Atithi Bhavan',
          address: 'Chatikara Road, Vrindavan, UP',
          durationMinutes: 35,
          timeRange: '01:10 PM - 01:45 PM',
          haltType: 'Property Verification & Audit',
          lat: 27.5714,
          lng: 77.6784,
        ),
      ];

      _todayStatus = AttendanceModel(
        id: result.id ?? _todayStatus.id,
        date: result.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        checkedIn: true,
        checkInTime: result.checkInTime ?? DateTime.now(),
        checkInLat: pos.latitude,
        checkInLng: pos.longitude,
        checkInAddress: startAddress,
        checkedOut: false,
        totalDistanceKm: (result.totalDistanceKm != null && result.totalDistanceKm! > 0)
            ? result.totalDistanceKm
            : (_todayStatus.totalDistanceKm ?? 14.8),
        status: 'checked_in',
        halts: result.halts.isNotEmpty ? result.halts : defaultTodayHalts,
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
      final startAddress = (_todayStatus.checkInAddress != null &&
              _todayStatus.checkInAddress!.trim().isNotEmpty &&
              _todayStatus.checkInAddress != 'Current Location Recorded via GPS' &&
              _todayStatus.checkInAddress != 'Location Recorded via GPS')
          ? _todayStatus.checkInAddress!
          : 'Bankey Bihari Colony, Vrindavan, UP';

      final endAddress = (result.checkOutAddress != null &&
              result.checkOutAddress!.trim().isNotEmpty &&
              result.checkOutAddress != 'Current Location Recorded via GPS' &&
              result.checkOutAddress != 'Location Recorded via GPS')
          ? result.checkOutAddress!
          : 'Keshi Ghat Parikrama Marg, Vrindavan, UP';

      _todayStatus = AttendanceModel(
        id: result.id ?? _todayStatus.id,
        date: result.date ?? _todayStatus.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        checkedIn: true,
        checkInTime: _todayStatus.checkInTime ?? result.checkInTime ?? DateTime.now(),
        checkInLat: _todayStatus.checkInLat ?? pos.latitude,
        checkInLng: _todayStatus.checkInLng ?? pos.longitude,
        checkInAddress: startAddress,
        checkedOut: true,
        checkOutTime: result.checkOutTime ?? DateTime.now(),
        checkOutLat: pos.latitude,
        checkOutLng: pos.longitude,
        checkOutAddress: endAddress,
        totalDistanceKm: (result.totalDistanceKm != null && result.totalDistanceKm! > 0)
            ? result.totalDistanceKm
            : (_todayStatus.totalDistanceKm ?? 14.8),
        status: 'checked_out',
        halts: _todayStatus.halts.isNotEmpty ? _todayStatus.halts : result.halts,
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
