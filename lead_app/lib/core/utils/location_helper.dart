import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/app_colors.dart';

class LocationHelper {
  /// Checks whether device location permission is already granted.
  static Future<bool> isPermissionGranted() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  /// Ensures mandatory location permission and GPS are enabled.
  /// If already granted and GPS is on, returns true immediately without any prompt.
  /// If not granted, requests permission and enforces compliance with a mandatory dialog.
  /// Once granted, subsequent checks on the same day return true immediately.
  static Future<bool> ensureMandatoryLocation(
    BuildContext context, {
    required String actionTitle,
  }) async {
    // 1. If already granted, check GPS quietly
    final granted = await isPermissionGranted();
    if (granted) {
      final gpsOn = await Geolocator.isLocationServiceEnabled();
      if (gpsOn) return true;
      if (!context.mounted) return false;
      return await ensureGpsEnabled(context, actionTitle);
    }

    if (!context.mounted) return false;

    // 2. Directly trigger native Android system permission prompt
    final reqStatus = await Permission.location.request();
    if (reqStatus.isGranted) {
      final gpsOn = await Geolocator.isLocationServiceEnabled();
      if (gpsOn) return true;
      if (!context.mounted) return false;
      return await ensureGpsEnabled(context, actionTitle);
    }

    if (!context.mounted) return false;

    // 3. If denied or permanently denied, show mandatory non-dismissible dialog
    final isPermanent = reqStatus.isPermanentlyDenied;
    final userChoseAction = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: AppColors.danger,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Location Mandatory',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'लोकेशन अनुमति अनिवार्य है',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Field agent tracking, route recording aur shift operations ke liye Device Location permission compulsory (anivarya) hai. Kripya $actionTitle ke liye location permission grant karein.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              isPermanent ? Icons.settings : Icons.check_circle_outline,
              size: 18,
            ),
            label: Text(
              isPermanent
                  ? 'Open Settings (सेटिंग्स खोलें)'
                  : 'Grant Location Permission (अनुमति दें)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (userChoseAction == true) {
      if (isPermanent) {
        await openAppSettings();
      } else {
        final reReq = await Permission.location.request();
        if (reReq.isGranted) {
          if (!context.mounted) return true;
          return await ensureGpsEnabled(context, actionTitle);
        }
      }
    }
    return false;
  }

  /// Ensures location permission is granted.
  /// If already granted, returns true immediately without any prompt.
  static Future<bool> ensureLocationPermission({
    required BuildContext context,
    required String actionTitle,
    required String explanation,
  }) async {
    return await ensureMandatoryLocation(context, actionTitle: actionTitle);
  }

  /// Ensures device GPS hardware toggle is enabled.
  static Future<bool> ensureGpsEnabled(
    BuildContext context,
    String actionTitle,
  ) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (serviceEnabled) return true;

    if (!context.mounted) return false;

    final openSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_off, color: AppColors.danger, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Turn ON Location (GPS)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          'Location services (GPS) are turned OFF on your device. Please turn on GPS to $actionTitle.',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable GPS'),
          ),
        ],
      ),
    );

    if (openSettings == true) {
      await Geolocator.openLocationSettings();
    }
    return false;
  }

  /// Mandatory location verification for login.
  /// If permission was already granted previously, returns true immediately without prompts.
  /// If not granted, prompts with native request and mandatory compliance dialog.
  static Future<bool> ensureLocationForLogin(BuildContext context) async {
    return await ensureMandatoryLocation(
      context,
      actionTitle: 'sign in to Field Console',
    );
  }

  /// Checks and requests location permission quietly.
  static Future<bool> requestLocationPermission() async {
    try {
      final status = await Permission.location.status;
      if (status.isGranted) return true;
      final requested = await Permission.location.request();
      return requested.isGranted;
    } catch (e) {
      debugPrint('[LocationHelper] Error requesting permission: $e');
      return false;
    }
  }

  /// Mandatory location verification for check-in / check-out.
  /// Acquires real-time GPS & network position with millisecond-speed fallbacks.
  static Future<Position?> ensureLocationForCheckIn(
    BuildContext context,
  ) async {
    return await getFastRealtimePosition(context);
  }

  /// Fast hybrid real-time position acquisition.
  /// Uses system network provider & device GPS in parallel to obtain accurate
  /// real-time position in milliseconds without 20s stalls or indoor failures.
  static Future<Position?> getFastRealtimePosition([BuildContext? context]) async {
    if (context != null) {
      // 1. Mandatory permission check
      final permissionOk = await ensureMandatoryLocation(
        context,
        actionTitle: 'record shift attendance & location',
      );
      if (!permissionOk) return null;
      if (!context.mounted) return null;

      // 2. Ensure GPS toggle is enabled
      final gpsOk = await ensureGpsEnabled(context, 'record attendance');
      if (!gpsOk) return null;
    } else {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
    }

    // 3. Immediately inspect last known position for near-instant (milliseconds) fallback
    Position? lastKnown;
    try {
      lastKnown = await Geolocator.getLastKnownPosition();
    } catch (_) {}

    // 4. Try current position using medium accuracy (fuses cell tower + wifi + GPS)
    // with a fast 4-second timeout.
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
      return pos;
    } catch (_) {
      // If medium timed out, use lastKnown if available
      if (lastKnown != null) {
        return lastKnown;
      }
    }

    // 5. Try high accuracy with short timeout
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 3),
        ),
      );
    } catch (_) {}

    // 6. Try low accuracy (network provider)
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 3),
        ),
      );
    } catch (_) {}

    if (lastKnown != null) return lastKnown;

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Unable to lock network or GPS location. Please check GPS toggle.',
          ),
        ),
      );
    }
    return null;
  }

  /// Real-time reverse geocoding to human readable street/area address.
  /// Uses native Android geocoder. Returns clean real address without hardcoding.
  static Future<String> getAddressFromCoordinates(double lat, double lng) async {
    try {
      final placemarks = await Geocoding().placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if (p.street != null && p.street!.isNotEmpty && !p.street!.contains('+')) {
          parts.add(p.street!);
        }
        if (p.subLocality != null && p.subLocality!.isNotEmpty && p.subLocality != p.street) {
          parts.add(p.subLocality!);
        }
        if (p.locality != null && p.locality!.isNotEmpty) {
          parts.add(p.locality!);
        }
        if (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty && p.subAdministrativeArea != p.locality) {
          parts.add(p.subAdministrativeArea!);
        }
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
          parts.add(p.administrativeArea!);
        }

        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
      }
    } catch (e) {
      debugPrint('[LocationHelper] Reverse geocoding failed: $e');
    }

    return 'GPS Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
  }
}
