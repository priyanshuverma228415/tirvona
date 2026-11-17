import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../models/lead_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/lead_provider.dart';
import 'create_lead_screen.dart';
import 'widgets/voice_playback_tile.dart';

class LeadDetailScreen extends StatelessWidget {
  final LeadModel lead;

  const LeadDetailScreen({super.key, required this.lead});

  void _callPhone(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openWhatsApp(String phone) async {
    String clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length == 10) clean = '91$clean';
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openMaps(double? lat, double? lng, String url) async {
    if (lat != null && lng != null) {
      final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (url.isNotEmpty) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().user;
    final isAuthorizedForInternalNotes =
        currentUser?.role != 'client' && currentUser?.role != 'public';
    final hasNotes = lead.notes.isNotEmpty || lead.meetingNotesAudio != null;
    final hasAgentNotes =
        isAuthorizedForInternalNotes &&
        (lead.agentNotes.isNotEmpty || lead.agentNotesAudio != null);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          lead.name,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateLeadScreen(editingLead: lead),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text(
                    'Delete Lead',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  content: Text(
                    'Are you sure you want to delete "${lead.name}"?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                await context.read<LeadProvider>().deleteLead(lead.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Lead removed')));
                }
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (lead.status == 'approved' ||
                                lead.status == 'converted' ||
                                lead.status == 'completed')
                            ? AppColors.successLight
                            : (lead.status == 'rejected'
                                  ? AppColors.dangerLight
                                  : (lead.status.toLowerCase().contains(
                                          'follow',
                                        )
                                        ? AppColors.accentLight
                                        : AppColors.infoLight)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              (lead.status == 'approved' ||
                                  lead.status == 'converted' ||
                                  lead.status == 'completed')
                              ? AppColors.successBorder
                              : (lead.status == 'rejected'
                                    ? AppColors.dangerBorder
                                    : (lead.status.toLowerCase().contains(
                                            'follow',
                                          )
                                          ? AppColors.accentBorder
                                          : AppColors.infoBorder)),
                        ),
                      ),
                      child: Text(
                        (lead.status == 'approved' ||
                                lead.status == 'converted' ||
                                lead.status == 'completed')
                            ? 'COMPLETED'
                            : lead.status.toUpperCase(),
                        style: TextStyle(
                          color:
                              (lead.status == 'approved' ||
                                  lead.status == 'converted' ||
                                  lead.status == 'completed')
                              ? AppColors.success
                              : (lead.status == 'rejected'
                                    ? AppColors.danger
                                    : (lead.status.toLowerCase().contains(
                                            'follow',
                                          )
                                          ? AppColors.accent
                                          : AppColors.primary)),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        lead.interest,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  lead.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (lead.address.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${lead.address}, ${lead.city}, ${lead.state}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (lead.lat != null && lead.lng != null) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () =>
                        _openMaps(lead.lat, lead.lng, lead.googleMapsUrl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.infoLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.infoBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.directions,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Navigate via Google Maps (${lead.lat!.toStringAsFixed(4)}, ${lead.lng!.toStringAsFixed(4)})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Contact Card with Quick Call/WhatsApp
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contact Person',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.primaryLight,
                      child: const Icon(Icons.person, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lead.ownerName.isNotEmpty
                                ? lead.ownerName
                                : 'Owner / Manager',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lead.phone.isNotEmpty
                                ? lead.phone
                                : 'No phone provided',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (lead.phone.isNotEmpty) ...[
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        icon: const Icon(Icons.phone, size: 18),
                        onPressed: () => _callPhone(lead.phone),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                        icon: const Icon(Icons.chat, size: 18),
                        onPressed: () => _openWhatsApp(lead.phone),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Inventory & Pricing
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Room Inventory & Pricing',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildStatItem('Total Rooms', '${lead.totalRooms ?? 0}'),
                    _buildStatItem(
                      'Avg Tariff',
                      '₹${lead.roomPrice?.toStringAsFixed(0) ?? 'N/A'}',
                    ),
                    _buildStatItem('Online Rooms', '${lead.onlineRooms ?? 0}'),
                    _buildStatItem(
                      'Offline Rooms',
                      '${lead.offlineRooms ?? 0}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Meeting & Notes
          if (lead.meetingRequested || hasNotes || hasAgentNotes)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lead.meetingRequested) ...[
                    const Text(
                      'Follow-Up Meeting',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lead.meetingTime.isNotEmpty
                                      ? DateFormat(
                                          'EEEE, dd MMM yyyy - hh:mm a',
                                        ).format(
                                          DateTime.parse(lead.meetingTime)
                                              .toLocal(),
                                        )
                                      : 'Date to be scheduled',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Mode: ${lead.meetingMode}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (hasNotes) ...[
                    VoicePlaybackTile(
                      title: 'Meeting / Discussion Notes',
                      transcript: lead.notes,
                      voiceNote: lead.meetingNotesAudio,
                      defaultAgentName: lead.capturedByName,
                      isPrivate: false,
                    ),
                  ],

                  if (hasAgentNotes) ...[
                    VoicePlaybackTile(
                      title: 'Internal Agent Notes (Private)',
                      transcript: lead.agentNotes,
                      voiceNote: lead.agentNotesAudio,
                      defaultAgentName: lead.capturedByName,
                      isPrivate: true,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Attached Photos
          if (lead.images.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stay Photos (${lead.images.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: lead.images.length,
                    itemBuilder: (ctx, i) {
                      final urlOrPath = lead.images[i];
                      final isRemote = urlOrPath.startsWith('http');
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: isRemote
                            ? Image.network(urlOrPath, fit: BoxFit.cover)
                            : Image.file(File(urlOrPath), fit: BoxFit.cover),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
