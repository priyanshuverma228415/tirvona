import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/location_helper.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/lead_provider.dart';
import '../attendance/agent_work_history_screen.dart';
import '../attendance/attendance_screen.dart';
import '../leads/create_lead_screen.dart';
import '../leads/lead_detail_screen.dart';
import '../leads/widgets/lead_card.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  bool _hasShownCheckInPrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<LeadProvider>().loadLeads();
      await context.read<AttendanceProvider>().loadTodayStatus();
      LocationHelper.requestLocationPermission();

      if (mounted) {
        final att = context.read<AttendanceProvider>();
        if (!att.todayStatus.isShiftActive &&
            !att.todayStatus.checkedOut &&
            !_hasShownCheckInPrompt) {
          _hasShownCheckInPrompt = true;
          _showCheckInPromptDialog();
        }
      }
    });
  }

  void _showCheckInPromptDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.pin_drop_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Start Today\'s Shift?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: const Text(
          'You are currently Off Duty. Would you like to punch Check-In now to start recording today\'s field route and activities?',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Later / बाद में',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AttendanceScreen()),
              );
            },
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Check-In Now'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leadProvider = context.watch<LeadProvider>();
    final attendanceProvider = context.watch<AttendanceProvider>();
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;
    final isShiftActive = attendanceProvider.todayStatus.isShiftActive;

    final stats = leadProvider.stats;
    final filteredLeads = leadProvider.filteredLeads;
    final unsyncedCount = leadProvider.leads.where((l) => !l.isSynced).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            await Future.wait([
              leadProvider.loadLeads(),
              attendanceProvider.loadTodayStatus(),
            ]);
          },
          child: CustomScrollView(
            slivers: [
              // Custom Modern Header
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      // Logo
                      Image.asset(
                        'assets/images/logo.png',
                        height: 34,
                        fit: BoxFit.contain,
                      ),
                      const Spacer(),

                      // Shift Status Pill
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AttendanceScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isShiftActive
                                ? AppColors.successLight
                                : AppColors.warningLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isShiftActive
                                  ? AppColors.successBorder
                                  : AppColors.warningBorder,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: isShiftActive
                                      ? AppColors.success
                                      : AppColors.warning,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isShiftActive ? 'On Duty' : 'Off Duty',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isShiftActive
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Sync Action Button
                      IconButton(
                        icon: Badge(
                          isLabelVisible: unsyncedCount > 0,
                          label: Text('$unsyncedCount'),
                          child: leadProvider.isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                )
                              : const Icon(
                                  Icons.sync,
                                  color: AppColors.primary,
                                ),
                        ),
                        onPressed: leadProvider.isSyncing
                            ? null
                            : () async {
                                final res = await leadProvider
                                    .syncOfflineData();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppColors.success,
                                      content: Text(
                                        'Synced: ${res['leads']} leads, ${res['pings']} tracking pings',
                                      ),
                                    ),
                                  );
                                }
                              },
                        tooltip: 'Sync Offline Data',
                      ),

                      // Daily Work & Analytics
                      IconButton(
                        icon: const Icon(
                          Icons.insights_rounded,
                          color: AppColors.primary,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AgentWorkHistoryScreen(),
                            ),
                          );
                        },
                        tooltip: 'Daily Work & Activity History',
                      ),

                      // Profile Avatar
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: AppColors.primaryLight,
                          child: Text(
                            (user?.name.isNotEmpty == true
                                    ? user!.name[0]
                                    : 'A')
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Title and Subtitle
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Namaste, ${user?.name ?? 'Agent'}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Stay Onboarding Field Console',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Shift Attendance & Check-In Banner (Top Priority)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          !isShiftActive &&
                              !attendanceProvider.todayStatus.checkedOut
                          ? AppColors.warningLight.withValues(alpha: 0.35)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color:
                            !isShiftActive &&
                                !attendanceProvider.todayStatus.checkedOut
                            ? AppColors.warningBorder
                            : AppColors.border,
                        width:
                            !isShiftActive &&
                                !attendanceProvider.todayStatus.checkedOut
                            ? 1.5
                            : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isShiftActive
                                    ? AppColors.successLight
                                    : (attendanceProvider.todayStatus.checkedOut
                                          ? AppColors.surfaceSecondary
                                          : AppColors.warningLight),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isShiftActive
                                    ? Icons.timer
                                    : (attendanceProvider.todayStatus.checkedOut
                                          ? Icons.check_circle_outline
                                          : Icons.login_rounded),
                                color: isShiftActive
                                    ? AppColors.success
                                    : (attendanceProvider.todayStatus.checkedOut
                                          ? AppColors.textSecondary
                                          : AppColors.warning),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isShiftActive
                                        ? 'Shift Started • On Duty'
                                        : (attendanceProvider
                                                  .todayStatus
                                                  .checkedOut
                                              ? 'Today\'s Shift Completed'
                                              : 'Shift Not Started • Check-In'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color:
                                          !isShiftActive &&
                                              !attendanceProvider
                                                  .todayStatus
                                                  .checkedOut
                                          ? AppColors.warning
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isShiftActive
                                        ? 'Shift is active • Tap Check-Out to end shift'
                                        : (attendanceProvider
                                                  .todayStatus
                                                  .checkedOut
                                              ? 'Daily route distance recorded'
                                              : 'Punch Check-In to start your field shift'),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isShiftActive
                                    ? AppColors.danger
                                    : (attendanceProvider.todayStatus.checkedOut
                                          ? AppColors.surfaceSecondary
                                          : AppColors.primary),
                                foregroundColor:
                                    attendanceProvider.todayStatus.checkedOut
                                    ? AppColors.textSecondary
                                    : Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AttendanceScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                isShiftActive
                                    ? 'Check-Out'
                                    : (attendanceProvider.todayStatus.checkedOut
                                          ? 'Summary'
                                          : 'Punch In'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isShiftActive || attendanceProvider.todayStatus.checkedOut) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.route_outlined, size: 14, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Today: ${(attendanceProvider.todayStatus.totalDistanceKm ?? 14.8).toStringAsFixed(1)} km • ${attendanceProvider.todayStatus.checkInAddress ?? 'Bankey Bihari Colony'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.only(top: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: AppColors.borderLight),
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const AgentWorkHistoryScreen(),
                                ),
                              );
                            },
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: 15,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'View Daily Work & Shift History (दैनिक कार्य व किलोमीटर)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 11,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Metrics Row (4 Cards)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      _buildMetricCard(
                        'Total Leads',
                        '${stats['total'] ?? 0}',
                        AppColors.primary,
                        AppColors.primaryLight,
                      ),
                      const SizedBox(width: 8),
                      _buildMetricCard(
                        'Pending',
                        '${stats['pending'] ?? 0}',
                        AppColors.accent,
                        AppColors.accentLight,
                      ),
                      const SizedBox(width: 8),
                      _buildMetricCard(
                        'Completed',
                        '${(stats['approved'] ?? 0) + (stats['converted'] ?? 0) + (stats['completed'] ?? 0)}',
                        AppColors.success,
                        AppColors.successLight,
                      ),
                      const SizedBox(width: 8),
                      _buildMetricCard(
                        'Meetings',
                        '${stats['appointments'] ?? 0}',
                        AppColors.info,
                        AppColors.infoLight,
                      ),
                    ],
                  ),
                ),
              ),

              // Search Bar & Filter Chips
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      // Search Input
                      TextField(
                        controller: _searchController,
                        onChanged: (q) => leadProvider.setSearchQuery(q),
                        decoration: InputDecoration(
                          hintText: 'Search stay, city, or owner...',
                          hintStyle: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    leadProvider.setSearchQuery('');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Status Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              'ALL',
                              'All Leads',
                              leadProvider.statusFilter,
                              (v) => leadProvider.setStatusFilter(v),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              'NEW',
                              'New Leads',
                              leadProvider.statusFilter,
                              (v) => leadProvider.setStatusFilter(v),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              'FOLLOW_UP',
                              'Follow Up',
                              leadProvider.statusFilter,
                              (v) => leadProvider.setStatusFilter(v),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              'pending',
                              'Pending',
                              leadProvider.statusFilter,
                              (v) => leadProvider.setStatusFilter(v),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              'completed',
                              'Completed',
                              leadProvider.statusFilter,
                              (v) => leadProvider.setStatusFilter(v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Leads List
              if (leadProvider.isLoading && leadProvider.leads.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (filteredLeads.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 48,
                            color: AppColors.textMuted.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No Leads Found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Start a field visit to onboard new stays.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text(
                              'Add First Lead',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CreateLeadScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final lead = filteredLeads[index];
                      return LeadCardWidget(
                        lead: lead,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LeadDetailScreen(lead: lead),
                            ),
                          );
                        },
                        onEdit: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CreateLeadScreen(editingLead: lead),
                            ),
                          );
                        },
                        onDelete: () => leadProvider.deleteLead(lead.id),
                      );
                    }, childCount: filteredLeads.length),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text(
          'New Stay Lead',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateLeadScreen()),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String count,
    Color color,
    Color bgColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String value,
    String label,
    String currentVal,
    Function(String) onSelect,
  ) {
    final isSelected = currentVal == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelect(value),
      selectedColor: AppColors.primaryLight,
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        fontSize: 11,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.primary : AppColors.border,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
