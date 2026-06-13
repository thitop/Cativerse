// lib/pages/cat_edit_page.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class CatEditPage extends StatefulWidget {
  final String catId;
  const CatEditPage({super.key, required this.catId});

  @override
  State<CatEditPage> createState() => _CatEditPageState();
}

class _CatEditPageState extends State<CatEditPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _otherBreedCtrl = TextEditingController(); // สำหรับกรอก breed อื่น ๆ

  String? _breed;
  String _gender = 'female';
  DateTime? _birthday;
  bool _availableForMatch = true;

  final _picker = ImagePicker();
  final List<String> _existingPhotos = [];
  final List<File> _newPhotos = [];

  bool _loading = true;
  bool _saving = false;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // Breed list + Other อยู่ล่างสุด
  final List<String> _breeds = const [
    'British Shorthair',
    'Persian',
    'Siamese',
    'Bengal',
    'Maine Coon',
    'Scottish Fold',
    'American Shorthair',
    'Ragdoll',
    'Sphynx',
    'Domestic Shorthair',
    'Domestic Longhair',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadCat();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _otherBreedCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _loadCat() async {
    final doc = await _db.collection('cats').doc(widget.catId).get();
    final data = doc.data();
    if (data != null) {
      _nameCtrl.text = (data['name'] ?? '').toString();
      _descCtrl.text = (data['description'] ?? '').toString();

      String? dbBreed = (data['breed'] as String?)?.trim();
      if (dbBreed != null && dbBreed.isNotEmpty) {
        if (_breeds.contains(dbBreed)) {
          // อยู่ในลิสต์ปกติ
          _breed = dbBreed;
          _otherBreedCtrl.clear();
        } else {
          // เป็นค่า custom => เลือก Other แล้วโชว์ในช่องกรอก
          _breed = 'Other';
          _otherBreedCtrl.text = dbBreed;
        }
      }

      final String? g =
          (data['gender'] as String?)?.toLowerCase().trim();
      if (g == 'male' || g == 'female') {
        _gender = g!;
      }

      final b = data['birthday'];
      if (b is Timestamp) {
        _birthday = b.toDate();
      }

      _availableForMatch =
          (data['isAvailableForMatch'] as bool?) ?? true;

      final photos = data['photos'];
      if (photos is List) {
        for (final p in photos) {
          if (p is String && p.trim().isNotEmpty) {
            _existingPhotos.add(p.trim());
          }
        }
      }
      if (_existingPhotos.isEmpty &&
          data['imageUrl'] is String &&
          (data['imageUrl'] as String).trim().isNotEmpty) {
        _existingPhotos.add((data['imageUrl'] as String).trim());
      }
    }

    setState(() {
      _loading = false;
    });
  }

  Future<void> _pickPhoto() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    setState(() {
      _newPhotos.add(File(x.path));
    });
  }

  Future<List<String>> _uploadNewPhotos() async {
    if (_newPhotos.isEmpty) return [];
    final storage = FirebaseStorage.instance;
    final List<String> urls = [];
    for (final file in _newPhotos) {
      final ref = storage
          .ref()
          .child('cat_photos')
          .child('${widget.catId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    // ตัดสินใจว่า breed จะเซฟค่าอะไร
    String? breedToSave;
    if (_breed == 'Other') {
      final t = _otherBreedCtrl.text.trim();
      if (t.isEmpty) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter the breed name for "Other".'),
          ),
        );
        return;
      }
      breedToSave = t;
    } else {
      breedToSave = _breed?.trim();
    }

    final newUrls = await _uploadNewPhotos();
    final allPhotos = [..._existingPhotos, ...newUrls];

    await _db.collection('cats').doc(widget.catId).update({
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'breed': breedToSave,
      'gender': _gender,
      'birthday': _birthday,
      'isAvailableForMatch': _availableForMatch,
      'photos': allPhotos,
      if (allPhotos.isNotEmpty) 'imageUrl': allPhotos.first,
    });

    setState(() => _saving = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cat profile saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit cat'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Photos
            Text(
              'Photos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final url in _existingPhotos)
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(url, fit: BoxFit.cover),
                    ),
                  ),
                for (final file in _newPhotos)
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(file, fit: BoxFit.cover),
                    ),
                  ),
                InkWell(
                  onTap: _pickPhoto,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: cs.surfaceVariant,
                    ),
                    child: const Icon(Icons.add_a_photo_outlined),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: _dec('Cat name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? 'Please enter the cat name'
                      : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: _dec('Description'),
            ),

            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _breeds.contains(_breed) ? _breed : null,
              decoration: _dec('Breed'),
              items: _breeds
                  .map(
                    (b) => DropdownMenuItem(
                      value: b,
                      child: Text(b),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _breed = v;
                  if (v != 'Other') {
                    _otherBreedCtrl.clear();
                  }
                });
              },
            ),

            // ถ้าเลือก Other ให้เปิดช่องให้พิมพ์เอง
            if (_breed == 'Other') ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _otherBreedCtrl,
                decoration: _dec('Custom breed'),
              ),
            ],

            const SizedBox(height: 12),
            Text(
              'Gender',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Female'),
                  selected: _gender == 'female',
                  onSelected: (_) => setState(() => _gender = 'female'),
                ),
                ChoiceChip(
                  label: const Text('Male'),
                  selected: _gender == 'male',
                  onSelected: (_) => setState(() => _gender = 'male'),
                ),
              ],
            ),

            const SizedBox(height: 12),
            InputDecorator(
              decoration: _dec('Birthday'),
              child: InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final initial = _birthday ?? DateTime(now.year - 1);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(2000),
                    lastDate: now,
                  );
                  if (picked != null) {
                    setState(() {
                      _birthday = picked;
                    });
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    _birthday == null
                        ? 'Tap to select'
                        : _fmt(_birthday!),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Available for matching'),
              value: _availableForMatch,
              onChanged: (v) => setState(() => _availableForMatch = v),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
