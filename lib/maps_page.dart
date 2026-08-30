// maps_page.dart
// صفحة الخريطة - تعرض مخيم اليوزر فقط
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_service.dart';

class MapsPage extends StatefulWidget {
  const MapsPage({super.key});

  @override
  State<MapsPage> createState() => _MapsPageState();
}

class _MapsPageState extends State<MapsPage> {
  Map<String, dynamic>? _camp;
  bool _loading = true;
  final MapController _mapController = MapController();

  // إحداثيات افتراضية (فلسطين)
  static const LatLng _defaultCenter = LatLng(31.9, 35.2);

  @override
  void initState() {
    super.initState();
    _loadCamp();
  }

  Future<void> _loadCamp() async {
    setState(() => _loading = true);
    final camp = await ApiService.getMyCamp();
    setState(() {
      _camp = camp;
      _loading = false;
    });
  }

  LatLng _getCampLocation() {
    if (_camp == null) return _defaultCenter;
    final lat = double.tryParse(_camp!['latitude']?.toString() ?? '');
    final lng = double.tryParse(_camp!['longitude']?.toString() ?? '');
    if (lat != null && lng != null) return LatLng(lat, lng);
    return _defaultCenter;
  }

  @override
  Widget build(BuildContext context) {
    final campLocation = _getCampLocation();
    final campName = _camp?['name'] ?? 'مخيمك';
    final status = _camp?['status'] ?? 'active';
    final markerColor = status == 'full' ? Colors.red : const Color(0xFF1E3A5F);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('خريطة المخيم'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadCamp),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: campLocation,
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.camp_app',
                      ),
                      if (_camp != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: campLocation,
                              width: 120,
                              height: 70,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      campName,
                                      style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF1E3A5F),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Icon(Icons.location_on, color: markerColor, size: 32),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  // بطاقة معلومات المخيم في الأسفل
                  if (_camp != null)
                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: _buildCampInfoCard(),
                    ),
                  if (_camp == null)
                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'لا توجد بيانات خريطة للمخيم',
                          style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildCampInfoCard() {
    final camp = _camp!;
    final status = camp['status'] ?? 'active';
    final statusColor = status == 'active'
        ? const Color(0xFF10B981)
        : status == 'full'
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);
    final statusText = status == 'active' ? 'نشط' : status == 'full' ? 'ممتلئ' : 'غير نشط';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.holiday_village, color: Color(0xFF1E3A5F), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  camp['name'] ?? 'المخيم',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E3A5F),
                  ),
                ),
              ),
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
          Row(
            children: [
              if (camp['location'] != null) ...[
                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    camp['location'].toString(),
                    style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                ),
              ],
              if (camp['capacity'] != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.people_outline, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text(
                  'سعة ${camp['capacity']}',
                  style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF64748B)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
