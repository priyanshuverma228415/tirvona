import 'package:intl/intl.dart';

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

    final distance =
        json['totalDistanceKm'] ?? json['distanceKm'] ?? json['shiftDistance'];

    final parsedInTime = parseDate(json['checkInTime']);
    final parsedOutTime = parseDate(json['checkOutTime']);

    String? recordDate = json['date']?.toString();
    if (recordDate == null && parsedInTime != null) {
      recordDate = DateFormat('yyyy-MM-dd').format(parsedInTime);
    }

    return AttendanceModel(
      id: (json['_id'] ?? json['id'])?.toString(),
      date: recordDate,
      checkedIn: json['checkedIn'] == true,
      checkInTime: parsedInTime,
      checkInLat: inLat != null ? (inLat as num).toDouble() : null,
      checkInLng: inLng != null ? (inLng as num).toDouble() : null,
      checkInAddress: (json['checkInAddress'] ?? inLoc['address'])?.toString(),
      checkedOut: json['checkedOut'] == true,
      checkOutTime: parsedOutTime,
      checkOutLat: outLat != null ? (outLat as num).toDouble() : null,
      checkOutLng: outLng != null ? (outLng as num).toDouble() : null,
      checkOutAddress: (json['checkOutAddress'] ?? outLoc['address'])
          ?.toString(),
      totalDistanceKm: distance != null ? (distance as num).toDouble() : null,
      batteryLevel: json['batteryLevel'] != null
          ? (json['batteryLevel'] as num).toInt()
          : null,
      notes: json['notes']?.toString(),
      photoUrl: json['photoUrl']?.toString(),
      totalWorkingMinutes: json['totalWorkingMinutes'] != null
          ? (json['totalWorkingMinutes'] as num).toInt()
          : null,
      formattedWorkingHours: json['formattedWorkingHours']?.toString(),
      status: json['status']?.toString(),
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
    };
  }
}
