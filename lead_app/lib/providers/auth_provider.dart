import 'package:flutter/foundation.dart';

import '../../models/user_model.dart';
import '../core/network/api_client.dart';
import '../core/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  LeadUser? _user;
  bool _isLoading = false;
  String? _errorMessage;

  LeadUser? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> initAuth() async {
    ApiClient.instance.onSessionExpired = () {
      handleSessionExpired();
    };

    _isLoading = true;
    notifyListeners();

    try {
      final token = await _authService.getToken();
      if (token != null && token.isNotEmpty) {
        _user = await _authService.getCurrentUser();
        // Background refresh profile
        _authService.fetchProfile().then((refreshed) {
          if (refreshed != null) {
            _user = refreshed;
            notifyListeners();
          }
        });
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  void handleSessionExpired() {
    _user = null;
    _errorMessage = 'Session expired. Field agent sign-in is required.';
    notifyListeners();
  }

  Future<bool> login(String phone, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authService.login(phone, password);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String phone,
    String? email,
    required String password,
    required String state,
    required String district,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.register(
        name: name,
        phone: phone,
        email: email,
        password: password,
        state: state,
        district: district,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfile({
    required String name,
    String? email,
    String? phone,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authService.updateProfile(
        name: name,
        email: email,
        phone: phone,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    notifyListeners();
  }
}
