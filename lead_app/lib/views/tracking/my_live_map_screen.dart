import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/services/tracking_service.dart';
import '../../providers/attendance_provider.dart';
import 'widgets/pulse_dot.dart';

const LatLng _defaultCentre = LatLng(27.4924, 77.6737); // Mathura

/// The agent's own live map: where they are now (the blue dot), the road
/// they have taken today, and whether their supervisor can see them live.
class MyLiveMapScreen extends StatefulWidget {
  const MyLiveMapScreen({super.key});

  @override
  State<MyLiveMapScreen> createState() => _MyLiveMapScreenState();
}

class _MyLiveMapScreenState extends State<MyLiveMapScreen> {
  GoogleMapController? _map;
  StreamSubscription<Position>? _positionSub;
  Timer? _clock;

  final List<LatLng> _serverRoute = [];
  final List<LatLng> _liveTrail = [];
  Position? _current;
  LatLng? _initialTarget;
  bool _follow = true;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    final tracking = TrackingService.instance;
    _current = tracking.latestPosition ?? tracking.lastRecordedPosition;
    _liveTrail.addAll(tracking.trail.map((p) => LatLng(p.lat, p.lng)));
    _positionSub = tracking.positions.listen(_onPosition);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _prepare();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    final permission = await Geolocator.checkPermission();
    _hasPermission = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (_current == null && _hasPermission) {
      try {
        _current = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }
    if (!mounted) return;

    final status = context.read<AttendanceProvider>().todayStatus;
    final checkIn = (status.checkInLat != null && status.checkInLng != null)
        ? LatLng(status.checkInLat!, status.checkInLng!)
        : null;
    setState(() {
      _initialTarget = _current != null
          ? LatLng(_current!.latitude, _current!.longitude)
          : (checkIn ?? _defaultCentre);
    });
    await _loadTodayRoute();
  }

  /// The route already on the server (stored every 30 s), so reopening the
  /// app mid-shift still shows the whole day, not just since this screen.
  Future<void> _loadTodayRoute() async {
    try {
      final res = await ApiClient.instance.dio.get(ApiEndpoints.trackingToday);
      final body = res.data;
      final data = body is Map ? (body['data'] ?? body) : null;
      final route = data is Map ? data['route'] : null;
      if (route is! List || !mounted) return;
      final points = <LatLng>[];
      for (final item in route) {
        if (item is! Map) continue;
        final lat = item['lat'];
        final lng = item['lng'];
        if (lat is num && lng is num) {
          points.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
      setState(() {
        _serverRoute
          ..clear()
          ..addAll(points);
      });
    } catch (_) {
      // Offline: the live trail below still draws.
    }
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    final point = LatLng(position.latitude, position.longitude);
    setState(() {
      _current = position;
      if (_liveTrail.isEmpty ||
          Geolocator.distanceBetween(
                _liveTrail.last.latitude,
                _liveTrail.last.longitude,
                point.latitude,
                point.longitude,
              ) >=
              5) {
        _liveTrail.add(point);
      }
    });
    if (_follow) {
      _map?.animateCamera(
        CameraUpdate.newLatLng(point),
        duration: const Duration(milliseconds: 800),
      );
    }
  }

  void _recenter() {
    setState(() => _follow = true);
    final current = _current;
    if (current != null) {
      _map?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(current.latitude, current.longitude),
          17,
        ),
      );
    }
  }

  Set<Polyline> _polylines() {
    return {
      if (_serverRoute.length > 1)
        Polyline(
          polylineId: const PolylineId('today'),
          points: _serverRoute,
          color: AppColors.primary.withValues(alpha: 0.45),
          width: 6,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      if (_liveTrail.length > 1)
        Polyline(
          polylineId: const PolylineId('live'),
          points: _liveTrail,
          color: AppColors.primary,
          width: 6,
          zIndex: 1,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };
  }

  Set<Marker> _markers(_ShiftInfo shift) {
    final markers = <Marker>{};
    if (shift.checkIn != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('check-in'),
          position: shift.checkIn!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: 'Check-in',
            snippet: shift.checkInAddress,
          ),
        ),
      );
    }
    // Without location permission the map cannot draw its own blue dot.
    if (!_hasPermission && _current != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: LatLng(_current!.latitude, _current!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final attendance = context.watch<AttendanceProvider>();
    final status = attendance.todayStatus;
    final shift = _ShiftInfo(
      active: status.isShiftActive,
      checkIn: (status.checkInLat != null && status.checkInLng != null)
          ? LatLng(status.checkInLat!, status.checkInLng!)
          : null,
      checkInAddress: status.checkInAddress,
      checkInTime: status.checkInTime,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Live Route',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: _initialTarget == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Stack(
              children: [
                Listener(
                  // Moving the map by hand stops it following you.
                  onPointerDown: (_) {
                    if (_follow) setState(() => _follow = false);
                  },
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _initialTarget!,
                      zoom: 16,
                    ),
                    myLocationEnabled: _hasPermission,
                    myLocationButtonEnabled: false,
                    compassEnabled: true,
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    polylines: _polylines(),
                    markers: _markers(shift),
                    padding: const EdgeInsets.only(top: 96, bottom: 150),
                    onMapCreated: (controller) => _map = controller,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _StatusCard(shiftActive: shift.active),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: _StatsCard(
                    shift: shift,
                    current: _current,
                    distanceKm: TrackingService.instance.distanceTravelledKm,
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 150,
                  child: FloatingActionButton.small(
                    heroTag: 'recenter',
                    backgroundColor:
                        _follow ? AppColors.primary : AppColors.surface,
                    foregroundColor:
                        _follow ? Colors.white : AppColors.primary,
                    onPressed: _recenter,
                    tooltip: 'Follow my location',
                    child: const Icon(Icons.my_location_rounded),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The parts of today's attendance the map needs.
class _ShiftInfo {
  final bool active;
  final LatLng? checkIn;
  final String? checkInAddress;
  final DateTime? checkInTime;

  const _ShiftInfo({
    required this.active,
    this.checkIn,
    this.checkInAddress,
    this.checkInTime,
  });
}

class _StatusCard extends StatelessWidget {
  final bool shiftActive;
  const _StatusCard({required this.shiftActive});

  @override
  Widget build(BuildContext context) {
    if (!shiftActive) {
      return const _Banner(
        color: AppColors.warning,
        background: AppColors.warningLight,
        border: AppColors.warningBorder,
        icon: Icons.info_outline_rounded,
        title: 'Shift not active',
        subtitle: 'Check in to share your live location with your supervisor.',
      );
    }
    return ValueListenableBuilder<TrackingSyncStatus>(
      valueListenable: TrackingService.instance.syncStatus,
      builder: (context, sync, _) {
        final last = sync.lastSyncedAt;
        if (sync.lastAttemptFailed) {
          return _Banner(
            color: AppColors.warning,
            background: AppColors.warningLight,
            border: AppColors.warningBorder,
            icon: Icons.cloud_off_rounded,
            title: 'No internet · saving on phone',
            subtitle: sync.pending > 0
                ? '${sync.pending} route points saved; they sync automatically when you are back online.'
                : 'Your route syncs automatically when you are back online.',
          );
        }
        if (last == null) {
          return const _Banner(
            color: AppColors.info,
            background: AppColors.infoLight,
            border: AppColors.infoBorder,
            icon: Icons.sync_rounded,
            title: 'Starting live sharing…',
            subtitle: 'Your first route points are on their way to the server.',
          );
        }
        return _Banner(
          color: AppColors.success,
          background: AppColors.successLight,
          border: AppColors.successBorder,
          icon: Icons.sensors_rounded,
          title: 'LIVE · Your supervisor can see your route',
          subtitle: 'Last synced ${_ago(DateTime.now().difference(last))}'
              '${sync.pending > 0 ? ' · ${sync.pending} waiting' : ''}',
          pulse: true,
        );
      },
    );
  }
}

String _ago(Duration d) {
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}

class _Banner extends StatelessWidget {
  final Color color;
  final Color background;
  final Color border;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool pulse;

  const _Banner({
    required this.color,
    required this.background,
    required this.border,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          pulse ? PulseDot(color: color) : Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final _ShiftInfo shift;
  final Position? current;
  final double distanceKm;

  const _StatsCard({
    required this.shift,
    required this.current,
    required this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    final onShift = (shift.active && shift.checkInTime != null)
        ? DateTime.now().difference(shift.checkInTime!)
        : null;
    final speed = current?.speed;
    final speedKmh = (speed != null && speed.isFinite && speed > 0.3)
        ? speed * 3.6
        : 0.0;
    final accuracy = current?.accuracy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          _Stat(label: 'Distance', value: '${distanceKm.toStringAsFixed(2)} km'),
          _divider(),
          _Stat(label: 'On shift', value: onShift == null ? '—' : _duration(onShift)),
          _divider(),
          _Stat(label: 'Speed', value: '${speedKmh.toStringAsFixed(0)} km/h'),
          _divider(),
          _Stat(
            label: 'GPS',
            value: (accuracy == null || !accuracy.isFinite)
                ? '—'
                : '±${accuracy.round()} m',
          ),
        ],
      ),
    );
  }

  static Widget _divider() =>
      Container(width: 1, height: 30, color: AppColors.border);

  static String _duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
