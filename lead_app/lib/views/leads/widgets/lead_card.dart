import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/lead_model.dart';

class LeadCardWidget extends StatelessWidget {
  final LeadModel lead;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const LeadCardWidget({
    super.key,
    required this.lead,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  Color _getStatusBg() {
    switch (lead.status.toLowerCase().trim()) {
      case 'approved':
      case 'converted':
      case 'completed':
        return AppColors.successLight;
      case 'rejected':
        return AppColors.dangerLight;
      case 'follow_up':
      case 'followup':
        return AppColors.accentLight;
      case 'new':
        return AppColors.infoLight;
      default:
        return AppColors.infoLight;
    }
  }

  Color _getStatusText() {
    switch (lead.status.toLowerCase().trim()) {
      case 'approved':
      case 'converted':
      case 'completed':
        return AppColors.success;
      case 'rejected':
        return AppColors.danger;
      case 'follow_up':
      case 'followup':
        return AppColors.accent;
      case 'new':
        return AppColors.info;
      default:
        return AppColors.primary;
    }
  }

  Color _getStatusBorder() {
    switch (lead.status.toLowerCase().trim()) {
      case 'approved':
      case 'converted':
      case 'completed':
        return AppColors.successBorder;
      case 'rejected':
        return AppColors.dangerBorder;
      case 'follow_up':
      case 'followup':
        return AppColors.accentBorder;
      case 'new':
        return AppColors.infoBorder;
      default:
        return AppColors.infoBorder;
    }
  }

  String _getStatusDisplayText() {
    final s = lead.status.toLowerCase().trim();
    if (s == 'approved' || s == 'converted' || s == 'completed') {
      return 'COMPLETED';
    }
    if (s == 'follow_up' || s == 'followup') {
      return 'FOLLOW UP';
    }
    if (s == 'new') {
      return 'NEW';
    }
    return lead.status.toUpperCase();
  }

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

  void _openMaps(double? lat, double? lng, String address) async {
    if (lat != null && lng != null) {
      final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (lead.googleMapsUrl.isNotEmpty) {
      final uri = Uri.parse(lead.googleMapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd MMM, yyyy').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatted = _formatDate(lead.createdAt);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Ashram Name & Status Badge & Sync Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lead.name.trim().toLowerCase() == 'ashram name'
                            ? 'Stays'
                            : lead.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (lead.city.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                lead.district.isNotEmpty &&
                                        lead.district != lead.city
                                    ? '${lead.city}, ${lead.district}'
                                    : '${lead.city}, ${lead.state}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusBg(),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getStatusBorder()),
                  ),
                  child: Text(
                    _getStatusDisplayText(),
                    style: TextStyle(
                      color: _getStatusText(),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                // Sync status indicator
                if (!lead.isSynced) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.warningBorder),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 12,
                          color: AppColors.warning,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Offline',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Middle Info: Owner contact & Inventory
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contact Person',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lead.ownerName.isNotEmpty
                              ? lead.ownerName
                              : 'Not specified',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (lead.phone.isNotEmpty)
                          Text(
                            lead.phone,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (lead.totalRooms != null) ...[
                    Container(height: 28, width: 1, color: AppColors.border),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Inventory',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${lead.totalRooms} Rooms',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (lead.roomPrice != null)
                          Text(
                            '₹${lead.roomPrice!.toStringAsFixed(0)}/night',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Bottom Actions & Date
            Row(
              children: [
                if (dateFormatted.isNotEmpty)
                  Text(
                    dateFormatted,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const Spacer(),

                // Action buttons: Phone Call, WhatsApp, Maps
                if (lead.phone.isNotEmpty) ...[
                  InkWell(
                    onTap: () => _callPhone(lead.phone),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.phone,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _openWhatsApp(lead.phone),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        size: 16,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                if (lead.lat != null || lead.googleMapsUrl.isNotEmpty) ...[
                  InkWell(
                    onTap: () => _openMaps(lead.lat, lead.lng, lead.address),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.infoLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.directions_outlined,
                        size: 16,
                        color: AppColors.info,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
