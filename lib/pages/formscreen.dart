// lib/pages/formscreen.dart 
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Breed option (top-level, not nested inside State)
class _BreedOption {
  final String id; // e.g. "beng"
  final String nameEn; // e.g. "Bengal"
  final String nameTh; // e.g. "เบงกอล"
  const _BreedOption(this.id, this.nameEn, this.nameTh);

  String get label => nameTh.isNotEmpty ? '$nameEn ($nameTh)' : nameEn;
}

/// Vaccine option + available doses
class _VaccineTypeOption {
  final String code; // e.g. "FVRCP"
  final String label; // e.g. "FVRCP — ไข้หัดแมว"
  final List<String> doses; // e.g. ["เข็มที่ 1", "เข็มที่ 2", "เข็มกระตุ้น"]

  const _VaccineTypeOption({
    required this.code,
    required this.label,
    required this.doses,
  });
}

// action ตอนปิด dialog วัคซีน
enum _VaccineDialogAction { save, delete }

// กำหนดจำนวนเข็มพื้นฐานของวัคซีนแต่ละตัว (จากแนวทางทั่วไป)
// ถ้าไม่พบ code ใน map นี้ จะ fallback เป็น ['เข็มที่ 1', 'เข็มกระตุ้น']
List<String> _dosesForVaccineCode(String rawCode) {
  final code = rawCode.toUpperCase();
  const map = <String, List<String>>{
    'FVRCP': ['เข็มที่ 1', 'เข็มที่ 2', 'เข็มที่ 3', 'เข็มกระตุ้น'],
    'FPV': ['เข็มที่ 1', 'เข็มที่ 2', 'เข็มกระตุ้น'],
    'FHV': ['เข็มที่ 1', 'เข็มที่ 2', 'เข็มกระตุ้น'],
    'FCV': ['เข็มที่ 1', 'เข็มที่ 2', 'เข็มกระตุ้น'],
    'RABIES': ['เข็มที่ 1', 'เข็มกระตุ้น'],
    'FELV': ['เข็มที่ 1', 'เข็มที่ 2', 'เข็มกระตุ้น'],
    'FIP': ['เข็มที่ 1', 'เข็มที่ 2'],
    'CORONA': ['เข็มที่ 1', 'เข็มที่ 2'],
    'DEWORM': ['ครั้งที่ 1', 'ครั้งที่ 2', 'ครั้งที่ 3', 'ครั้งที่ 4+'],
  };

  return map[code] ?? const ['เข็มที่ 1', 'เข็มกระตุ้น'];
}

class AddCatForm extends StatefulWidget {
  const AddCatForm({super.key});

  @override
  State<AddCatForm> createState() => _AddCatFormState();
}

class _AddCatFormState extends State<AddCatForm> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _otherBreedCtrl = TextEditingController();

  /// Store breed “English name”
  String? _breed;
  bool _breedIsOther = false;
  String _gender = 'female'; // male | female
  DateTime? _birthday;

  // ===== images (multi) =====
  final _picker = ImagePicker();
  final List<XFile> _picked = [];
  final List<Uint8List> _thumbs = []; // fast preview

  bool _saving = false;

  // ===== health draft =====
  final List<Map<String, dynamic>> _vaccines = [];
  final List<Map<String, dynamic>> _illness = [];
  final List<Map<String, dynamic>> _checkups = [];
  final List<Map<String, dynamic>> _treatments = [];
  final List<Map<String, dynamic>> _births = []; // will not be saved for males

  // ===== cache futures =====
  late Future<List<_BreedOption>> _breedsFuture;
  late Future<List<_VaccineTypeOption>> _vaccineTypesFuture;

  @override
  void initState() {
    super.initState();
    _breedsFuture = _loadBreeds();
    _vaccineTypesFuture = _loadVaccineTypes();
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _otherBreedCtrl.dispose();
    super.dispose();
  }

  // ===== Firestore helpers =====
  Future<List<_BreedOption>> _loadBreeds() async {
    final qs = await FirebaseFirestore.instance
        .collection('lookups')
        .doc('catBreeds')
        .collection('items')
        .orderBy(FieldPath.documentId)
        .get();

    // doc: { id, name_en, name_th }
    final list = qs.docs.map((d) {
      final m = d.data();
      final en = (m['name_en'] ?? '').toString().trim();
      final th = (m['name_th'] ?? '').toString().trim();
      final id = (m['id'] ?? d.id).toString().trim();
      return _BreedOption(id, en.isNotEmpty ? en : id, th);
    }).toList();

    // ย้าย "Other" ไปไว้ล่างสุด
    bool isOther(_BreedOption b) {
      final id = b.id.toLowerCase();
      final en = b.nameEn.toLowerCase();
      final th = b.nameTh.toLowerCase();
      return id == 'other' ||
          en == 'other' ||
          en.contains('other') ||
          th.contains('อื่น');
    }

    final normal = <_BreedOption>[];
    final others = <_BreedOption>[];
    for (final b in list) {
      if (isOther(b)) {
        others.add(b);
      } else {
        normal.add(b);
      }
    }
    return [...normal, ...others];
  }

  Future<List<_VaccineTypeOption>> _loadVaccineTypes() async {
    final qs = await FirebaseFirestore.instance
        .collection('lookups')
        .doc('vaccineTypes')
        .collection('items')
        .orderBy(FieldPath.documentId)
        .get();

    // doc: { code, name/desc }
    return qs.docs.map((d) {
      final m = d.data();
      final code = (m['code'] ?? d.id).toString().trim();
      final desc = (m['desc'] ?? m['name'] ?? '').toString().trim();
      final label = desc.isNotEmpty ? '$code — $desc' : code;
      final doses = _dosesForVaccineCode(code);
      return _VaccineTypeOption(code: code, label: label, doses: doses);
    }).toList();
  }

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  // ===== image picker =====
  Future<void> _pickMultiImages() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    for (final f in files) {
      final bytes = await f.readAsBytes();
      _picked.add(f);
      _thumbs.add(bytes);
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 1, now.month, now.day),
      firstDate: DateTime(now.year - 30),
      lastDate: now,
    );
    if (d != null) setState(() => _birthday = d);
  }

  // ========== vaccines: add / edit / delete ==========

  Future<void> _addVaccine() async {
    await _openVaccineDialog(); // เพิ่มใหม่
  }

  Future<void> _editVaccine(int index) async {
    await _openVaccineDialog(editIndex: index); // แก้ของเดิม
  }

  Future<void> _openVaccineDialog({int? editIndex}) async {
    final types = await _vaccineTypesFuture;
    if (types.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No vaccine types found in lookups/vaccineTypes/items'),
        ),
      );
      return;
    }

    _VaccineTypeOption? selectedType;
    String? selectedDose;
    DateTime date = DateTime.now();
    final notes = TextEditingController();
    String? error;

    // โหลดค่าเดิมในโหมดแก้ไข
    if (editIndex != null) {
      final current = _vaccines[editIndex];
      final code = (current['vaccineCode'] ?? '').toString();
      selectedType = types.firstWhere(
        (t) => t.code.toUpperCase() == code.toUpperCase(),
        orElse: () => types.first,
      );
      selectedDose = (current['dose'] ?? '') as String?;
      final ts = current['date'] as Timestamp?;
      if (ts != null) date = ts.toDate();
      notes.text = (current['notes'] ?? '').toString();
    }

    final action = await showDialog<_VaccineDialogAction>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title:
              Text(editIndex == null ? 'Add vaccination' : 'Edit vaccination'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<_VaccineTypeOption>(
                  isExpanded: true, // ✅ กัน overflow แนวนอน
                  decoration: const InputDecoration(labelText: 'Vaccine type'),
                  value: selectedType,
                  items: types
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setSt(() {
                      selectedType = v;
                      selectedDose = null; // reset เมื่อเปลี่ยนชนิดวัคซีน
                    });
                  },
                ),
                if (selectedType != null)
                  DropdownButtonFormField<String>(
                    isExpanded: true, // ✅ กัน overflow แนวนอน
                    decoration: const InputDecoration(labelText: 'Dose'),
                    value: selectedDose,
                    items: selectedType!.doses
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(d),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setSt(() => selectedDose = v),
                  ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Date: ${_fmt(date)}')),
                    IconButton(
                      icon: const Icon(Icons.date_range),
                      onPressed: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(DateTime.now().year - 10),
                          lastDate: DateTime.now(),
                        );
                        if (p != null) setSt(() => date = p);
                      },
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (editIndex != null)
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, _VaccineDialogAction.delete),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedType == null || selectedDose == null) {
                  setSt(() =>
                      error = 'กรุณาเลือกชนิดวัคซีนและเข็มที่ให้ครบถ้วน');
                  return;
                }
                Navigator.pop(ctx, _VaccineDialogAction.save);
              },
              child: Text(editIndex == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;

    // ลบ
    if (action == _VaccineDialogAction.delete && editIndex != null) {
      setState(() => _vaccines.removeAt(editIndex));
      return;
    }

    // บันทึก
    if (action == _VaccineDialogAction.save &&
        selectedType != null &&
        selectedDose != null) {
      final map = <String, dynamic>{
        'date': Timestamp.fromDate(date),
        'vaccineCode': selectedType!.code,
        'vaccineLabel': selectedType!.label,
        'dose': selectedDose,
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        // สำรอง key เดิมไว้ เผื่อหน้าอื่นใช้
        'type': selectedType!.label,
      };

      setState(() {
        if (editIndex == null) {
          _vaccines.add(map);
        } else {
          _vaccines[editIndex] = map;
        }
      });
    }
  }

  // ========== health inline: อื่น ๆ ==========
  Future<void> _addIllness() async {
    final dC = TextEditingController();
    final tC = TextEditingController();
    final nC = TextEditingController();
    DateTime date = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Add illness record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dC,
                  decoration: const InputDecoration(labelText: 'Diagnosis'),
                ),
                TextField(
                  controller: tC,
                  decoration: const InputDecoration(labelText: 'Treatment'),
                ),
                TextField(
                  controller: nC,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Date: ${_fmt(date)}')),
                    IconButton(
                      icon: const Icon(Icons.date_range),
                      onPressed: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(DateTime.now().year - 10),
                          lastDate: DateTime.now(),
                        );
                        if (p != null) setSt(() => date = p);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      setState(() {
        _illness.add({
          'date': Timestamp.fromDate(date),
          'diagnosis': dC.text.trim(),
          'treatment': tC.text.trim().isEmpty ? null : tC.text.trim(),
          'notes': nC.text.trim().isEmpty ? null : nC.text.trim(),
        });
      });
    }
  }

  Future<void> _addCheckup() async {
    final cC = TextEditingController();
    final wC = TextEditingController();
    final nC = TextEditingController();
    DateTime date = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Add health checkup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cC,
                  decoration: const InputDecoration(
                    labelText: 'Clinic / animal hospital',
                  ),
                ),
                TextField(
                  controller: wC,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Weight (kg)'),
                ),
                TextField(
                  controller: nC,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Date: ${_fmt(date)}')),
                    IconButton(
                      icon: const Icon(Icons.date_range),
                      onPressed: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(DateTime.now().year - 10),
                          lastDate: DateTime.now(),
                        );
                        if (p != null) setSt(() => date = p);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      setState(() {
        _checkups.add({
          'date': Timestamp.fromDate(date),
          'clinic': cC.text.trim().isEmpty ? null : cC.text.trim(),
          'weightKg': double.tryParse(wC.text.trim()),
          'notes': nC.text.trim().isNotEmpty ? nC.text.trim() : null,
        });
      });
    }
  }

  Future<void> _addTreatment() async {
    final nameCtrl = TextEditingController();
    final medCtrl = TextEditingController();
    final doseCtrl = TextEditingController();
    final clinicCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime date = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Add treatment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Treatment name'),
                ),
                TextField(
                  controller: medCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Medicine / supplies',
                  ),
                ),
                TextField(
                  controller: doseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dose / frequency',
                  ),
                ),
                TextField(
                  controller: clinicCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Clinic / animal hospital',
                  ),
                ),
                TextField(
                  controller: noteCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Additional notes'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Date: ${_fmt(date)}')),
                    IconButton(
                      icon: const Icon(Icons.date_range),
                      onPressed: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(DateTime.now().year - 10),
                          lastDate: DateTime.now(),
                        );
                        if (p != null) setSt(() => date = p);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    setState(() {
      _treatments.add({
        'name': nameCtrl.text.trim(),
        'medicine': medCtrl.text.trim(),
        'dose': doseCtrl.text.trim(),
        'clinic': clinicCtrl.text.trim(),
        'note': noteCtrl.text.trim(),
        'date': Timestamp.fromDate(date),
      });
    });
  }

  Future<void> _addBirth() async {
    if (_gender == 'male') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Male cats cannot have birth records'),
        ),
      );
      return;
    }

    final total = TextEditingController();
    final notes = TextEditingController();
    DateTime date = DateTime.now();
    bool healthyAll = true;
    bool other = false;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Add birth record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Date: ${_fmt(date)}')),
                    IconButton(
                      icon: const Icon(Icons.date_range),
                      onPressed: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(DateTime.now().year - 10),
                          lastDate: DateTime.now(),
                        );
                        if (p != null) setSt(() => date = p);
                      },
                    ),
                  ],
                ),
                TextField(
                  controller: total,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Total kittens',
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: healthyAll,
                  onChanged: (v) => setSt(() => healthyAll = v ?? true),
                  title: const Text('All kittens healthy'),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: other,
                  onChanged: (v) => setSt(() => other = v ?? false),
                  title: const Text('Other (specify in notes)'),
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final t = int.tryParse(total.text.trim()) ?? 0;
                if (t <= 0) {
                  setSt(
                    () => error =
                        'Please enter a valid total number of kittens.',
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      setState(() {
        _births.add({
          'date': Timestamp.fromDate(date),
          'kittens': int.tryParse(total.text.trim()) ?? 0,
          'healthyAll': healthyAll,
          'other': other,
          'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        });
      });
    }
  }

  // ========== save ==========
  Future<void> _save() async {
    if (_saving) return;

    if (_picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเลือกรูปแมวอย่างน้อย 1 รูปก่อนบันทึก'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_gender == 'male' && _births.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('แมวเพศผู้ไม่สามารถมีประวัติการคลอดได้'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // ✅ โหลดตำแหน่งล่าสุดของผู้ใช้จาก users/{uid}
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      Map<String, dynamic>? loc =
          userSnap.data()?['location'] as Map<String, dynamic>?;

      final double? ownerLat =
          (loc?['lat'] as num?)?.toDouble(); // ถ้าไม่มีจะเป็น null
      final double? ownerLng =
          (loc?['lng'] as num?)?.toDouble(); // ถ้าไม่มีจะเป็น null

      // ===== อัปโหลดรูปทั้งหมด =====
      final storage = FirebaseStorage.instance;
      final List<String> imageUrls = [];
      for (int i = 0; i < _picked.length; i++) {
        final f = _picked[i];
        final ref = storage.ref(
          'cats/$uid/${DateTime.now().millisecondsSinceEpoch}-$i-${f.name}',
        );
        await ref.putFile(File(f.path));
        imageUrls.add(await ref.getDownloadURL());
      }

      // กำหนดค่าสายพันธุ์ที่จะบันทึก
      final normalizedOther = _otherBreedCtrl.text.trim();
      final breedToSave =
          _breedIsOther && normalizedOther.isNotEmpty ? normalizedOther : (_breed ?? '');

      // ===== สร้างเอกสารแมว =====
      final catRef =
          await FirebaseFirestore.instance.collection('cats').add({
        'ownerId': uid,
        'name': _name.text.trim(),
        'breed': breedToSave, // ชื่อสายพันธุ์ที่ใช้จริง (ถ้า other จะเป็นค่าที่ผู้ใช้กรอก)
        'breedRaw': _breed ?? '', // เก็บตัวเลือกดรอปดาวเดิมไว้เผื่อใช้ทีหลัง
        'gender': _gender,
        'birthday':
            _birthday != null ? Timestamp.fromDate(_birthday!) : null,
        'description': _desc.text.trim(),
        'imageUrls': imageUrls,
        'imageUrl':
            imageUrls.isNotEmpty ? imageUrls.first : null, // สำหรับหน้าเก่า
        'createdAt': FieldValue.serverTimestamp(),

        // ✅ เก็บตำแหน่งเจ้าของลงแมวตั้งแต่ตอนสร้างเลย
        'ownerLat': ownerLat,
        'ownerLng': ownerLng,
      });

      // ===== เขียนประวัติสุขภาพ (subcollections) =====
      final batch = FirebaseFirestore.instance.batch();
      void addAll(String col, List<Map<String, dynamic>> list) {
        for (final m in list) {
          batch.set(catRef.collection(col).doc(), m);
        }
      }

      addAll('vaccineRecords', _vaccines);
      addAll('illnessRecords', _illness);
      addAll('checkupRecords', _checkups);
      addAll('treatmentRecords', _treatments);
      if (_gender != 'male') addAll('birthRecords', _births);

      await batch.commit();

      // ===== ตั้ง activeCatId อัตโนมัติถ้ายังไม่มี =====
      final userDoc =
          FirebaseFirestore.instance.collection('users').doc(uid);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(userDoc);
        final data = (snap.data() ?? <String, dynamic>{});
        final currentActive = (data['activeCatId'] as String?) ?? '';
        if (currentActive.isEmpty) {
          tx.set(
            userDoc,
            {'activeCatId': catRef.id},
            SetOptions(merge: true),
          );
        }
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add cat profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ==== Images — single button, multi-select ====
            InkWell(
              onTap: _pickMultiImages,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(.6),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library, size: 36),
                      SizedBox(height: 6),
                      Text('Select/add photos (multiple allowed)'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_thumbs.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < _thumbs.length; i++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _thumbs[i],
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _thumbs.removeAt(i);
                                _picked.removeAt(i);
                              });
                            },
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            const Divider(height: 24),

            // Name
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Cat name'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter the cat name'
                  : null,
            ),
            const SizedBox(height: 12),

            // Breed: show “English (Thai)” + Other field
            FutureBuilder<List<_BreedOption>>(
              future: _breedsFuture,
              builder: (c, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator(minHeight: 2);
                }
                if (s.hasError) {
                  return Text(
                    'Failed to load breeds: ${s.error}',
                    style: const TextStyle(color: Colors.red),
                  );
                }
                final breeds = s.data ?? const <_BreedOption>[];
                return DropdownButtonFormField<String>(
                  value: _breed,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Breed'),
                  items: breeds
                      .map(
                        (b) => DropdownMenuItem(
                          value: b.nameEn, // store English name
                          child: Text(
                            b.label, // show English (Thai)
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _breed = v;
                      _breedIsOther = false;
                      // เช็คว่า option ที่เลือกคือ Other หรือไม่
                      for (final b in breeds) {
                        if (b.nameEn == v) {
                          final id = b.id.toLowerCase();
                          final en = b.nameEn.toLowerCase();
                          final th = b.nameTh.toLowerCase();
                          _breedIsOther = id == 'other' ||
                              en == 'other' ||
                              en.contains('other') ||
                              th.contains('อื่น');
                          break;
                        }
                      }
                      if (!_breedIsOther) {
                        _otherBreedCtrl.clear();
                      }
                    });
                  },
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please select a breed';
                    }
                    if (_breedIsOther &&
                        _otherBreedCtrl.text.trim().isEmpty) {
                      return 'Please specify the breed';
                    }
                    return null;
                  },
                );
              },
            ),
            if (_breedIsOther) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _otherBreedCtrl,
                decoration: const InputDecoration(
                  labelText: 'Specify breed',
                  hintText: 'เช่น Bengal mix, Persian ฯลฯ',
                ),
                validator: (v) {
                  if (_breedIsOther && (v == null || v.trim().isEmpty)) {
                    return 'กรุณาระบุสายพันธุ์';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 12),

            // Gender
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
              ],
              onChanged: (v) => setState(() => _gender = v ?? 'female'),
            ),
            const SizedBox(height: 12),

            // Birthday
            InkWell(
              onTap: _pickBirthday,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Birthday (tap to select)',
                ),
                child: Text(_birthday != null ? _fmt(_birthday!) : ''),
              ),
            ),
            const SizedBox(height: 12),

            // Description
            TextFormField(
              controller: _desc,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const Divider(height: 32),

            // ===== Health records =====
            Text(
              'Health records',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),

            // ---- Vaccines (จัดกลุ่ม + แตะเพื่อแก้ไขได้) ----
            _VaccineCard(
              title: 'Vaccinations',
              vaccines: _vaccines,
              onAdd: _addVaccine,
              onEdit: _editVaccine,
            ),
            const SizedBox(height: 12),

            _HealthCard(
              title: 'Illness',
              emptyText: 'No records yet',
              items: _illness
                  .map(
                    (e) =>
                        '${DateFormat('yyyy-MM-dd').format((e['date'] as Timestamp).toDate())} • ${e['diagnosis']}${e['treatment'] != null ? ' • Rx: ${e['treatment']}' : ''}${e['notes'] != null ? ' • ${e['notes']}' : ''}',
                  )
                  .toList(),
              onAdd: _addIllness,
            ),
            const SizedBox(height: 12),

            _HealthCard(
              title: 'Checkups',
              emptyText: 'No records yet',
              items: _checkups
                  .map(
                    (e) =>
                        '${DateFormat('yyyy-MM-dd').format((e['date'] as Timestamp).toDate())}'
                        '${e['clinic'] != null ? ' • ${e['clinic']}' : ''}'
                        '${e['weightKg'] != null ? ' • ${e['weightKg']} kg' : ''}'
                        '${e['notes'] != null ? ' • ${e['notes']}' : ''}',
                  )
                  .toList(),
              onAdd: _addCheckup,
            ),
            const SizedBox(height: 12),

            _HealthCard(
              title: 'Treatments',
              emptyText: 'No records yet',
              items: _treatments.map((e) {
                final dt = DateFormat('yyyy-MM-dd')
                    .format((e['date'] as Timestamp).toDate());
                final parts = <String>[
                  dt,
                  if ((e['clinic'] ?? '').toString().isNotEmpty)
                    e['clinic'],
                  if ((e['medicine'] ?? '').toString().isNotEmpty)
                    'Medicine: ${e['medicine']}',
                  if ((e['dose'] ?? '').toString().isNotEmpty)
                    'Dose: ${e['dose']}',
                  if ((e['note'] ?? '').toString().isNotEmpty) e['note'],
                ];
                final name = (e['name'] ?? 'Treatment').toString();
                return '$name • ${parts.join(' • ')}';
              }).toList(),
              onAdd: _addTreatment,
            ),
            const SizedBox(height: 12),

            _HealthCard(
              title: 'Births',
              emptyText: 'No records yet',
              items: _births
                  .map(
                    (e) =>
                        '${DateFormat('yyyy-MM-dd').format((e['date'] as Timestamp).toDate())} • Total ${e['kittens']} kittens'
                        '${(e['healthyAll'] ?? true) ? ' • All healthy' : ''}'
                        '${(e['other'] ?? false) ? ' • Other' : ''}'
                        '${e['notes'] != null ? ' • ${e['notes']}' : ''}',
                  )
                  .toList(),
              onAdd: _gender == 'male' ? null : _addBirth,
              disabledHint: 'Female cats only',
            ),
            const SizedBox(height: 24),

            SafeArea(
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<String> items;
  final Future<void> Function()? onAdd;
  final String? disabledHint;

  const _HealthCard({
    required this.title,
    required this.emptyText,
    required this.items,
    this.onAdd,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final canAdd = onAdd != null;
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: canAdd ? onAdd : null,
                  icon: const Icon(Icons.add),
                  tooltip: canAdd ? 'Add' : (disabledHint ?? ''),
                )
              ],
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  emptyText,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
            for (final t in items) ...[
              const Divider(height: 8),
              Text(t),
            ],
          ],
        ),
      ),
    );
  }
}

// การ์ดเฉพาะสำหรับวัคซีน: แสดงเป็น “ชื่อวัคซีน -> list ของเข็ม”
class _VaccineCard extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> vaccines;
  final Future<void> Function() onAdd;
  final Future<void> Function(int index) onEdit;

  const _VaccineCard({
    required this.title,
    required this.vaccines,
    required this.onAdd,
    required this.onEdit,
  });

  void _showVaccineGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        Widget buildCell(String text, {bool header = false}) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: header ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        }

        TableRow buildRow(String age, String vaccine, String program,
            {bool header = false}) {
          return TableRow(
            children: [
              buildCell(age, header: header),
              buildCell(vaccine, header: header),
              buildCell(program, header: header),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'เราควรฉีดวัคซีนแมวเมื่อไรดี?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'การฉีดวัคซีนแมวสามารถเริ่มได้ตั้งแต่ตอนเป็นลูกแมว โดยส่วนใหญ่จะต้องฉีดทั้งหมด 3 เข็มในปีแรก '
                  'และฉีดกระตุ้น 1 เข็มในปีถัด ๆ ไป ตารางด้านล่างเป็นตัวอย่างโปรแกรมการฉีดวัคซีนพื้นฐาน',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),

                // ----- ตารางตามรูป -----
                Table(
                  border: TableBorder.all(
                    color: Colors.grey,
                    width: 0.7,
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(1.1), // อายุแมว
                    1: FlexColumnWidth(1.8), // วัคซีน
                    2: FlexColumnWidth(1.1), // โปรแกรมการฉีด
                  },
                  children: [
                    // header
                    buildRow('อายุแมว', 'วัคซีน', 'โปรแกรมการฉีด', header: true),

                    buildRow('8 สัปดาห์ขึ้นไป', 'วัคซีนรวมแมว (หลัก)', 'เข็มที่ 1'),
                    buildRow('12–14 สัปดาห์', 'วัคซีนเอดส์แมว (ทางเลือก)', 'เข็มที่ 1'),
                    buildRow('12 สัปดาห์', 'วัคซีนรวมแมว (หลัก)', 'เข็มที่ 2'),
                    buildRow('12 สัปดาห์', 'วัคซีนลิวคีเมีย (ทางเลือก)', 'เข็มที่ 1'),
                    buildRow('12 สัปดาห์', 'วัคซีนพิษสุนัขบ้า (หลัก)',
                        'เข็มที่ 1 และฉีดกระตุ้นซ้ำทุกปี'),
                    buildRow('12–14 สัปดาห์', 'วัคซีนคลาไมเดีย (ทางเลือก)', 'เข็มที่ 1'),
                    buildRow('14 สัปดาห์', 'วัคซีนลิวคีเมีย (ทางเลือก)',
                        'เข็มที่ 2 และฉีดกระตุ้นซ้ำทุกปี'),
                    buildRow('16 สัปดาห์',
                        'วัคซีนเยื่อบุช่องท้องอักเสบ (ทางเลือก)', 'เข็มที่ 1'),
                  ],
                ),

                const SizedBox(height: 12),
                const Text(
                  'หมายเหตุ: ตารางนี้เป็นแนวทางทั่วไปเท่านั้น ช่วงอายุที่เริ่มฉีด จำนวนเข็ม และการกระตุ้นซ้ำ '
                  'ควรปรึกษาสัตวแพทย์ทุกครั้งให้เหมาะกับสุขภาพและไลฟ์สไตล์ของน้องแมวแต่ละตัว',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),

                // 🔹 ปุ่มเครื่องหมายคำถามเล็กๆ
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 20),
                  tooltip: 'แนะนำวัคซีนที่ควรฉีด',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showVaccineGuide(context),
                ),

                const Spacer(),

                // ปุ่มเพิ่มวัคซีนเดิม
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add',
                ),
              ],
            ),
            if (vaccines.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No records yet',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
            if (vaccines.isNotEmpty) ...[
              const SizedBox(height: 4),
              ..._buildGrouped(context),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGrouped(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final v in vaccines) {
      final label = (v['vaccineLabel'] ?? v['type'] ?? 'Unknown').toString();
      grouped.putIfAbsent(label, () => []).add(v);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final widgets = <Widget>[];

    for (int g = 0; g < entries.length; g++) {
      final entry = entries[g];
      final label = entry.key;
      final list = entry.value;

      if (g > 0) {
        widgets.add(const Divider(height: 16));
      }

      widgets.add(Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ));
      widgets.add(const SizedBox(height: 4));

      // sort ตามวันที่
      list.sort((a, b) {
        final ad = (a['date'] as Timestamp?)?.toDate() ?? DateTime(1900);
        final bd = (b['date'] as Timestamp?)?.toDate() ?? DateTime(1900);
        return ad.compareTo(bd);
      });

      for (final v in list) {
        final index = vaccines.indexOf(v);
        final dt = DateFormat('yyyy-MM-dd')
            .format((v['date'] as Timestamp).toDate());
        final dose = (v['dose'] ?? '').toString();
        final notes = (v['notes'] ?? '').toString();

        String line = dt;
        if (dose.isNotEmpty) line += ' • $dose';
        if (notes.isNotEmpty) line += ' • $notes';

        widgets.add(
          InkWell(
            onTap: () => onEdit(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(line)),
                ],
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }
}
