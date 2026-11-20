import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../models/live_agent.dart';
import 'widgets/pulse_dot.dart';

const LatLng _defaultCentre = LatLng(27.4924, 77.6737); // Mathura

/// How often the team's positions are fetched while the map is open.
const Duration _pollInterval = Duration(seconds: 15);

/// How often the selected agent's full route for today is refreshed.
const Duration _routeRefresh = Duration(minutes: 1);

const Color _movingColor = AppColors.success;
const Color _stoppedColor = AppColors.warning;
const Color _offlineColor = AppColors.textMuted;

Color _statusColor(LiveStatus status) => switch (status) {
  LiveStatus.moving => _movingColor,
  LiveStatus.stopped => _stoppedColor,
  LiveStatus.offline => _offlineColor,
};

/// The supervisor's live map: every field executive of the district, with
/// markers that glide from one reported position to the next, Uber style.
///
/// Positions come from `GET /supervisor/tracking/live`, refreshed every 15 s.
/// Agents' phones upload a route point every 30 s while moving, so a marker
/// is typically under a minute behind the agent and keeps moving smoothly in
/// between instead of jumping.
class TeamLiveMapScreen extends StatefulWidget {
  const TeamLiveMapScreen({super.key});

  @override
  State<TeamLiveMapScreen> createState() => _TeamLiveMapScreenState();
}

/// One agent's marker and the animation that moves it.
class _Track {
  _Track(this.agent)
    : shown = LatLng(agent.lat, agent.lng),
      from = LatLng(agent.lat, agent.lng),
      to = LatLng(agent.lat, agent.lng);

  LiveAgent agent;
  LatLng shown;
  LatLng from;
  LatLng to;
  DateTime animStart = DateTime.now();
  Duration animDuration = Duration.zero;
  final List<LatLng> trail = [];
}

class _MapLayers {
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  const _MapLayers(this.markers, this.polylines);
}

class _TeamLiveMapScreenState extends State<TeamLiveMapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final Map<String, _Track> _tracks = {};
  final ValueNotifier<_MapLayers> _layers = ValueNotifier(
    const _MapLayers(<Marker>{}, <Polyline>{}),
  );
  late final Ticker _ticker;
  late final _AgentIcons _icons;
  Duration _lastFrame = Duration.zero;

  GoogleMapController? _map;
  Timer? _clock;
  Timer? _poll;
  Timer? _routeTimer;
  bool _polling = false;

  DateTime? _lastPollOkAt;
  bool _lastPollFailed = false;

  String? _selectedId;
  bool _follow = false;
  List<LatLng> _selectedRoute = const [];
  bool _loading = true;
  String? _error;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _icons = _AgentIcons(onReady: _rebuildLayers);

    _loadBoard();
    _startPolling();
    // Statuses age (moving → stopped → offline) even without new data.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _rebuildLayers();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _icons.pixelRatio = MediaQuery.of(context).devicePixelRatio;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No polling in the background: nobody is looking, and it costs data.
    if (state == AppLifecycleState.resumed) {
      _loadBoard(silent: true);
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _poll?.cancel();
    _routeTimer?.cancel();
    _ticker.dispose();
    _layers.dispose();
    super.dispose();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _loadBoard(silent: true));
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadBoard({bool silent = false}) async {
    if (_polling) return;
    _polling = true;
    try {
      final res = await ApiClient.instance.dio.get(
        ApiEndpoints.supervisorLiveTracking,
      );
      final body = res.data;
      final list = body is Map ? body['data'] : body;
      if (list is List) {
        for (final row in list) {
          if (row is! Map) continue;
          final agent = LiveAgent.fromJson(Map<String, dynamic>.from(row));
          if (agent != null) _upsert(agent);
        }
      }
      _error = null;
      _lastPollOkAt = DateTime.now();
      _lastPollFailed = false;
    } on DioException catch (e) {
      _lastPollFailed = true;
      if (!silent || _tracks.isEmpty) {
        _error = e.response?.statusCode == 403
            ? 'Only field supervisors can open the team map.'
            : 'Could not reach the server. Retrying automatically.';
      }
    } catch (_) {
      _lastPollFailed = true;
      if (!silent) _error = 'Could not load your team.';
    } finally {
      _polling = false;
      if (mounted) {
        setState(() => _loading = false);
        _afterData();
      }
    }
  }

  Future<void> _loadRoute(String agentId) async {
    try {
      final res = await ApiClient.instance.dio.get(
        ApiEndpoints.supervisorAgentTracking(agentId),
      );
      final body = res.data;
      final data = body is Map ? body['data'] : null;
      final day = data is Map ? data['day'] : null;
      final route = day is Map ? day['route'] : null;
      if (route is! List || !mounted || _selectedId != agentId) return;
      final points = <LatLng>[];
      for (final item in route) {
        if (item is! Map) continue;
        final lat = item['lat'];
        final lng = item['lng'];
        if (lat is num && lng is num) {
          points.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
      setState(() => _selectedRoute = points);
      _rebuildLayers();
    } catch (_) {
      // The trail since the map opened still shows where they went.
    }
  }

  void _upsert(LiveAgent incoming) {
    final position = LatLng(incoming.lat, incoming.lng);
    final track = _tracks[incoming.agentId];

    if (track == null) {
      _tracks[incoming.agentId] = _Track(incoming)..trail.add(position);
      return;
    }

    final previous = track.agent;
    final seconds =
        incoming.updatedAt.difference(previous.updatedAt).inMilliseconds / 1000;
    // Same point as last poll, or an older one: nothing moves.
    if (seconds <= 0) return;

    // Speed and direction from the last two points (the API sends neither).
    final metres = _metres(track.to, position);
    final speed = (seconds >= 5 && seconds <= 600) ? metres / seconds : 0.0;
    final heading = metres >= 10
        ? _bearing(track.to, position)
        : previous.heading;
    track.agent = incoming.withMotion(
      speed: incoming.speed ?? speed,
      heading: incoming.heading ?? heading,
    );

    if (metres < 0.5) return;

    if (metres > 3000) {
      // A jump this big is a gap in tracking, not a drive to animate.
      track
        ..shown = position
        ..from = position
        ..to = position
        ..animDuration = Duration.zero;
      if (_follow && incoming.agentId == _selectedId) {
        _map?.animateCamera(CameraUpdate.newLatLng(position));
      }
    } else {
      // Glide over the real time between the two points: the marker keeps
      // moving until about when the next point arrives, instead of jumping.
      track
        ..from = track.shown
        ..to = position
        ..animStart = DateTime.now()
        ..animDuration = Duration(
          milliseconds: (seconds * 1000).round().clamp(2000, 30000),
        );
      if (!_ticker.isActive) _ticker.start();
    }

    if (track.trail.isEmpty || _metres(track.trail.last, position) >= 3) {
      track.trail.add(position);
      if (track.trail.length > 1500) track.trail.removeAt(0);
    }
  }

  void _afterData() {
    if (!mounted) return;
    _rebuildLayers();
    if (!_fitted && _tracks.isNotEmpty && _map != null) {
      _fitted = true;
      Future<void>.delayed(const Duration(milliseconds: 300), _fitAll);
    }
    setState(() {});
  }

  // ── Animation ────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    // About 30 frames a second is smooth on a map and spares the battery.
    if (elapsed - _lastFrame < const Duration(milliseconds: 33)) return;
    _lastFrame = elapsed;

    final now = DateTime.now();
    var stillMoving = false;
    for (final track in _tracks.values) {
      if (track.animDuration == Duration.zero) continue;
      final progress =
          now.difference(track.animStart).inMicroseconds /
          track.animDuration.inMicroseconds;
      if (progress >= 1) {
        track
          ..shown = track.to
          ..animDuration = Duration.zero;
      } else {
        track.shown = LatLng(
          track.from.latitude +
              (track.to.latitude - track.from.latitude) * progress,
          track.from.longitude +
              (track.to.longitude - track.from.longitude) * progress,
        );
        stillMoving = true;
      }
    }

    // Following: the camera rides along with the selected marker.
    final selected = _selectedId == null ? null : _tracks[_selectedId];
    if (_follow && selected != null && selected.animDuration > Duration.zero) {
      _map?.moveCamera(CameraUpdate.newLatLng(selected.shown));
    }

    _rebuildLayers();
    if (!stillMoving) {
      _ticker.stop();
      _lastFrame = Duration.zero;
    }
  }

  void _rebuildLayers() {
    if (!mounted) return;
    final now = DateTime.now();
    final markers = <Marker>{};
    for (final track in _tracks.values) {
      final agent = track.agent;
      final status = agent.statusAt(now);
      final selected = agent.agentId == _selectedId;
      markers.add(
        Marker(
          markerId: MarkerId(agent.agentId),
          position: track.shown,
          icon: _icons.iconFor(
            agent.initials,
            status,
            status == LiveStatus.moving ? agent.heading : null,
            selected,
          ),
          anchor: const Offset(0.5, 0.5),
          zIndexInt: selected
              ? 4
              : switch (status) {
                  LiveStatus.moving => 3,
                  LiveStatus.stopped => 2,
                  LiveStatus.offline => 1,
                },
          consumeTapEvents: true,
          onTap: () => _select(agent.agentId),
        ),
      );
    }

    final polylines = <Polyline>{};
    final selected = _selectedId == null ? null : _tracks[_selectedId];
    if (selected != null) {
      if (_selectedRoute.length > 1) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: _selectedRoute,
            color: AppColors.primary.withValues(alpha: 0.45),
            width: 6,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
      }
      final trail = [...selected.trail, selected.shown];
      if (trail.length > 1) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('trail'),
            points: trail,
            color: AppColors.primary,
            width: 6,
            zIndex: 1,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
      }
    }
    _layers.value = _MapLayers(markers, polylines);
  }

  // ── Interaction ──────────────────────────────────────────────────────────

  void _select(String agentId) {
    final track = _tracks[agentId];
    if (track == null) return;
    setState(() {
      _selectedId = agentId;
      _follow = true;
      _selectedRoute = const [];
    });
    _map?.animateCamera(CameraUpdate.newLatLngZoom(track.shown, 16));
    _rebuildLayers();
    _loadRoute(agentId);
    _routeTimer?.cancel();
    _routeTimer = Timer.periodic(_routeRefresh, (_) {
      final id = _selectedId;
      if (id != null) _loadRoute(id);
    });
  }

  void _clearSelection() {
    _routeTimer?.cancel();
    _routeTimer = null;
    setState(() {
      _selectedId = null;
      _follow = false;
      _selectedRoute = const [];
    });
    _rebuildLayers();
  }

  void _fitAll() {
    final map = _map;
    if (map == null || _tracks.isEmpty) return;
    final points = _tracks.values.map((t) => t.shown).toList();
    if (points.length == 1) {
      map.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    // Agents standing together would zoom in to street-sign level.
    if (north - south < 0.002) {
      south -= 0.002;
      north += 0.002;
    }
    if (east - west < 0.002) {
      west -= 0.002;
      east += 0.002;
    }
    map.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        64,
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tracks = _tracks.values.toList()
      ..sort((a, b) {
        final byStatus = a.agent
            .statusAt(now)
            .index
            .compareTo(b.agent.statusAt(now).index);
        return byStatus != 0
            ? byStatus
            : a.agent.agentName.toLowerCase().compareTo(
                b.agent.agentName.toLowerCase(),
              );
      });
    final selected = _selectedId == null ? null : _tracks[_selectedId];
    final movingCount = tracks
        .where((t) => t.agent.statusAt(now) == LiveStatus.moving)
        .length;
    final activeCount = tracks
        .where((t) => t.agent.statusAt(now) != LiveStatus.offline)
        .length;
    final sheetHeight = MediaQuery.of(context).size.height * 0.30;
    final live =
        !_lastPollFailed &&
        _lastPollOkAt != null &&
        now.difference(_lastPollOkAt!) < const Duration(seconds: 45);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Team Live Map',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            Text(
              '$activeCount active · $movingCount moving',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          _ConnectionChip(live: live),
          IconButton(
            tooltip: 'Show everyone',
            icon: const Icon(Icons.zoom_out_map_rounded),
            onPressed: () {
              setState(() => _follow = false);
              _fitAll();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Listener(
            // Dragging the map by hand stops following the selected agent.
            onPointerDown: (_) {
              if (_follow) setState(() => _follow = false);
            },
            child: ValueListenableBuilder<_MapLayers>(
              valueListenable: _layers,
              builder: (context, layers, _) => GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _defaultCentre,
                  zoom: 12,
                ),
                markers: layers.markers,
                polylines: layers.polylines,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: true,
                padding: EdgeInsets.only(
                  top: selected != null ? 110 : 0,
                  bottom: sheetHeight,
                ),
                onMapCreated: (controller) {
                  _map = controller;
                  if (_tracks.isNotEmpty && !_fitted) {
                    _fitted = true;
                    Future<void>.delayed(
                      const Duration(milliseconds: 300),
                      _fitAll,
                    );
                  }
                },
                onTap: (_) {
                  if (_selectedId != null) _clearSelection();
                },
              ),
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primary,
              backgroundColor: Colors.transparent,
            ),
          if (selected != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _SelectedCard(
                agent: selected.agent,
                now: now,
                following: _follow,
                onFollow: () {
                  setState(() => _follow = true);
                  _map?.animateCamera(
                    CameraUpdate.newLatLngZoom(selected.shown, 16),
                  );
                },
                onClose: _clearSelection,
              ),
            ),
          DraggableScrollableSheet(
            initialChildSize: 0.30,
            minChildSize: 0.12,
            maxChildSize: 0.75,
            builder: (context, scroll) => _AgentSheet(
              scroll: scroll,
              tracks: tracks,
              now: now,
              selectedId: _selectedId,
              loading: _loading,
              error: _error,
              onSelect: _select,
              onRetry: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadBoard();
              },
            ),
          ),
        ],
      ),
    );
  }
}

double _metres(LatLng a, LatLng b) =>
    Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

/// Initial bearing from one point to the next, degrees clockwise from north.
double _bearing(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLng = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

String _ago(Duration d) {
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

String _statusLine(LiveAgent agent, DateTime now) {
  switch (agent.statusAt(now)) {
    case LiveStatus.moving:
      return 'Moving · ${agent.speedKmh.toStringAsFixed(0)} km/h';
    case LiveStatus.stopped:
      return 'Stopped';
    case LiveStatus.offline:
      return 'Offline · last seen ${_ago(now.difference(agent.updatedAt))}';
  }
}

class _ConnectionChip extends StatelessWidget {
  final bool live;
  const _ConnectionChip({required this.live});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: live ? AppColors.successLight : AppColors.warningLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: live ? AppColors.successBorder : AppColors.warningBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          live
              ? const PulseDot(color: AppColors.success, size: 12)
              : const Icon(
                  Icons.sync_rounded,
                  size: 12,
                  color: AppColors.warning,
                ),
          const SizedBox(width: 5),
          Text(
            live ? 'LIVE' : 'Reconnecting',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: live ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedCard extends StatelessWidget {
  final LiveAgent agent;
  final DateTime now;
  final bool following;
  final VoidCallback onFollow;
  final VoidCallback onClose;

  const _SelectedCard({
    required this.agent,
    required this.now,
    required this.following,
    required this.onFollow,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final status = agent.statusAt(now);
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          _Avatar(initials: agent.initials, color: color, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  agent.agentName.isEmpty ? 'Field executive' : agent.agentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_statusLine(agent, now)} · ${_ago(now.difference(agent.updatedAt))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: status == LiveStatus.offline
                        ? AppColors.textSecondary
                        : color,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: following ? null : onFollow,
            icon: Icon(
              following ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
              size: 16,
            ),
            label: Text(following ? 'Following' : 'Follow'),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _AgentSheet extends StatelessWidget {
  final ScrollController scroll;
  final List<_Track> tracks;
  final DateTime now;
  final String? selectedId;
  final bool loading;
  final String? error;
  final ValueChanged<String> onSelect;
  final VoidCallback onRetry;

  const _AgentSheet({
    required this.scroll,
    required this.tracks,
    required this.now,
    required this.selectedId,
    required this.loading,
    required this.error,
    required this.onSelect,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(color: Color(0x26000000), blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Field executives',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (error != null)
            _Notice(
              icon: Icons.cloud_off_rounded,
              text: error!,
              action: TextButton(onPressed: onRetry, child: const Text('Retry')),
            )
          else if (tracks.isEmpty && !loading)
            const _Notice(
              icon: Icons.location_searching_rounded,
              text:
                  'Nobody has shared a location in the last 12 hours. Field executives appear here once they check in.',
            ),
          for (final track in tracks)
            _AgentTile(
              agent: track.agent,
              now: now,
              selected: track.agent.agentId == selectedId,
              onTap: () => onSelect(track.agent.agentId),
            ),
        ],
      ),
    );
  }
}

class _AgentTile extends StatelessWidget {
  final LiveAgent agent;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  const _AgentTile({
    required this.agent,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = agent.statusAt(now);
    final color = _statusColor(status);
    return Material(
      color: selected ? AppColors.primaryLight : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              _Avatar(initials: agent.initials, color: color, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.agentName.isEmpty
                          ? 'Field executive'
                          : agent.agentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLine(agent, now),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: status == LiveStatus.offline
                            ? AppColors.textSecondary
                            : color,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _ago(now.difference(agent.updatedAt)),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;
  const _Avatar({required this.initials, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Notice({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Draws the round, initialled markers, with an arrow showing the direction
/// of travel, and caches them: drawing is async and costs a few milliseconds.
class _AgentIcons {
  _AgentIcons({required this.onReady});

  final VoidCallback onReady;
  double pixelRatio = 3;
  final Map<String, BitmapDescriptor> _cache = {};
  final Map<String, BitmapDescriptor> _latestPerAgent = {};
  final Set<String> _drawing = {};

  BitmapDescriptor iconFor(
    String initials,
    LiveStatus status,
    double? heading,
    bool selected,
  ) {
    // 24 directions are smooth enough and keep the cache small.
    final bucket = heading == null ? -1 : ((heading / 15).round() * 15) % 360;
    final agentKey = '$initials|${status.index}|$selected';
    final key = '$agentKey|$bucket';

    final cached = _cache[key];
    if (cached != null) {
      _latestPerAgent[agentKey] = cached;
      return cached;
    }
    if (_drawing.add(key)) {
      _draw(
            initials,
            _statusColor(status),
            bucket < 0 ? null : bucket.toDouble(),
            selected,
          )
          .then((icon) {
            _cache[key] = icon;
            _drawing.remove(key);
            onReady();
          })
          .catchError((Object _) {
            _drawing.remove(key);
          });
    }
    // While the new direction draws, keep showing the previous one.
    return _latestPerAgent[agentKey] ??
        BitmapDescriptor.defaultMarkerWithHue(switch (status) {
          LiveStatus.moving => BitmapDescriptor.hueGreen,
          LiveStatus.stopped => BitmapDescriptor.hueOrange,
          LiveStatus.offline => BitmapDescriptor.hueAzure,
        });
  }

  Future<BitmapDescriptor> _draw(
    String initials,
    Color color,
    double? heading,
    bool selected,
  ) async {
    final dpr = pixelRatio;
    const logical = 56.0;
    final size = logical * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final centre = Offset(size / 2, size / 2);
    final radius = size * 0.29;

    if (heading != null) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(heading * math.pi / 180);
      final arrow = Path()
        ..moveTo(0, -size * 0.49)
        ..lineTo(-size * 0.14, -radius * 0.8)
        ..lineTo(size * 0.14, -radius * 0.8)
        ..close();
      canvas.drawPath(arrow, Paint()..color = color);
      canvas.restore();
    }

    canvas.drawCircle(
      centre.translate(0, dpr),
      radius + 3 * dpr,
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * dpr),
    );
    if (selected) {
      canvas.drawCircle(
        centre,
        radius + 5 * dpr,
        Paint()..color = AppColors.primary.withValues(alpha: 0.35),
      );
    }
    canvas.drawCircle(
      centre,
      radius + 2.5 * dpr,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(centre, radius, Paint()..color = color);

    final text = TextPainter(
      text: TextSpan(
        text: initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, centre - Offset(text.width / 2, text.height / 2));

    final image = await recorder.endRecording().toImage(
      size.round(),
      size.round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: dpr,
    );
  }
}
