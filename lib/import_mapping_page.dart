// import_mapping_page.dart
// صفحة تحديد أعمدة ملف Excel/CSV قبل الاستيراد.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'excel_service.dart';

class ImportMappingPage extends StatefulWidget {
  final List<int> fileBytes;
  final String fileName;
  const ImportMappingPage({super.key, required this.fileBytes, required this.fileName});
  @override
  State<ImportMappingPage> createState() => _ImportMappingPageState();
}

class _ImportMappingPageState extends State<ImportMappingPage> {
  bool _loading = true, _submitting = false;
  String? _error;
  List<String> _headers = [];
  List<dynamic> _rows = [];
  Map<String, dynamic> _dbFields = {};
  Map<String, String?> _mapping = {};
  int _totalRows = 0, _newGuardiansCount = 0;
  static const _requiredFields = ['guardian_card_id', 'name'];

  @override
  void initState() { super.initState(); _loadPreview(); }

  Future<void> _loadPreview() async {
    setState(() { _loading = true; _error = null; });
    final result = await ExcelService.importPreview(widget.fileBytes, widget.fileName);
    if (!mounted) return;
    if (result == null || result['error'] != null) {
      setState(() { _loading = false; _error = result?['error'] ?? 'تعذّرت قراءة الملف'; });
      return;
    }
    setState(() {
      _headers = List<String>.from(result['headers'] ?? const []);
      _rows = List<dynamic>.from(result['rows'] ?? const []);
      _dbFields = Map<String, dynamic>.from(result['db_fields'] ?? const {});
      _mapping = (result['auto_mapping'] as Map?)?.map((k, v) => MapEntry(k.toString(), v?.toString())) ?? {};
      _totalRows = int.tryParse('${result['total_rows'] ?? _rows.length}') ?? _rows.length;
      _newGuardiansCount = (result['new_guardian_card_ids'] as List?)?.length ?? 0;
      _loading = false;
    });
  }

  bool get _canSubmit => _requiredFields.every((f) => _mapping[f]?.isNotEmpty == true);

  Future<void> _confirmImport() async {
    if (!_canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لازم تحدد عمود رقم هوية رب الأسرة واسم الفرد على الأقل', style: GoogleFonts.cairo())));
      return;
    }
    setState(() => _submitting = true);
    final result = await ExcelService.importExecute(_mapping, _rows);
    if (!mounted) return;
    setState(() => _submitting = false);
    final success = result['success'] == true;
    final created = result['created'] ?? 0;
    final updated = result['updated'] ?? 0;
    final errors = List<dynamic>.from(result['errors'] ?? const []);
    await showDialog(context: context, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: Text(success ? 'نتيجة الاستيراد' : 'فشل الاستيراد', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
      content: success ? Text('تم إضافة $created سجل جديد\nتم تحديث $updated سجل${errors.isNotEmpty ? '\nعدد الأخطاء: ${errors.length}' : ''}', style: GoogleFonts.cairo()) : Text(result['message'] ?? 'حدث خطأ غير متوقع', style: GoogleFonts.cairo()),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('حسناً', style: GoogleFonts.cairo()))],
    )));
    if (mounted) Navigator.pop(context, success && (created > 0 || updated > 0));
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: Text('تحديد أعمدة الملف', style: GoogleFonts.cairo())),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: GoogleFonts.cairo(color: Colors.red), textAlign: TextAlign.center)))
        : Column(children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(14), color: const Color(0xFFEFF6FF), child: Text('الملف يحتوي $_totalRows صف${_newGuardiansCount > 0 ? '، وسيتم إضافة $_newGuardiansCount عائلة جديدة تلقائياً' : ''}', style: GoogleFonts.cairo(fontSize: 12))),
          Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('حدد العمود المقابل لكل حقل (تم الاقتراح تلقائياً)', style: GoogleFonts.cairo(fontSize: 12)),
            const SizedBox(height: 12),
            ..._dbFields.entries.map((entry) {
              final field = entry.key, label = entry.value.toString();
              final selected = _headers.contains(_mapping[field]) ? _mapping[field] : null;
              return Padding(padding: const EdgeInsets.only(bottom: 12), child: DropdownButtonFormField<String>(
                value: selected, isExpanded: true,
                decoration: InputDecoration(labelText: _requiredFields.contains(field) ? '$label *' : label, labelStyle: GoogleFonts.cairo(fontSize: 12)),
                items: _headers.map((h) => DropdownMenuItem(value: h, child: Text(h, style: GoogleFonts.cairo(fontSize: 13)))).toList(),
                onChanged: (v) => setState(() => _mapping[field] = v),
              ));
            }),
          ])),
          SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
            onPressed: _submitting ? null : _confirmImport,
            child: _submitting ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text('تأكيد الاستيراد', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ))))
        ]),
    ),
  );
}
