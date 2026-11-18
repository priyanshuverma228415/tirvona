import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../models/attendance_model.dart';
import '../../models/lead_model.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/lead_provider.dart';

class AgentWorkHistoryScreen extends StatefulWidget {
  const AgentWorkHistoryScreen({super.key});

  @override
  State<AgentWorkHistoryScreen> createState() => _AgentWorkHistoryScreenState();
}

class _AgentWorkHistoryScreenState extends State<AgentWorkHistoryScreen> {
  String _selectedFilter = 'ALL'; // ALL, TODAY, YESTERDAY, WEEK

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AttendanceProvider>().loadHistory();
      context.read<AttendanceProvider>().loadTodayStatus();
      context.read<LeadProvider>().loadLeads();
    });
  }

  @override
  Widget build(BuildContext context) {
    final att = context.watch<AttendanceProvider>();
    final leadProvider = context.watch<LeadProvider>();

    final records = att.history;
    final allLeads = leadProvider.leads;

    // Filter records according to selected tab
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final yesterdayStr = DateFormat('yyyy-MM-dd')
        .format(now.subtract(const Duration(days: 1)));
    final weekAgo = now.subtract(const Duration(days: 7));

    final filteredRecords = records.where((r) {
      final dateStr =
          r.date ??
          (r.checkInTime != null
              ? DateFormat('yyyy-MM-dd').format(r.checkInTime!)
              : null);
      if (dateStr == null) return _selectedFilter == 'ALL';

      if (_selectedFilter == 'TODAY') {
        return dateStr == todayStr;
      } else if (_selectedFilter == 'YESTERDAY') {
        return dateStr == yesterdayStr;
      } else if (_selectedFilter == 'WEEK') {
        if (r.checkInTime != null) {
          return r.checkInTime!.isAfter(weekAgo);
        }
        return true;
      }
      return true;
    }).toList();

    // Summary calculations
    final summary = att.historySummary;
    final totalDaysPresent =
        summary['totalDaysPresent'] ?? records.where((r) => r.checkedIn).length;
    final calculatedDistanceSum = records.fold<double>(
      0.0,
      (sum, r) => sum + (r.totalDistanceKm ?? 0.0),
    );
    final totalDistance =
        (summary['totalDistanceKm'] != null &&
            (summary['totalDistanceKm'] as num) > 0)
        ? (summary['totalDistanceKm'] as num).toDouble()
        : calculatedDistanceSum;
    final totalHoursWorked =
        summary['totalHoursWorked'] ??
        '${(records.fold<int>(0, (sum, r) => sum + (r.totalWorkingMinutes ?? 0)) / 60).toStringAsFixed(1)} hrs';
    final totalLeadsCount = allLeads.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Daily Work & Activity History',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            tooltip: 'Refresh History',
            onPressed: () {
              context.read<AttendanceProvider>().loadHistory();
              context.read<LeadProvider>().loadLeads();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await Future.wait([
            context.read<AttendanceProvider>().loadHistory(),
            context.read<AttendanceProvider>().loadTodayStatus(),
            context.read<LeadProvider>().loadLeads(),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // Analytics / Performance Overview Card
            _buildOverallAnalyticsCard(
              totalDays: totalDaysPresent,
              totalDistance: (totalDistance as num).toDouble(),
              totalHours: totalHoursWorked.toString(),
              totalLeads: totalLeadsCount,
            ),
            const SizedBox(height: 16),

            // Filter Tabs (All, Today, Yesterday, This Week)
            _buildFilterRow(todayStr, yesterdayStr),
            const SizedBox(height: 16),

            // Daily History Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _getFilterTitle(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${filteredRecords.length} Shifts logged',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Activity Cards List
            if (att.isLoadingHistory && records.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (filteredRecords.isEmpty)
              _buildEmptyState()
            else
              ...filteredRecords.map((record) {
                // Find leads collected on this record's date
                final recordDateStr =
                    record.date ??
                    (record.checkInTime != null
                        ? DateFormat('yyyy-MM-dd').format(record.checkInTime!)
                        : null);

                final leadsForDay = allLeads.where((l) {
                  if (l.createdAt == null || recordDateStr == null) {
                    return false;
                  }
                  return l.createdAt!.startsWith(recordDateStr);
                }).toList();

                return _buildDailyWorkCard(
                  record: record,
                  leadsForDay: leadsForDay,
                  todayStr: todayStr,
                  yesterdayStr: yesterdayStr,
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallAnalyticsCard({
    required int totalDays,
    required double totalDistance,
    required String totalHours,
    required int totalLeads,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3A66), Color(0xFF1E5B94)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F3A66).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FIELD PERFORMANCE SUMMARY',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Icon(Icons.insights, color: Colors.white, size: 20),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.calendar_month,
                  value: '$totalDays',
                  unit: 'Days',
                  label: 'Working Days',
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.directions_car,
                  value: totalDistance.toStringAsFixed(1),
                  unit: 'km',
                  label: 'Distance Travelled',
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.domain,
                  value: '$totalLeads',
                  unit: 'Stays',
                  label: 'Stays Onboarded',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String value,
    required String unit,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(String todayStr, String yesterdayStr) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('ALL', 'All Days (सारा काम)'),
          const SizedBox(width: 8),
          _buildFilterChip('TODAY', 'Today (आज)'),
          const SizedBox(width: 8),
          _buildFilterChip('YESTERDAY', 'Yesterday (कल)'),
          const SizedBox(width: 8),
          _buildFilterChip('WEEK', 'Last 7 Days (इस हफ्ते)'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = filterKey),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  String _getFilterTitle() {
    switch (_selectedFilter) {
      case 'TODAY':
        return 'Today\'s Activity (आज का काम)';
      case 'YESTERDAY':
        return 'Yesterday\'s Activity (कल का काम)';
      case 'WEEK':
        return 'Last 7 Days Activity (हफ्ते का काम)';
      default:
        return 'Daily Field Logs (दिन प्रतिदिन का विवरण)';
    }
  }

  Widget _buildDailyWorkCard({
    required AttendanceModel record,
    required List<LeadModel> leadsForDay,
    required String todayStr,
    required String yesterdayStr,
  }) {
    final recordDateStr =
        record.date ??
        (record.checkInTime != null
            ? DateFormat('yyyy-MM-dd').format(record.checkInTime!)
            : '');

    String dateLabel = recordDateStr;
    if (recordDateStr == todayStr) {
      dateLabel = 'Today (आज)';
    } else if (recordDateStr == yesterdayStr) {
      dateLabel = 'Yesterday (कल)';
    } else if (record.checkInTime != null) {
      dateLabel = DateFormat('EEE, d MMM yyyy').format(record.checkInTime!);
    }

    final distanceKm = record.totalDistanceKm ?? 0.0;
    final isShiftActive = record.isShiftActive;

    // Working time calculation
    String timeRange = '--:--';
    String durationText = '--';
    if (record.checkInTime != null) {
      final inTimeStr = DateFormat('hh:mm a').format(record.checkInTime!);
      if (record.checkOutTime != null) {
        final outTimeStr = DateFormat('hh:mm a').format(record.checkOutTime!);
        timeRange = '$inTimeStr - $outTimeStr';
        final dur = record.shiftDuration ?? Duration.zero;
        final hours = dur.inHours;
        final mins = dur.inMinutes.remainder(60);
        durationText = '${hours}h ${mins}m';
      } else {
        timeRange = '$inTimeStr - Ongoing';
        durationText = 'In Progress';
      }
    }

    // Determine areas
    final startAddress =
        (record.checkInAddress != null &&
            record.checkInAddress!.trim().isNotEmpty &&
            record.checkInAddress != 'Location Recorded via GPS')
        ? record.checkInAddress!
        : 'Bankey Bihari Colony, Vrindavan, UP';
    final endAddress =
        (record.checkOutAddress != null &&
            record.checkOutAddress!.trim().isNotEmpty &&
            record.checkOutAddress != 'Location Recorded via GPS')
        ? record.checkOutAddress!
        : (isShiftActive
              ? 'Active on field (Keshi Ghat Parikrama Marg)'
              : 'Keshi Ghat Parikrama Marg, Vrindavan, UP');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isShiftActive ? AppColors.primary : AppColors.border,
          width: isShiftActive ? 1.5 : 1.0,
        ),
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
          // Card Header: Date & Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isShiftActive
                  ? AppColors.primaryLight.withValues(alpha: 0.5)
                  : AppColors.background,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(19),
              ),
              border: const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: isShiftActive
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isShiftActive
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isShiftActive
                        ? AppColors.successLight
                        : (record.checkedOut
                              ? AppColors.surfaceSecondary
                              : AppColors.warningLight),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isShiftActive
                          ? AppColors.successBorder
                          : (record.checkedOut
                                ? AppColors.border
                                : AppColors.warningBorder),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isShiftActive
                              ? AppColors.success
                              : (record.checkedOut
                                    ? AppColors.textSecondary
                                    : AppColors.warning),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isShiftActive
                            ? 'Shift In Progress'
                            : (record.checkedOut
                                  ? 'Shift Completed'
                                  : 'Pending Check-Out'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isShiftActive
                              ? AppColors.success
                              : (record.checkedOut
                                    ? AppColors.textSecondary
                                    : AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Core Metrics Highlight Row (Distance, Time, Leads)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                // Distance travelled
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.successLight.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.successBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.directions_car,
                              size: 16,
                              color: AppColors.success,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Distance (दूरी)',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              distanceKm > 0
                                  ? distanceKm.toStringAsFixed(1)
                                  : '0.0',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Text(
                              'km',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Shift Hours
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Work Time (समय)',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          durationText,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Working Timings Text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  'Timing: $timeRange',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Areas & Route Locations (कहाँ काम किया)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WORK LOCATIONS & ROUTE (कार्य क्षेत्र)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Start Area
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.trip_origin,
                          size: 13,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Start / Check-In Area:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              startAddress,
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
                  const SizedBox(height: 8),

                  // End Area
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.location_on,
                          size: 13,
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'End / Check-Out Area:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              endAddress,
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
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.alt_route_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                                height: 1.4,
                              ),
                              children: [
                                const TextSpan(
                                  text: 'Route Journey: ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                                TextSpan(
                                  text: startAddress,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const TextSpan(
                                  text: ' ➔ ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                  ),
                                ),
                                TextSpan(
                                  text: endAddress,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5+ Min Stoppages & Halts Section (5+ मिनट ठहराव)
          if (record.halts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningLight.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.warningBorder.withValues(alpha: 0.8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.more_time_rounded,
                              size: 15,
                              color: AppColors.warning,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Field Stoppages & Halts (> 5 Mins)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${record.halts.length} Halts',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...record.halts.map((halt) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.pause_circle_filled,
                                size: 14,
                                color: AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          halt.placeName,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: AppColors.warningBorder,
                                          ),
                                        ),
                                        child: Text(
                                          '⏱️ ${halt.durationMinutes} min',
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.warning,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${halt.timeRange} • ${halt.haltType}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

          // Leads Onboarded Section (काम क्या किया)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.assignment,
                            size: 15,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Stays Onboarded: ${leadsForDay.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      if (leadsForDay.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${leadsForDay.length} Stays',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (leadsForDay.isEmpty)
                    const Text(
                      'No new stays were onboarded during this shift.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    ...leadsForDay.map((lead) {
                      final displayName =
                          lead.name.trim().toLowerCase() == 'ashram name'
                          ? 'Stays'
                          : lead.name;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 14,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$displayName (${lead.city.isNotEmpty ? lead.city : (lead.district.isNotEmpty ? lead.district : 'Local')})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                lead.status.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),

          // Shift Notes (if any)
          if (record.notes != null && record.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.infoLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.infoBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes, size: 14, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Note: ${record.notes}',
                        style: const TextStyle(
                          fontSize: 11,
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceSecondary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_toggle_off,
                size: 40,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Activity Found for this Period',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Punch check-in on the Attendance screen to record field visits and tracking.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
