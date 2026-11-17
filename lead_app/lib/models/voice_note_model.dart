import 'dart:convert';

class VoiceNoteModel {
  final String audioUrl;
  final double duration; // in seconds
  final String recordedAt;
  final String transcript;
  final String agentId;
  final String agentName;
  final String? localFilePath;

  VoiceNoteModel({
    this.audioUrl = '',
    this.duration = 0.0,
    this.recordedAt = '',
    this.transcript = '',
    this.agentId = '',
    this.agentName = '',
    this.localFilePath,
  });

  bool get hasAudio =>
      audioUrl.isNotEmpty ||
      (localFilePath != null && localFilePath!.isNotEmpty);

  bool get hasTranscript => transcript.trim().isNotEmpty;

  factory VoiceNoteModel.fromJson(Map<String, dynamic> json) {
    return VoiceNoteModel(
      audioUrl: (json['audioUrl'] ?? json['url'] ?? '').toString(),
      duration: (json['duration'] is num)
          ? (json['duration'] as num).toDouble()
          : (double.tryParse((json['duration'] ?? '0').toString()) ?? 0.0),
      recordedAt: (json['recordedAt'] ?? '').toString(),
      transcript: (json['transcript'] ?? json['text'] ?? '').toString(),
      agentId: (json['agentId'] ?? '').toString(),
      agentName: (json['agentName'] ?? '').toString(),
      localFilePath: json['localFilePath']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'audioUrl': audioUrl,
      'duration': duration,
      'recordedAt': recordedAt,
      'transcript': transcript,
      'agentId': agentId,
      'agentName': agentName,
      if (localFilePath != null) 'localFilePath': localFilePath,
    };
  }

  static VoiceNoteModel? fromRawJson(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return VoiceNoteModel.fromJson(raw);
    if (raw is Map) {
      return VoiceNoteModel.fromJson(Map<String, dynamic>.from(raw));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return VoiceNoteModel.fromJson(decoded);
        }
        if (decoded is Map) {
          return VoiceNoteModel.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return null;
  }

  String toRawJson() => jsonEncode(toJson());

  VoiceNoteModel copyWith({
    String? audioUrl,
    double? duration,
    String? recordedAt,
    String? transcript,
    String? agentId,
    String? agentName,
    String? localFilePath,
  }) {
    return VoiceNoteModel(
      audioUrl: audioUrl ?? this.audioUrl,
      duration: duration ?? this.duration,
      recordedAt: recordedAt ?? this.recordedAt,
      transcript: transcript ?? this.transcript,
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      localFilePath: localFilePath ?? this.localFilePath,
    );
  }
}
