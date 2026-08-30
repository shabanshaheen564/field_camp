// api_service.dart
// خدمة الـ API - تتعامل مع Laravel مباشرة عبر HTTP
//
// ============================================================
// تحديث: دعم العمل بدون إنترنت (Offline Mode)
// ============================================================
// الفكرة العامة:
// 1) كل دالة "قراءة" (get...) بتحاول تجيب البيانات من السيرفر،
//    ولو فشل الاتصال (ما في نت / تايم اوت) بترجع آخر نسخة محفوظة
//    محلياً بدل ما ترجع فاضية.
// 2) كل دالة "كتابة" (add../update../delete..) بتحاول ترفع
//    للسيرفر مباشرة، ولو فشل الاتصال بتخزن العملية محلياً بطابور
//    اسمه pending_actions، وبترجع "نجاح" وهمي عشان واجهة المستخدم
//    تكمل عملها عادي (تقفل الفورم، ترجع للشاشة السابقة...).
// 3) لما يرجع النت، بتنادي syncPendingActions() (بنستدعيها من
//    home.dart عند فتح التطبيق) وهي بترفع كل العمليات المتراكمة.
//
// كل هاد بدون أي مكتبة جديدة - بس SharedPreferences الموجودة أصلاً.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // ============================================================
  // ⚠️ غيّر هذا العنوان لعنوان Laravel عندك
  // ============================================================
  static const String baseUrl = 'https://camp-management-qrvx.onrender.com/api';

  // أقصى مدة ننتظرها للرد قبل ما نعتبر إنه "ما في نت"
  // (لو السيرفر بطيء لأنه استضافة مجانية، ممكن تكبرها شوي مثلاً 10 ثواني)
  static const Duration _timeout = Duration(seconds: 6);

  // ============================================================
  // مفاتيح التخزين المحلي (كاش القراءة + طابور الكتابة)
  // ============================================================
  static const String _kCacheCamp = 'cache_camp';
  static const String _kCacheGuardians = 'cache_guardians';
  static const String _kCacheStats = 'cache_stats';
  static const String _kPendingActions = 'pending_actions';

  // ============================================================
  // إدارة التوكن (بدون تغيير)
  // ============================================================
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<void> saveUserData(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('user_data');
    if (str == null) return null;
    return jsonDecode(str);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
    // ملاحظة: ما بنمسح الكاش ولا الطابور عند تسجيل الخروج،
    // عشان لو كان في عمليات ما زالت معلّقة ما تضيع.
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ============================================================
  // Headers المشتركة
  // ============================================================
  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ============================================================
  // دوال مساعدة عامة: تخزين واسترجاع أي بيانات كـ JSON نصي
  // ============================================================

  // يخزن أي Map أو List تحت مفتاح معيّن
  static Future<void> _saveCache(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  // يرجع البيانات المخزنة تحت مفتاح معيّن، أو null لو ما في شي محفوظ
  static Future<dynamic> _loadCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(key);
    if (str == null) return null;
    try {
      return jsonDecode(str);
    } catch (_) {
      return null;
    }
  }

  // يولّد معرّف مؤقت للسجلات اللي بتتعمل وهي أوفلاين
  // (كل معرّف مؤقت يبدأ بـ local_ عشان نميزه عن id السيرفر الحقيقي)
  static String _generateTempId() {
    return 'local_${DateTime.now().millisecondsSinceEpoch}';
  }

  // يتحقق: هل هاد الـ id مؤقت (لسا ما انرفع عالسيرفر) ولا id حقيقي؟
  static bool _isTempId(dynamic id) {
    return id is String && id.startsWith('local_');
  }

  static Future<List<Map<String, dynamic>>> _loadCachedGuardians() async {
    final data = await _loadCache(_kCacheGuardians);
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(data);
  }

  // ============================================================
  // طابور الإجراءات المعلّقة (Pending Actions Queue)
  // أي عملية كتابة فشلت بسبب انقطاع النت بتتخزن هون كسجل صغير،
  // وبترتفع لاحقاً لما تنادي syncPendingActions()
  // ============================================================

  static Future<List<Map<String, dynamic>>> _loadPendingActions() async {
    final data = await _loadCache(_kPendingActions);
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<void> _savePendingActions(List<Map<String, dynamic>> actions) async {
    await _saveCache(_kPendingActions, actions);
  }

  static Future<void> _addPendingAction(Map<String, dynamic> action) async {
    final actions = await _loadPendingActions();
    actions.add(action);
    await _savePendingActions(actions);
  }

  // تقدر تنادي هاي الدالة من أي شاشة لتعرف كم عملية لسا معلّقة
  // (مفيدة لو بدك تعرض للمستخدم مثلاً "3 عمليات بانتظار الرفع")
  static Future<int> getPendingActionsCount() async {
    final actions = await _loadPendingActions();
    return actions.length;
  }

  // ============================================================
  // تسجيل الدخول
  // POST /api/login
  // (تسجيل الدخول لازم إنترنت أصلاً، ما في داعي نخزنه أوفلاين)
  // ============================================================
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/login'),
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      await saveToken(data['token']);
      await saveUserData(data['user']);
      return {'success': true, 'user': data['user']};
    } else {
      return {'success': false, 'message': data['message'] ?? 'خطأ في تسجيل الدخول'};
    }
  }

  // ============================================================
  // تسجيل الخروج
  // POST /api/logout
  // ============================================================
  static Future<void> logout() async {
    try {
      final headers = await _headers();
      await http.post(Uri.parse('$baseUrl/logout'), headers: headers).timeout(_timeout);
    } catch (_) {
      // حتى لو ما قدرنا نوصل للسيرفر، لازم نسجل خروج محلياً بأي حال
    }
    await clearSession();
  }

  // ============================================================
  // جلب بيانات المخيم الخاص باليوزر
  // GET /api/camps/{camp_id}
  // ============================================================
  static Future<Map<String, dynamic>?> getMyCamp() async {
    final user = await getUserData();
    if (user == null || user['camp_id'] == null) return null;

    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$baseUrl/camps/${user['camp_id']}'), headers: headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // نجح الطلب -> خزّن آخر نسخة صحيحة بالكاش
        await _saveCache(_kCacheCamp, data);
        return data;
      }
      // السيرفر رد بس فيه خطأ (مش مشكلة اتصال) -> جرب الكاش
      final cached = await _loadCache(_kCacheCamp);
      return cached != null ? Map<String, dynamic>.from(cached) : null;
    } catch (e) {
      // ما في نت أو انتهت مهلة الاتصال -> رجّع آخر نسخة محفوظة بالجهاز
      final cached = await _loadCache(_kCacheCamp);
      return cached != null ? Map<String, dynamic>.from(cached) : null;
    }
  }

  // ============================================================
  // جلب العائلات (الـ Guardians) في مخيم اليوزر
  // GET /api/camps/{camp_id}/guardians
  // ============================================================
  static Future<List<Map<String, dynamic>>> getGuardians() async {
    final user = await getUserData();
    if (user == null || user['camp_id'] == null) return [];

    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$baseUrl/camps/${user['camp_id']}/guardians'), headers: headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> freshList;
        if (data is List) {
          freshList = List<Map<String, dynamic>>.from(data);
        } else if (data['data'] != null) {
          freshList = List<Map<String, dynamic>>.from(data['data']);
        } else {
          freshList = [];
        }

        // مهم جداً: لا نستبدل الكاش بالكامل بدون تفكير!
        // لازم نحافظ على أي عائلات أضيفت محلياً وأنت أوفلاين ولسا
        // ما انرفعت للسيرفر (معلّمة _pending_sync)، وإلا بتختفي من
        // الشاشة رغم إنها لسا موجودة بطابور الرفع.
        final oldCache = await _loadCachedGuardians();
        final stillPendingLocal =
            oldCache.where((g) => g['_pending_sync'] == true).toList();

        final merged = [...freshList, ...stillPendingLocal];
        await _saveCache(_kCacheGuardians, merged);

        // بما إننا وصلنا للسيرفر بنجاح معناته أكيد في نت الآن،
        // فلو في سجلات معلّقة، منحاول نرفعها بالخلفية بدون ما ننتظرها
        // (بدون await) عشان ما نأخر ظهور الشاشة للمستخدم
        if (stillPendingLocal.isNotEmpty) {
          syncPendingActions();
        }

        return merged;
      }
      return await _loadCachedGuardians();
    } catch (e) {
      // ما في نت -> رجّع آخر نسخة محفوظة (وفيها أي عائلات ضفتها وأنت أوفلاين)
      return await _loadCachedGuardians();
    }
  }

  // ============================================================
  // إضافة ربّ عائلة جديد
  // POST /api/guardians
  // ============================================================
  static Future<Map<String, dynamic>> addGuardian(Map<String, dynamic> data) async {
    final user = await getUserData();
    data['camp_id'] = user?['camp_id'];

    try {
      final headers = await _headers();
      final response = await http
          .post(Uri.parse('$baseUrl/guardians'), headers: headers, body: jsonEncode(data))
          .timeout(_timeout);

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        // نجح الرفع -> حدّث الكاش المحلي بإضافة السجل الجديد فوراً
        final guardians = await _loadCachedGuardians();
        guardians.add(Map<String, dynamic>.from(body));
        await _saveCache(_kCacheGuardians, guardians);
        return {'success': true, 'guardian': body};
      }
      return {'success': false, 'message': body['message'] ?? 'فشل الحفظ'};
    } catch (e) {
      // ما في نت -> خزّن العائلة محلياً بمعرّف مؤقت، وضيفها لطابور الرفع
      final tempId = _generateTempId();
      final localGuardian = Map<String, dynamic>.from(data);
      localGuardian['id'] = tempId;
      // علامة بسيطة تقدر تستخدمها بالواجهة لعرض أيقونة "بانتظار الرفع" مثلاً
      localGuardian['_pending_sync'] = true;

      final guardians = await _loadCachedGuardians();
      guardians.add(localGuardian);
      await _saveCache(_kCacheGuardians, guardians);

      await _addPendingAction({
        'type': 'add_guardian',
        'temp_id': tempId,
        'data': data,
      });

      // نرجع "نجاح" للواجهة عشان الفورم يقفل عادي متل ما لو نجح فعلاً
      return {'success': true, 'guardian': localGuardian, 'offline': true};
    }
  }

  // ============================================================
  // تعديل ربّ عائلة
  // PUT /api/guardians/{id}
  // ملاحظة: غيّرنا نوع id من int إلى dynamic، عشان يقبل أيضاً
  // المعرّفات المؤقتة (نص) للسجلات اللي أضيفت أوفلاين ولسا ما انرفعت
  // ============================================================
  static Future<Map<String, dynamic>> updateGuardian(dynamic id, Map<String, dynamic> data) async {
    // الحالة الخاصة: السجل نفسه لسا ما انرفع للسيرفر (id مؤقت)
    // هون ما منبعت طلب تعديل منفصل، منعدّل على بيانات إجراء
    // "الإضافة" المعلّق نفسه بالطابور
    if (_isTempId(id)) {
      final actions = await _loadPendingActions();
      final index = actions.indexWhere((a) => a['type'] == 'add_guardian' && a['temp_id'] == id);
      if (index != -1) {
        actions[index]['data'] = {...actions[index]['data'], ...data};
        await _savePendingActions(actions);
      }
      // حدّث الكاش المعروض بالواجهة فوراً
      final guardians = await _loadCachedGuardians();
      final gIndex = guardians.indexWhere((g) => g['id'] == id);
      if (gIndex != -1) {
        guardians[gIndex] = {...guardians[gIndex], ...data};
        await _saveCache(_kCacheGuardians, guardians);
      }
      return {'success': true, 'offline': true};
    }

    try {
      final headers = await _headers();
      final response = await http
          .put(Uri.parse('$baseUrl/guardians/$id'), headers: headers, body: jsonEncode(data))
          .timeout(_timeout);

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final guardians = await _loadCachedGuardians();
        final gIndex = guardians.indexWhere((g) => g['id'] == id);
        if (gIndex != -1) {
          guardians[gIndex] = {...guardians[gIndex], ...data};
          await _saveCache(_kCacheGuardians, guardians);
        }
        return {'success': true};
      }
      return {'success': false, 'message': body['message'] ?? 'فشل التعديل'};
    } catch (e) {
      // ما في نت -> خزّن التعديل بالطابور، وحدّث الكاش المحلي فوراً
      // عشان التعديل ينعكس بالواجهة حتى بدون نت
      await _addPendingAction({
        'type': 'update_guardian',
        'target_id': id,
        'data': data,
      });

      final guardians = await _loadCachedGuardians();
      final gIndex = guardians.indexWhere((g) => g['id'] == id);
      if (gIndex != -1) {
        guardians[gIndex] = {...guardians[gIndex], ...data, '_pending_sync': true};
        await _saveCache(_kCacheGuardians, guardians);
      }

      return {'success': true, 'offline': true};
    }
  }

  // ============================================================
  // حذف ربّ عائلة
  // DELETE /api/guardians/{id}
  // (id أصبح dynamic لنفس سبب updateGuardian)
  // ============================================================
  static Future<bool> deleteGuardian(dynamic id) async {
    // لو السجل لسا ما انرفع للسيرفر أصلاً (id مؤقت):
    // فقط امسحه من الكاش وألغِ إجراء الإضافة المعلّق، بدون داعي نتصل بالسيرفر
    if (_isTempId(id)) {
      final actions = await _loadPendingActions();
      actions.removeWhere((a) => a['type'] == 'add_guardian' && a['temp_id'] == id);
      await _savePendingActions(actions);

      final guardians = await _loadCachedGuardians();
      guardians.removeWhere((g) => g['id'] == id);
      await _saveCache(_kCacheGuardians, guardians);
      return true;
    }

    try {
      final headers = await _headers();
      final response = await http
          .delete(Uri.parse('$baseUrl/guardians/$id'), headers: headers)
          .timeout(_timeout);

      final ok = response.statusCode == 200 || response.statusCode == 204;
      if (ok) {
        final guardians = await _loadCachedGuardians();
        guardians.removeWhere((g) => g['id'] == id);
        await _saveCache(_kCacheGuardians, guardians);
      }
      return ok;
    } catch (e) {
      // ما في نت -> سجّل إجراء الحذف بالطابور، واحذفه من الكاش المعروض فوراً
      await _addPendingAction({'type': 'delete_guardian', 'target_id': id});

      final guardians = await _loadCachedGuardians();
      guardians.removeWhere((g) => g['id'] == id);
      await _saveCache(_kCacheGuardians, guardians);
      return true;
    }
  }

  // ============================================================
  // جلب أفراد عائلة معينة
  // GET /api/guardians/{guardian_id}/members
  // كل عائلة إلها كاش خاص فيها باسم cache_members_<guardianId>
  // ============================================================
  static Future<List<Map<String, dynamic>>> getFamilyMembers(dynamic guardianId) async {
    final cacheKey = 'cache_members_$guardianId';

    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$baseUrl/guardians/$guardianId/members'), headers: headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> freshList;
        if (data is List) {
          freshList = List<Map<String, dynamic>>.from(data);
        } else if (data['data'] != null) {
          freshList = List<Map<String, dynamic>>.from(data['data']);
        } else {
          freshList = [];
        }

        // نفس فكرة العائلات بالضبط: حافظ على الأفراد اللي أضيفوا
        // أوفلاين ولسا ما انرفعوا، بدل ما يختفوا عند الريفرش
        final oldCached = await _loadCache(cacheKey);
        final oldList = oldCached != null
            ? List<Map<String, dynamic>>.from(oldCached)
            : <Map<String, dynamic>>[];
        final stillPendingLocal =
            oldList.where((m) => m['_pending_sync'] == true).toList();

        final merged = [...freshList, ...stillPendingLocal];
        await _saveCache(cacheKey, merged);

        if (stillPendingLocal.isNotEmpty) {
          syncPendingActions();
        }

        return merged;
      }
      final cached = await _loadCache(cacheKey);
      return cached != null ? List<Map<String, dynamic>>.from(cached) : [];
    } catch (e) {
      final cached = await _loadCache(cacheKey);
      return cached != null ? List<Map<String, dynamic>>.from(cached) : [];
    }
  }

  // ============================================================
  // إضافة فرد لعائلة
  // POST /api/family-members
  // ============================================================
  static Future<Map<String, dynamic>> addFamilyMember(Map<String, dynamic> data) async {
    final guardianId = data['guardian_id'];
    final cacheKey = 'cache_members_$guardianId';

    try {
      final headers = await _headers();
      final response = await http
          .post(Uri.parse('$baseUrl/family-members'), headers: headers, body: jsonEncode(data))
          .timeout(_timeout);

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final cached = await _loadCache(cacheKey);
        final list = cached != null ? List<Map<String, dynamic>>.from(cached) : <Map<String, dynamic>>[];
        list.add(Map<String, dynamic>.from(body));
        await _saveCache(cacheKey, list);
        return {'success': true, 'member': body};
      }
      return {'success': false, 'message': body['message'] ?? 'فشل الحفظ'};
    } catch (e) {
      // ما في نت -> نفس فكرة العائلات بالضبط: خزّن الفرد محلياً وطابور
      final tempId = _generateTempId();
      final localMember = Map<String, dynamic>.from(data);
      localMember['id'] = tempId;
      localMember['_pending_sync'] = true;

      final cached = await _loadCache(cacheKey);
      final list = cached != null ? List<Map<String, dynamic>>.from(cached) : <Map<String, dynamic>>[];
      list.add(localMember);
      await _saveCache(cacheKey, list);

      await _addPendingAction({
        'type': 'add_member',
        'temp_id': tempId,
        'guardian_id': guardianId,
        'data': data,
      });

      return {'success': true, 'member': localMember, 'offline': true};
    }
  }

  // ============================================================
  // حذف فرد من العائلة
  // DELETE /api/family-members/{id}
  // ملاحظة: بما إن الدالة الأصلية ما بتاخد guardianId، بنفتش
  // بكل مفاتيح cache_members_* لحد ما نلاقي وين محفوظ الفرد
  // ============================================================
  static Future<bool> deleteFamilyMember(dynamic id) async {
    final prefs = await SharedPreferences.getInstance();
    final memberKeys = prefs.getKeys().where((k) => k.startsWith('cache_members_'));

    if (_isTempId(id)) {
      // فرد لسا ما انرفع -> امسحه من الكاش وألغِ إجراء إضافته المعلّق
      final actions = await _loadPendingActions();
      actions.removeWhere((a) => a['type'] == 'add_member' && a['temp_id'] == id);
      await _savePendingActions(actions);

      for (final key in memberKeys) {
        final data = await _loadCache(key);
        if (data == null) continue;
        final list = List<Map<String, dynamic>>.from(data);
        final before = list.length;
        list.removeWhere((m) => m['id'] == id);
        if (list.length != before) await _saveCache(key, list);
      }
      return true;
    }

    try {
      final headers = await _headers();
      final response = await http
          .delete(Uri.parse('$baseUrl/family-members/$id'), headers: headers)
          .timeout(_timeout);

      final ok = response.statusCode == 200 || response.statusCode == 204;
      if (ok) {
        for (final key in memberKeys) {
          final data = await _loadCache(key);
          if (data == null) continue;
          final list = List<Map<String, dynamic>>.from(data);
          list.removeWhere((m) => m['id'] == id);
          await _saveCache(key, list);
        }
      }
      return ok;
    } catch (e) {
      await _addPendingAction({'type': 'delete_member', 'target_id': id});

      for (final key in memberKeys) {
        final data = await _loadCache(key);
        if (data == null) continue;
        final list = List<Map<String, dynamic>>.from(data);
        list.removeWhere((m) => m['id'] == id);
        await _saveCache(key, list);
      }
      return true;
    }
  }

  // ============================================================
  // إحصائيات المخيم
  // GET /api/camps/{camp_id}/statistics
  // ============================================================
  static Future<Map<String, dynamic>> getCampStatistics() async {
    final user = await getUserData();
    if (user == null || user['camp_id'] == null) return {};

    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$baseUrl/camps/${user['camp_id']}/statistics'), headers: headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveCache(_kCacheStats, data);
        return data;
      }
      final cached = await _loadCache(_kCacheStats);
      return cached != null ? Map<String, dynamic>.from(cached) : {};
    } catch (e) {
      final cached = await _loadCache(_kCacheStats);
      return cached != null ? Map<String, dynamic>.from(cached) : {};
    }
  }

  // ============================================================
  // استيراد ملف إكسل/CSV - خطوتين زي الويب بالظبط:
  // 1) importPreview: يرفع الملف ويرجع الأعمدة + اقتراح مطابقة تلقائي
  // 2) importExecute: بعد ما المستخدم يأكّد/يعدّل المطابقة، ينفّذ فعلياً
  // ============================================================
  static Future<Map<String, dynamic>?> importPreview(
    List<int> fileBytes,
    String fileName,
  ) async {
    final user = await getUserData();
    if (user == null || user['camp_id'] == null) return null;

    try {
      final token = await getToken();
      final uri = Uri.parse('$baseUrl/camps/${user['camp_id']}/guardians/import/preview');
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        })
        ..files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      final body = jsonDecode(response.body);
      return {'error': body['message'] ?? 'فشل قراءة الملف'};
    } catch (e) {
      return {'error': 'تعذّر رفع الملف. تأكد من الاتصال بالإنترنت'};
    }
  }

  static Future<Map<String, dynamic>> importExecute(
    Map<String, String?> mapping,
    List<dynamic> rows,
  ) async {
    final user = await getUserData();
    if (user == null || user['camp_id'] == null) {
      return {'success': false, 'message': 'لا يوجد مخيم مرتبط بحسابك'};
    }

    try {
      final headers = await _headers();
      final response = await http
          .post(
            Uri.parse('$baseUrl/camps/${user['camp_id']}/guardians/import/execute'),
            headers: headers,
            body: jsonEncode({'mapping': mapping, 'rows': rows}),
          )
          .timeout(const Duration(seconds: 30));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, ...Map<String, dynamic>.from(body)};
      }
      return {'success': false, 'message': body['message'] ?? 'فشل الاستيراد'};
    } catch (e) {
      return {'success': false, 'message': 'تعذّر إتمام الاستيراد. تأكد من الاتصال بالإنترنت'};
    }
  }

  // ============================================================
  // تصدير الأفراد كملف CSV (يفتح تلقائياً على Excel وغيره).
  // GET /api/camps/{camp_id}/guardians/export
  // ============================================================
  static Future<Uint8List?> exportGuardiansExcel() async {
    final user = await getUserData();
    if (user == null || user['camp_id'] == null) return null;

    try {
      final headers = await _headers();
      final response = await http
          .get(
            Uri.parse('$baseUrl/camps/${user['camp_id']}/guardians/export'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // الإشعارات (نفس NotificationController المستخدم بالويب بالضبط)
  // GET /api/notifications  ->  {notifications: [...], unread_count: N}
  // PATCH /api/notifications/{id}/read
  // PATCH /api/notifications/read-all
  // ============================================================
  static Future<Map<String, dynamic>> getNotifications() async {
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$baseUrl/notifications'), headers: headers)
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Map<String, dynamic>.from(data);
      }
      return {'notifications': [], 'unread_count': 0};
    } catch (e) {
      return {'notifications': [], 'unread_count': 0};
    }
  }

  static Future<void> markNotificationRead(String id) async {
    try {
      final headers = await _headers();
      await http
          .patch(Uri.parse('$baseUrl/notifications/$id/read'), headers: headers)
          .timeout(_timeout);
    } catch (_) {
      // ما في نت -> تجاهل بهدوء، رح تترجع "غير مقروءة" بالمرة الجاية وما في مشكلة
    }
  }

  static Future<void> markAllNotificationsRead() async {
    try {
      final headers = await _headers();
      await http
          .patch(Uri.parse('$baseUrl/notifications/read-all'), headers: headers)
          .timeout(_timeout);
    } catch (_) {}
  }

  // ============================================================
  // مساعدات للتعرف على أخطاء "غير حقيقية" أثناء المزامنة
  // (يعني السيرفر رد برفض، بس الرفض نفسه معناه إن العملية
  // أصلاً متحققة أو ما عاد إلها معنى -> ما في داعي نعيد المحاولة للأبد)
  // ============================================================

  // مثال: حاولنا نضيف سجل عندنا نسخة محلية منه، بس هو أصلاً
  // موجود بقاعدة البيانات (رفع بمحاولة سابقة، وانقطع النت قبل
  // ما نمسحه من الطابور المحلي) -> السيرفر بيرفض بـ unique constraint
  static bool _isDuplicateKeyError(http.Response response) {
    final body = response.body.toLowerCase();
    return response.statusCode == 409 ||
        body.contains('unique constraint') ||
        body.contains('duplicate key') ||
        body.contains('duplicate entry');
  }

  // مثال: حاولنا نعدّل أو نحذف سجل، بس هو أصلاً مش موجود عالسيرفر
  // (ممكن كان تحذف من جهاز تاني، أو اتحذف بعملية سابقة نجحت
  // والطابور المحلي ما كان محدّث) -> ما في داعي نعيد المحاولة
  static bool _isNotFoundError(http.Response response) {
    return response.statusCode == 404;
  }

  // ============================================================
  // مزامنة الإجراءات المعلّقة مع السيرفر (Sync Engine)
  // بتنادى هاي الدالة لما نفترض إنه رجع النت - مثلاً عند فتح
  // شاشة home.dart، أو لما المستخدم يضغط زر تحديث بأي شاشة
  // ============================================================
  static Future<int> syncPendingActions() async {
    final actions = await _loadPendingActions();
    if (actions.isEmpty) return 0;

    final headers = await _headers();
    // قائمة للإجراءات اللي بتفشل مرة ثانية (بتضل بالطابور لحد ما ننجح)
    final List<Map<String, dynamic>> stillPending = [];
    // عداد العمليات اللي نجحت فعلاً بالرفع هالمرة (بنستخدمه بالواجهة
    // لعرض رسالة "تم الرفع بنجاح" لو كان أكبر من صفر)
    int syncedCount = 0;

    for (final action in actions) {
      try {
        switch (action['type']) {
          // ---- إضافة عائلة كانت معلّقة ----
          case 'add_guardian':
            final response = await http
                .post(Uri.parse('$baseUrl/guardians'),
                    headers: headers, body: jsonEncode(action['data']))
                .timeout(_timeout);
            if (response.statusCode == 200 || response.statusCode == 201) {
              // نجح الرفع -> استبدل الـ id المؤقت بالـ id الحقيقي بالكاش
              final body = jsonDecode(response.body);
              final guardians = await _loadCachedGuardians();
              final index = guardians.indexWhere((g) => g['id'] == action['temp_id']);
              if (index != -1) {
                guardians[index] = Map<String, dynamic>.from(body);
                await _saveCache(_kCacheGuardians, guardians);
              }
              syncedCount++;
            } else if (_isDuplicateKeyError(response)) {
              // السجل هاد أصلاً موجود بالسيرفر (رفع بمحاولة سابقة ناجحة
              // وانقطع قبل ما ينمسح من الطابور) -> امسح النسخة المحلية
              // المؤقتة، وبأول فتح لشاشة العائلات رح تنجلب النسخة
              // الصحيحة تلقائياً من السيرفر
              final guardians = await _loadCachedGuardians();
              guardians.removeWhere((g) => g['id'] == action['temp_id']);
              await _saveCache(_kCacheGuardians, guardians);
              syncedCount++;
            } else {
              stillPending.add(action);
            }
            break;

          // ---- تعديل عائلة كان معلّق ----
          case 'update_guardian':
            final response = await http
                .put(Uri.parse('$baseUrl/guardians/${action['target_id']}'),
                    headers: headers, body: jsonEncode(action['data']))
                .timeout(_timeout);
            if (response.statusCode == 200) {
              syncedCount++;
            } else if (_isNotFoundError(response) || _isDuplicateKeyError(response)) {
              // السجل المستهدف اتحذف من مكان تاني، أو التعديل بيسبب
              // تعارض مع سجل تاني -> ما في داعي نضل نحاول للأبد
              syncedCount++;
            } else {
              stillPending.add(action);
            }
            break;

          // ---- حذف عائلة كان معلّق ----
          case 'delete_guardian':
            final response = await http
                .delete(Uri.parse('$baseUrl/guardians/${action['target_id']}'), headers: headers)
                .timeout(_timeout);
            if (response.statusCode == 200 || response.statusCode == 204) {
              syncedCount++;
            } else if (_isNotFoundError(response)) {
              // أصلاً محذوف بالسيرفر (من محاولة سابقة نجحت أو من جهاز تاني)
              syncedCount++;
            } else {
              stillPending.add(action);
            }
            break;

          // ---- إضافة فرد كانت معلّقة ----
          case 'add_member':
            final response = await http
                .post(Uri.parse('$baseUrl/family-members'),
                    headers: headers, body: jsonEncode(action['data']))
                .timeout(_timeout);
            if (response.statusCode == 200 || response.statusCode == 201) {
              final body = jsonDecode(response.body);
              final cacheKey = 'cache_members_${action['guardian_id']}';
              final cached = await _loadCache(cacheKey);
              if (cached != null) {
                final list = List<Map<String, dynamic>>.from(cached);
                final index = list.indexWhere((m) => m['id'] == action['temp_id']);
                if (index != -1) {
                  list[index] = Map<String, dynamic>.from(body);
                  await _saveCache(cacheKey, list);
                }
              }
              syncedCount++;
            } else if (_isDuplicateKeyError(response)) {
              // نفس فكرة add_guardian: الفرد هاد أصلاً موجود بالسيرفر
              final cacheKey = 'cache_members_${action['guardian_id']}';
              final cached = await _loadCache(cacheKey);
              if (cached != null) {
                final list = List<Map<String, dynamic>>.from(cached);
                list.removeWhere((m) => m['id'] == action['temp_id']);
                await _saveCache(cacheKey, list);
              }
              syncedCount++;
            } else {
              stillPending.add(action);
            }
            break;

          // ---- حذف فرد كان معلّق ----
          case 'delete_member':
            final response = await http
                .delete(Uri.parse('$baseUrl/family-members/${action['target_id']}'), headers: headers)
                .timeout(_timeout);
            if (response.statusCode == 200 || response.statusCode == 204) {
              syncedCount++;
            } else if (_isNotFoundError(response)) {
              syncedCount++;
            } else {
              stillPending.add(action);
            }
            break;
        }
      } catch (e) {
        // لسا ما في نت -> خلي هاد الإجراء بالطابور وحاول مرة ثانية لاحقاً
        stillPending.add(action);
      }
    }

    // حدّث الطابور بس بالإجراءات اللي لسا فاشلة
    await _savePendingActions(stillPending);

    // ملاحظة: ما بنسحب نسخة جديدة من السيرفر هون بشكل تلقائي،
    // لأن getGuardians() و getFamilyMembers() صار عندهم منطق دمج
    // ذكي بيتعامل مع هاد الموضوع لحالهم أول ما تنفتح الشاشة المعنية.
    return syncedCount;
  }
}
