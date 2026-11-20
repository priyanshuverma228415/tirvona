import 'package:connectivity_plus/connectivity_plus.dart';

import '../constants/api_endpoints.dart';
import '../database/local_db.dart';
import '../network/api_client.dart';
import 'tracking_service.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  final LocalDatabase _localDb = LocalDatabase.instance;
  final ApiClient _apiClient = ApiClient.instance;

  bool _isSyncing = false;
  SyncService._init();

  bool get isSyncing => _isSyncing;

  Future<bool> isOnline() async {
    final connectivity = await Connectivity().checkConnectivity();
    return !connectivity.contains(ConnectivityResult.none);
  }

  Future<Map<String, int>> syncPendingData() async {
    if (_isSyncing) return {'leads': 0, 'pings': 0};
    if (!await isOnline()) return {'leads': 0, 'pings': 0};

    _isSyncing = true;
    int leadsSynced = 0;
    int pingsSynced = 0;

    try {
      // 1. Sync pending leads
      final unsyncedLeads = await _localDb.getUnsyncedLeads();
      for (final lead in unsyncedLeads) {
        try {
          final response = await _apiClient.dio.post(
            ApiEndpoints.agentLeads,
            data: lead.toApiJson(),
          );
          if (response.statusCode == 200 || response.statusCode == 201) {
            await _localDb.markLeadSynced(lead.id);
            leadsSynced++;
          }
        } catch (_) {}
      }

      // 2. Route points queued on the phone (one uploader, one format).
      pingsSynced = await TrackingService.instance.uploadPending();
    } finally {
      _isSyncing = false;
    }

    return {'leads': leadsSynced, 'pings': pingsSynced};
  }
}
