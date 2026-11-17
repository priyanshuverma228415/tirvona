import 'package:flutter/foundation.dart';

import '../../models/lead_model.dart';
import '../core/services/lead_service.dart';
import '../core/services/sync_service.dart';

class LeadProvider extends ChangeNotifier {
  final LeadService _leadService = LeadService();
  final SyncService _syncService = SyncService.instance;

  List<LeadModel> _leads = [];
  Map<String, int> _stats = {
    'total': 0,
    'pending': 0,
    'approved': 0,
    'rejected': 0,
    'appointments': 0,
  };

  bool _isLoading = false;
  bool _isSyncing = false;
  String _statusFilter = 'ALL';
  String _interestFilter = 'ALL';
  String _cityFilter = 'ALL';
  String _searchQuery = '';

  List<LeadModel> get leads => _leads;
  Map<String, int> get stats => _stats;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;

  String get statusFilter => _statusFilter;
  String get interestFilter => _interestFilter;
  String get cityFilter => _cityFilter;
  String get searchQuery => _searchQuery;

  List<String> get availableCities {
    final set = <String>{};
    for (final l in _leads) {
      if (l.city.trim().isNotEmpty) set.add(l.city.trim());
    }
    final list = set.toList();
    list.sort();
    return list;
  }

  List<LeadModel> get filteredLeads {
    return _leads.where((lead) {
      final q = _searchQuery.toLowerCase().trim();
      final matchSearch =
          q.isEmpty ||
          lead.name.toLowerCase().contains(q) ||
          lead.city.toLowerCase().contains(q) ||
          lead.ownerName.toLowerCase().contains(q) ||
          lead.phone.contains(q);

      final statusLower = lead.status.toLowerCase().trim();
      final interestLower = lead.interest.toLowerCase().trim();

      bool matchStatus;
      switch (_statusFilter) {
        case 'ALL':
          matchStatus = true;
          break;
        case 'NEW':
          // New leads: status is 'new' or pending without follow-up
          matchStatus =
              statusLower == 'new' ||
              (statusLower == 'pending' &&
                  !interestLower.contains('follow') &&
                  !lead.meetingRequested);
          break;
        case 'FOLLOW_UP':
          // Follow up: interest has follow-up, or status is follow_up, or meeting requested
          matchStatus =
              interestLower.contains('follow') ||
              statusLower == 'follow_up' ||
              statusLower == 'followup' ||
              lead.meetingRequested;
          break;
        case 'pending':
          matchStatus = statusLower == 'pending';
          break;
        case 'completed':
        case 'approved':
          matchStatus =
              statusLower == 'approved' ||
              statusLower == 'completed' ||
              statusLower == 'converted';
          break;
        default:
          matchStatus = statusLower == _statusFilter.toLowerCase();
      }

      final matchInterest =
          _interestFilter == 'ALL' || lead.interest == _interestFilter;
      final matchCity = _cityFilter == 'ALL' || lead.city == _cityFilter;

      return matchSearch && matchStatus && matchInterest && matchCity;
    }).toList();
  }

  void setStatusFilter(String val) {
    _statusFilter = val;
    notifyListeners();
  }

  void setInterestFilter(String val) {
    _interestFilter = val;
    notifyListeners();
  }

  void setCityFilter(String val) {
    _cityFilter = val;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> loadLeads() async {
    _isLoading = true;
    notifyListeners();

    try {
      final queryStatus =
          (_statusFilter == 'ALL' ||
              _statusFilter == 'NEW' ||
              _statusFilter == 'FOLLOW_UP')
          ? ''
          : (_statusFilter == 'completed' ? 'approved' : _statusFilter);
      _leads = await _leadService.fetchLeads(
        status: queryStatus,
        search: _searchQuery,
        interest: _interestFilter,
      );
      _stats = await _leadService.fetchStats();
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createLead(LeadModel lead) async {
    _isLoading = true;
    notifyListeners();

    try {
      final created = await _leadService.createLead(lead);
      _leads.insert(0, created);
      _stats = await _leadService.fetchStats();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateLead(LeadModel lead) async {
    _isLoading = true;
    notifyListeners();

    try {
      final updated = await _leadService.updateLead(lead);
      final idx = _leads.indexWhere((l) => l.id == updated.id);
      if (idx != -1) {
        _leads[idx] = updated;
      }
      _stats = await _leadService.fetchStats();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteLead(String id) async {
    _leads.removeWhere((l) => l.id == id);
    notifyListeners();
    await _leadService.deleteLead(id);
    _stats = await _leadService.fetchStats();
    notifyListeners();
  }

  Future<Map<String, int>> syncOfflineData() async {
    _isSyncing = true;
    notifyListeners();

    final result = await _syncService.syncPendingData();
    await loadLeads();

    _isSyncing = false;
    notifyListeners();
    return result;
  }
}
