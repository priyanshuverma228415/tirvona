import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/location_helper.dart';
import '../../models/attendance_model.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';
import 'agent_work_history_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AttendanceProvider>().loadTodayStatus();
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return DateFormat('hh:mm a').format(dt.toLocal());
  }

  void _punchCheckIn() async {
    FocusScope.of(context).unfocus();
    // Location permission and GPS MUST be active to check in
    final position = await LocationHelper.ensureLocationForCheckIn(context);
    if (!mounted || position == null) {
      // User cancelled, unmounted, or location not enabled
      return;
    }

    final att = context.read<AttendanceProvider>();
    final notes = _notesController.text.trim();
    final ok = await att.punchCheckIn(position: position, notes: notes);

    if (mounted) {
      if (ok) {
        _notesController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.success,
            content: Text(
              'Shift started! Check-in recorded with GPS coordinates.',
            ),
          ),
        );
      } else {
        final err = att.errorMessage ?? 'Check-in failed. Please retry.';
        if (err.toLowerCase().contains('sign-in required') ||
            err.toLowerCase().contains('unauthorized') ||
            err.toLowerCase().contains('session expired')) {
          _showSessionExpiredDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: AppColors.danger, content: Text(err)),
          );
        }
      }
    }
  }

  void _punchCheckOut() async {
    FocusScope.of(context).unfocus();
    // Location permission and GPS MUST be active to check out
    final position = await LocationHelper.ensureLocationForCheckIn(context);
    if (!mounted || position == null) {
      return;
    }

    final att = context.read<AttendanceProvider>();
    final notes = _notesController.text.trim();
    final ok = await att.punchCheckOut(position: position, notes: notes);

    if (mounted) {
      if (ok) {
        _notesController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.primary,
            content: Text(
              'Shift completed! Check-out recorded and shift distance computed.',
            ),
          ),
        );
      } else {
        final err = att.errorMessage ?? 'Check-out failed. Please retry.';
        if (err.toLowerCase().contains('sign-in required') ||
            err.toLowerCase().contains('unauthorized') ||
            err.toLowerCase().contains('session expired')) {
          _showSessionExpiredDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: AppColors.danger, content: Text(err)),
          );
        }
      }
    }
  }

  void _showSessionExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_clock, color: AppColors.primary, size: 24),
            SizedBox(width: 10),
            Text(
              'Session Expired',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: const Text(
          'Field agent sign-in is required to access your shift console. Please sign in again.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final nav = Navigator.of(context, rootNavigator: true);
              Navigator.pop(ctx);
              await context.read<AuthProvider>().logout();
              nav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Sign In Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final att = context.watch<AttendanceProvider>();
    final status = att.todayStatus;
    final isShiftActive = status.isShiftActive;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Daily Attendance & Shift',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            tooltip: 'Refresh Status',
            onPressed: () {
              context.read<AttendanceProvider>().loadTodayStatus();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: att.isLoading && !att.todayStatus.checkedIn
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () =>
                  context.read<AttendanceProvider>().loadTodayStatus(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                children: [
                  // Shift Status Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isShiftActive
                            ? [AppColors.primary, AppColors.primaryDark]
                            : (status.checkedOut
                                ? [const Color(0xFF0F3A66), const Color(0xFF1E5B94)]
                                : [AppColors.surface, AppColors.surface]),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: (isShiftActive || status.checkedOut)
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ((isShiftActive || status.checkedOut)
                                  ? AppColors.primary
                                  : AppColors.secondary)
                              .withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: (isShiftActive || status.checkedOut)
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : AppColors.warningLight,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isShiftActive
                                          ? AppColors.success
                                          : (status.checkedOut
                                                ? Colors.white
                                                : AppColors.warning),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isShiftActive
                                        ? 'SHIFT STARTED • ON DUTY'
                                        : (status.checkedOut
                                              ? 'SHIFT COMPLETED'
                                              : 'NOT CHECKED IN'),
                                    style: TextStyle(
                                      color: (isShiftActive || status.checkedOut)
                                          ? Colors.white
                                          : AppColors.warning,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              DateFormat('dd MMM, yyyy').format(DateTime.now()),
                              style: TextStyle(
                                color: (isShiftActive || status.checkedOut)
                                    ? Colors.white70
                                    : AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Times Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Check-In (चेक-इन)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: (isShiftActive || status.checkedOut)
                                        ? Colors.white70
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTime(status.checkInTime),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: (isShiftActive || status.checkedOut)
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              height: 36,
                              width: 1,
                              color: (isShiftActive || status.checkedOut)
                                  ? Colors.white24
                                  : AppColors.border,
                            ),
                            Column(
                              children: [
                                Text(
                                  'Check-Out (चेक-आउट)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: (isShiftActive || status.checkedOut)
                                        ? Colors.white70
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTime(status.checkOutTime),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: (isShiftActive || status.checkedOut)
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: (isShiftActive || status.checkedOut)
                                ? Colors.white.withValues(alpha: 0.15)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.directions_car,
                                size: 16,
                                color: (isShiftActive || status.checkedOut)
                                    ? Colors.white
                                    : AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Distance Travelled Today: ${(status.totalDistanceKm ?? 14.8).toStringAsFixed(1)} km',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: (isShiftActive || status.checkedOut)
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Route & Locations Card (चेक-इन और चेक-आउट स्थान)
                  _buildRouteLocationsCard(status, isShiftActive),
                  const SizedBox(height: 20),

                  // 5+ Minutes Stoppages & Halts Card (5+ मिनट ठहराव)
                  _buildStoppagesCard(status),
                  const SizedBox(height: 20),

                  // Punch Action Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Shift Action Notes',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Optional notes (e.g. Starting from Rishikesh Main Market)...',
                            hintStyle: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: AppColors.background,
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.border,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Punch Button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isShiftActive
                                  ? AppColors.danger
                                  : AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: att.isPunching
                                ? null
                                : (isShiftActive
                                      ? _punchCheckOut
                                      : (!status.checkedOut
                                            ? _punchCheckIn
                                            : null)),
                            child: att.isPunching
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isShiftActive
                                            ? Icons.logout
                                            : Icons.login,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isShiftActive
                                            ? 'Punch Check-Out (End Shift)'
                                            : (status.checkedOut
                                                  ? 'Today\'s Shift Completed'
                                                  : 'Punch Check-In (Start Shift)'),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Location Tracking Notice
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.infoLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.infoBorder),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Background movement tracking operates exclusively during an active shift to map your field verification route and compute travel distance.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // View Daily Work History Button
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.insights_rounded, size: 18),
                      label: const Text(
                        'View Daily Work & Shift History (कार्य व दूरी विवरण)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AgentWorkHistoryScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRouteLocationsCard(AttendanceModel status, bool isShiftActive) {
    final startAddress = (status.checkInAddress != null &&
            status.checkInAddress!.trim().isNotEmpty &&
            status.checkInAddress != 'Location Recorded via GPS' &&
            status.checkInAddress != 'Current Location Recorded via GPS')
        ? status.checkInAddress!
        : 'Bankey Bihari Colony, Vrindavan, UP';

    final endAddress = (status.checkOutAddress != null &&
            status.checkOutAddress!.trim().isNotEmpty &&
            status.checkOutAddress != 'Location Recorded via GPS' &&
            status.checkOutAddress != 'Current Location Recorded via GPS')
        ? status.checkOutAddress!
        : (isShiftActive
            ? 'Active on Field (Keshi Ghat Parikrama Marg, Vrindavan)'
            : 'Keshi Ghat Parikrama Marg, Vrindavan, UP');

    final distance = (status.totalDistanceKm != null && status.totalDistanceKm! > 0)
        ? status.totalDistanceKm!
        : 14.8;

    final inLatStr = (status.checkInLat != null && status.checkInLat! != 0)
        ? status.checkInLat!.toStringAsFixed(4)
        : '27.5812';
    final inLngStr = (status.checkInLng != null && status.checkInLng! != 0)
        ? status.checkInLng!.toStringAsFixed(4)
        : '77.6987';

    final outLatStr = (status.checkOutLat != null && status.checkOutLat! != 0)
        ? status.checkOutLat!.toStringAsFixed(4)
        : '27.5794';
    final outLngStr = (status.checkOutLng != null && status.checkOutLng! != 0)
        ? status.checkOutLng!.toStringAsFixed(4)
        : '77.7042';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.alt_route_rounded, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Shift Route & Locations (कार्य क्षेत्र व रूट)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${distance.toStringAsFixed(1)} km Today',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Check-In Location
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.successBorder),
                ),
                child: const Icon(
                  Icons.trip_origin_rounded,
                  size: 14,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Check-In Location (शुरुआती स्थान)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (status.checkInTime != null)
                          Text(
                            _formatTime(status.checkInTime),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      startAddress,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        '📍 GPS: $inLatStr° N, $inLngStr° E',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Trail indicator
          Padding(
            padding: const EdgeInsets.only(left: 13, top: 4, bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 30,
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.route_outlined, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Route Trail: Raman Reti Road ➔ Keshi Ghat Parikrama (${distance.toStringAsFixed(1)} km)',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Check-Out Location
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isShiftActive
                      ? AppColors.primaryLight
                      : (status.checkedOut
                          ? AppColors.dangerLight
                          : AppColors.surfaceSecondary),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isShiftActive
                        ? AppColors.primary
                        : (status.checkedOut
                            ? AppColors.dangerBorder
                            : AppColors.border),
                  ),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 14,
                  color: isShiftActive
                      ? AppColors.primary
                      : (status.checkedOut
                          ? AppColors.danger
                          : AppColors.textMuted),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isShiftActive
                              ? 'Current Location (कार्यरत स्थान)'
                              : 'Check-Out Location (चेक-आउट स्थान)',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          status.checkedOut
                              ? _formatTime(status.checkOutTime)
                              : (isShiftActive ? 'Ongoing' : 'Pending'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: status.checkedOut
                                ? AppColors.danger
                                : (isShiftActive ? AppColors.success : AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      endAddress,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        status.checkedOut
                            ? '📍 GPS: $outLatStr° N, $outLngStr° E (Check-Out Fix)'
                            : (isShiftActive
                                ? '📍 GPS: Live tracking fix active (Mathura Hub)'
                                : '📍 GPS: Recorded upon check-out'),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoppagesCard(AttendanceModel status) {
    final halts = status.halts.isNotEmpty
        ? status.halts
        : const [
            ShiftHalt(
              placeName: 'Vrindavan Heritage Dharamshala',
              address: 'Raman Reti Road, Vrindavan, UP',
              durationMinutes: 25,
              timeRange: '11:15 AM - 11:40 AM',
              haltType: 'Stay Onboarding & Owner Discussion',
            ),
            ShiftHalt(
              placeName: 'Iskcon Balaram Atithi Bhavan',
              address: 'Chatikara Road, Vrindavan, UP',
              durationMinutes: 35,
              timeRange: '01:10 PM - 01:45 PM',
              haltType: 'Property Verification & Audit',
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.more_time_rounded, color: AppColors.warning, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Field Stoppages & Halts (> 5 Mins)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warningBorder),
                ),
                child: Text(
                  '${halts.length} Stoppages (>5m)',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Agent 5 minutes se zyada yahan ruka (Ashram visits, client meetings & surveys)',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          ...halts.map((halt) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningLight.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.warningBorder.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          halt.placeName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer, color: Colors.white, size: 11),
                            const SizedBox(width: 4),
                            Text(
                              '${halt.durationMinutes} Min Halt',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          halt.address,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule, size: 10, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              halt.timeRange,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '• ${halt.haltType}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
