import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config/env.dart';
import 'auth_session.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Blueprint API auth (`/v1/auth/*`) — mirrors iOS `AuthSessionManager`.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _sessionStorageKey = 'bp.auth.session';

  final _storage = const FlutterSecureStorage();
  final _sessionController = StreamController<AuthSession?>.broadcast();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {'Accept': 'application/json'},
    ),
  );

  AuthSession? _session;
  bool _bootstrapped = false;

  Stream<AuthSession?> get sessionStream => _sessionController.stream;
  AuthSession? get currentSession => _session;

  String get _apiRoot => Env.blueprintApiUrl;

  String _authPath(String segment) => '$_apiRoot/v1/auth/$segment';

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    if (!Env.isApiConfigured) {
      _emit(null);
      return;
    }
    final raw = await _storage.read(key: _sessionStorageKey);
    if (raw == null || raw.isEmpty) {
      _emit(null);
      return;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final stored = AuthSession.fromJson(json);
      if (stored.refreshToken.isEmpty) {
        _emit(null);
        return;
      }
      _session = stored;
      try {
        await refreshSession();
      } catch (_) {
        await signOut();
      }
    } catch (_) {
      await signOut();
    }
  }

  Future<void> signIn(String email, String password) async {
    final session = await _postToken(
      grantType: 'password',
      body: {'email': email.trim(), 'password': password},
    );
    await _persist(session);
  }

  Future<void> signUp(String email, String password) async {
    if (!Env.isApiConfigured) {
      throw AuthException('Blueprint API URL is not configured');
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        _authPath('signup'),
        data: {'email': email.trim(), 'password': password},
        options: Options(contentType: Headers.jsonContentType),
      );
      await _persist(AuthSession.fromJson(res.data ?? {}));
    } on DioException catch (e) {
      throw AuthException(_parseDioError(e));
    }
  }

  Future<void> requestPasswordRecovery(String email) async {
    if (!Env.isApiConfigured) {
      throw AuthException('Blueprint API URL is not configured');
    }
    try {
      await _dio.post<void>(
        _authPath('recover'),
        data: {'email': email.trim()},
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      throw AuthException(_parseDioError(e));
    }
  }

  Future<void> signOut() async {
    _session = null;
    await _storage.delete(key: _sessionStorageKey);
    _emit(null);
  }

  Future<String> accessTokenForApi() async {
    if (_session == null) throw AuthException('Not signed in');
    final expiresAt = _session!.expiresAt;
    if (expiresAt != null &&
        DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)))) {
      await refreshSession();
    }
    final token = _session?.accessToken;
    if (token == null || token.isEmpty) {
      throw AuthException('Not signed in');
    }
    return token;
  }

  Future<void> refreshSession() async {
    final refresh = _session?.refreshToken;
    if (refresh == null || refresh.isEmpty) {
      throw AuthException('No refresh token');
    }
    final session = await _postToken(
      grantType: 'refresh_token',
      body: {'refresh_token': refresh},
    );
    await _persist(session);
  }

  Future<AuthSession> _postToken({
    required String grantType,
    required Map<String, dynamic> body,
  }) async {
    if (!Env.isApiConfigured) {
      throw AuthException('Blueprint API URL is not configured');
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        _authPath('token'),
        queryParameters: {'grant_type': grantType},
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
      return AuthSession.fromJson(res.data ?? {});
    } on DioException catch (e) {
      throw AuthException(_parseDioError(e));
    }
  }

  Future<void> _persist(AuthSession session) async {
    _session = session;
    await _storage.write(
      key: _sessionStorageKey,
      value: jsonEncode(session.toJson()),
    );
    _emit(session);
  }

  void _emit(AuthSession? session) {
    if (!_sessionController.isClosed) {
      _sessionController.add(session);
    }
  }

  String _parseDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      return _parseError(data, e.response?.statusCode ?? 0);
    }
    return e.message ?? 'Auth request failed';
  }

  String _parseError(Map<String, dynamic> data, int status) {
    final message = data['message'] ?? data['error'];
    if (message is String && message.isNotEmpty) return message;
    return 'Auth failed ($status)';
  }

  @visibleForTesting
  void resetForTest() {
    _bootstrapped = false;
    _session = null;
  }
}
