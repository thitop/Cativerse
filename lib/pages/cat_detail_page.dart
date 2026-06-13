// lib/pages/cat_detail_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/cat_models.dart';
import 'cat_health_page.dart';

class CatDetailPage extends StatefulWidget {
  final String catId;
  const CatDetailPage({super.key, required this.catId});

  @override
  State<CatDetailPage> createState() => _CatDetailPageState();
}

class _CatDetailPageState extends State<CatDetailPage> {
  int _currentImage = 0;
  final _pageCtrl = PageController();

  // แคช future กันกระพริบตอน setState จากการปัดรูป
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _catFuture;

  @override
  void initState() {
    super.initState();
    _catFuture =
        FirebaseFirestore.instance.collection('cats').doc(widget.catId).get();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _openDetailsSheet({
    required String title,
    required String subcollection,
    required bool canManage,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) => Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Text(title),
            ),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('cats/${widget.catId}/$subcollection')
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (_, s) {
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = s.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No records yet'));
                }
                return ListView.separated(
                  controller: controller,
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final t = (m['date'] as Timestamp?)?.toDate();
                    switch (subcollection) {
                      case 'vaccineRecords':
                        return ListTile(
                          title: Text(m['type']?.toString() ?? '-'),
                          subtitle: Text(
                            '${t != null ? _fmtDate(t) : '-'}'
                            '${(m['notes'] ?? '').toString().isNotEmpty ? ' • ${m['notes']}' : ''}',
                          ),
                        );
                      case 'illnessRecords':
                        return ListTile(
                          title: Text(m['diagnosis']?.toString() ?? '-'),
                          subtitle: Text(
                            '${t != null ? _fmtDate(t) : '-'}'
                            '${(m['treatment'] ?? '').toString().isNotEmpty ? ' • Rx: ${m['treatment']}' : ''}'
                            '${(m['notes'] ?? '').toString().isNotEmpty ? ' • ${m['notes']}' : ''}',
                          ),
                        );
                      case 'checkupRecords':
                        return ListTile(
                          title: Text(
                            '${t != null ? _fmtDate(t) : '-'}'
                            '${(m['clinic'] ?? '').toString().isNotEmpty ? ' • ${m['clinic']}' : ''}',
                          ),
                          subtitle: Text(
                            '${m['weightKg'] != null ? 'Weight ${m['weightKg']} kg' : ''}'
                            '${(m['notes'] ?? '').toString().isNotEmpty ? ' • ${m['notes']}' : ''}',
                          ),
                        );
                      case 'treatmentRecords':
                        final parts = <String>[
                          if (t != null) _fmtDate(t),
                          if ((m['clinic'] ?? '').toString().isNotEmpty) m['clinic'],
                          if ((m['medicine'] ?? '').toString().isNotEmpty)
                            'Medicine: ${m['medicine']}',
                          if ((m['dose'] ?? '').toString().isNotEmpty)
                            'Dose: ${m['dose']}',
                          if ((m['note'] ?? m['notes'] ?? '').toString().isNotEmpty)
                            (m['note'] ?? m['notes']).toString(),
                        ];
                        return ListTile(
                          title: Text((m['name'] ?? 'Treatment').toString()),
                          subtitle: Text(parts.join(' • ')),
                        );
                      default: // birthRecords
                        final parts = <String>[
                          if (t != null) _fmtDate(t),
                          'Total ${(m['kittens'] ?? 0)} kittens',
                          (m['healthyAll'] ?? true)
                              ? 'All healthy'
                              : 'Some weak/ill kittens',
                          if ((m['other'] ?? false) == true) 'Other issues',
                          if ((m['notes'] ?? '').toString().isNotEmpty) m['notes'],
                        ];
                        return ListTile(
                          title: const Text('Birth'),
                          subtitle: Text(parts.join(' • ')),
                        );
                    }
                  },
                );
              },
            ),
            bottomNavigationBar: canManage
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CatHealthPage(catId: widget.catId),
                            ),
                          );
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open full health records'),
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Cat details')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _catFuture,
        builder: (c, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Cat not found'));
          }

          final cat = Cat.fromDoc(snap.data!);
          final images = cat.imageUrls;
          final hasImages = images.isNotEmpty;
          final isOwner = cat.ownerId == uid;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ===== รูปภาพ: ธรรมดา ปัดได้ =====
              AspectRatio(
                aspectRatio: 16 / 10,
                child: hasImages
                    ? PageView.builder(
                        controller: _pageCtrl,
                        physics: const BouncingScrollPhysics(),
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => _currentImage = i),
                        itemBuilder: (_, i) => Image.network(
                          images[i],
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, prog) =>
                              prog == null
                                  ? child
                                  : const Center(child: CircularProgressIndicator()),
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(child: Icon(Icons.image_not_supported)),
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: Icon(Icons.pets, size: 64, color: Colors.grey),
                        ),
                      ),
              ),

              // ✅ เม็ดบอกหน้า — ใต้รูป
              if (hasImages && images.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentImage == i ? 14 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentImage == i
                            ? Colors.black.withOpacity(0.7)
                            : Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // ⭐ NEW: ข้อมูลเจ้าของ (รูป + ชื่อ)
              FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(cat.ownerId)
                    .get(),
                builder: (_, userSnap) {
                  if (userSnap.connectionState == ConnectionState.waiting) {
                    return const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text('Loading owner...'),
                    );
                  }

                  if (!userSnap.hasData || !userSnap.data!.exists) {
                    return const SizedBox.shrink();
                  }

                  final data = userSnap.data!.data() ?? {};
                  // พยายามดึงชื่อจาก username -> firstName + lastName
                  String displayName = (data['username'] ?? '').toString();
                  if (displayName.trim().isEmpty) {
                    final first = (data['firstName'] ?? '').toString();
                    final last = (data['lastName'] ?? '').toString();
                    displayName = '$first $last'.trim();
                  }
                  if (displayName.isEmpty) {
                    displayName = 'Unknown owner';
                  }

                  final avatarUrl = (data['imageUrl'] ?? data['photoUrl'])?.toString();

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: (avatarUrl == null || avatarUrl.isEmpty)
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Owner'),
                  );
                },
              ),

              const SizedBox(height: 12),

              // ชื่อ/สายพันธุ์/อายุ
              Text(cat.name, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                '${cat.breed} • ${ageLabel(cat.birthdate)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),

              // คำอธิบาย
              if (cat.description.isNotEmpty)
                Text(
                  cat.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              if (cat.description.isEmpty)
                Text(
                  '— No description —',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey),
                ),
              const Divider(height: 32),

              // ===== สรุปสุขภาพ (แตะเพื่อดูรายละเอียด) =====
              const Text(
                'Health summary',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _SummaryItem(
                title: 'Vaccines',
                subtitleStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/vaccineRecords')
                    .orderBy('date', descending: true)
                    .limit(1)
                    .snapshots()
                    .map(
                      (s) => s.docs.isEmpty
                          ? 'No record yet'
                          : 'Latest: ${_fmtDate((s.docs.first['date'] as Timestamp).toDate())}',
                    ),
                countStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/vaccineRecords')
                    .snapshots()
                    .map((s) => s.docs.length),
                onTap: () => _openDetailsSheet(
                  title: 'Vaccines',
                  subcollection: 'vaccineRecords',
                  canManage: isOwner,
                ),
              ),
              _SummaryItem(
                title: 'Illness',
                subtitleStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/illnessRecords')
                    .orderBy('date', descending: true)
                    .limit(1)
                    .snapshots()
                    .map(
                      (s) => s.docs.isEmpty
                          ? 'No record yet'
                          : 'Latest: ${_fmtDate((s.docs.first['date'] as Timestamp).toDate())}',
                    ),
                countStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/illnessRecords')
                    .snapshots()
                    .map((s) => s.docs.length),
                onTap: () => _openDetailsSheet(
                  title: 'Illness history',
                  subcollection: 'illnessRecords',
                  canManage: isOwner,
                ),
              ),
              _SummaryItem(
                title: 'Checkups',
                subtitleStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/checkupRecords')
                    .orderBy('date', descending: true)
                    .limit(1)
                    .snapshots()
                    .map(
                      (s) => s.docs.isEmpty
                          ? 'No record yet'
                          : 'Latest: ${_fmtDate((s.docs.first['date'] as Timestamp).toDate())}',
                    ),
                countStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/checkupRecords')
                    .snapshots()
                    .map((s) => s.docs.length),
                onTap: () => _openDetailsSheet(
                  title: 'Checkups',
                  subcollection: 'checkupRecords',
                  canManage: isOwner,
                ),
              ),
              _SummaryItem(
                title: 'Treatments',
                subtitleStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/treatmentRecords')
                    .orderBy('date', descending: true)
                    .limit(1)
                    .snapshots()
                    .map(
                      (s) => s.docs.isEmpty
                          ? 'No record yet'
                          : 'Latest: ${_fmtDate((s.docs.first['date'] as Timestamp).toDate())}',
                    ),
                countStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/treatmentRecords')
                    .snapshots()
                    .map((s) => s.docs.length),
                onTap: () => _openDetailsSheet(
                  title: 'Treatments',
                  subcollection: 'treatmentRecords',
                  canManage: isOwner,
                ),
              ),
              _SummaryItem(
                title: 'Birth / litters',
                subtitleStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/birthRecords')
                    .orderBy('date', descending: true)
                    .limit(1)
                    .snapshots()
                    .map(
                      (s) => s.docs.isEmpty
                          ? 'No record yet'
                          : 'Latest: ${_fmtDate((s.docs.first['date'] as Timestamp).toDate())}',
                    ),
                countStream: FirebaseFirestore.instance
                    .collection('cats/${cat.id}/birthRecords')
                    .snapshots()
                    .map((s) => s.docs.length),
                onTap: () => _openDetailsSheet(
                  title: 'Birth / litters',
                  subcollection: 'birthRecords',
                  canManage: isOwner,
                ),
              ),

              if (isOwner) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CatHealthPage(catId: cat.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.health_and_safety),
                  label: const Text('Manage health'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String title;
  final Stream<String> subtitleStream;
  final Stream<int> countStream;
  final VoidCallback onTap;

  const _SummaryItem({
    required this.title,
    required this.subtitleStream,
    required this.countStream,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: onTap,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: StreamBuilder<String>(
          stream: subtitleStream,
          builder: (_, s) => Text(s.data ?? 'Loading...'),
        ),
        trailing: StreamBuilder<int>(
          stream: countStream,
          builder: (_, s) => Chip(
            label: Text('${s.data ?? 0}'),
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          ),
        ),
      ),
    );
  }
}
