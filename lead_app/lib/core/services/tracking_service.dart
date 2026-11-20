import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/attendance_model.dart';
import '../constants/api_endpoints.dart';
import '../database/local_db.dart';
import '../network/api_client.dart';
import '../utils/location_helper.dart';

/// One point of the shift's on-screen trail (the agent's own live map).
class TrailPoint {
  final double lat;
  final double lng;
  final DateTime at;
  const TrailPoint(this.lat, this.lng, this.at);
}

/// How far the server is behind this phone, for the "live" banner.
class TrackingSyncStatus {
  /// The last time the server accepted an upload.
  final DateTime? lastSyncedAt;

  /// Route points still waiting on the phone.
  final int pending;

  /// The most recent upload attempt failed (offline, server down).
  final bool lastAttemptFailed;

  const TrackingSyncStatus({
    this.lastSyncedAt,
    this.pending = 0,
    this.lastAttemptFailed = false,
  });

  TrackingSyncStatus copyWith({
    DateTime? lastSyncedAt,
    int? pending,
    bool? lastAttemptFailed,
  }) => TrackingSyncStatus(
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    pending: pending ?? this.pending,
    lastAttemptFailed: lastAttemptFailed ?? this.lastAttemptFailed,
  );
}

/// Records the agent's route from check-in to check-out.
///
/// Every fix is written to the phone's SQLite queue first and uploaded to
/// `POST /agent/tracking/fixes` in batches, so nothing is lost while offline,
/// while the app is killed between uploads, or when the server is down.
///
/// Server contract (strict whitelist; any extra field rejects the whole batch):
///   lat, lng, accuracy, speed, heading, altitude, recordedAt, source
///   recordedAt = ISO string in UTC ("...Z"). A local time without an offset
///   is read by the server as UTC, lands 5.5 h in the future, and every point
///   is silently dropped as "off_duty".
class TrackingService {
  static final TrackingService instance = TrackingService._init();
  final ApiClient _apiClient = ApiClient.instance;
  final LocalDatabase _localDb = LocalDatabase.instance;

  static const String _distanceKey = 'tirvona_tracked_distance_km';
  static const String _distanceDateKey = 'tirvona_tracked_distance_date';
  static const String _haltsKey = 'tirvona_tracked_halts';

  /// The fallback sampler's interval when the GPS stream goes quiet.
  static const Duration sampleInterval = Duration(seconds: 30);

  /// How often the GPS reports during a shift. Every fix moves the agent's
  /// own map; only some are stored as route points (below).
  static const Duration liveInterval = Duration(seconds: 5);

  /// A route point is stored this often while moving, and this often while
  /// standing still (the server keeps only one per 2 min of those anyway).
  static const Duration storeIntervalMoving = Duration(seconds: 15);
  static const Duration storeIntervalStill = Duration(seconds: 30);

  /// Route points are uploaded this often while moving, so the supervisor's
  /// team map stays near-live, and this often while standing still.
  static const Duration uploadIntervalMoving = Duration(seconds: 30);
  static const Duration uploadIntervalStill = Duration(minutes: 2);

  /// Moved within this long: the agent counts as moving.
  static const Duration movingWindow = Duration(minutes: 2);

  /// Cap on the in-memory trail drawn on the agent's own map.
  static const int maxTrailPoints = 5000;

  /// Server limit per request.
  static const int maxBatchSize = 100;

  /// The server drops anything less certain than this, so don't queue it.
  static const double maxAccuracyMetres = 100;

  Timer? _sampleTimer;
  Timer? _uploadTimer;
  StreamSubscription<Position>? _positionStreamSub;
  bool _isTracking = false;
  bool _isUploading = false;
  DateTime? _lastQueuedAt;
  DateTime? _lastMovedAt;
  DateTime? _lastUploadAttemptAt;

  /// Upload progress, for the agent's live map banner.
  final ValueNotifier<TrackingSyncStatus> syncStatus =
      ValueNotifier<TrackingSyncStatus>(const TrackingSyncStatus());
  double _distanceTravelledKm = 0.0;
  Position? _lastRecordedPosition;

  DateTime? _stationaryStart;
  Position? _stationaryPos;
  String? _stationaryAddr;
  final List<ShiftHalt> _trackedHalts = [];

  final List<TrailPoint> _trail = [];
  Position? _latestPosition;
  final StreamController<Position> _positionController =
      StreamController<Position>.broadcast();

  TrackingService._init() {
    _loadSavedState();
  }

  bool get isTracking => _isTracking;
  double get distanceTravelledKm => _distanceTravelledKm;
  Position? get lastRecordedPosition => _lastRecordedPosition;
  List<ShiftHalt> get trackedHalts => List.unmodifiable(_trackedHalts);

  /// Every fix as it arrives during a shift (about every 5 s).
  Stream<Position> get positions => _positionController.stream;

  /// Moved in the last [movingWindow]: store and upload more often.
  bool get isMoving =>
      _lastMovedAt != null &&
      DateTime.now().difference(_lastMovedAt!) < movingWindow;

  /// The newest fix of this shift, moved or not.
  Position? get latestPosition => _latestPosition;

  /// This shift's path since the app started tracking (for the live map).
  List<TrailPoint> get trail => List.unmodifiable(_trail);

  Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final savedDate = prefs.getString(_distanceDateKey);
      if (savedDate == todayStr) {
        _distanceTravelledKm = prefs.getDouble(_distanceKey) ?? 0.0;
        final rawHalts = prefs.getString(_haltsKey);
        if (rawHalts != null && rawHalts.isNotEmpty) {
          final list = jsonDecode(rawHalts) as List;
          _trackedHalts.clear();
          for (final item in list) {
            _trackedHalts.add(ShiftHalt.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      } else {
        _distanceTravelledKm = 0.0;
        _trackedHalts.clear();
      }
    } catch (_) {}
  }

  Future<void> resetDistance() async {
    _distanceTravelledKm = 0.0;
    _lastRecordedPosition = null;
    _stationaryStart = null;
    _stationaryPos = null;
    _stationaryAddr = null;
    _trackedHalts.clear();
    _trail.clear();
    _latestPosition = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await prefs.setString(_distanceDateKey, todayStr);
      await prefs.setDouble(_distanceKey, 0.0);
      await prefs.remove(_haltsKey);
    } catch (_) {}
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await prefs.setString(_distanceDateKey, todayStr);
      await prefs.setDouble(_distanceKey, _distanceTravelledKm);
      final jsonHalts = jsonEncode(_trackedHalts.map((h) => h.toJson()).toList());
      await prefs.setString(_haltsKey, jsonHalts);
    } catch (_) {}
  }

  /// On-device distance and stoppage estimate shown in the app UI.
  void recordMovement(Position newPosition) async {
    if (_lastRecordedPosition == null) {
      _lastRecordedPosition = newPosition;
    } else {
      final distMeters = Geolocator.distanceBetween(
        _lastRecordedPosition!.latitude,
        _lastRecordedPosition!.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );
      // Under 10 m is GPS jitter: keep the anchor, so slow walking still adds
      // up once it is 10 m from where it was last counted. Over 5 km in one
      // step is a bad fix: count nothing and restart from here.
      if (distMeters >= 10 && distMeters <= 5000) {
        _distanceTravelledKm += (distMeters / 1000.0);
        _lastRecordedPosition = newPosition;
        _lastMovedAt = DateTime.now();
      } else if (distMeters > 5000) {
        _lastRecordedPosition = newPosition;
      }
    }

    // Check Stoppage / Halt (> 5 minutes within 50m radius)
    if (_stationaryPos == null) {
      _stationaryPos = newPosition;
      _stationaryStart = DateTime.now();
    } else {
      final distFromStationary = Geolocator.distanceBetween(
        _stationaryPos!.latitude,
        _stationaryPos!.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );
      if (distFromStationary <= 50) {
        if (_stationaryStart != null) {
          final diffMins = DateTime.now().difference(_stationaryStart!).inMinutes;
          if (diffMins >= 5) {
            _stationaryAddr ??= await LocationHelper.getAddressFromCoordinates(
              _stationaryPos!.latitude,
              _stationaryPos!.longitude,
            );
            final startTimeStr = DateFormat('hh:mm a').format(_stationaryStart!);
            final endTimeStr = DateFormat('hh:mm a').format(DateTime.now());
            final halt = ShiftHalt(
              placeName: _stationaryAddr ?? 'Field Stoppage Site',
              address: _stationaryAddr ?? 'Field Location',
              durationMinutes: diffMins,
              timeRange: '$startTimeStr - $endTimeStr',
              haltType: 'Client Survey & Stay Meeting (> 5 Mins)',
              lat: _stationaryPos!.latitude,
              lng: _stationaryPos!.longitude,
            );

            // Update existing or add new
            if (_trackedHalts.isNotEmpty &&
                _trackedHalts.last.lat == _stationaryPos!.latitude &&
                _trackedHalts.last.lng == _stationaryPos!.longitude) {
              _trackedHalts[_trackedHalts.length - 1] = halt;
            } else {
              _trackedHalts.add(halt);
            }
          }
        }
      } else {
        // Agent moved away (> 50m) - reset stationary anchor
        _stationaryPos = newPosition;
        _stationaryStart = DateTime.now();
        _stationaryAddr = null;
      }
    }

    _saveState();
  }

  // ── Shift tracking ────────────────────────────────────────────────────────

  /// Starts tracking for an open shift: GPS every 5 s for the agent's own
  /// map; a route point every 15 s while moving (30 s still), uploaded every
  /// 30 s while moving (2 min still) so the supervisor's team map stays
  /// near-live. Kept alive by a foreground-service notification on Android
  /// when the phone is locked.
  void startTracking() {
    if (_isTracking) return;
    _isTracking = true;

    _startPositionStream();

    // Fallback sampler: if the stream is silent (indoors, OEM throttling,
    // stream failed to start) take a one-off fix so the route has no holes.
    _sampleTimer = Timer.periodic(sampleInterval, (_) => _sampleIfStale());

    _uploadTimer = Timer.periodic(uploadIntervalMoving, (_) => _uploadTick());

    // First point right away, then push whatever is already queued.
    _sampleIfStale(force: true).then((_) => uploadPending());
  }

  void stopTracking() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _isTracking = false;
  }

  /// Every 30 s: upload while moving; standing still, only every 2 min.
  void _uploadTick() {
    final last = _lastUploadAttemptAt;
    if (isMoving ||
        last == null ||
        DateTime.now().difference(last) >= uploadIntervalStill) {
      uploadPending();
    }
  }

  /// One fix from the GPS stream or the fallback sampler: on-screen
  /// distance, the agent's own map, and (throttled) the stored route.
  Future<void> _onPosition(Position position, {bool forceQueue = false}) async {
    _latestPosition = position;
    recordMovement(position);
    _addTrail(position);
    if (!_positionController.isClosed) _positionController.add(position);
    await _queueFix(position, force: forceQueue);
  }

  void _addTrail(Position position) {
    if (!_finite(position.latitude) || !_finite(position.longitude)) return;
    if (_finite(position.accuracy) && position.accuracy > maxAccuracyMetres) {
      return;
    }
    final last = _trail.isEmpty ? null : _trail.last;
    if (last != null &&
        Geolocator.distanceBetween(
              last.lat,
              last.lng,
              position.latitude,
              position.longitude,
            ) <
            5) {
      return;
    }
    _trail.add(TrailPoint(position.latitude, position.longitude, DateTime.now()));
    if (_trail.length > maxTrailPoints) {
      _trail.removeRange(0, _trail.length - maxTrailPoints);
    }
  }

  /// Check-out step 1: record where the agent is now and upload everything
  /// still queued, so the route reaches the server before the shift closes.
  Future<void> flushBeforeCheckOut({Position? finalPosition}) async {
    if (finalPosition != null) {
      await _queueFix(finalPosition, force: true);
    }
    await uploadPending().timeout(
      const Duration(seconds: 20),
      onTimeout: () => 0,
    );
  }

  /// Before signing out: try to send what is queued, then clear the queue so
  /// the next account on this phone never uploads this agent's points.
  Future<void> beforeLogout() async {
    stopTracking();
    try {
      await uploadPending().timeout(
        const Duration(seconds: 15),
        onTimeout: () => 0,
      );
    } catch (_) {}
    try {
      await _localDb.clearAllPings();
    } catch (_) {}
    await resetDistance();
    syncStatus.value = const TrackingSyncStatus();
  }

  LocationSettings _streamSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: liveInterval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Field shift active',
          notificationText: 'Tirvona Lead is recording your route until you check out.',
          notificationChannelName: 'Shift route tracking',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  void _startPositionStream() {
    try {
      _positionStreamSub?.cancel();
      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: _streamSettings(),
      ).listen(
        (pos) => _onPosition(pos),
        onError: (Object e) {
          debugPrint('[TrackingService] position stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('[TrackingService] could not start position stream: $e');
    }
  }

  Future<void> _sampleIfStale({bool force = false}) async {
    if (!_isTracking) return;
    final last = _lastQueuedAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < sampleInterval + const Duration(seconds: 15)) {
      return;
    }
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      await _onPosition(position, forceQueue: true);
    } catch (e) {
      debugPrint('[TrackingService] sample failed: $e');
    }
  }

  /// Writes one fix to the phone queue in exactly the server's format.
  Future<void> _queueFix(Position position, {bool force = false}) async {
    // The GPS reports every 5 s; store one point per 15 s while moving and
    // per 30 s standing still (a second of slack absorbs timer jitter).
    final now = DateTime.now();
    final every = isMoving ? storeIntervalMoving : storeIntervalStill;
    if (!force &&
        _lastQueuedAt != null &&
        now.difference(_lastQueuedAt!) < every - const Duration(seconds: 1)) {
      return;
    }
    if (!_finite(position.latitude) || !_finite(position.longitude)) return;
    if (position.latitude == 0 && position.longitude == 0) return;
    if (_finite(position.accuracy) && position.accuracy > maxAccuracyMetres) {
      return;
    }

    // Time the fix was taken, in UTC. Guard against a bogus device stamp.
    var takenAt = position.timestamp.toUtc();
    final nowUtc = now.toUtc();
    if (takenAt.isAfter(nowUtc.add(const Duration(minutes: 2))) ||
        takenAt.isBefore(nowUtc.subtract(const Duration(hours: 24)))) {
      takenAt = nowUtc;
    }

    _lastQueuedAt = now;
    try {
      await _localDb.queueTrackingPing({
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': _finite(position.accuracy) ? position.accuracy : null,
        'speed': _finite(position.speed) && position.speed >= 0 ? position.speed : null,
        'heading':
            _finite(position.heading) && position.heading >= 0 ? position.heading : null,
        'altitude': _finite(position.altitude) ? position.altitude : null,
        'recordedAt': takenAt.toIso8601String(),
        'source': _isForeground() ? 'foreground' : 'background',
      });
      syncStatus.value = syncStatus.value.copyWith(
        pending: syncStatus.value.pending + 1,
      );
    } catch (e) {
      debugPrint('[TrackingService] could not queue fix: $e');
    }
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  /// Sends every queued fix to the server, oldest first, at most 100 per
  /// request. Fixes leave the phone only after the server answered 2xx; on a
  /// network error, 401/403 or 5xx they stay queued for the next attempt.
  /// Safe to call any time (app start, sync button, check-out): fixes from a
  /// shift that is already closed are still attached to that shift.
  /// Returns how many fixes were delivered.
  Future<int> uploadPending() async {
    if (_isUploading) return 0;
    _isUploading = true;
    _lastUploadAttemptAt = DateTime.now();
    var delivered = 0;
    var failed = false;
    DateTime? syncedAt;
    try {
      for (var round = 0; round < 50; round++) {
        final rows = await _localDb.getUnsyncedPings(limit: maxBatchSize);
        if (rows.isEmpty) break;

        final ids = <int>[];
        final badIds = <int>[];
        final fixes = <Map<String, dynamic>>[];
        for (final row in rows) {
          final id = row['id'] as int;
          final fix = _toServerFix(row);
          if (fix == null) {
            badIds.add(id);
          } else {
            ids.add(id);
            fixes.add(fix);
          }
        }
        if (badIds.isNotEmpty) await _localDb.deletePings(badIds);
        if (fixes.isEmpty) continue;

        try {
          final response = await _apiClient.dio.post(
            ApiEndpoints.trackingFixes,
            data: {'fixes': fixes},
          );
          await _localDb.deletePings(ids);
          delivered += ids.length;
          syncedAt = DateTime.now();
          _handleUploadResult(response.data);
        } on DioException catch (e) {
          final status = e.response?.statusCode;
          debugPrint(
            '[TrackingService] upload failed ($status): ${e.response?.data ?? e.message}',
          );
          if (status == 400 || status == 422) {
            // The server will never accept this batch as sent; drop it so it
            // does not block every later upload.
            await _localDb.deletePings(ids);
            continue;
          }
          // Offline, signed out, tracking consent off, or server error:
          // keep everything on the phone and try again later.
          failed = true;
          break;
        }

        if (rows.length < maxBatchSize) break;
      }
    } catch (e) {
      failed = true;
      debugPrint('[TrackingService] uploadPending error: $e');
    } finally {
      _isUploading = false;
    }
    try {
      syncStatus.value = syncStatus.value.copyWith(
        lastSyncedAt: syncedAt,
        pending: await _localDb.countUnsyncedPings(),
        lastAttemptFailed: failed,
      );
    } catch (_) {}
    if (delivered > 0) {
      debugPrint('[TrackingService] uploaded $delivered fixes');
    }
    return delivered;
  }

  /// Builds the request item with only the fields the server allows.
  /// Returns null for a row the server could never accept.
  Map<String, dynamic>? _toServerFix(Map<String, dynamic> row) {
    final lat = _asDouble(row['lat']);
    final lng = _asDouble(row['lng']);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

    final recordedAt = _normaliseRecordedAt(row['recordedAt']);
    if (recordedAt == null) return null;

    final fix = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'recordedAt': recordedAt,
      'source': row['source'] == 'foreground' ? 'foreground' : 'background',
    };
    final accuracy = _asDouble(row['accuracy']);
    if (accuracy != null && accuracy >= 0 && accuracy <= 100000) {
      fix['accuracy'] = accuracy;
    }
    final speed = _asDouble(row['speed']);
    if (speed != null) fix['speed'] = speed;
    final heading = _asDouble(row['heading']);
    if (heading != null) fix['heading'] = heading;
    final altitude = _asDouble(row['altitude']);
    if (altitude != null) fix['altitude'] = altitude;
    return fix;
  }

  /// Always a UTC ISO string. Rows queued by older app versions were stored as
  /// local phone time without an offset; those are converted here so the
  /// backlog still lands in the right shift.
  String? _normaliseRecordedAt(Object? raw) {
    if (raw == null) return null;
    DateTime? parsed;
    if (raw is int) {
      parsed = DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    } else {
      parsed = DateTime.tryParse(raw.toString());
    }
    if (parsed == null) return null;
    return parsed.toUtc().toIso8601String();
  }

  void _handleUploadResult(dynamic body) {
    final data = body is Map ? (body['data'] is Map ? body['data'] : body) : null;
    if (data is! Map) return;
    final reasons = data['reasons'];
    if (reasons is Map && reasons.isNotEmpty) {
      debugPrint(
        '[TrackingService] server accepted ${data['accepted']}, rejected ${data['rejected']}: $reasons',
      );
    }
    // Shift closed on the server (e.g. 9-hour auto check-out): stop recording.
    if (data['onDuty'] == false && _isTracking) {
      debugPrint('[TrackingService] server reports shift closed; stopping tracking');
      stopTracking();
    }
  }

  static bool _finite(double v) => !v.isNaN && !v.isInfinite;

  static double? _asDouble(Object? v) {
    if (v is num) {
      final d = v.toDouble();
      return _finite(d) ? d : null;
    }
    return null;
  }

  static bool _isForeground() {
    try {
      final state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } catch (_) {
      return false;
    }
  }

  // ── Consent ───────────────────────────────────────────────────────────────

  /// Turns server-side route recording on or off for this agent. The backend
  /// rejects every GPS point while consent is off, so this must succeed before
  /// a shift's route can appear on the admin monitoring dashboard.
  /// Returns true when the server accepted the change.
  Future<bool> setConsent(bool granted, {String? deviceLabel}) async {
    try {
      final payload = <String, dynamic>{'granted': granted};
      if (deviceLabel != null) payload['deviceLabel'] = deviceLabel;
      await _apiClient.dio.post(ApiEndpoints.trackingConsent, data: payload);
      if (granted) {
        // Points queued while consent was off can go now.
        unawaited(uploadPending());
      }
      return true;
    } catch (e) {
      debugPrint('[TrackingService] setConsent($granted) failed: $e');
      return false;
    }
  }

  /// The consent stored on the server, or null when it could not be read.
  Future<bool?> getConsent() async {
    try {
      final response = await _apiClient.dio.get(ApiEndpoints.trackingConsent);
      final body = response.data;
      final data = body is Map ? (body['data'] ?? body) : null;
      final consent = data is Map ? data['consent'] : null;
      if (consent is Map) return consent['granted'] == true;
      return null;
    } catch (_) {
      return null;
    }
  }
}
