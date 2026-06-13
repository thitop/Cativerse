// lib/pages/cat_edit_and_match_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'cat_edit_page.dart';
import 'cat_detail_page.dart';

/// Helper function:
/// Use this to set the active cat for the current user from anywhere in the app.
/// Just import this file and call setActiveCatForCurrentUser(...)
Future<void> setActiveCatForCurrentUser({
  required BuildContext context,
  required String catId,
  String? name,
  String? avatarUrl,
}) async {
  final auth = FirebaseAuth.instance;
  final db = FirebaseFirestore.instance;
  final uid = auth.currentUser?.uid;
  if (uid == null) return;

  String catName = (name ?? '').trim();
  String catAvatar = (avatarUrl ?? '').trim();

  // If name/avatar are not provided or empty, fetch from the 'cats' collection
  if (catName.isEmpty || catAvatar.isEmpty) {
    final doc = await db.collection('cats').doc(catId).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;

      if (catName.isEmpty) {
        catName = (data['name'] ?? '').toString().trim();
      }

      if (catAvatar.isEmpty) {
        // ลองดึงจาก photos ก่อน ถ้าไม่มีค่อย fallback ไป field อื่น
        final photos = data['photos'];
        if (photos is List &&
            photos.isNotEmpty &&
            photos.first is String &&
            (photos.first as String).trim().isNotEmpty) {
          catAvatar = (photos.first as String).trim();
        } else {
          catAvatar =
              (data['imageUrl'] ?? data['avatar'] ?? '').toString().trim();
        }
      }
    }
  }

  await db.collection('users').doc(uid).set(
    {
      'activeCatId': catId,
      'activeCatName': catName,
      'activeCatAvatar': catAvatar,
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  // Show a small confirmation message
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Set "${catName.isEmpty ? 'your cat' : catName}" as your active cat for matching.',
      ),
    ),
  );
}

class CatEditAndMatchPage extends StatefulWidget {
  const CatEditAndMatchPage({super.key});

  @override
  State<CatEditAndMatchPage> createState() => _CatEditAndMatchPageState();
}

class _CatEditAndMatchPageState extends State<CatEditAndMatchPage> {
  final _auth = FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? _selectedMatchId;
  bool _loadingActive = true;

  @override
  void initState() {
    super.initState();
    _loadActiveCat();
  }

  Future<void> _loadActiveCat() async {
    final uid = _auth.currentUser!.uid;
    final userDoc = await _db.collection('users').doc(uid).get();
    setState(() {
      _selectedMatchId = userDoc.data()?['activeCatId'] as String?;
      _loadingActive = false;
    });
  }

  Future<void> _setActiveCat({
    required String catId,
    required String name,
    String? avatarUrl,
  }) async {
    setState(() {
      _selectedMatchId = catId;
    });

    await setActiveCatForCurrentUser(
      context: context,
      catId: catId,
      name: name,
      avatarUrl: avatarUrl,
    );
  }

  Future<void> _deleteCat(String catId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete cat'),
        content: const Text(
          'Are you sure you want to delete this cat profile? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _db.collection('cats').doc(catId).delete();

    // If the deleted cat is currently active, clear it from the user document
    if (_selectedMatchId == catId) {
      final uid = _auth.currentUser!.uid;
      await _db.collection('users').doc(uid).set(
        {
          'activeCatId': FieldValue.delete(),
          'activeCatName': FieldValue.delete(),
          'activeCatAvatar': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
      setState(() {
        _selectedMatchId = null;
      });
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cat profile deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My cats'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection('cats')
            .where('ownerId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData || _loadingActive) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final an = (a.data()['name'] ?? '') as String;
              final bn = (b.data()['name'] ?? '') as String;
              return an.toLowerCase().compareTo(bn.toLowerCase());
            });

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'You have no cats yet.\nAdd a cat profile first.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final catId = doc.id;

              final name = (data['name'] ?? 'Unnamed') as String;
              final breed = (data['breed'] ?? '-') as String;
              final gender = (data['gender'] ?? '-') as String;

              String? imageUrl;
              final photos = data['photos'];
              if (photos is List &&
                  photos.isNotEmpty &&
                  photos.first is String) {
                imageUrl = (photos.first as String).trim();
              } else if (data['imageUrl'] is String &&
                  (data['imageUrl'] as String).trim().isNotEmpty) {
                imageUrl = (data['imageUrl'] as String).trim();
              }

              final isSelected = _selectedMatchId == catId;

              return Card(
                child: ListTile(
                  // ✅ กดแถว (รูป/ชื่อ) → ไปหน้าโปรไฟล์แมว
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CatDetailPage(catId: catId),
                      ),
                    );
                  },
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                        ? NetworkImage(imageUrl)
                        : null,
                    child: (imageUrl == null || imageUrl.isEmpty)
                        ? const Icon(Icons.pets)
                        : null,
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$breed • $gender',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Set as active cat',
                        icon: Icon(
                          isSelected ? Icons.star : Icons.star_border,
                        ),
                        onPressed: () => _setActiveCat(
                          catId: catId,
                          name: name,
                          avatarUrl: imageUrl,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CatEditPage(catId: catId),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteCat(catId),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
