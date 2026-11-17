import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../models/voice_note_model.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';

class VoiceService {
  static final VoiceService instance = VoiceService._init();
  final AudioRecorder _recorder = AudioRecorder();
  final ApiClient _apiClient = ApiClient.instance;

  VoiceService._init();

  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  Future<bool> checkPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final req = await Permission.microphone.request();
    return req.isGranted;
  }

  Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  Future<String?> startRecording() async {
    final hasPerm = await checkPermission();
    if (!hasPerm) {
      throw Exception(
        'Microphone permission is required to record voice notes',
      );
    }

    final isRec = await _recorder.isRecording();
    if (isRec) {
      await _recorder.stop();
    }

    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(tempDir.path, 'lead_voice_$now.m4a');
    _currentRecordingPath = filePath;
    _recordingStartTime = DateTime.now();

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );

    return filePath;
  }

  Future<String?> stopRecording() async {
    final isRec = await _recorder.isRecording();
    if (!isRec) return _currentRecordingPath;

    final path = await _recorder.stop();
    _currentRecordingPath = path ?? _currentRecordingPath;
    return _currentRecordingPath;
  }

  Future<void> cancelRecording() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    if (_currentRecordingPath != null) {
      final f = File(_currentRecordingPath!);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    _currentRecordingPath = null;
    _recordingStartTime = null;
  }

  Duration getElapsedRecordingTime() {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }

  Future<VoiceNoteModel> uploadAndTranscribe({
    required String filePath,
    required String type, // 'meeting' or 'internal'
    required double durationSeconds,
    String? leadId,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Audio recording file not found on device');
    }

    final fileName = p.basename(filePath);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      'type': type,
      'duration': durationSeconds.toStringAsFixed(1),
      if (leadId != null && leadId.isNotEmpty) 'leadId': leadId,
    });

    final response = await _apiClient.dio.post(
      ApiEndpoints.voiceTranscribe,
      data: formData,
    );

    final body = response.data;
    final data = body['data'] ?? body;
    final model = VoiceNoteModel.fromJson(Map<String, dynamic>.from(data));

    return model.copyWith(
      localFilePath: filePath,
      duration: durationSeconds > 0 ? durationSeconds : model.duration,
    );
  }

  void dispose() {
    _recorder.dispose();
  }
}
