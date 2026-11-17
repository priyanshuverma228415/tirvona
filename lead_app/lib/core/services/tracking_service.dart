import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/api_endpoints.dart';
import '../database/local_db.dart';
import '../network/api_client.dart';

class TrackingService {
  static final TrackingService instance = TrackingService._init();
  final ApiClient _apiClient = ApiClient.instance;
  final LocalDatabase _localDb = LocalDatabase.instance;
  final Battery _battery = Battery();

  Timer? _timer;
  bool _isTracking = false;

  TrackingService._init();

  bool get isTracking => _isTracking;

  void startTracking({Duration interval = const Duration(minutes: 3)}) {
    if (_isTracking) return;
    _isTracking = true;

    // Send first ping immediately
    _sendPing();

    // Recurring pings
    _timer = Timer.periodic(interval, (_) => _sendPing());
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _isTracking = false;
  }

  Future<void> _sendPing() async {
    try {
      final hasPermission = await Geolocator.checkPermission();
      if (hasPermission == LocationPermission.denied ||
          hasPermission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Gate: skip fixes less certain than 100 metres (per backend constants)
      if (position.accuracy > 100) return;

      int batteryLevel = 100;
      bool isCharging = false;
      try {
        batteryLevel = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        isCharging =
            state == BatteryState.charging || state == BatteryState.full;
      } catch (_) {}

      final fixPayload = <String, dynamic>{
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
        'altitude': position.altitude,
        'recordedAt': DateTime.now().toIso8601String(),
        'source': 'background',
      };

      try {
        await _apiClient.dio.post(
          ApiEndpoints.trackingFixes,
          data: {
            'fixes': [fixPayload],
          },
        );
      } catch (_) {
        // Queue locally in SQLite when offline
        await _localDb.queueTrackingPing({
          ...fixPayload,
          'batteryLevel': batteryLevel,
          'isCharging': isCharging ? 1 : 0,
        });
      }
    } catch (_) {}
  }

  Future<void> setConsent(bool granted, {String? deviceLabel}) async {
    try {
      final payload = <String, dynamic>{'granted': granted};
      if (deviceLabel != null) payload['deviceLabel'] = deviceLabel;
      await _apiClient.dio.post(ApiEndpoints.trackingConsent, data: payload);
    } catch (_) {}
  }
}
