import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/voice_note_model.dart';

class VoicePlaybackTile extends StatefulWidget {
  final String title;
  final String transcript;
  final VoiceNoteModel? voiceNote;
  final String defaultAgentName;
  final bool isPrivate;

  const VoicePlaybackTile({
    super.key,
    required this.title,
    required this.transcript,
    this.voiceNote,
    this.defaultAgentName = 'Field Agent',
    this.isPrivate = false,
  });

  @override
  State<VoicePlaybackTile> createState() => _VoicePlaybackTileState();
}

class _VoicePlaybackTileState extends State<VoicePlaybackTile> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _currentPos = Duration.zero;
  Duration _totalDur = Duration.zero;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    if (widget.voiceNote != null && widget.voiceNote!.duration > 0) {
      _totalDur = Duration(seconds: widget.voiceNote!.duration.toInt());
    }

    _posSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _currentPos = pos);
    });

    _durSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _totalDur = dur);
    });

    _stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _currentPos = Duration.zero;
            _isPlaying = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    final localPath = widget.voiceNote?.localFilePath;
    final audioUrl = widget.voiceNote?.audioUrl;

    if (localPath != null && File(localPath).existsSync()) {
      await _audioPlayer.play(DeviceFileSource(localPath));
    } else if (audioUrl != null && audioUrl.isNotEmpty) {
      await _audioPlayer.play(UrlSource(audioUrl));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio stream not available for this note'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  String _formatDuration(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatTimestamp(String? ts) {
    if (ts == null || ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      return DateFormat('dd MMM, hh:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio =
        widget.voiceNote?.hasAudio == true ||
        (widget.voiceNote?.audioUrl.isNotEmpty == true);
    final agentName = widget.voiceNote?.agentName.isNotEmpty == true
        ? widget.voiceNote!.agentName
        : widget.defaultAgentName;
    final recordedAtFormatted = _formatTimestamp(widget.voiceNote?.recordedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isPrivate
              ? AppColors.accentBorder
              : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                widget.isPrivate
                    ? Icons.lock_outline
                    : Icons.record_voice_over_outlined,
                size: 16,
                color: widget.isPrivate ? AppColors.accent : AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
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
                    'PRIVATE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                ),
            ],
          ),

          // Metadata row: Agent & Timestamp & Duration
          if (hasAudio || recordedAtFormatted.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (agentName.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'By: $agentName',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                if (recordedAtFormatted.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        recordedAtFormatted,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // Audio player bar (if audio available)
          if (hasAudio)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: _togglePlay,
                    borderRadius: BorderRadius.circular(18),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: widget.isPrivate
                          ? AppColors.accent
                          : AppColors.primary,
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                        trackHeight: 3,
                        activeTrackColor: widget.isPrivate
                            ? AppColors.accent
                            : AppColors.primary,
                        inactiveTrackColor: AppColors.border,
                        thumbColor: widget.isPrivate
                            ? AppColors.accent
                            : AppColors.primary,
                      ),
                      child: Slider(
                        value: _currentPos.inSeconds.toDouble().clamp(
                          0.0,
                          _totalDur.inSeconds > 0
                              ? _totalDur.inSeconds.toDouble()
                              : 1.0,
                        ),
                        max: _totalDur.inSeconds > 0
                            ? _totalDur.inSeconds.toDouble()
                            : 1.0,
                        onChanged: (val) {
                          _audioPlayer.seek(Duration(seconds: val.toInt()));
                        },
                      ),
                    ),
                  ),
                  Text(
                    '${_formatDuration(_currentPos.inSeconds)} / ${_formatDuration(_totalDur.inSeconds)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

          if (hasAudio) const SizedBox(height: 8),

          // Transcript Text
          if (widget.transcript.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'TRANSCRIPT',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: widget.transcript),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Transcript copied to clipboard'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: const Icon(
                          Icons.copy_outlined,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.transcript,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      height: 1.4,
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
