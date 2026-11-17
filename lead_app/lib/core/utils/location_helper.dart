import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/app_colors.dart';

class LocationHelper {
  /// Checks whether device location permission is already granted.
  static Future<bool> isPermissionGranted() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  /// Ensures location permission is granted.
  /// If already granted, returns true immediately without any dialog.
  /// If not granted, shows an informative popup asking the agent to allow
  /// location, then triggers the Android system permission request.
  /// Once granted, it is remembered and won't prompt again.
  static Future<bool> ensureLocationPermission({
    required BuildContext context,
    required String actionTitle,
    required String explanation,
  }) async {
    // 1. Check if permission is already granted
    final currentStatus = await Permission.location.status;
    if (currentStatus.isGranted) {
      return true;
    }

    if (!context.mounted) return false;

    // 2. If permanently denied, prompt user to open App Settings
    if (currentStatus.isPermanentlyDenied) {
      final openSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.security, color: AppColors.warning, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Location Access Required',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(
            'Location permission is permanently denied. Please enable Location in App Settings to $actionTitle.',
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
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (openSettings == true) {
        await openAppSettings();
      }
      return false;
    }

    // 3. Show clear in-app permission prompt
    final userAccepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Location Permission',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: AppColors.success,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'One-time permission required',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                explanation,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
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
            child: const Text('Allow Location'),
          ),
        ],
      ),
    );

    if (userAccepted != true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Location permission mandatory hai.'),
          ),
        );
      }
      return false;
    }

    // 4. Request native Android system permission
    final newStatus = await Permission.location.request();
    if (newStatus.isGranted) {
      return true;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Location permission is mandatory. Please grant location access.',
          ),
        ),
      );
    }
    return false;
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
  /// If not granted, asks for permission first, verifies GPS, and returns true only if allowed.
  static Future<bool> ensureLocationForLogin(BuildContext context) async {
    // 1. Ensure permission is granted (asks only if not granted)
    final permissionOk = await ensureLocationPermission(
      context: context,
      actionTitle: 'sign in',
      explanation: 'Your location is required to verify your field shift and ensure secure login.',
    );
    if (!permissionOk) return false;
    if (!context.mounted) return false;

    // 2. Ensure device GPS is turned ON
    final gpsOk = await ensureGpsEnabled(context, 'sign in');
    if (!gpsOk) return false;

    return true;
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
  /// If permission was already granted during login, it directly fetches GPS coordinates.
  /// If permission was not granted yet, prompts user first.
  /// Returns a valid [Position] if all conditions pass, or null if blocked.
  static Future<Position?> ensureLocationForCheckIn(
    BuildContext context,
  ) async {
    // 1. Ensure permission is granted (asks only if not granted)
    final permissionOk = await ensureLocationPermission(
      context: context,
      actionTitle: 'punch check-in',
      explanation: 'Your location is required to verify your field shift and record attendance.',
    );
    if (!permissionOk) return null;
    if (!context.mounted) return null;

    // 2. Ensure device GPS is turned ON
    final gpsOk = await ensureGpsEnabled(context, 'punch attendance');
    if (!gpsOk) return null;

    // 3. Acquire GPS Position
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(
              'Unable to acquire GPS fix. Please ensure you are in an open area with GPS active.',
            ),
          ),
        );
      }
      return null;
    }
  }
}
