import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../models/attendance_model.dart';
import '../core/services/attendance_service.dart';
import '../core/services/tracking_service.dart';
import '../core/utils/location_helper.dart';

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
      final loadedRecords = (res['records'] as List<AttendanceModel>?) ?? [];
      _historySummary = (res['summary'] as Map<String, dynamic>?) ?? {};

      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _history = loadedRecords.map((r) {
        final rDate = r.date ??
            (r.checkInTime != null
                ? DateFormat('yyyy-MM-dd').format(r.checkInTime!)
                : null);
        if ((rDate == todayStr || r.id == _todayStatus.id) &&
            (r.totalDistanceKm == null || r.totalDistanceKm == 0.0) &&
            (_todayStatus.totalDistanceKm != null && _todayStatus.totalDistanceKm! > 0)) {
          return AttendanceModel(
            id: r.id,
            date: r.date,
            checkedIn: r.checkedIn,
            checkInTime: r.checkInTime,
            checkInLat: r.checkInLat,
            checkInLng: r.checkInLng,
            checkInAddress: r.checkInAddress,
            checkedOut: r.checkedOut,
            checkOutTime: r.checkOutTime,
            checkOutLat: r.checkOutLat,
            checkOutLng: r.checkOutLng,
            checkOutAddress: r.checkOutAddress,
            totalDistanceKm: _todayStatus.totalDistanceKm,
            batteryLevel: r.batteryLevel,
            notes: r.notes,
            photoUrl: r.photoUrl,
            totalWorkingMinutes: r.totalWorkingMinutes,
            formattedWorkingHours: r.formattedWorkingHours,
            status: r.status,
            halts: r.halts,
          );
        }
        return r;
      }).toList();
    } catch (_) {}

    _isLoadingHistory = false;
    notifyListeners();
  }

  void resetState() {
    _todayStatus = AttendanceModel();
    _history = [];
    _historySummary = {};
    _isLoading = false;
    _isLoadingHistory = false;
    _isPunching = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> loadTodayStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      final status = await _attendanceService.getTodayStatus();
      _todayStatus = status;

      if (_todayStatus.isShiftActive) {
        TrackingService.instance.startTracking();
      } else {
        TrackingService.instance.stopTracking();
      }
    } catch (_) {}

    // Send any route points still saved on the phone (earlier shifts, offline
    // periods, or fixes queued by an older app version).
    TrackingService.instance.uploadPending();

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

      // Fast real-time reverse geocoding in milliseconds
      final geoAddress = await LocationHelper.getAddressFromCoordinates(pos.latitude, pos.longitude);
      final addressToSend = geoAddress.isNotEmpty
          ? geoAddress
          : 'GPS: ${pos.latitude.toStringAsFixed(4)}° N, ${pos.longitude.toStringAsFixed(4)}° E';

      final result = await _attendanceService.checkIn(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        address: addressToSend,
        notes: notes,
      );

      // Reset today's distance & live halts for the new shift
      await TrackingService.instance.resetDistance();

      final recordAddress = (result.checkInAddress != null &&
              result.checkInAddress!.trim().isNotEmpty &&
              result.checkInAddress != 'Mathura, Uttar Pradesh')
          ? result.checkInAddress!
          : addressToSend;

      _todayStatus = AttendanceModel(
        id: result.id ?? _todayStatus.id,
        date: result.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        checkedIn: true,
        checkInTime: result.checkInTime ?? DateTime.now(),
        checkInLat: pos.latitude,
        checkInLng: pos.longitude,
        checkInAddress: recordAddress,
        checkedOut: false,
        totalDistanceKm: 0.0,
        status: 'checked_in',
        halts: const [],
        notes: (notes != null && notes.trim().isNotEmpty) ? notes.trim() : 'Field shift check-in',
      );
      await _attendanceService.saveLocalTodayStatus(_todayStatus);
      await TrackingService.instance.setConsent(
        true,
        deviceLabel: 'Field Console app',
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

      // Fast real-time reverse geocoding in milliseconds
      final geoAddress = await LocationHelper.getAddressFromCoordinates(pos.latitude, pos.longitude);
      final addressToSend = geoAddress.isNotEmpty
          ? geoAddress
          : 'GPS: ${pos.latitude.toStringAsFixed(4)}° N, ${pos.longitude.toStringAsFixed(4)}° E';
      final trackedKm = TrackingService.instance.distanceTravelledKm;

      // Upload the remaining route points first, so they land inside the
      // shift before it closes; then check out; then stop location.
      await TrackingService.instance.flushBeforeCheckOut(finalPosition: pos);

      final result = await _attendanceService.checkOut(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        address: addressToSend,
        notes: notes,
        distanceKm: trackedKm,
      );

      final startAddress = (_todayStatus.checkInAddress != null && _todayStatus.checkInAddress!.trim().isNotEmpty)
          ? _todayStatus.checkInAddress!
          : addressToSend;

      final endAddress = (result.checkOutAddress != null &&
              result.checkOutAddress!.trim().isNotEmpty &&
              result.checkOutAddress != 'Mathura, Uttar Pradesh')
          ? result.checkOutAddress!
          : addressToSend;

      final finalDist = (result.totalDistanceKm != null && result.totalDistanceKm! > 0)
          ? result.totalDistanceKm!
          : (trackedKm > 0 ? double.parse(trackedKm.toStringAsFixed(2)) : 0.0);

      final halts = TrackingService.instance.trackedHalts.isNotEmpty
          ? TrackingService.instance.trackedHalts
          : result.halts;

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
        totalDistanceKm: finalDist,
        status: 'checked_out',
        halts: halts,
        notes: notes ?? 'Field shift check-out',
      );
      await _attendanceService.saveLocalTodayStatus(_todayStatus);
      TrackingService.instance.stopTracking();
      // Anything the flush could not send (e.g. no signal) is still queued
      // and stamped inside the shift; try once more now.
      TrackingService.instance.uploadPending();
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
    return await LocationHelper.getFastRealtimePosition();
  }
}
