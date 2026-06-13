// lib/pages/chat_detail_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'cat_detail_page.dart';

class ChatDetailPage extends StatefulWidget {
  final String roomId;
  final String otherUid;

  // ✅ รับ otherCatId มาจากหน้า ChatPage
  final String? otherCatId;

  const ChatDetailPage({
    super.key,
    required this.roomId,
    required this.otherUid,
    this.otherCatId,
  });

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _ctrl = TextEditingController();
  bool _sending = false;

  // ===== active cat ของเรา (ใช้ตอนส่งข้อความ) =====
  String? _activeCatId;
  bool _loadingActive = true;

  // ===== ข้อมูลแมวของอีกฝั่ง สำหรับโชว์บน AppBar =====
  String? _otherCatId;
  String? _otherCatName;
  String? _otherCatImageUrl;
  bool _loadingHeader = true;

  @override
  void initState() {
    super.initState();
    _loadActiveCatId();

    // ✅ เริ่มต้นด้วย otherCatId ที่ส่งมาจาก ChatPage ก่อนเลย
    _otherCatId = widget.otherCatId;
    _loadOtherCatHeader();
  }

  Future<void> _loadActiveCatId() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        final doc = await _db.collection('users').doc(uid).get();
        _activeCatId = (doc.data() ?? {})['activeCatId'] as String?;
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingActive = false);
    }
  }

  // ✅ ดึงแมวของฝั่งตรงข้ามมาโชว์รูป+ชื่อใน AppBar
  Future<void> _loadOtherCatHeader() async {
    try {
      String? catId = _otherCatId;

      // ถ้า ChatPage ส่ง catId มาให้แล้ว ใช้อันนั้นเลย
      if (catId == null || catId.isEmpty) {
        // ถ้าไม่มี ใช้ activeCatId ของอีกฝั่งเป็น fallback
        final userDoc =
            await _db.collection('users').doc(widget.otherUid).get();
        final userData = userDoc.data() ?? {};
        catId = userData['activeCatId'] as String?;
      }

      if (catId == null || catId.isEmpty) {
        return;
      }

      final catDoc = await _db.collection('cats').doc(catId).get();
      final cat = catDoc.data() ?? {};

      _otherCatId = catId;
      _otherCatName = (cat['name'] as String?) ?? 'Cat';

      // พยายามดึงจาก photos[0] ก่อน ถ้าไม่มีค่อยใช้ imageUrl
      final photos = cat['photos'];
      if (photos is List && photos.isNotEmpty) {
        _otherCatImageUrl = photos.first as String;
      } else {
        _otherCatImageUrl = cat['imageUrl'] as String?;
      }
    } catch (e) {
      debugPrint('Failed to load other cat header: $e');
    } finally {
      if (mounted) setState(() => _loadingHeader = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final uid = _auth.currentUser!.uid;
      final now = FieldValue.serverTimestamp();

      final msgRef = _db
          .collection('rooms')
          .doc(widget.roomId)
          .collection('messages')
          .doc();

      await msgRef.set({
        'id': msgRef.id,
        'authorId': uid, // legacy
        'senderUid': uid,
        'senderCatId': _activeCatId,
        'text': text,
        'createdAt': now,
        'type': 'text',
      });

      await _db.collection('rooms').doc(widget.roomId).set({
        'lastMessage': text,
        'updatedAt': now,
      }, SetOptions(merge: true));

      _ctrl.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ✅ Widget บน AppBar: รูป + ชื่อแมว กดแล้วไป CatDetailPage
  Widget _buildHeaderTitle(BuildContext context) {
    if (_loadingHeader || _otherCatId == null || _otherCatId!.isEmpty) {
      return const Text('Chat');
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CatDetailPage(catId: _otherCatId!),
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey[300],
            backgroundImage: _otherCatImageUrl != null
                ? NetworkImage(_otherCatImageUrl!)
                : null,
            child: _otherCatImageUrl == null
                ? const Icon(Icons.pets, size: 18)
                : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _otherCatName ?? 'Cat',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser!.uid;
    final stream = _db
        .collection('rooms')
        .doc(widget.roomId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: _buildHeaderTitle(context),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final msgs = snap.data!.docs;
                if (msgs.isEmpty) {
                  return const Center(
                    child: Text('Start the conversation with a message'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i].data();
                    final isMe = m['authorId'] == uid || m['senderUid'] == uid;
                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          (m['text'] as String?) ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
                    child: TextField(
                      controller: _ctrl,
                      decoration: InputDecoration(
                        hintText: _loadingActive
                            ? 'Preparing your cat profile…'
                            : 'Type a message…',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      enabled: !_sending,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 12, 12),
                  child: IconButton(
                    icon: _sending
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                    tooltip: _activeCatId == null
                        ? 'Send without cat profile (no active cat selected)'
                        : 'Send as selected cat',
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
