/// One agent on the supervisor's team map, from a row of
/// `GET /supervisor/tracking/live`: the newest route point the agent's phone
/// has uploaded (every 30 s while moving, every 2 min standing still).
enum LiveStatus { moving, stopped, offline }

class LiveAgent {
  final String agentId;
  final String agentName;
  final double lat;
  final double lng;

  /// When the phone took this position, in this phone's local time.
  final DateTime updatedAt;

  /// Metres per second, worked out from the last two positions.
  final double? speed;

  /// Degrees clockwise from north, worked out from the last two positions.
  final double? heading;

  const LiveAgent({
    required this.agentId,
    required this.agentName,
    required this.lat,
    required this.lng,
    required this.updatedAt,
    this.speed,
    this.heading,
  });

  static LiveAgent? fromJson(Map<String, dynamic> json) {
    final lat = _num(json['lat']);
    final lng = _num(json['lng']);
    final id = (json['agentId'] ?? '').toString();
    if (lat == null || lng == null || id.isEmpty) return null;

    final raw = json['recordedAt']?.toString();
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    // Without a timestamp, fall back on the server's own "minutes ago".
    final minutesAgo = _num(json['minutesAgo']);
    final updatedAt =
        parsed?.toLocal() ??
        DateTime.now().subtract(Duration(minutes: (minutesAgo ?? 0).round()));

    return LiveAgent(
      agentId: id,
      agentName: (json['agentName'] ?? '').toString(),
      lat: lat,
      lng: lng,
      updatedAt: updatedAt,
      speed: _num(json['speed']),
      heading: _num(json['heading']),
    );
  }

  LiveAgent withMotion({double? speed, double? heading}) => LiveAgent(
    agentId: agentId,
    agentName: agentName,
    lat: lat,
    lng: lng,
    updatedAt: updatedAt,
    speed: speed ?? this.speed,
    heading: heading ?? this.heading,
  );

  /// Standing still, a phone on shift still uploads a point every couple of
  /// minutes, so ten minutes of silence means it stopped reporting.
  LiveStatus statusAt(DateTime now) {
    final age = now.difference(updatedAt);
    if (age > const Duration(minutes: 10)) return LiveStatus.offline;
    if ((speed ?? 0) >= 1.0 && age < const Duration(minutes: 3)) {
      return LiveStatus.moving;
    }
    return LiveStatus.stopped;
  }

  double get speedKmh => (speed ?? 0) * 3.6;

  String get initials {
    final parts = agentName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(1, 2))
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static double? _num(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }
}
