import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/lead_model.dart';
import '../constants/api_endpoints.dart';
import '../database/local_db.dart';
import '../network/api_client.dart';

class LeadService {
  final ApiClient _apiClient = ApiClient.instance;
  final LocalDatabase _localDb = LocalDatabase.instance;

  Future<List<LeadModel>> fetchLeads({
    String? status,
    String? search,
    String? interest,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (status != null && status != 'ALL' && status.isNotEmpty) {
        queryParams['status'] = status;
      }
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (interest != null && interest != 'ALL' && interest.isNotEmpty) {
        queryParams['interest'] = interest;
      }

      final response = await _apiClient.dio.get(
        ApiEndpoints.agentLeads,
        queryParameters: queryParams,
      );

      final body = response.data;
      final data = body['data'] ?? body;
      final items = data['items'] ?? data;

      if (items is List) {
        final serverLeads = items
            .map(
              (item) => LeadModel.fromApiJson(Map<String, dynamic>.from(item)),
            )
            .toList();

        // Cache server leads locally
        await _localDb.insertLeadsBatch(serverLeads);

        // Fetch any local offline leads that are not yet synced
        final unsynced = await _localDb.getUnsyncedLeads();
        final unsyncedIds = unsynced.map((e) => e.id).toSet();

        // Merge: offline unsynced on top
        final merged = [
          ...unsynced,
          ...serverLeads.where((s) => !unsyncedIds.contains(s.id)),
        ];
        return merged;
      }
    } catch (_) {
      // Offline fallback: load from local SQLite database!
      return await _localDb.getAllLeads();
    }
    return await _localDb.getAllLeads();
  }

  Future<Map<String, int>> fetchStats() async {
    try {
      final response = await _apiClient.dio.get(ApiEndpoints.agentStats);
      final body = response.data;
      final data = body['data'] ?? body;
      if (data is Map) {
        return {
          'total': (data['total'] ?? 0) as int,
          'pending': (data['pending'] ?? 0) as int,
          'approved': (data['approved'] ?? 0) as int,
          'rejected': (data['rejected'] ?? 0) as int,
          'appointments':
              (data['meetingsRequested'] ??
                      data['meetings'] ??
                      data['appointments'] ??
                      0)
                  as int,
        };
      }
    } catch (_) {}

    // Compute stats from local DB if offline
    final leads = await _localDb.getAllLeads();
    return {
      'total': leads.length,
      'pending': leads.where((l) => l.status == 'pending').length,
      'approved': leads
          .where((l) => l.status == 'approved' || l.status == 'converted')
          .length,
      'rejected': leads.where((l) => l.status == 'rejected').length,
      'appointments': leads
          .where((l) => l.meetingRequested && l.meetingTime.isNotEmpty)
          .length,
    };
  }

  Future<LeadModel> createLead(LeadModel lead) async {
    try {
      final response = await _apiClient.dio.post(
        ApiEndpoints.agentLeads,
        data: lead.toApiJson(),
      );

      final body = response.data;
      final data = body['data'] ?? body;
      final created = LeadModel.fromApiJson(Map<String, dynamic>.from(data));

      // Save to SQLite as synced
      await _localDb.insertOrUpdateLead(created.copyWith(isSynced: true));
      return created;
    } catch (e) {
      // Offline mode: save locally with isSynced: false
      final offlineLead = lead.copyWith(
        isSynced: false,
        createdAt: DateTime.now().toIso8601String(),
      );
      await _localDb.insertOrUpdateLead(offlineLead);
      return offlineLead;
    }
  }

  Future<LeadModel> updateLead(LeadModel lead) async {
    try {
      final response = await _apiClient.dio.put(
        '${ApiEndpoints.agentLeads}/${lead.id}',
        data: lead.toApiJson(),
      );

      final body = response.data;
      final data = body['data'] ?? body;
      final updated = LeadModel.fromApiJson(Map<String, dynamic>.from(data));

      await _localDb.insertOrUpdateLead(updated.copyWith(isSynced: true));
      return updated;
    } catch (_) {
      // Update local copy
      final offlineLead = lead.copyWith(isSynced: false);
      await _localDb.insertOrUpdateLead(offlineLead);
      return offlineLead;
    }
  }

  Future<void> deleteLead(String id) async {
    try {
      await _apiClient.dio.delete('${ApiEndpoints.agentLeads}/$id');
    } catch (_) {}
    await _localDb.deleteLead(id);
  }

  Future<String> uploadImage(XFile file, {bool isCamera = false}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.name),
      'source': isCamera ? 'camera' : 'picker',
    });

    final response = await _apiClient.dio.post(
      ApiEndpoints.uploads,
      data: formData,
    );

    final body = response.data;
    final data = body['data'] ?? body;
    return (data['url'] ?? data['secure_url'] ?? data).toString();
  }
}
