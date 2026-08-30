import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Excel/CSV integration for the Flutter field app.
///
/// Files are selected on-device with file_picker and uploaded as multipart
/// data to the Laravel API. The server remains responsible for parsing XLSX,
/// XLS and CSV, so the Flutter app does not need an Excel parser package.
class ExcelService {
  static const String _baseUrl = ApiService.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await ApiService.getToken();
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<String?> _campId() async {
    final user = await ApiService.getUserData();
    final value = user?['camp_id'];
    if (value == null || value.toString().trim().isEmpty) return null;
    return value.toString();
  }

  /// Upload an Excel/CSV file and ask Laravel for a preview + auto mapping.
  static Future<Map<String, dynamic>?> importPreview(
    List<int> bytes,
    String fileName,
  ) async {
    final campId = await _campId();
    if (campId == null) {
      return {'error': 'لا يوجد مخيم مرتبط بحساب المستخدم'};
    }
    if (bytes.isEmpty) {
      return {'error': 'الملف فارغ'};
    }

    final uri = Uri.parse(
      '$_baseUrl/camps/$campId/guardians/import/preview',
    );

    try {
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _headers());
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );

      final streamed = await request.send().timeout(
        const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamed);
      final body = _decodeJson(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (body is Map<String, dynamic>) return body;
        return {'error': 'استجابة غير صحيحة من الخادم'};
      }

      return {
        'error': _serverMessage(body, response.statusCode),
      };
    } catch (e) {
      return {'error': 'تعذر رفع ملف Excel: $e'};
    }
  }

  /// Execute the mapping returned/edited by the user.
  static Future<Map<String, dynamic>> importExecute(
    Map<String, String?> mapping,
    List<dynamic> rows,
  ) async {
    final campId = await _campId();
    if (campId == null) {
      return {'success': false, 'message': 'لا يوجد مخيم مرتبط بحساب المستخدم'};
    }

    final cleanMapping = <String, String>{};
    for (final entry in mapping.entries) {
      final value = entry.value;
      if (value != null && value.isNotEmpty) {
        cleanMapping[entry.key] = value;
      }
    }

    final uri = Uri.parse(
      '$_baseUrl/camps/$campId/guardians/import/execute',
    );

    try {
      final headers = await _headers();
      headers['Content-Type'] = 'application/json';

      final response = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'mapping': cleanMapping,
              'rows': rows,
            }),
          )
          .timeout(const Duration(seconds: 60));

      final body = _decodeJson(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = body is Map<String, dynamic>
            ? Map<String, dynamic>.from(body)
            : <String, dynamic>{};
        data['success'] = true;
        return data;
      }

      return {
        'success': false,
        'message': _serverMessage(body, response.statusCode),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'تعذر تنفيذ استيراد الملف: $e',
      };
    }
  }

  static dynamic _decodeJson(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(body);
    } catch (_) {
      return <String, dynamic>{'message': body};
    }
  }

  static String _serverMessage(dynamic body, int statusCode) {
    if (body is Map) {
      final message = body['message'] ?? body['error'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }

      final errors = body['errors'];
      if (errors is Map) {
        final messages = <String>[];
        for (final value in errors.values) {
          if (value is List) {
            messages.addAll(value.map((e) => e.toString()));
          } else {
            messages.add(value.toString());
          }
        }
        if (messages.isNotEmpty) return messages.join('\n');
      }
    }
    return 'فشل الطلب من الخادم (HTTP $statusCode)';
  }
}
