class ApiEndpoints {
  // Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String me = '/auth/me';

  // Leads
  static const String agentLeads = '/agent/leads';
  static const String agentStats = '/agent/leads/stats';
  static const String fieldAgents = '/agent/leads/field-agents';
  static const String uploads = '/agent/uploads';
  static const String voiceTranscribe = '/agent/voice/transcribe';

  // Attendance
  static const String checkIn = '/agent/attendance/check-in';
  static const String checkOut = '/agent/attendance/check-out';
  static const String todayAttendance = '/agent/attendance/today';
  static const String attendanceHistory = '/agent/attendance/history';

  // Tracking
  static const String trackingConsent = '/agent/tracking/consent';
  static const String trackingFixes = '/agent/tracking/fixes';
  static const String trackingPing = '/agent/tracking/fixes';
  static const String shiftTracking = '/agent/tracking/shift';
  static const String trackingToday = '/agent/tracking/today';

  // Supervisor (field_supervisor logins only)
  /// Newest stored position of every agent in the supervisor's district.
  static const String supervisorLiveTracking = '/supervisor/tracking/live';
  static String supervisorAgentTracking(String agentId) =>
      '/supervisor/agents/$agentId/tracking';
}
