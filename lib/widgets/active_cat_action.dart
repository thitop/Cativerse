import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:cativerse/pages/cat_edit_and_match_page.dart'; // for setActiveCatForCurrentUser

/// ====== Shared active-cat picker ======
Future<void> _openActiveCatPicker(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final db = FirebaseFirestore.instance;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      // limit height to ~65% of screen
      return FractionallySizedBox(
        heightFactor: 0.65,
        child: SafeArea(
          top: false,
          child: _ActiveCatList(uid: uid, db: db),
        ),
      );
    },
  );
}

class _ActiveCatList extends StatelessWidget {
  const _ActiveCatList({required this.uid, required this.db});
  final String uid;
  final FirebaseFirestore db;

  @override
  Widget build(BuildContext context) {
    // support both ownerUid and ownerId
    final qUid = db.collection('cats').where('ownerUid', isEqualTo: uid);
    final qId = db.collection('cats').where('ownerId', isEqualTo: uid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: qUid.snapshots(),
      builder: (context, snapUid) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: qId.snapshots(),
          builder: (context, snapId) {
            if (!snapUid.hasData && !snapId.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // merge two queries and deduplicate by doc.id
            final combined = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            if (snapUid.hasData) combined.addAll(snapUid.data!.docs);
            if (snapId.hasData) combined.addAll(snapId.data!.docs);

            final docs = {
              for (final d in combined) d.id: d,
            }.values.toList()
              ..sort((a, b) {
                final ta = a.data()['createdAt'] as Timestamp?;
                final tb = b.data()['createdAt'] as Timestamp?;
                final da = ta?.toDate();
                final dbb = tb?.toDate();
                if (da == null && dbb == null) return 0;
                if (da == null) return 1;
                if (dbb == null) return -1;
                // newest first
                return dbb.compareTo(da);
              });

            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('You have no cats in your profile yet.'),
              );
            }

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: db.collection('users').doc(uid).get(),
              builder: (context, uSnap) {
                final activeId =
                    uSnap.data?.data()?['activeCatId'] as String?;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();
                    final id = d.id;
                    final name = (data['name'] ?? '-') as String;
                    final breed =
                        (data['breedNameEn'] ?? data['breed'] ?? '') as String;

                    // resolve thumbnail from multiple possible fields
                    String? thumb;
                    final imageUrls = data['imageUrls'];
                    if (imageUrls is List &&
                        imageUrls.isNotEmpty &&
                        imageUrls.first is String) {
                      thumb = (imageUrls.first as String).trim();
                    } else if (data['imageUrl'] is String &&
                        (data['imageUrl'] as String).trim().isNotEmpty) {
                      thumb = (data['imageUrl'] as String).trim();
                    } else if (data['avatar'] is String &&
                        (data['avatar'] as String).trim().isNotEmpty) {
                      thumb = (data['avatar'] as String).trim();
                    }

                    final selected = activeId == id;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage:
                            thumb != null && thumb.isNotEmpty
                                ? NetworkImage(thumb)
                                : null,
                        child: (thumb == null || thumb.isEmpty)
                            ? const Icon(Icons.pets, color: Colors.white70)
                            : null,
                      ),
                      title: Text(name),
                      subtitle: breed.isNotEmpty ? Text(breed) : null,
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.chevron_right),
                      onTap: () async {
                        await setActiveCatForCurrentUser(
                          context: context,
                          catId: id,
                          name: name,
                          avatarUrl: thumb,
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// ====== Chip on AppBar (show current active cat) ======
class ActiveCatAction extends StatelessWidget {
  const ActiveCatAction({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(uid).snapshots(),
      builder: (context, uSnap) {
        final activeId = uSnap.data?.data()?['activeCatId'] as String?;

        if (activeId == null || activeId.isEmpty) {
          return IconButton(
            tooltip: 'Select cat',
            icon: const Icon(Icons.pets_rounded),
            onPressed: () => _openActiveCatPicker(context),
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('cats').doc(activeId).snapshots(),
          builder: (context, cSnap) {
            final cat = cSnap.data?.data();
            final name = (cat?['name'] ?? 'My cat') as String;

            String? thumb;
            final imageUrls = cat?['imageUrls'];
            if (imageUrls is List &&
                imageUrls.isNotEmpty &&
                imageUrls.first is String) {
              thumb = (imageUrls.first as String).trim();
            } else if (cat?['imageUrl'] is String &&
                (cat?['imageUrl'] as String).trim().isNotEmpty) {
              thumb = (cat?['imageUrl'] as String).trim();
            } else if (cat?['avatar'] is String &&
                (cat?['avatar'] as String).trim().isNotEmpty) {
              thumb = (cat?['avatar'] as String).trim();
            }

            // limit chip width and ellipsis the name
            final maxW = MediaQuery.of(context).size.width * 0.32;

            final chip = InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _openActiveCatPicker(context),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage:
                            thumb != null && thumb.isNotEmpty
                                ? NetworkImage(thumb)
                                : null,
                        child: (thumb == null || thumb.isEmpty)
                            ? const Icon(Icons.pets,
                                size: 16, color: Colors.white70)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
            );

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: chip,
            );
          },
        );
      },
    );
  }
}

/// ===== Buttons / tiles that open the picker (optional) =====
class ActiveCatActionButton extends StatelessWidget {
  const ActiveCatActionButton({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return _ActionButton(
      icon: Icons.pets_rounded,
      label: label ?? 'Switch cat',
      onTap: () => _openActiveCatPicker(context),
    );
  }
}

class CurrentActiveCatTile extends StatelessWidget {
  const CurrentActiveCatTile({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(uid).snapshots(),
      builder: (context, uSnap) {
        final activeId = uSnap.data?.data()?['activeCatId'] as String?;
        return ListTile(
          leading: const Icon(Icons.pets_outlined),
          title: Text(
            activeId == null || activeId.isEmpty
                ? 'No active cat selected yet'
                : 'Current active cat',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openActiveCatPicker(context),
        );
      },
    );
  }
}

/// ===== UI helper button =====
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
