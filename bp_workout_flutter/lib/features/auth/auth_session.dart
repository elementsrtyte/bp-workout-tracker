class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String?,
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    this.user,
    this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final AuthUser? user;
  final DateTime? expiresAt;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return AuthSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: expiresIn,
      user: json['user'] is Map<String, dynamic>
          ? AuthUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_in': expiresIn,
        if (user != null) 'user': {'id': user!.id, 'email': user!.email},
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      };

  AuthSession copyWith({
    String? accessToken,
    String? refreshToken,
    int? expiresIn,
    AuthUser? user,
    DateTime? expiresAt,
  }) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresIn: expiresIn ?? this.expiresIn,
      user: user ?? this.user,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
