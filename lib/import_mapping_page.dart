// import_mapping_page.dart
// صفحة تحديد الأعمدة قبل الاستيراد - نفس فكرة صفحة الويب
// (members_import_map) بالظبط: بنعرض أعمدة الملف، اقتراح مطابقة
// تلقائي جاهز، والمستخدم يقدر يعدّل أي عمود قبل ما يأكّد الاستيراد.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';

class ImportMappingPage extends StatefulWidget {
  final List<int> fileBytes;
  final String fileName;
  const ImportMappingPage({
    super.key,
    required this.fileBytes,
    required this.fileName,
  });

  @override
  State<ImportMappingPage> createState() => _ImportMappingPageState();
}

class _ImportMappingPageState extends State<ImportMappingPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  List<String> _headers = [];
  List<dynamic> _rows = [];
  Map<String, dynamic> _dbFields = {};
  Map<String, String?> _mapping = {};
  int _totalRows = 0;
  int _newGuardiansCount = 0;

  // الحقول المطلوبة إجبارياً عشان الاستيراد يشتغل
  static const _requiredFields = ['guardian_card_id', 'name'];

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.importPreview(widget.fileBytes, widget.fileName);

    if (result == null || result['error'] != null) {
      setState(() {
        _loading = false;
        _error = result?['error'] ?? 'تعذّرت قراءة الملف';
      });
      return;
    }

    setState(() {
      _headers = List<String>.from(result['headers'] ?? []);
      _rows = result['rows'] ?? [];
      _dbFields = Map<String, dynamic>.from(result['db_fields'] ?? {});
      _mapping = Map<String, String?>.from(result['auto_mapping'] ?? {});
      _totalRows = result['total_rows'] ?? _rows.length;
      _newGuardiansCount = (result['new_guardian_card_ids'] as List?)?.length ?? 0;
      _loading = false;
    });
  }

  bool get _canSubmit =>
      _requiredFields.every((f) => _mapping[f] != null && _mapping[f]!.isNotEmpty);

  Future<void> _confirmImport() async {
    if (!_canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لازم تحدد عمود "رقم هوية رب الأسرة" و"اسم الفرد" على الأقل',
              style: GoogleFonts.cairo()),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final result = await ApiService.importExecute(_mapping, _rows);
    setState(() => _submitting = false);

    if (!mounted) return;

    final success = result['success'] == true;
    final created = result['created'] ?? 0;
    final updated = result['updated'] ?? 0;
    final errors = List<dynamic>.from(result['errors'] ?? []);

    await showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(success ? 'نتيجة الاستيراد' : 'فشل الاستيراد',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          content: success
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('✅ تم إضافة $created سجل جديد', style: GoogleFonts.cairo()),
                    Text('🔄 تم تحديث $updated سجل', style: GoogleFonts.cairo()),
                    if (errors.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('⚠️ ${errors.length} خطأ:',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      ...errors.take(5).map((e) => Text('• $e',
                          style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey[700]))),
                      if (errors.length > 5)
                        Text('... و ${errors.length - 5} أخطاء إضافية',
                            style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ],
                )
              : Text(result['message'] ?? 'حدث خطأ غير متوقع', style: GoogleFonts.cairo()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('حسناً', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    // نرجع true بس إذا فعلاً تم إضافة أو تحديث شي، عشان صفحة العائلات تعمل تحديث
    Navigator.pop(context, success && (created > 0 || updated > 0));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تحديد أعمدة الملف')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: GoogleFonts.cairo(color: const Color(0xFFEF4444)),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        color: const Color(0xFFEFF6FF),
                        child: Text(
                          'الملف يحتوي $_totalRows صف${_newGuardiansCount > 0 ? '، وسيتم إضافة $_newGuardiansCount عائلة جديدة تلقائياً إذا لم تكن موجودة' : ''}',
                          style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF1E3A5F)),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(
                              'حدد أي عمود بالملف يقابل كل حقل (تم الاقتراح تلقائياً، وتقدر تعدّله)',
                              style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey[700]),
                            ),
                            const SizedBox(height: 12),
                            ..._dbFields.entries.map((entry) {
                              final field = entry.key;
                              final label = entry.value;
                              final isRequired = _requiredFields.contains(field);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: DropdownButtonFormField<String?>(
                                  value: (_mapping[field] != null &&
                                          _headers.contains(_mapping[field]))
                                      ? _mapping[field]
                                      : null,
                                  isExpanded: true,
                                  style: GoogleFonts.cairo(
                                      color: const Color(0xFF1E293B), fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: isRequired ? '$label *' : label,
                                    labelStyle: GoogleFonts.cairo(fontSize: 12),
                                  ),
                                  items: [
                                    DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('-- تجاهل --', style: GoogleFonts.cairo(fontSize: 12)),
                                    ),
                                    ..._headers.map((h) => DropdownMenuItem<String?>(
                                          value: h,
                                          child: Text(h, style: GoogleFonts.cairo(fontSize: 13)),
                                        )),
                                  ],
                                  onChanged: (v) => setState(() => _mapping[field] = v),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _confirmImport,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text('تأكيد الاستيراد',
                                      style: GoogleFonts.cairo(
                                          fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
