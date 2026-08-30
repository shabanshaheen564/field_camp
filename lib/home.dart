// home.dart
// الصفحة الرئيسية بعد الدخول - تعرض بيانات المخيم وأزرار التنقل
//
// التعديل الوحيد هون مقارنة بالنسخة الأصلية: عند فتح الصفحة، بننادي
// ApiService.syncPendingActions() عشان أي عمليات صارت وانت أوفلاين
// (إضافة/تعديل/حذف عائلات) تترفع تلقائياً أول ما يكون في نت.
// وبنعرض شريط بسيط فوق لو لسا في عمليات معلّقة ما انرفعت.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';
import 'login.dart';
import 'families_page.dart';
import 'statistics_page.dart';
import 'maps_page.dart';
import 'notifications_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _camp;
  bool _loading = true;
  // عدد العمليات اللي لسا بانتظار الرفع للسيرفر (0 يعني كل شي متزامن)
  int _pendingCount = 0;
  // عدد الإشعارات غير المقروءة (بيظهر كشارة فوق جرس الإشعارات بالهيدر)
  int _unreadNotifCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // كم عملية كانت معلّقة قبل ما نحاول نرفعها (عشان نعرف إذا كان أصلاً في شي معلّق)
    final beforeCount = await ApiService.getPendingActionsCount();

    // نحاول نرفع أي عمليات معلّقة من مرة سابقة كان فيها انقطاع نت
    // وهلأ بترجع لنا كم عملية نجحت فعلاً بالرفع
    final syncedCount = await ApiService.syncPendingActions();

    _user = await ApiService.getUserData();
    _camp = await ApiService.getMyCamp();
    _pendingCount = await ApiService.getPendingActionsCount();

    final notifData = await ApiService.getNotifications();
    _unreadNotifCount = notifData['unread_count'] ?? 0;

    if (mounted) {
      setState(() => _loading = false);

      // لو كان في شي معلّق ونجح رفع شي منه فعلاً (يعني رجع النت) -> رسالة نجاح
      if (beforeCount > 0 && syncedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم رفع $syncedCount تعديل بنجاح ✅',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الصفحة الرئيسية'),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'الإشعارات',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationsPage()),
                  );
                  _loadData(); // تحديث العداد بعد الرجوع من صفحة الإشعارات
                },
              ),
              if (_unreadNotifCount > 0)
                Positioned(
                  top: 8,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
                      style: const TextStyle(color: Colors.white, fontSize: 9),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'تسجيل خروج',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // شريط تنبيه بسيط: بيظهر بس لو في عمليات لسا ما انرفعت
              if (_pendingCount > 0) _buildPendingBanner(),
              if (_pendingCount > 0) const SizedBox(height: 16),

              // بطاقة ترحيب
              _buildWelcomeCard(),
              const SizedBox(height: 20),
              // بطاقة المخيم
              if (_camp != null) _buildCampCard(),
              const SizedBox(height: 24),
              // عنوان الأزرار
              Text(
                'الخدمات المتاحة',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E3A5F),
                ),
              ),
              const SizedBox(height: 12),
              // شبكة الأزرار
              _buildNavGrid(),
            ],
          ),
        ),
      ),
    );
  }

  // شريط صغير أصفر بيقول للمستخدم إنه في تعديلات عم تنتظر رفعها للسيرفر
  Widget _buildPendingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'في $_pendingCount تعديل بانتظار الرفع للسيرفر، رح يترفع تلقائياً أول ما يرجع النت',
              style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFFB45309)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFFB45309), size: 20),
            onPressed: _loadData,
            tooltip: 'إعادة محاولة الرفع',
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    final name = _user?['name'] ?? 'المستخدم';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF2D5B8E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              name.isNotEmpty ? name[0] : 'م',
              style: GoogleFonts.cairo(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أهلاً، $name',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _user?['email'] ?? '',
                  style: GoogleFonts.cairo(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _user?['role'] ?? 'مشرف',
                    style: GoogleFonts.cairo(fontSize: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampCard() {
    final camp = _camp!;
    final status = camp['status'] ?? 'active';
    final statusColor = status == 'active'
        ? const Color(0xFF10B981)
        : status == 'full'
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);
    final statusText = status == 'active'
        ? 'نشط'
        : status == 'full'
        ? 'ممتلئ'
        : 'غير نشط';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.holiday_village, color: Color(0xFF1E3A5F), size: 20),
              const SizedBox(width: 8),
              Text(
                'مخيمك',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            camp['name'] ?? 'مخيم',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E3A5F),
            ),
          ),
          if (camp['location'] != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text(
                  camp['location'],
                  style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ],
          if (camp['capacity'] != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.people_outline, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text(
                  'الطاقة الاستيعابية: ${camp['capacity']}',
                  style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavGrid() {
    final items = [
      _NavItem(
        icon: Icons.family_restroom,
        label: 'العائلات',
        color: const Color(0xFF3B82F6),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FamiliesPage()),
        ),
      ),
      _NavItem(
        icon: Icons.bar_chart,
        label: 'الإحصائيات',
        color: const Color(0xFF10B981),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StatisticsPage()),
        ),
      ),
      _NavItem(
        icon: Icons.map,
        label: 'الخريطة',
        color: const Color(0xFFF59E0B),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MapsPage()),
        ),
      ),
      _NavItem(
        icon: Icons.notifications_outlined,
        label: 'الإشعارات',
        color: const Color(0xFF8B5CF6),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsPage()),
          );
          _loadData();
        },
      ),
      _NavItem(
        icon: Icons.logout,
        label: 'تسجيل الخروج',
        color: const Color(0xFFEF4444),
        onTap: _logout,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: item.color, size: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  item.label,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.color, required this.onTap});
}