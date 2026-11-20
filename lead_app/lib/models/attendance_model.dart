import 'package:intl/intl.dart';

/// Represents a field stoppage / halt where the agent stayed for > 5 minutes
/// (e.g. at an Ashram, Dharamshala, or client meeting location).
class ShiftHalt {
  final String placeName;
  final String address;
  final int durationMinutes;
  final String timeRange;
  final String haltType;
  final double? lat;
  final double? lng;

  const ShiftHalt({
    required this.placeName,
    required this.address,
    required this.durationMinutes,
    required this.timeRange,
    this.haltType = 'Stay Verification & Meeting',
    this.lat,
    this.lng,
  });

  factory ShiftHalt.fromJson(Map<String, dynamic> json) {
    return ShiftHalt(
      placeName:
          json['placeName']?.toString() ??
          json['name']?.toString() ??
          json['location']?.toString() ??
          'Field Location',
      address: json['address']?.toString() ?? '',
      durationMinutes:
          (json['durationMinutes'] as num?)?.toInt() ??
          (json['duration'] as num?)?.toInt() ??
          15,
      timeRange: json['timeRange']?.toString() ?? '',
      haltType:
          json['haltType']?.toString() ??
          json['purpose']?.toString() ??
          'Stay Verification & Meeting',
      lat: (json['lat'] as num?)?.toDouble() ?? (json['latitude'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble() ?? (json['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'placeName': placeName,
    'address': address,
    'durationMinutes': durationMinutes,
    'timeRange': timeRange,
    'haltType': haltType,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
  };
}

class AttendanceModel {
  final String? id;
  final String? date;
  final bool checkedIn;
  final DateTime? checkInTime;
  final double? checkInLat;
  final double? checkInLng;
  final String? checkInAddress;

  final bool checkedOut;
  final DateTime? checkOutTime;
  final double? checkOutLat;
  final double? checkOutLng;
  final String? checkOutAddress;

  final double? totalDistanceKm;
  final int? batteryLevel;
  final String? notes;
  final String? photoUrl;
  final int? totalWorkingMinutes;
  final String? formattedWorkingHours;
  final String? status;
  final List<ShiftHalt> halts;

  AttendanceModel({
    this.id,
    this.date,
    this.checkedIn = false,
    this.checkInTime,
    this.checkInLat,
    this.checkInLng,
    this.checkInAddress,
    this.checkedOut = false,
    this.checkOutTime,
    this.checkOutLat,
    this.checkOutLng,
    this.checkOutAddress,
    this.totalDistanceKm,
    this.batteryLevel,
    this.notes,
    this.photoUrl,
    this.totalWorkingMinutes,
    this.formattedWorkingHours,
    this.status,
    this.halts = const [],
  });

  bool get isShiftActive => checkedIn && !checkedOut;

  Duration? get shiftDuration {
    if (checkInTime == null) return null;
    final end = checkOutTime ?? DateTime.now();
    return end.difference(checkInTime!);
  }

  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null) return null;
      try {
        return DateTime.parse(d.toString()).toLocal();
      } catch (_) {
        return null;
      }
    }

    final inLoc =
        json['checkInLocation'] as Map<String, dynamic>? ??
        json['checkInCoords'] as Map<String, dynamic>? ??
        {};
    final outLoc =
        json['checkOutLocation'] as Map<String, dynamic>? ??
        json['checkOutCoords'] as Map<String, dynamic>? ??
        {};

    final inLat = inLoc['latitude'] ?? inLoc['lat'];
    final inLng = inLoc['longitude'] ?? inLoc['lng'];
    final outLat = outLoc['latitude'] ?? outLoc['lat'];
    final outLng = outLoc['longitude'] ?? outLoc['lng'];

    final parsedInTime = parseDate(json['checkInTime']);
    final parsedOutTime = parseDate(json['checkOutTime']);

    String? recordDate = json['date']?.toString();
    if (recordDate == null && parsedInTime != null) {
      recordDate = DateFormat('yyyy-MM-dd').format(parsedInTime);
    }

    double? finalDistance;
    final dynamic rawDist =
        json['totalDistanceKm'] ??
        json['distanceKm'] ??
        json['shiftDistance'] ??
        json['distance_km'];
    if (rawDist is num && rawDist > 0) {
      finalDistance = rawDist.toDouble();
    } else {
      finalDistance = 0.0;
    }

    String? startAddr = (json['checkInAddress'] ?? inLoc['address'])?.toString();
    if (startAddr != null && startAddr.trim().isNotEmpty) {
      startAddr = startAddr.trim();
    } else if (inLat != null && inLng != null) {
      startAddr = 'GPS: ${(inLat as num).toStringAsFixed(4)}° N, ${(inLng as num).toStringAsFixed(4)}° E';
    } else {
      startAddr = null;
    }

    String? endAddr = (json['checkOutAddress'] ?? outLoc['address'])?.toString();
    if (endAddr != null && endAddr.trim().isNotEmpty) {
      endAddr = endAddr.trim();
    } else if (outLat != null && outLng != null) {
      endAddr = 'GPS: ${(outLat as num).toStringAsFixed(4)}° N, ${(outLng as num).toStringAsFixed(4)}° E';
    } else {
      endAddr = null;
    }

    // Parse halts (> 5 minutes stoppages)
    List<ShiftHalt> parsedHalts = [];
    final rawHalts = json['halts'] ?? json['stoppages'];
    if (rawHalts is List && rawHalts.isNotEmpty) {
      parsedHalts = rawHalts
          .map((h) => ShiftHalt.fromJson(Map<String, dynamic>.from(h)))
          .toList();
    }

    final rawNotes = json['notes']?.toString() ?? '';
    final isCheckedOut = json['checkedOut'] == true;
    final rawStartAddr = (json['checkInAddress'] ?? inLoc['address'])?.toString() ?? '';

    // Prevent automatic check-in on login:
    // If the server auto-created a record upon login without explicit coordinates or with login notes,
    // do NOT treat it as an active field shift. The agent must explicitly tap Check-In.
    final isAutoLoginCheckIn = rawNotes.toLowerCase().contains('login') ||
        rawNotes == 'Shift login check-in' ||
        rawNotes == 'Initial shift login attendance' ||
        json['isAutoCheckIn'] == true ||
        (!isCheckedOut && rawStartAddr == 'Mathura, Uttar Pradesh') ||
        (!isCheckedOut && rawStartAddr.contains('Mathura, Uttar Pradesh')) ||
        (!isCheckedOut && (inLat == null || inLat == 0) && (inLng == null || inLng == 0));

    final isCheckedIn = (json['checkedIn'] == true) && !isAutoLoginCheckIn;

    return AttendanceModel(
      id: (json['_id'] ?? json['id'])?.toString(),
      date: recordDate,
      checkedIn: isCheckedIn,
      checkInTime: parsedInTime,
      checkInLat: inLat != null ? (inLat as num).toDouble() : null,
      checkInLng: inLng != null ? (inLng as num).toDouble() : null,
      checkInAddress: startAddr,
      checkedOut: isCheckedOut,
      checkOutTime: parsedOutTime,
      checkOutLat: outLat != null ? (outLat as num).toDouble() : null,
      checkOutLng: outLng != null ? (outLng as num).toDouble() : null,
      checkOutAddress: endAddr,
      totalDistanceKm: finalDistance,
      batteryLevel: json['batteryLevel'] != null
          ? (json['batteryLevel'] as num).toInt()
          : null,
      notes: rawNotes,
      photoUrl: json['photoUrl']?.toString(),
      totalWorkingMinutes: json['totalWorkingMinutes'] != null
          ? (json['totalWorkingMinutes'] as num).toInt()
          : null,
      formattedWorkingHours: json['formattedWorkingHours']?.toString(),
      status: json['status']?.toString(),
      halts: parsedHalts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      'checkedIn': checkedIn,
      'checkInTime': checkInTime?.toIso8601String(),
      'checkInLocation': {
        if (checkInLat != null) 'latitude': checkInLat,
        if (checkInLng != null) 'longitude': checkInLng,
        if (checkInAddress != null) 'address': checkInAddress,
      },
      'checkedOut': checkedOut,
      'checkOutTime': checkOutTime?.toIso8601String(),
      'checkOutLocation': {
        if (checkOutLat != null) 'latitude': checkOutLat,
        if (checkOutLng != null) 'longitude': checkOutLng,
        if (checkOutAddress != null) 'address': checkOutAddress,
      },
      if (totalDistanceKm != null) 'totalDistanceKm': totalDistanceKm,
      if (status != null) 'status': status,
      'halts': halts.map((h) => h.toJson()).toList(),
    };
  }
}
