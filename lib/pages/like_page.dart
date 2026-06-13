// lib/pages/like_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// LikesPage (hybrid)
/// - Supports both "user-based" likes (user to user)
///   and "cat-based" likes (cat to cat)
/// - If a document has field `toCatId`, it is treated as cat-based.
///   Otherwise it will automatically fall back to user-based.
class LikesPage extends StatefulWidget {
  const LikesPage({super.key});

  @override
  State<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> {
  final _db = FirebaseFirestore.instance;
  late final String _me;

  String? _activeCatId;
  bool _loadingActive = true;

  // Prevent double-tap / duplicate actions
  final Set<String> _busyKeys = {};

  @override
  void initState() {
    super.initState();
    _me = FirebaseAuth.instance.currentUser!.uid;
    _loadActiveCatId();
  }

  Future<void> _loadActiveCatId() async {
    try {
      final meDoc = await _db.collection('users').doc(_me).get();
      _activeCatId = (meDoc.data() ?? const {})['activeCatId'] as String?;
    } catch (_) {
      _activeCatId = null;
    } finally {
      if (mounted) setState(() => _loadingActive = false);
    }
  }

  // ========= Create / update room (user-to-user) =========
  Future<void> _ensureRoomUserUser(String a, String b) async {
    final db = _db;
    final ids = [a, b]..sort();
    final roomId = '${ids[0]}__${ids[1]}';
    final roomRef = db.collection('rooms').doc(roomId);

    await db.runTransaction((tx) async {
      final snap = await tx.get(roomRef);
      if (snap.exists) {
        tx.set(
          roomRef,
          {
            'updatedAt': FieldValue.serverTimestamp(),
            'userIds': ids,
            'ownerUids': ids,
          },
          SetOptions(merge: true),
        );
      } else {
        tx.set(roomRef, {
          'userIds': ids,
          'ownerUids': ids,
          'catIds': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
        });
      }
    });
  }

  // ========= Create / update room (cat-to-cat) =========
  Future<void> _ensureRoomCatCat({
    required String myOwnerUid,
    required String myCatId,
    required String otherOwnerUid,
    required String otherCatId,
  }) async {
    final db = _db;
    final catIds = [myCatId, otherCatId]..sort();
    final pairId = '${catIds[0]}__${catIds[1]}'; // Use catIds as ID to avoid duplicates
    final roomRef = db.collection('rooms').doc(pairId);

    final ownerUids = <String>{myOwnerUid, otherOwnerUid}.toList()..sort();

    await db.runTransaction((tx) async {
      final snap = await tx.get(roomRef);
      if (snap.exists) {
        final currCatIds =
            (snap.data()?['catIds'] as List?)?.cast<String>() ?? const <String>[];
        final nextCatIds = <String>{...currCatIds, ...catIds}.toList();
        tx.set(
          roomRef,
          {
            'userIds': ownerUids,
            'ownerUids': ownerUids,
            'catIds': nextCatIds,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        tx.set(roomRef, {
          'userIds': ownerUids,
          'ownerUids': ownerUids,
          'catIds': catIds,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
        });
      }
    });
  }

  // ========= Accept like (user-to-user) =========
  Future<void> _acceptUserLike({
    required String likerUid,
    required String likeDocId,
  }) async {
    if (_busyKeys.contains(likeDocId)) return;
    setState(() => _busyKeys.add(likeDocId));

    try {
      final db = _db;
      final myLikeId = '${_me}__${likerUid}';
      final otherLikeId = '${likerUid}__${_me}';

      // Create our like doc (if not exists) and then mark both docs as matched
      final batch = db.batch();
      batch.set(
        db.collection('matches').doc(myLikeId),
        {
          'userId': _me,
          'likedUserId': likerUid,
          'timestamp': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      batch.set(
        db.collection('matches').doc(myLikeId),
        {
          'matched': true,
          'matchedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      batch.set(
        db.collection('matches').doc(otherLikeId),
        {
          'matched': true,
          'matchedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();

      await _ensureRoomUserUser(_me, likerUid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('It\'s a match! Chat room is ready.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyKeys.remove(likeDocId));
    }
  }

  // ========= Accept like (cat-to-cat) =========
  Future<void> _acceptCatLike({
    required String matchDocId,
    required String fromOwnerUid,
    required String fromCatId,
  }) async {
    if (_activeCatId == null || _activeCatId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You haven\'t selected an active cat profile yet (go to "My cat" and choose one).',
          ),
        ),
      );
      return;
    }
    if (_busyKeys.contains(matchDocId)) return;
    setState(() => _busyKeys.add(matchDocId));

    try {
      final now = FieldValue.serverTimestamp();

      // 1) mark matched
      final matchRef = _db.collection('matches').doc(matchDocId);
      await matchRef.set(
        {
          'matched': true,
          'acceptedAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      // 2) create/update room based on catIds
      await _ensureRoomCatCat(
        myOwnerUid: _me,
        myCatId: _activeCatId!,
        otherOwnerUid: fromOwnerUid,
        otherCatId: fromCatId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('It\'s a match! Chat room is ready.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyKeys.remove(matchDocId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingActive) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // --------- Stream (cat-based) ----------
    final Stream<QuerySnapshot<Map<String, dynamic>>> catBasedStream =
        (_activeCatId == null || _activeCatId!.isEmpty)
            ? const Stream.empty()
            : _db
                .collection('matches')
                .where('toCatId', isEqualTo: _activeCatId)
                .where('matched', isEqualTo: false)
                .orderBy('updatedAt', descending: true)
                .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('People who liked you')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: catBasedStream,
        builder: (context, catSnap) {
          // If cat-based matches exist, show them first
          final hasCatData = catSnap.hasData && catSnap.data!.docs.isNotEmpty;

          if (hasCatData) {
            final docs = catSnap.data!.docs;
            return _CatBasedList(
              docs: docs,
              processingKeys: _busyKeys,
              onAccept: (docId, fromOwnerUid, fromCatId) => _acceptCatLike(
                matchDocId: docId,
                fromOwnerUid: fromOwnerUid,
                fromCatId: fromCatId,
              ),
            );
          }

          // --------- Fallback: Stream (user-based) ----------
          final userBasedStream = _db
              .collection('matches')
              .where('likedUserId', isEqualTo: _me)
              .where('matched', isEqualTo: false)
              .orderBy('timestamp', descending: true)
              .snapshots();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: userBasedStream,
            builder: (context, userSnap) {
              if (userSnap.connectionState == ConnectionState.waiting &&
                  catSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (userSnap.hasError) {
                return Center(
                  child: Text('Error: ${userSnap.error}'),
                );
              }
              final docs = userSnap.data?.docs ?? const [];
              if (docs.isEmpty) {
                // No data in either mode
                return const Center(
                  child: Text('No one has liked you yet'),
                );
              }

              return _UserBasedList(
                docs: docs,
                processingKeys: _busyKeys,
                onAccept: (likeDocId, likerUid) =>
                    _acceptUserLike(likerUid: likerUid, likeDocId: likeDocId),
              );
            },
          );
        },
      ),
    );
  }
}

/* ========================= WIDGETS ========================= */

class _CatBasedList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Set<String> processingKeys;
  final Future<void> Function(
    String docId,
    String fromOwnerUid,
    String fromCatId,
  ) onAccept;

  const _CatBasedList({
    required this.docs,
    required this.processingKeys,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final doc = docs[i];
        final m = doc.data();
        final fromOwnerUid = (m['fromOwnerUid'] as String?) ?? '';
        final fromCatId = (m['fromCatId'] as String?) ?? '';

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: db.collection('cats').doc(fromCatId).get(),
          builder: (context, catSnap) {
            String catName = 'Unnamed cat';
            String photo = '';
            String breed = '';

            if (catSnap.hasData && catSnap.data!.exists) {
              final c = catSnap.data!.data()!;
              catName = (c['name'] as String?)?.trim().isNotEmpty == true
                  ? (c['name'] as String).trim()
                  : catName;
              breed = (c['breed'] as String?)?.trim() ?? '';
              final imageUrl = (c['imageUrl'] as String?)?.trim() ?? '';
              if (imageUrl.isNotEmpty) {
                photo = imageUrl;
              } else {
                final imgs = (c['imageUrls'] as List?) ?? const [];
                if (imgs.isNotEmpty && imgs.first is String) {
                  photo = (imgs.first as String).trim();
                }
              }
            }

            final busy = processingKeys.contains(doc.id);

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage:
                      photo.isNotEmpty ? NetworkImage(photo) : null,
                  child: photo.isEmpty ? const Icon(Icons.pets) : null,
                ),
                title: Text(
                  catName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  breed.isNotEmpty
                      ? 'Breed: $breed'
                      : 'Liked your cat',
                ),
                trailing: TextButton.icon(
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.favorite),
                  label: Text(busy ? 'Accepting…' : 'Accept'),
                  onPressed: busy
                      ? null
                      : () => onAccept(doc.id, fromOwnerUid, fromCatId),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UserBasedList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Set<String> processingKeys;
  final Future<void> Function(String likeDocId, String likerUid) onAccept;

  const _UserBasedList({
    required this.docs,
    required this.processingKeys,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final d = docs[i];
        final m = d.data();
        final likerUid = (m['userId'] as String?) ?? '';

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: db.collection('users').doc(likerUid).get(),
          builder: (context, s) {
            String name = likerUid;
            String photo = '';

            if (s.hasData && s.data!.exists) {
              final u = s.data!.data()!;
              final fn = (u['firstName'] as String?)?.trim() ?? '';
              final ln = (u['lastName'] as String?)?.trim() ?? '';
              final imageUrl = (u['imageUrl'] as String?)?.trim() ?? '';
              final avatar = (u['avatar'] as String?)?.trim() ?? '';
              final candidate = ('$fn $ln').trim();
              if (candidate.isNotEmpty) name = candidate;
              photo = imageUrl.isNotEmpty ? imageUrl : avatar;
            }

            final busy = processingKeys.contains(d.id);

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage:
                      photo.isNotEmpty ? NetworkImage(photo) : null,
                  child: photo.isEmpty ? const Icon(Icons.person) : null,
                ),
                title: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Liked you'),
                trailing: TextButton.icon(
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.favorite),
                  label: Text(busy ? 'Accepting…' : 'Accept'),
                  onPressed: busy ? null : () => onAccept(d.id, likerUid),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
