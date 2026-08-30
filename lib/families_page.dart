// families_page.dart
// صفحة العائلات: عرض أرباب الأسر مع أفرادهم
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'api_service.dart';
import 'add_guardian.dart';
import 'add_member.dart';
import 'import_mapping_page.dart';

class FamiliesPage extends StatefulWidget {
  const FamiliesPage({super.key});

  @override
  State<FamiliesPage> createState() => _FamiliesPageState();
}

class _FamiliesPageState extends State<FamiliesPage> {
  List<Map<String, dynamic>> _guardians = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ApiService.getGuardians();
    setState(() {
      _guardians = data;
      _filtered = data;
      _loading = false;
    });
  }

  void _filter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _guardians
          : _guardians.where((g) {
              final name =
                  '${g['first_name']} ${g['second_name']} ${g['third_name']} ${g['family_name']}'
                      .toLowerCase();
              final id = (g['card_id'] ?? '').toString().toLowerCase();
              return name.contains(q) || id.contains(q);
            }).toList();
    });
  }

  Future<void> _deleteGuardian(dynamic id, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تأكيد الحذف',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          content: Text('هل أنت متأكد من حذف هذه العائلة؟',
              style: GoogleFonts.cairo()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف', style: GoogleFonts.cairo(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    final ok = await ApiService.deleteGuardian(id);
    if (ok) {
      setState(() {
        _guardians.removeWhere((g) => g['id'] == id);
        _filtered.removeWhere((g) => g['id'] == id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم حذف العائلة'),
              backgroundColor: Color(0xFF10B981)),
        );
      }
    }
  }

  // استيراد ملف إكسل/CSV: نختار الملف وننتقل لصفحة تحديد الأعمدة
  // (زي الويب بالظبط)، والصفحة هي يلي بتنفّذ الاستيراد فعلياً.
  Future<void> _importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    final file = result.files.single;
    if (!mounted) return;

    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportMappingPage(
          fileBytes: file.bytes!,
          fileName: file.name,
        ),
      ),
    );

    if (imported == true) _load();
  }

  // تصدير الأفراد كملف CSV
  // تصدير الأفراد كملف Excel
  Future<void> _exportExcel() async {
    bool dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    void closeDialog() {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    try {
      final bytes = await ApiService.exportGuardiansExcel();
      closeDialog();

      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تصدير الملف، تأكد من الاتصال بالإنترنت',
                style: GoogleFonts.cairo()),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/families_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(path);
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(path)],
          text: 'تصدير بيانات الأفراد (Excel)');
    } catch (e) {
      // أي خطأ غير متوقع (حفظ، صلاحيات تخزين، إلخ) - نتأكد نقفل الدائرة
      // ونعرض رسالة بدل ما تضل "تلف" للأبد
      closeDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء التصدير: $e',
              style: GoogleFonts.cairo(fontSize: 12)),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('العائلات'),
          actions: [
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'استيراد من إكسل',
              onPressed: _importExcel,
            ),
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'تصدير الأفراد',
              onPressed: _exportExcel,
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF1E3A5F),
          onPressed: () async {
            final added = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => const AddGuardianPage()),
            );
            if (added == true) _load();
          },
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text('إضافة عائلة',
              style: GoogleFonts.cairo(color: Colors.white)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // شريط البحث
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _searchCtrl,
                      style: GoogleFonts.cairo(),
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم أو رقم الهوية...',
                        hintStyle: GoogleFonts.cairo(),
                        prefixIcon:
                            const Icon(Icons.search, color: Color(0xFF1E3A5F)),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _filter();
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                  // العدد
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          '${_filtered.length} عائلة',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // القائمة
                  Expanded(
                    child: _filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.family_restroom,
                                    size: 64, color: Colors.grey[300]),
                                const SizedBox(height: 12),
                                Text(
                                  'لا توجد عائلات مسجلة',
                                  style: GoogleFonts.cairo(
                                      fontSize: 16, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final g = _filtered[i];
                              final fullName =
                                  '${g['first_name'] ?? ''} ${g['second_name'] ?? ''} ${g['third_name'] ?? ''} ${g['family_name'] ?? ''}'
                                      .trim();
                              return _GuardianCard(
                                guardian: g,
                                fullName: fullName,
                                onDelete: () => _deleteGuardian(g['id'], i),
                                onEdit: () async {
                                  final updated = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AddGuardianPage(editData: g),
                                    ),
                                  );
                                  if (updated == true) _load();
                                },
                                onAddMember: () async {
                                  final added = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AddMemberPage(guardianId: g['id']),
                                    ),
                                  );
                                  if (added == true) _load();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

// =========================================================
// بطاقة ربّ الأسرة مع توسيع لعرض الأفراد
// =========================================================
class _GuardianCard extends StatefulWidget {
  final Map<String, dynamic> guardian;
  final String fullName;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onAddMember;

  const _GuardianCard({
    required this.guardian,
    required this.fullName,
    required this.onDelete,
    required this.onEdit,
    required this.onAddMember,
  });

  @override
  State<_GuardianCard> createState() => _GuardianCardState();
}

class _GuardianCardState extends State<_GuardianCard> {
  bool _expanded = false;
  List<Map<String, dynamic>> _members = [];
  bool _membersLoading = false;

  Future<void> _loadMembers() async {
    if (_members.isNotEmpty) return;
    setState(() => _membersLoading = true);
    final data = await ApiService.getFamilyMembers(widget.guardian['id']);
    setState(() {
      _members = data;
      _membersLoading = false;
    });
  }

  String _maritalStatusLabel(String status) {
    const labels = {
      'single': 'أعزب',
      'married': 'متزوج',
      'divorced': 'مطلق',
      'widowed': 'أرمل',
    };
    return labels[status] ?? status;
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: GoogleFonts.cairo(
            fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guardian;
    final memberCount = g['family_member_number'] ?? _members.length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // الرأس
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // أيقونة الشخص
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person,
                      color: Color(0xFF1E3A5F), size: 24),
                ),
                const SizedBox(width: 12),
                // المعلومات
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fullName,
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E3A5F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.badge_outlined,
                              size: 13, color: Colors.grey[600]),
                          const SizedBox(width: 3),
                          Text(
                            g['card_id'] ?? '',
                            style: GoogleFonts.cairo(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.people_outline,
                              size: 13, color: Colors.grey[600]),
                          const SizedBox(width: 3),
                          Text(
                            '$memberCount أفراد',
                            style: GoogleFonts.cairo(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      if (g['phone'] != null &&
                          g['phone'].toString().isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.phone_outlined,
                                size: 13, color: Colors.grey[600]),
                            const SizedBox(width: 3),
                            Text(
                              g['phone'].toString(),
                              style: GoogleFonts.cairo(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      if (g['marital_status'] != null ||
                          g['is_disabled'] == true ||
                          g['is_disabled'] == 1) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (g['marital_status'] != null)
                              _badge(_maritalStatusLabel(g['marital_status']),
                                  const Color(0xFF3B82F6)),
                            if (g['is_disabled'] == true ||
                                g['is_disabled'] == 1)
                              _badge('من ذوي الإعاقة', const Color(0xFFEF4444)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // الأزرار (تعديل - حذف - إضافة فرد) + زر توسيع الأفراد
                Column(
                  children: [
                    Row(
                      children: [
                        // أيقونة التعديل
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Color(0xFF3B82F6), size: 20),
                          onPressed: widget.onEdit,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        // أيقونة الحذف
                        IconButton(
                          icon: const Icon(Icons.delete_outlined,
                              color: Color(0xFFEF4444), size: 20),
                          onPressed: widget.onDelete,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        // أيقونة إضافة فرد
                        IconButton(
                          icon: const Icon(Icons.person_add_alt,
                              color: Color(0xFF10B981), size: 20),
                          onPressed: widget.onAddMember,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: 'إضافة فرد',
                        ),
                      ],
                    ),
                    // زر توسيع/طي الأفراد
                    GestureDetector(
                      onTap: () {
                        setState(() => _expanded = !_expanded);
                        if (_expanded) _loadMembers();
                      },
                      child: Row(
                        children: [
                          Text(
                            _expanded ? 'إخفاء' : 'الأفراد',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: const Color(0xFF1E3A5F),
                            ),
                          ),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: const Color(0xFF1E3A5F),
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // قائمة الأفراد (عند التوسيع)
          if (_expanded)
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: _membersLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        // زر إضافة فرد داخل القائمة الموسعة (اختياري)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'أفراد العائلة',
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E3A5F),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final added = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AddMemberPage(
                                        guardianId: widget.guardian['id']),
                                  ),
                                );
                                if (added == true) {
                                  setState(() => _members = []);
                                  _loadMembers();
                                }
                              },
                              icon: const Icon(Icons.add,
                                  size: 16, color: Color(0xFF3B82F6)),
                              label: Text(
                                'إضافة فرد',
                                style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: const Color(0xFF3B82F6)),
                              ),
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_members.isEmpty)
                          Text(
                            'لا يوجد أفراد مسجلون',
                            style: GoogleFonts.cairo(
                                fontSize: 13, color: Colors.grey),
                          )
                        else
                          ..._members.map((m) => _MemberRow(
                                member: m,
                                onDelete: () async {
                                  final ok =
                                      await ApiService.deleteFamilyMember(
                                          m['id']);
                                  if (ok) {
                                    setState(() {
                                      _members.remove(m);
                                    });
                                  }
                                },
                              )),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

// صف فرد العائلة
class _MemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onDelete;

  const _MemberRow({required this.member, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final gender = member['gender'] == 'male' ? '♂' : '♀';
    final rel = member['relationship'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Text(gender, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member['name'] ?? '',
                  style: GoogleFonts.cairo(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (rel.isNotEmpty)
                  Text(
                    rel,
                    style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                color: Color(0xFFEF4444), size: 18),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}
