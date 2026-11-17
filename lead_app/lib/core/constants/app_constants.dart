import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

class AppConstants {
  static const String appName = 'Tirvona Lead';
  static const String appVersion = '1.0.0';

  // Base API URL default:
  // Android emulator uses 10.0.2.2 to connect to host machine localhost:5000
  // Web / Desktop / physical devices use localhost or custom host.
  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:5000';
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:5000';
      }
    } catch (_) {}
    return 'http://localhost:5000';
  }

  static const String apiPrefix = '/api/lead-collection';

  // Storage Keys
  static const String tokenKey = 'tirvona_lead_jwt_token';
  static const String userKey = 'tirvona_lead_user_profile';
  static const String serverUrlKey = 'tirvona_lead_server_url';
  static const String offlineLeadsDb = 'tirvona_lead_local.db';

  // Status & Interests
  static const List<String> interests = [
    'Interested',
    'Follow-up Required',
    'Not Interested',
  ];

  static const List<String> meetingModes = ['Call', 'In-person'];

  static const List<String> statuses = [
    'pending',
    'approved',
    'rejected',
    'converted',
  ];

  static const List<String> defaultStates = ['Uttar Pradesh', 'Uttarakhand'];
}
