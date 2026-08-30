// statistics_page.dart
// صفحة الإحصائيات - تجلب البيانات من Laravel API
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool _loading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _guardians = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // جلب الإحصائيات من الـ API
    final stats = await ApiService.getCampStatistics();
    // جلب العائلات لحساب إحصائيات إضافية
    final guardians = await ApiService.getGuardians();

    // حساب إحصائيات محلية من بيانات العائلات
    int totalMembers = 0;
    for (var g in guardians) {
      totalMembers += (int.tryParse(g['family_member_number']?.toString() ?? '0') ?? 0);
    }
    setState(() {
      _stats = stats;
      _guardians = guardians;
      // إذا الـ API ما رجع إحصائيات، نحسبها محلياً
      if (!_stats.containsKey('total_families')) {
        _stats['total_families'] = guardians.length;
      }
      if (!_stats.containsKey('total_individuals')) {
        _stats['total_individuals'] = totalMembers;
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الإحصائيات'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // بطاقات الإحصائيات الرئيسية
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        childAspectRatio: 1.4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        children: [
                          _StatCard(
                            icon: Icons.family_restroom,
                            label: 'إجمالي العائلات',
                            value: '${_stats['total_families'] ?? _guardians.length}',
                            color: const Color(0xFF3B82F6),
                          ),
                          _StatCard(
                            icon: Icons.people,
                            label: 'إجمالي الأفراد',
                            value: '${_stats['total_individuals'] ?? 0}',
                            color: const Color(0xFF10B981),
                          ),
                          _StatCard(
                            icon: Icons.people_outline,
                            label: 'متوسط حجم العائلة',
                            value: _avgFamilySize(),
                            color: const Color(0xFFF59E0B),
                          ),
                          _StatCard(
                            icon: Icons.holiday_village,
                            label: 'مخيمك',
                            value: '1',
                            color: const Color(0xFF8B5CF6),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // قائمة العائلات مع أعداد الأفراد
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تفاصيل العائلات',
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E3A5F),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_guardians.isEmpty)
                              Center(
                                child: Text(
                                  'لا توجد عائلات',
                                  style: GoogleFonts.cairo(color: Colors.grey),
                                ),
                              )
                            else
                              ..._guardians.map((g) {
                                final name =
                                    '${g['first_name'] ?? ''} ${g['family_name'] ?? ''}'.trim();
                                final members = g['family_member_number'] ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF1E3A5F),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          name.isEmpty ? 'عائلة' : name,
                                          style: GoogleFonts.cairo(fontSize: 14),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E3A5F).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '$members أفراد',
                                          style: GoogleFonts.cairo(
                                            fontSize: 12,
                                            color: const Color(0xFF1E3A5F),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),

                      // إذا في إحصائيات إضافية من الـ API
                      if (_stats.containsKey('camp') && _stats['camp'] != null) ...[
                        const SizedBox(height: 16),
                        _buildCampDetails(_stats['camp']),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  String _avgFamilySize() {
    // تحويل القيم إلى أرقام بشكل آمن
    final total = double.tryParse((_stats['total_individuals'] ?? 0).toString()) ?? 0;
    final families = double.tryParse((_stats['total_families'] ?? _guardians.length).toString()) ?? 0;
    if (families == 0) return '0';
    final avg = total / families;
    return avg.toStringAsFixed(1);
  }

  Widget _buildCampDetails(dynamic camp) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'معلومات المخيم',
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E3A5F),
            ),
          ),
          const SizedBox(height: 10),
          if (camp['capacity'] != null) ...[
            _InfoRow(label: 'الطاقة الاستيعابية', value: '${camp['capacity']}'),
            const SizedBox(height: 6),
          ],
          if (camp['manager'] != null)
            _InfoRow(label: 'المدير', value: '${camp['manager']}'),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          Text(
            label,
            style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF64748B))),
        Text(value, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
