// notifications_page.dart
// صفحة الإشعارات بالتطبيق - نفس فكرة جرس الإشعارات بالويب
// تستخدم GET /api/notifications (نفس NotificationController الموجود
// بالويب، مضاف له route بالـ API بـ api.php).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ApiService.getNotifications();
    setState(() {
      _notifications = List<Map<String, dynamic>>.from(data['notifications'] ?? []);
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    await ApiService.markAllNotificationsRead();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => n['read_at'] == null);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الإشعارات'),
          actions: [
            if (hasUnread)
              TextButton(
                onPressed: _markAllRead,
                child: Text('تحديد الكل كمقروء',
                    style: GoogleFonts.cairo(color: Colors.white, fontSize: 12)),
              ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _notifications.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Icon(Icons.notifications_off_outlined,
                              size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Center(
                            child: Text('لا توجد إشعارات حالياً',
                                style: GoogleFonts.cairo(color: Colors.grey)),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: _notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final n = _notifications[i];
                          final isRead = n['read_at'] != null;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              if (!isRead && n['id'] != null) {
                                await ApiService.markNotificationRead(n['id'].toString());
                                _load();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isRead ? Colors.white : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isRead
                                      ? const Color(0xFFE2E8F0)
                                      : const Color(0xFFBFDBFE),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _iconFor(n['icon']),
                                    color: const Color(0xFF3B82F6),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n['title'] ?? 'إشعار',
                                          style: GoogleFonts.cairo(
                                              fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          n['message'] ?? '',
                                          style: GoogleFonts.cairo(
                                              fontSize: 12, color: Colors.grey[700]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isRead)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(top: 4),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF3B82F6),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }

  IconData _iconFor(String? name) {
    switch (name) {
      case 'fa-tent':
        return Icons.holiday_village;
      case 'fa-users':
        return Icons.family_restroom;
      case 'fa-user-plus':
        return Icons.person_add_alt;
      default:
        return Icons.notifications;
    }
  }
}
