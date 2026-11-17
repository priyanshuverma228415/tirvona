import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/voice_service.dart';
import '../../../models/voice_note_model.dart';

class VoiceNoteRecorderWidget extends StatefulWidget {
  final String label;
  final String hint;
  final String type; // 'meeting' or 'internal'
  final bool isPrivate;
  final VoiceNoteModel? initialVoiceNote;
  final String? initialTranscript;
  final Function(VoiceNoteModel? voiceNote, String transcript) onChanged;

  const VoiceNoteRecorderWidget({
    super.key,
    required this.label,
    required this.hint,
    required this.type,
    this.isPrivate = false,
    this.initialVoiceNote,
    this.initialTranscript,
    required this.onChanged,
  });

  @override
  State<VoiceNoteRecorderWidget> createState() =>
      _VoiceNoteRecorderWidgetState();
}

class _VoiceNoteRecorderWidgetState extends State<VoiceNoteRecorderWidget>
    with SingleTickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isRecording = false;
  bool _isTranscribing = false;
  String? _errorMessage;

  Timer? _recordTimer;
  int _recordSeconds = 0;

  String? _recordedFilePath;
  VoiceNoteModel? _currentVoiceNote;
  String _currentTranscript = '';

  // Audio Playback states
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playerStateSub;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _currentVoiceNote = widget.initialVoiceNote;
    _currentTranscript =
        widget.initialTranscript ?? widget.initialVoiceNote?.transcript ?? '';

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    _posSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });

    _durSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _totalDuration = dur);
    });

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _currentPosition = Duration.zero;
            _isPlaying = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playerStateSub?.cancel();
    _audioPlayer.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    // Stop playback if playing
    if (_isPlaying) {
      await _audioPlayer.stop();
    }

    setState(() {
      _errorMessage = null;
    });

    try {
      final path = await _voiceService.startRecording();
      if (path != null) {
        setState(() {
          _isRecording = true;
          _recordedFilePath = path;
          _recordSeconds = 0;
        });

        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() => _recordSeconds++);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage ?? 'Could not start recording'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _stopRecordingAndTranscribe() async {
    _recordTimer?.cancel();

    final recordedSeconds = _recordSeconds;
    setState(() {
      _isRecording = false;
      _isTranscribing = true;
      _errorMessage = null;
    });

    try {
      final filePath = await _voiceService.stopRecording();
      if (filePath == null || filePath.isEmpty) {
        throw Exception('Audio file could not be saved');
      }

      _recordedFilePath = filePath;
      final duration = recordedSeconds.toDouble();

      // Upload and transcribe on backend
      final result = await _voiceService.uploadAndTranscribe(
        filePath: filePath,
        type: widget.type,
        durationSeconds: duration,
      );

      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _currentVoiceNote = result;
          _currentTranscript = result.transcript;
          _totalDuration = Duration(seconds: recordedSeconds);
        });

        widget.onChanged(_currentVoiceNote, _currentTranscript);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _errorMessage =
              'Transcription failed: ${e.toString().replaceAll('Exception: ', '')}. Audio is saved, you can retry.';
          // Keep the local voice note even if upload failed
          _currentVoiceNote = VoiceNoteModel(
            localFilePath: _recordedFilePath,
            duration: recordedSeconds.toDouble(),
            recordedAt: DateTime.now().toIso8601String(),
            transcript: _currentTranscript.isNotEmpty
                ? _currentTranscript
                : '[Voice Note Recorded - Tap Retry to transcribe]',
          );
        });

        widget.onChanged(_currentVoiceNote, _currentTranscript);
      }
    }
  }

  Future<void> _retryTranscription() async {
    final path = _recordedFilePath ?? _currentVoiceNote?.localFilePath;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio file not found on device for retry'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _isTranscribing = true;
      _errorMessage = null;
    });

    try {
      final dur = _currentVoiceNote?.duration ?? _recordSeconds.toDouble();
      final result = await _voiceService.uploadAndTranscribe(
        filePath: path,
        type: widget.type,
        durationSeconds: dur,
      );

      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _currentVoiceNote = result;
          _currentTranscript = result.transcript;
        });

        widget.onChanged(_currentVoiceNote, _currentTranscript);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _errorMessage =
              'Retry failed: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    final localPath = _recordedFilePath ?? _currentVoiceNote?.localFilePath;
    final remoteUrl = _currentVoiceNote?.audioUrl;

    if (localPath != null && File(localPath).existsSync()) {
      await _audioPlayer.play(DeviceFileSource(localPath));
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      await _audioPlayer.play(UrlSource(remoteUrl));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio not available for playback')),
      );
    }
  }

  void _confirmReRecord() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-record Voice Note?'),
        content: const Text(
          'Recording a new voice note will replace the previous recording and transcript.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _resetAndRecord();
            },
            child: const Text('Re-record'),
          ),
        ],
      ),
    );
  }

  void _resetAndRecord() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
    }
    setState(() {
      _currentVoiceNote = null;
      _currentTranscript = '';
      _recordedFilePath = null;
      _recordSeconds = 0;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
      _errorMessage = null;
    });
    widget.onChanged(null, '');
    _startRecording();
  }

  String _formatDuration(int totalSecs) {
    final mins = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSecs % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio =
        _currentVoiceNote?.hasAudio == true ||
        (_recordedFilePath != null && File(_recordedFilePath!).existsSync());
    final hasTranscript = _currentTranscript.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isRecording
              ? AppColors.danger
              : (widget.isPrivate ? AppColors.accent : AppColors.border),
          width: _isRecording ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _isRecording
                ? AppColors.danger.withValues(alpha: 0.08)
                : AppColors.secondary.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Label & Privacy Badge
          Row(
            children: [
              Icon(
                widget.isPrivate ? Icons.lock_outline : Icons.mic_none_outlined,
                size: 16,
                color: widget.isPrivate ? AppColors.accent : AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: widget.isPrivate
                        ? AppColors.textPrimary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              if (widget.isPrivate)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.accentBorder),
                  ),
                  child: const Text(
                    'PRIVATE / INTERNAL',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 1. STATE: Currently Recording
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.dangerLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.dangerBorder),
              ),
              child: Row(
                children: [
                  FadeTransition(
                    opacity: _pulseController,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Recording... ${_formatDuration(_recordSeconds)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text(
                      'Stop & Transcribe',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _stopRecordingAndTranscribe,
                  ),
                ],
              ),
            )
          // 2. STATE: Transcribing / Uploading
          else if (_isTranscribing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.infoBorder),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Converting Speech to Text...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Uploading audio securely and running AI transcription',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          // 3. STATE: Recording available (Playback + Transcript)
          else if (hasAudio)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Audio Player Control Card
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSecondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      // Play/Pause button
                      InkWell(
                        onTap: _togglePlayback,
                        borderRadius: BorderRadius.circular(20),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: AppColors.primary,
                          child: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Duration & timeline
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isPlaying ? 'Playing Recording' : 'Voice Note',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_formatDuration(_currentPosition.inSeconds)} / ${_formatDuration(_totalDuration.inSeconds > 0 ? _totalDuration.inSeconds : (_currentVoiceNote?.duration.toInt() ?? 0))}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Re-record button
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        color: AppColors.textSecondary,
                        tooltip: 'Re-record voice note',
                        onPressed: _confirmReRecord,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Transcribed Text Display Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.subtitles_outlined,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'AI Speech Transcript',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const Spacer(),
                          if (_errorMessage != null)
                            InkWell(
                              onTap: _retryTranscription,
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.replay,
                                    size: 12,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    'Retry STT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hasTranscript
                            ? _currentTranscript
                            : 'Transcript pending or empty.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: hasTranscript
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          // 4. STATE: Idle / No Recording yet
          else
            InkWell(
              onTap: _startRecording,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.border,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.primaryLight,
                      child: const Icon(
                        Icons.mic,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tap to Record Voice Note',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.hint,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),

          // Error banner if any
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 13,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
