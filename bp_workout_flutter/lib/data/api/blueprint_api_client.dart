import 'package:dio/dio.dart';

import '../../core/config/env.dart';

class BlueprintApiClient {
  BlueprintApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: Env.blueprintApiUrl,
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
                headers: const {
                  'Accept': 'application/json',
                },
              ),
            );

  final Dio _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    String? bearerToken,
  }) async {
    final headers = <String, dynamic>{};
    if (bearerToken != null && bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }
    return _dio.get<T>(
      path,
      queryParameters: query,
      options: Options(headers: headers),
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? body,
    String? bearerToken,
  }) async {
    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
    };
    if (bearerToken != null && bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }
    return _dio.post<T>(
      path,
      data: body,
      options: Options(headers: headers),
    );
  }
}
