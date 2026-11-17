class LeadUser {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String role;
  final String status;
  final String? region;
  final String? city;
  final String? state;
  final String? district;
  final String? employeeCode;
  final bool trackingConsent;
  final String? deviceLabel;

  LeadUser({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    this.status = 'active',
    this.region,
    this.city,
    this.state,
    this.district,
    this.employeeCode,
    this.trackingConsent = false,
    this.deviceLabel,
  });

  factory LeadUser.fromJson(Map<String, dynamic> json) {
    final consent = json['trackingConsent'];
    bool hasConsent = false;
    String? devLabel;
    if (consent is Map) {
      hasConsent = consent['granted'] == true;
      devLabel = consent['deviceLabel']?.toString();
    } else if (consent is bool) {
      hasConsent = consent;
    }

    final String? assignedRegion = json['region']?.toString();
    final String? assignedDistrict = json['district']?.toString();
    final String? assignedState = json['state']?.toString();

    // Determine city from explicit field, or parse from region (e.g. "Mathura, Uttar Pradesh" -> "Mathura"), or fallback to district
    String? assignedCity = json['city']?.toString();
    if (assignedCity == null || assignedCity.trim().isEmpty) {
      if (assignedRegion != null && assignedRegion.trim().isNotEmpty) {
        assignedCity = assignedRegion.split(',').first.trim();
      } else if (assignedDistrict != null &&
          assignedDistrict.trim().isNotEmpty) {
        assignedCity = assignedDistrict.trim();
      }
    }

    return LeadUser(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      email: json['email']?.toString(),
      role: (json['role'] ?? 'field_agent').toString(),
      status: (json['status'] ?? 'active').toString(),
      region: assignedRegion,
      city: assignedCity,
      state: assignedState,
      district: assignedDistrict,
      employeeCode: json['employeeCode']?.toString(),
      trackingConsent: hasConsent,
      deviceLabel: devLabel,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'status': status,
      'region': region,
      'city': city,
      'state': state,
      'district': district,
      'employeeCode': employeeCode,
      'trackingConsent': {
        'granted': trackingConsent,
        'deviceLabel': deviceLabel,
      },
    };
  }
}
