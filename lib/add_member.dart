// add_member.dart
// نموذج إضافة فرد لعائلة
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';

class AddMemberPage extends StatefulWidget {
  final int guardianId;
  const AddMemberPage({super.key, required this.guardianId});

  @override
  State<AddMemberPage> createState() => _AddMemberPageState();
}

class _AddMemberPageState extends State<AddMemberPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  String _gender = 'male';
  String _relationship = 'ابن';
  String _nationality = 'فلسطيني';
  bool _isDisabled = false;
  bool _loading = false;
  String _error = '';

  final List<String> _relationships = [
    'زوجة', 'ابن', 'ابنة', 'أب', 'أم', 'أخ', 'أخت', 'جد', 'جدة', 'حفيد', 'أخرى'
  ];

  final List<String> _nationalities = [
    'فلسطيني', 'أردني', 'مصري', 'أخرى'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cardCtrl.dispose();
    _phoneCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    DateTime selected = DateTime(now.year - 20, now.month, now.day);

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
    setState(() { _loading = true; _error = ''; });

    final result = await ApiService.addFamilyMember({
      'guardian_id': widget.guardianId,
      'name': _nameCtrl.text.trim(),
      'card_id': _cardCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim(),
      'gender': _gender,
      'relationship': _relationship,
      'date_of_birth': _dobCtrl.text.trim(),
      'nationality': _nationality,
      'is_disabled': _isDisabled,
    });

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
        appBar: AppBar(title: const Text('إضافة فرد للعائلة')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  style: GoogleFonts.cairo(),
                  decoration: InputDecoration(labelText: 'الاسم الكامل', labelStyle: GoogleFonts.cairo()),
                  validator: (v) => (v == null || v.isEmpty) ? 'أدخل الاسم' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cardCtrl,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.cairo(),
                  decoration: InputDecoration(labelText: 'رقم الهوية', labelStyle: GoogleFonts.cairo()),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.cairo(),
                  decoration: InputDecoration(labelText: 'رقم الهاتف', labelStyle: GoogleFonts.cairo()),
                ),
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

                // صلة القرابة
                DropdownButtonFormField<String>(
                  value: _relationship,
                  style: GoogleFonts.cairo(color: const Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    labelText: 'صلة القرابة',
                    labelStyle: GoogleFonts.cairo(),
                  ),
                  items: _relationships
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r, style: GoogleFonts.cairo()),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _relationship = v!),
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
                      Text('الجنس', style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF64748B))),
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
                    child: Text(_error, style: GoogleFonts.cairo(color: const Color(0xFFEF4444))),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('حفظ', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
