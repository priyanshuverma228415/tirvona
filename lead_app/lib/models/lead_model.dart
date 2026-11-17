import 'dart:convert';

import 'voice_note_model.dart';

class LeadModel {
  final String id;
  final String name;
  final String address;
  final String googleMapsUrl;
  final String city;
  final String district;
  final String state;
  final double? lat;
  final double? lng;

  final int? totalRooms;
  final double? roomPrice;
  final int? onlineRooms;
  final int? offlineRooms;

  final String ownerName;
  final String phone;

  final String notes;
  final String agentNotes;
  final VoiceNoteModel? meetingNotesAudio;
  final VoiceNoteModel? agentNotesAudio;
  final String interest;

  final bool meetingRequested;
  final String meetingTime;
  final String meetingMode;

  final List<String> images;
  final String status;

  final bool fieldVerified;
  final bool documentVerified;
  final String docVerificationStatus;

  final String capturedByName;
  final String? createdAt;
  final bool isSynced;

  LeadModel({
    required this.id,
    required this.name,
    this.address = '',
    this.googleMapsUrl = '',
    this.city = '',
    this.district = '',
    this.state = '',
    this.lat,
    this.lng,
    this.totalRooms,
    this.roomPrice,
    this.onlineRooms,
    this.offlineRooms,
    this.ownerName = '',
    this.phone = '',
    this.notes = '',
    this.agentNotes = '',
    this.meetingNotesAudio,
    this.agentNotesAudio,
    this.interest = 'Interested',
    this.meetingRequested = true,
    this.meetingTime = '',
    this.meetingMode = 'Call',
    this.images = const [],
    this.status = 'pending',
    this.fieldVerified = false,
    this.documentVerified = false,
    this.docVerificationStatus = 'pending',
    this.capturedByName = '',
    this.createdAt,
    this.isSynced = true,
  });

  factory LeadModel.fromApiJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>? ?? {};
    final coords = location['coordinates'] as Map<String, dynamic>? ?? {};
    final inventory = json['roomInventory'] as Map<String, dynamic>? ?? {};
    final contact = json['contact'] as Map<String, dynamic>? ?? {};
    final meeting = json['meeting'] as Map<String, dynamic>? ?? {};

    List<String> imgList = [];
    if (json['images'] is List) {
      imgList = (json['images'] as List).map((e) => e.toString()).toList();
    }

    return LeadModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      address: (location['address'] ?? '').toString(),
      googleMapsUrl: (location['googleMapsUrl'] ?? '').toString(),
      city: (location['city'] ?? '').toString(),
      district: (location['district'] ?? '').toString(),
      state: (location['state'] ?? '').toString(),
      lat: coords['lat'] != null ? (coords['lat'] as num).toDouble() : null,
      lng: coords['lng'] != null ? (coords['lng'] as num).toDouble() : null,
      totalRooms: inventory['totalRooms'] != null
          ? (inventory['totalRooms'] as num).toInt()
          : null,
      roomPrice: inventory['roomPrice'] != null
          ? (inventory['roomPrice'] as num).toDouble()
          : null,
      onlineRooms: inventory['onlineRooms'] != null
          ? (inventory['onlineRooms'] as num).toInt()
          : null,
      offlineRooms: inventory['offlineRooms'] != null
          ? (inventory['offlineRooms'] as num).toInt()
          : null,
      ownerName: (contact['ownerName'] ?? '').toString(),
      phone: (contact['phone'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      agentNotes: (json['agentNotes'] ?? '').toString(),
      meetingNotesAudio: VoiceNoteModel.fromRawJson(json['meetingNotesAudio']),
      agentNotesAudio: VoiceNoteModel.fromRawJson(json['agentNotesAudio']),
      interest: (json['interest'] ?? 'Interested').toString(),
      meetingRequested: meeting['requested'] == true,
      meetingTime: (meeting['time'] ?? '').toString(),
      meetingMode: (meeting['mode'] ?? 'Call').toString(),
      images: imgList,
      status: (json['status'] ?? 'pending').toString(),
      fieldVerified: json['fieldVerified'] == true,
      documentVerified: json['documentVerified'] == true,
      docVerificationStatus: (json['docVerificationStatus'] ?? 'pending')
          .toString(),
      capturedByName: (json['capturedByName'] ?? '').toString(),
      createdAt:
          (json['capturedAt'] ?? json['createdAt'] ?? '').toString().isNotEmpty
          ? (json['capturedAt'] ?? json['createdAt']).toString()
          : null,
      isSynced: true,
    );
  }

  Map<String, dynamic> toApiJson() {
    final Map<String, dynamic> data = {'name': name};

    final Map<String, dynamic> location = {
      'address': address,
      'googleMapsUrl': googleMapsUrl,
      'city': city,
      'district': district,
      'state': state,
    };
    if (lat != null && lng != null) {
      location['coordinates'] = {'lat': lat, 'lng': lng};
    }
    data['location'] = location;

    data['roomInventory'] = {
      if (totalRooms != null) 'totalRooms': totalRooms,
      if (roomPrice != null) 'roomPrice': roomPrice,
      if (onlineRooms != null) 'onlineRooms': onlineRooms,
      if (offlineRooms != null) 'offlineRooms': offlineRooms,
    };

    data['contact'] = {'ownerName': ownerName, 'phone': phone};

    data['notes'] = notes;
    data['agentNotes'] = agentNotes;
    if (meetingNotesAudio != null) {
      data['meetingNotesAudio'] = meetingNotesAudio!.toJson();
    }
    if (agentNotesAudio != null) {
      data['agentNotesAudio'] = agentNotesAudio!.toJson();
    }
    data['interest'] = interest;

    data['meeting'] = {
      'requested': meetingRequested,
      'time': meetingRequested ? meetingTime : '',
      'mode': meetingRequested ? meetingMode : '',
    };

    data['images'] = images;
    return data;
  }

  // SQLite Mapping
  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'googleMapsUrl': googleMapsUrl,
      'city': city,
      'district': district,
      'state': state,
      'lat': lat,
      'lng': lng,
      'totalRooms': totalRooms,
      'roomPrice': roomPrice,
      'onlineRooms': onlineRooms,
      'offlineRooms': offlineRooms,
      'ownerName': ownerName,
      'phone': phone,
      'notes': notes,
      'agentNotes': agentNotes,
      'meetingNotesAudioJson': meetingNotesAudio?.toRawJson(),
      'agentNotesAudioJson': agentNotesAudio?.toRawJson(),
      'interest': interest,
      'meetingRequested': meetingRequested ? 1 : 0,
      'meetingTime': meetingTime,
      'meetingMode': meetingMode,
      'imagesJson': jsonEncode(images),
      'status': status,
      'fieldVerified': fieldVerified ? 1 : 0,
      'documentVerified': documentVerified ? 1 : 0,
      'docVerificationStatus': docVerificationStatus,
      'capturedByName': capturedByName,
      'createdAt': createdAt,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory LeadModel.fromDbMap(Map<String, dynamic> map) {
    List<String> imgs = [];
    if (map['imagesJson'] != null) {
      try {
        final decoded = jsonDecode(map['imagesJson'] as String);
        if (decoded is List) {
          imgs = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return LeadModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      googleMapsUrl: map['googleMapsUrl']?.toString() ?? '',
      city: map['city']?.toString() ?? '',
      district: map['district']?.toString() ?? '',
      state: map['state']?.toString() ?? '',
      lat: map['lat'] != null ? (map['lat'] as num).toDouble() : null,
      lng: map['lng'] != null ? (map['lng'] as num).toDouble() : null,
      totalRooms: map['totalRooms'] != null
          ? (map['totalRooms'] as num).toInt()
          : null,
      roomPrice: map['roomPrice'] != null
          ? (map['roomPrice'] as num).toDouble()
          : null,
      onlineRooms: map['onlineRooms'] != null
          ? (map['onlineRooms'] as num).toInt()
          : null,
      offlineRooms: map['offlineRooms'] != null
          ? (map['offlineRooms'] as num).toInt()
          : null,
      ownerName: map['ownerName']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      agentNotes: map['agentNotes']?.toString() ?? '',
      meetingNotesAudio: VoiceNoteModel.fromRawJson(
        map['meetingNotesAudioJson'],
      ),
      agentNotesAudio: VoiceNoteModel.fromRawJson(map['agentNotesAudioJson']),
      interest: map['interest']?.toString() ?? 'Interested',
      meetingRequested: map['meetingRequested'] == 1,
      meetingTime: map['meetingTime']?.toString() ?? '',
      meetingMode: map['meetingMode']?.toString() ?? 'Call',
      images: imgs,
      status: map['status']?.toString() ?? 'pending',
      fieldVerified: map['fieldVerified'] == 1,
      documentVerified: map['documentVerified'] == 1,
      docVerificationStatus:
          map['docVerificationStatus']?.toString() ?? 'pending',
      capturedByName: map['capturedByName']?.toString() ?? '',
      createdAt: map['createdAt']?.toString(),
      isSynced: map['isSynced'] == 1,
    );
  }

  LeadModel copyWith({
    String? id,
    String? name,
    String? address,
    String? googleMapsUrl,
    String? city,
    String? district,
    String? state,
    double? lat,
    double? lng,
    int? totalRooms,
    double? roomPrice,
    int? onlineRooms,
    int? offlineRooms,
    String? ownerName,
    String? phone,
    String? notes,
    String? agentNotes,
    VoiceNoteModel? meetingNotesAudio,
    VoiceNoteModel? agentNotesAudio,
    String? interest,
    bool? meetingRequested,
    String? meetingTime,
    String? meetingMode,
    List<String>? images,
    String? status,
    bool? fieldVerified,
    bool? documentVerified,
    String? docVerificationStatus,
    String? capturedByName,
    String? createdAt,
    bool? isSynced,
  }) {
    return LeadModel(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      googleMapsUrl: googleMapsUrl ?? this.googleMapsUrl,
      city: city ?? this.city,
      district: district ?? this.district,
      state: state ?? this.state,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      totalRooms: totalRooms ?? this.totalRooms,
      roomPrice: roomPrice ?? this.roomPrice,
      onlineRooms: onlineRooms ?? this.onlineRooms,
      offlineRooms: offlineRooms ?? this.offlineRooms,
      ownerName: ownerName ?? this.ownerName,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      agentNotes: agentNotes ?? this.agentNotes,
      meetingNotesAudio: meetingNotesAudio ?? this.meetingNotesAudio,
      agentNotesAudio: agentNotesAudio ?? this.agentNotesAudio,
      interest: interest ?? this.interest,
      meetingRequested: meetingRequested ?? this.meetingRequested,
      meetingTime: meetingTime ?? this.meetingTime,
      meetingMode: meetingMode ?? this.meetingMode,
      images: images ?? this.images,
      status: status ?? this.status,
      fieldVerified: fieldVerified ?? this.fieldVerified,
      documentVerified: documentVerified ?? this.documentVerified,
      docVerificationStatus:
          docVerificationStatus ?? this.docVerificationStatus,
      capturedByName: capturedByName ?? this.capturedByName,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
