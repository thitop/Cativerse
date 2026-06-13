// lib/pages/cat_health_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/* -------------------- Vaccine types helper -------------------- */

class _VaccineTypeOption {
  final String code; // e.g. "FVRCP"
  final String label; // e.g. "FVRCP — วัคซีนรวม 3 โรค"
  final List<String> doses; // e.g. ["เข็มที่ 1", "เข็มที่ 2", "เข็มกระตุ้น"]

  const _VaccineTypeOption({
    required this.code,
    required this.label,
    required this.doses,
  });
}

enum _VaccineDialogAction { save, delete }

// จำนวนเข็มพื้นฐานต่อวัคซีนแต่ละตัว
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

Future<List<_VaccineTypeOption>> _fetchVaccineTypes() async {
  final qs = await FirebaseFirestore.instance
      .collection('lookups')
      .doc('vaccineTypes')
      .collection('items')
      .get();

  return qs.docs.map((d) {
    final m = d.data();
    final code = (m['code'] ?? d.id).toString().trim();
    final desc = (m['desc'] ?? m['name'] ?? '').toString().trim();
    final label = desc.isNotEmpty ? '$code — $desc' : code;
    return _VaccineTypeOption(
      code: code,
      label: label,
      doses: _dosesForVaccineCode(code),
    );
  }).toList();
}

/* -------------------- Small utilities -------------------- */

InputDecoration _fieldDec(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

Future<bool> _confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $what'),
      content: const Text('Are you sure you want to delete this record?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}

/* -------------------- Page -------------------- */

class CatHealthPage extends StatelessWidget {
  final String catId;
  final int initialTab; // receive initial tab index from other pages

  const CatHealthPage({
    super.key,
    required this.catId,
    this.initialTab = 0,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      initialIndex: initialTab.clamp(0, 4).toInt(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Health records'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Vaccines'),
              Tab(text: 'Illness'),
              Tab(text: 'Checkups'),
              Tab(text: 'Treatments'),
              Tab(text: 'Births'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _VaccinesTab(catId: catId),
            _IllnessTab(catId: catId),
            _CheckupTab(catId: catId),
            _TreatmentTab(catId: catId),
            _BirthTab(catId: catId),
          ],
        ),
      ),
    );
  }
}

/* ---------- List + Add button wrapper ---------- */
class _ListWithAdd extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final Widget Function(DocumentSnapshot<Map<String, dynamic>>) itemBuilder;
  final Future<void> Function() onAdd;

  const _ListWithAdd({
    required this.stream,
    required this.itemBuilder,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (c, s) {
              if (s.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) {
                return Center(child: Text('Error: ${s.error}'));
              }
              final docs = s.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No records yet.'));
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (c, i) => itemBuilder(docs[i]),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add record'),
            ),
          ),
        ),
      ],
    );
  }
}

/* -------------------- Vaccines -------------------- */
class _VaccinesTab extends StatelessWidget {
  final String catId;
  const _VaccinesTab({required this.catId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('cats')
        .doc(catId)
        .collection('vaccineRecords');

    return _ListWithAdd(
      stream: col.orderBy('date', descending: true).snapshots(),
      itemBuilder: (d) {
        final x = d.data()!;
        final date =
            (x['date'] as Timestamp?)?.toDate().toString().split(' ').first ??
                '';
        final label =
            (x['vaccineLabel'] ?? x['type'] ?? '').toString(); // รองรับข้อมูลเก่า
        final dose = (x['dose'] ?? '').toString();
        final notes = (x['notes'] ?? '').toString();
        final parts = <String>[
          date,
          if (dose.isNotEmpty) dose,
          if (notes.isNotEmpty) notes,
        ];

        return ListTile(
          title: Text(
            label.isEmpty ? '-' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            parts.join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _openVaccineDialog(
            context: context,
            col: col,
            existing: d,
          ),
          onLongPress: () async {
            if (await _confirmDelete(context, 'vaccine record')) {
              await d.reference.delete();
            }
          },
        );
      },
      onAdd: () => _openVaccineDialog(
        context: context,
        col: col,
      ),
    );
  }

  Future<void> _openVaccineDialog({
    required BuildContext context,
    required CollectionReference<Map<String, dynamic>> col,
    DocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    final types = await _fetchVaccineTypes();
    if (types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No vaccine types found in lookups/vaccineTypes/items'),
        ),
      );
      return;
    }

    _VaccineTypeOption? selectedType;
    String? selectedDose;
    DateTime date = DateTime.now();
    final notesCtrl = TextEditingController();
    String? error;

    if (existing != null) {
      final x = existing.data()!;
      final label =
          (x['vaccineLabel'] ?? x['type'] ?? '').toString();
      final code = (x['vaccineCode'] ?? '').toString();
      final dose = (x['dose'] ?? '').toString();
      final ts = x['date'] as Timestamp?;
      date = ts?.toDate() ?? date;
      notesCtrl.text = (x['notes'] ?? '').toString();

      selectedType = types.firstWhere(
        (t) =>
            t.code.toUpperCase() == code.toUpperCase() ||
            t.label == label,
        orElse: () => types.first,
      );
      selectedDose = dose.isEmpty ? null : dose;
    }

    final action = await showDialog<_VaccineDialogAction>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Add vaccine' : 'Edit vaccine'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<_VaccineTypeOption>(
                  isExpanded: true, // กัน overflow แนวนอน
                  value: selectedType,
                  items: types
                      .map(
                        (e) => DropdownMenuItem<_VaccineTypeOption>(
                          value: e,
                          child: Text(
                            e.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  selectedItemBuilder: (ctx) => types
                      .map(
                        (e) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            e.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setSt(() {
                      selectedType = v;
                      selectedDose = null;
                    });
                  },
                  decoration: _fieldDec('Vaccine type').copyWith(
                    contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14)
                        .copyWith(right: 40),
                  ),
                  icon: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.arrow_drop_down_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                if (selectedType != null)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: selectedDose,
                    items: selectedType!.doses
                        .map(
                          (d) => DropdownMenuItem<String>(
                            value: d,
                            child: Text(d),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setSt(() => selectedDose = v),
                    decoration: _fieldDec('Dose'),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: _fieldDec('Notes'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Date: ${date.toString().split(' ').first}',
                      ),
                    ),
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
            if (existing != null)
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, _VaccineDialogAction.delete),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedType == null || selectedDose == null) {
                  setSt(() => error =
                      'กรุณาเลือกชนิดวัคซีนและเข็มที่ให้ครบถ้วน');
                  return;
                }
                Navigator.pop(ctx, _VaccineDialogAction.save);
              },
              child: Text(existing == null ? 'Save' : 'Update'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;

    if (action == _VaccineDialogAction.delete && existing != null) {
      await existing.reference.delete();
      return;
    }

    if (action == _VaccineDialogAction.save &&
        selectedType != null &&
        selectedDose != null) {
      final data = {
        'date': Timestamp.fromDate(date),
        'vaccineCode': selectedType!.code,
        'vaccineLabel': selectedType!.label,
        'dose': selectedDose,
        'notes': notesCtrl.text.trim().isEmpty
            ? null
            : notesCtrl.text.trim(),
        'type': selectedType!.label, // สำรองให้หน้าเก่าใช้
      };

      if (existing == null) {
        await col.add(data);
      } else {
        await existing.reference.update(data);
      }
    }
  }
}

/* -------------------- Illness -------------------- */
class _IllnessTab extends StatelessWidget {
  final String catId;
  const _IllnessTab({required this.catId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('cats')
        .doc(catId)
        .collection('illnessRecords');

    return _ListWithAdd(
      stream: col.orderBy('date', descending: true).snapshots(),
      itemBuilder: (d) {
        final x = d.data()!;
        final date =
            (x['date'] as Timestamp?)?.toDate().toString().split(' ').first ??
                '';
        final dx = (x['diagnosis'] ?? '').toString();
        final rx = (x['treatment'] ?? '').toString();
        final notes = (x['notes'] ?? '').toString();
        final parts = <String>[
          date,
          if (rx.isNotEmpty) 'Rx: $rx',
          if (notes.isNotEmpty) notes,
        ];
        return ListTile(
          title: Text(dx.isEmpty ? '-' : dx),
          subtitle: Text(parts.join(' • ')),
          onLongPress: () => d.reference.delete(),
        );
      },
      onAdd: () async {
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
                        decoration: _fieldDec('Diagnosis')),
                    TextField(
                        controller: tC,
                        decoration: _fieldDec('Treatment')),
                    TextField(
                        controller: nC,
                        decoration: _fieldDec('Notes')),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: Text(
                                'Date: ${date.toString().split(' ').first}')),
                        IconButton(
                          icon: const Icon(Icons.date_range),
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate:
                                  DateTime(DateTime.now().year - 10),
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
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save')),
              ],
            ),
          ),
        );

        if (ok == true) {
          await col.add({
            'date': Timestamp.fromDate(date),
            'diagnosis': dC.text.trim(),
            'treatment':
                tC.text.trim().isEmpty ? null : tC.text.trim(),
            'notes': nC.text.trim().isEmpty ? null : nC.text.trim(),
          });
        }
      },
    );
  }
}

/* -------------------- Checkups -------------------- */
class _CheckupTab extends StatelessWidget {
  final String catId;
  const _CheckupTab({required this.catId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('cats')
        .doc(catId)
        .collection('checkupRecords');

    return _ListWithAdd(
      stream: col.orderBy('date', descending: true).snapshots(),
      itemBuilder: (d) {
        final x = d.data()!;
        final date =
            (x['date'] as Timestamp?)?.toDate().toString().split(' ').first ??
                '';
        final clinic = (x['clinic'] ?? '').toString();
        final weight = (x['weightKg'] as num?)?.toString();
        final notes = (x['notes'] ?? '').toString();
        final parts = <String>[
          if (clinic.isNotEmpty) clinic,
          if (weight != null) '$weight kg',
          if (notes.isNotEmpty) notes,
        ];
        return ListTile(
          title: Text(date),
          subtitle: Text(parts.join(' • ')),
          onLongPress: () => d.reference.delete(),
        );
      },
      onAdd: () async {
        final cC = TextEditingController();
        final wC = TextEditingController();
        final nC = TextEditingController();
        DateTime date = DateTime.now();

        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setSt) => AlertDialog(
              title: const Text('Add checkup'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                        controller: cC,
                        decoration: _fieldDec('Clinic / hospital')),
                    TextField(
                      controller: wC,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDec('Weight (kg)'),
                    ),
                    TextField(
                        controller: nC,
                        decoration: _fieldDec('Notes')),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: Text(
                                'Date: ${date.toString().split(' ').first}')),
                        IconButton(
                          icon: const Icon(Icons.date_range),
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate:
                                  DateTime(DateTime.now().year - 10),
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
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );

        if (ok == true) {
          await col.add({
            'date': Timestamp.fromDate(date),
            'clinic': cC.text.trim().isEmpty ? null : cC.text.trim(),
            'weightKg': double.tryParse(wC.text.trim()),
            'notes': nC.text.trim().isEmpty ? null : nC.text.trim(),
          });
        }
      },
    );
  }
}

/* -------------------- Treatments -------------------- */
class _TreatmentTab extends StatelessWidget {
  final String catId;
  const _TreatmentTab({required this.catId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('cats')
        .doc(catId)
        .collection('treatmentRecords');

    return _ListWithAdd(
      stream: col.orderBy('date', descending: true).snapshots(),
      itemBuilder: (d) {
        final x = d.data()!;
        final date =
            (x['date'] as Timestamp?)?.toDate().toString().split(' ').first ??
                '';
        final name = (x['name'] ?? 'Treatment').toString();
        final med = (x['medicine'] ?? '').toString();
        final dose = (x['dose'] ?? '').toString();
        final clinic = (x['clinic'] ?? '').toString();
        final note = (x['note'] ?? x['notes'] ?? '').toString();
        final parts = <String>[
          date,
          if (clinic.isNotEmpty) clinic,
          if (med.isNotEmpty) 'Medicine: $med',
          if (dose.isNotEmpty) 'Dose: $dose',
          if (note.isNotEmpty) note,
        ];
        return ListTile(
          title: Text(name),
          subtitle: Text(parts.join(' • ')),
          onLongPress: () => d.reference.delete(),
        );
      },
      onAdd: () async {
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
                        decoration: _fieldDec('Treatment name')),
                    TextField(
                        controller: medCtrl,
                        decoration:
                            _fieldDec('Medicine / supplies')),
                    TextField(
                        controller: doseCtrl,
                        decoration:
                            _fieldDec('Dose / frequency')),
                    TextField(
                        controller: clinicCtrl,
                        decoration:
                            _fieldDec('Clinic / animal hospital')),
                    TextField(
                        controller: noteCtrl,
                        decoration:
                            _fieldDec('Additional notes')),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: Text(
                                'Date: ${date.toString().split(' ').first}')),
                        IconButton(
                          icon: const Icon(Icons.date_range),
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate:
                                  DateTime(DateTime.now().year - 10),
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
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Save')),
              ],
            ),
          ),
        );

        await col.add({
          'name': nameCtrl.text.trim(),
          'medicine': medCtrl.text.trim(),
          'dose': doseCtrl.text.trim(),
          'clinic': clinicCtrl.text.trim(),
          'note': noteCtrl.text.trim(),
          'date': Timestamp.fromDate(date),
        });
      },
    );
  }
}

/* -------------------- Births -------------------- */
class _BirthTab extends StatelessWidget {
  final String catId;
  const _BirthTab({required this.catId});

  Future<bool> _isMale() async {
    final d =
        await FirebaseFirestore.instance.collection('cats').doc(catId).get();
    return (d.data()?['gender'] ?? '')
            .toString()
            .toLowerCase() ==
        'male';
  }

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('cats')
        .doc(catId)
        .collection('birthRecords');

    return _ListWithAdd(
      stream: col.orderBy('date', descending: true).snapshots(),
      itemBuilder: (d) {
        final x = d.data()!;
        final date =
            (x['date'] as Timestamp?)?.toDate().toString().split(' ').first ??
                '';
        final kittens = (x['kittens'] ?? 0).toString();
        final healthyAll = (x['healthyAll'] ?? true) == true;
        final other = (x['other'] ?? false) == true;
        final notes = (x['notes'] ?? '').toString();
        final parts = <String>[
          'Total $kittens kittens',
          if (healthyAll) 'All healthy',
          if (other) 'Other',
          if (notes.isNotEmpty) notes,
        ];
        return ListTile(
          title: Text('Birth on $date'),
          subtitle: Text(parts.join(' • ')),
          onLongPress: () => d.reference.delete(),
        );
      },
      onAdd: () async {
        if (await _isMale()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Male cats cannot have birth records.')),
          );
          return;
        }

        DateTime date = DateTime.now();
        final totalC = TextEditingController();
        final notesC = TextEditingController();
        bool healthyAll = true;
        bool other = false;
        String? err;

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
                        Expanded(
                          child: Text(
                              'Date: ${date.toString().split(' ').first}'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.date_range),
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate:
                                  DateTime(DateTime.now().year - 10),
                              lastDate: DateTime.now(),
                            );
                            if (p != null) setSt(() => date = p);
                          },
                        ),
                      ],
                    ),
                    TextField(
                      controller: totalC,
                      keyboardType: TextInputType.number,
                      decoration:
                          _fieldDec('Total number of kittens'),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: healthyAll,
                      onChanged: (v) =>
                          setSt(() => healthyAll = v ?? true),
                      title: const Text('All kittens healthy'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: other,
                      onChanged: (v) => setSt(() => other = v ?? false),
                      title:
                          const Text('Other (specify in notes)'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    TextField(
                        controller: notesC,
                        decoration: _fieldDec('Notes')),
                    if (err != null) ...[
                      const SizedBox(height: 6),
                      Text(err!,
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    final t = int.tryParse(totalC.text.trim()) ?? 0;
                    if (t <= 0) {
                      setSt(() => err =
                          'Please enter a valid total number of kittens.');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );

        if (ok == true) {
          await col.add({
            'date': Timestamp.fromDate(date),
            'kittens': int.tryParse(totalC.text.trim()) ?? 0,
            'healthyAll': healthyAll,
            'other': other,
            'notes': notesC.text.trim().isEmpty
                ? null
                : notesC.text.trim(),
          });
        }
      },
    );
  }
}
