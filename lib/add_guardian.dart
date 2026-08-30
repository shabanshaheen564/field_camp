// add_guardian.dart
// نموذج إضافة/تعديل ربّ عائلة
//
// تعديل: الاسم صار حقل واحد "الاسم الكامل" بدل 4 حقول منفصلة.
// عند الحفظ بنقسم النص المكتوب على مسافات ونوزعه تلقائياً على
// first_name / second_name / third_name / family_name (بالضبط
// متل ما الباك إند متوقعهم)، وعند التعديل بنعكس العملية ونجمعهم
// بحقل واحد للعرض.
//
// وأضفنا حقلين جدد يطابقوا التعديلات اللي صارت بالويب:
// - الحالة الاجتماعية (marital_status)
// - من ذوي الإعاقة (is_disabled)
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';

class AddGuardianPage extends StatefulWidget {
  final Map<String, dynamic>? editData;
  const AddGuardianPage({super.key, this.editData});

  @override
  State<AddGuardianPage> createState() => _AddGuardianPageState();
}

class _AddGuardianPageState extends State<AddGuardianPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _cardIdCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _membersCtrl = TextEditingController();
  final _dobCtrl = TextEditingController(); // تاريخ الميلاد
  final _addressCtrl = TextEditingController(); // العنوان
  String _gender = 'male';
  String _nationality = 'فلسطيني';
  String _maritalStatus = 'single';
  bool _isDisabled = false;
  bool _loading = false;
  String _error = '';

  final List<String> _nationalities = [
    'فلسطيني', 'أردني', 'مصري', 'أخرى'
  ];

  // القيم مطابقة تماماً لما هو مخزّن بعمود marital_status بقاعدة البيانات
  final Map<String, String> _maritalStatuses = {
    'single': 'أعزب',
    'married': 'متزوج',
    'divorced': 'مطلق',
    'widowed': 'أرمل',
  };

  bool get _isEdit => widget.editData != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final d = widget.editData!;

      // نجمع الأربع حقول القديمة بحقل واحد للعرض والتعديل
      final parts = [
        d['first_name'],
        d['second_name'],
        d['third_name'],
        d['family_name'],
      ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');
      _fullNameCtrl.text = parts;

      _cardIdCtrl.text = d['card_id'] ?? '';
      _phoneCtrl.text = d['phone'] ?? '';
      _membersCtrl.text = (d['family_member_number'] ?? '').toString();
      _gender = d['gender'] ?? 'male';
      _dobCtrl.text = d['date_of_birth'] ?? '';
      _addressCtrl.text = d['address'] ?? '';
      _isDisabled = d['is_disabled'] == true || d['is_disabled'] == 1;
      if (_maritalStatuses.containsKey(d['marital_status'])) {
        _maritalStatus = d['marital_status'];
      }
      if (_nationalities.contains(d['nationality'])) {
        _nationality = d['nationality'];
      } else if (d['nationality'] != null &&
          (d['nationality'] as String).isNotEmpty) {
        _nationality = 'أخرى';
      }
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _cardIdCtrl.dispose();
    _phoneCtrl.dispose();
    _membersCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  // بيقسم "محمد أحمد سليم الحلبي" إلى:
  // first_name=محمد, second_name=أحمد, third_name=سليم, family_name=الحلبي
  // (متل ما هو متوقع بجدول guardians بالضبط)
  Map<String, String> _splitFullName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    switch (parts.length) {
      case 0:
        return {'first_name': '', 'second_name': '', 'third_name': '', 'family_name': ''};
      case 1:
        return {'first_name': parts[0], 'second_name': '', 'third_name': '', 'family_name': ''};
      case 2:
        return {'first_name': parts[0], 'second_name': '', 'third_name': '', 'family_name': parts[1]};
      case 3:
        return {'first_name': parts[0], 'second_name': parts[1], 'third_name': '', 'family_name': parts[2]};
      default:
        return {
          'first_name': parts[0],
          'second_name': parts[1],
          'third_name': parts[2],
          // أي كلمات زيادة عن 4 منضمها كلها لاسم العائلة (نادراً ما بصير بس أسلم)
          'family_name': parts.sublist(3).join(' '),
        };
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    DateTime selected = DateTime(now.year - 30, now.month, now.day);

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 320,
              height: 380,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('اختر تاريخ الميلاد',
                          style: GoogleFonts.cairo(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Expanded(
                    child: CalendarDatePicker(
                      initialDate: selected,
                      firstDate: DateTime(1920),
                      lastDate: now,
                      onDateChanged: (d) => selected = d,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('إلغاء', style: GoogleFonts.cairo()),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, selected),
                          child: Text('تم', style: GoogleFonts.cairo()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (picked != null) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() => _dobCtrl.text = formatted);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    final nameParts = _splitFullName(_fullNameCtrl.text);

    final data = {
      ...nameParts,
      'card_id': _cardIdCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'family_member_number': int.tryParse(_membersCtrl.text.trim()) ?? 0,
      'gender': _gender,
      'date_of_birth': _dobCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'nationality': _nationality,
      'marital_status': _maritalStatus,
      'is_disabled': _isDisabled,
    };

    Map<String, dynamic> result;
    if (_isEdit) {
      result = await ApiService.updateGuardian(widget.editData!['id'], data);
    } else {
      result = await ApiService.addGuardian(data);
    }

    setState(() => _loading = false);

    if (result['success'] == true) {
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() => _error = result['message'] ?? 'فشل الحفظ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'تعديل عائلة' : 'إضافة عائلة'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // الاسم الكامل - حقل واحد بدل 4 حقول
                _field(
                  _fullNameCtrl,
                  'الاسم الكامل (مثال: محمد أحمد سليم الحلبي)',
                  required: true,
                ),
                const SizedBox(height: 6),
                Text(
                  'اكتب الاسم كامل مفصول بمسافات: الاسم الأول ثم الثاني ثم الثالث ثم اسم العائلة',
                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 14),
                _field(_cardIdCtrl, 'رقم الهوية',
                    required: true, type: TextInputType.number),
                const SizedBox(height: 14),
                _field(_phoneCtrl, 'رقم الهاتف', type: TextInputType.phone),
                const SizedBox(height: 14),
                _field(_membersCtrl, 'عدد الأفراد', type: TextInputType.number),
                const SizedBox(height: 14),

                // تاريخ الميلاد - منتقي تاريخ
                TextFormField(
                  controller: _dobCtrl,
                  readOnly: true,
                  onTap: _pickDate,
                  style: GoogleFonts.cairo(),
                  decoration: InputDecoration(
                    labelText: 'تاريخ الميلاد',
                    labelStyle: GoogleFonts.cairo(),
                    suffixIcon: const Icon(Icons.calendar_today),
                  ),
                ),
                const SizedBox(height: 14),

                // حقل العنوان
                _field(
                  _addressCtrl,
                  'العنوان',
                  type: TextInputType.streetAddress,
                ),
                const SizedBox(height: 14),

                // الجنسية - قائمة منسدلة
                DropdownButtonFormField<String>(
                  value: _nationality,
                  style: GoogleFonts.cairo(color: const Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    labelText: 'الجنسية',
                    labelStyle: GoogleFonts.cairo(),
                  ),
                  items: _nationalities
                      .map((n) => DropdownMenuItem(
                            value: n,
                            child: Text(n, style: GoogleFonts.cairo()),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _nationality = v!),
                ),
                const SizedBox(height: 14),

                // الحالة الاجتماعية - قائمة منسدلة (حقل جديد)
                DropdownButtonFormField<String>(
                  value: _maritalStatus,
                  style: GoogleFonts.cairo(color: const Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    labelText: 'الحالة الاجتماعية',
                    labelStyle: GoogleFonts.cairo(),
                  ),
                  items: _maritalStatuses.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value, style: GoogleFonts.cairo()),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _maritalStatus = v!),
                ),
                const SizedBox(height: 14),

                // الجنس
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الجنس',
                          style: GoogleFonts.cairo(
                              fontSize: 13, color: const Color(0xFF64748B))),
                      Row(
                        children: [
                          Radio<String>(
                            value: 'male',
                            groupValue: _gender,
                            onChanged: (v) => setState(() => _gender = v!),
                            activeColor: const Color(0xFF1E3A5F),
                          ),
                          Text('ذكر', style: GoogleFonts.cairo()),
                          const SizedBox(width: 20),
                          Radio<String>(
                            value: 'female',
                            groupValue: _gender,
                            onChanged: (v) => setState(() => _gender = v!),
                            activeColor: const Color(0xFF1E3A5F),
                          ),
                          Text('أنثى', style: GoogleFonts.cairo()),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // من ذوي الإعاقة - حقل جديد
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('من ذوي الإعاقة', style: GoogleFonts.cairo(fontSize: 14)),
                    value: _isDisabled,
                    activeColor: const Color(0xFF1E3A5F),
                    onChanged: (v) => setState(() => _isDisabled = v),
                  ),
                ),

                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error,
                        style:
                            GoogleFonts.cairo(color: const Color(0xFFEF4444))),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            _isEdit ? 'تحديث' : 'حفظ',
                            style: GoogleFonts.cairo(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    TextInputType type = TextInputType.text,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      style: GoogleFonts.cairo(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(),
      ),
      validator: required
          ? (v) => (v == null || v.isEmpty) ? 'هذا الحقل مطلوب' : null
          : null,
    );
  }
}
