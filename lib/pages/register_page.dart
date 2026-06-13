// lib/pages/register_page.dart (with avatar upload and imageUrl sync)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  File? _avatar;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() {
        _avatar = File(picked.path);
      });
    }
  }

  Future<String> _uploadAvatar(File file, String uid) async {
    final fileName = DateTime.now().millisecondsSinceEpoch.toString();
    final ref =
        FirebaseStorage.instance.ref().child('avatars/$uid/$fileName.jpg');
    final task = await ref.putFile(file);
    return await task.ref.getDownloadURL();
  }

  // ✅ เปลี่ยนจาก hintText เป็น labelText + floatingLabelBehavior.always
  InputDecoration _minimalInput(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      );

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  Future<bool> _isUsernameAvailable(String username) async {
    final unameLower = username.trim().toLowerCase();
    if (unameLower.isEmpty) return false;
    final q = await FirebaseFirestore.instance
        .collection('users')
        .where('usernameLower', isEqualTo: unameLower)
        .limit(1)
        .get();
    return q.docs.isEmpty;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 0) Check duplicated username first to avoid failing after Auth user was created
      final username = _usernameController.text.trim();
      final ok = await _isUsernameAvailable(username);
      if (!ok) {
        setState(() => _error = 'This username is already taken');
        return;
      }

      // 1) Create auth user
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final uid = cred.user!.uid;

      // 2) Upload avatar (if any)
      String avatarUrl = '';
      if (_avatar != null) {
        avatarUrl = await _uploadAvatar(_avatar!, uid);
      }

      // 3) Write profile to Firestore
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim();
      final usernameLower = username.toLowerCase();

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'firstName': firstName,
          'lastName': lastName,
          'phone': phone,
          'username': username,
          'usernameLower': usernameLower,
          'email': email,
          'avatar': avatarUrl,
          'imageUrl': avatarUrl, // keep in sync with places that read imageUrl
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 4) Update FirebaseAuth profile (optional)
      try {
        final displayName = '$firstName $lastName'.trim();
        if (displayName.isNotEmpty) {
          await cred.user!.updateDisplayName(displayName);
        }
        if (avatarUrl.isNotEmpty) {
          await cred.user!.updatePhotoURL(avatarUrl);
        }
      } catch (_) {
        // non-fatal
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful!')),
      );

      // User is already logged in → go into the app
      Navigator.of(context).pushReplacementNamed('/root');
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'This email is already in use';
          break;
        case 'invalid-email':
          msg = 'Invalid email format';
          break;
        case 'weak-password':
          msg = 'Password is too weak';
          break;
        default:
          msg = e.message ?? 'Registration failed';
      }
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = 'Registration failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_isLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                GestureDetector(
                  onTap: _pickAvatar,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.grey[200],
                    backgroundImage:
                        _avatar != null ? FileImage(_avatar!) : null,
                    child: _avatar == null
                        ? Icon(Icons.camera_alt,
                            size: 32, color: Colors.grey[600])
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _firstNameController,
                  decoration: _minimalInput('First name'),
                  validator: _req,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastNameController,
                  decoration: _minimalInput('Last name'),
                  validator: _req,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: _minimalInput('Phone number'),
                  validator: _req,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  decoration: _minimalInput('Username'),
                  validator: _req,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: _minimalInput('Email'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                      return 'Invalid email format';
                    }
                    return null;
                  },
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: _minimalInput(
                    'Password',
                    suffix: IconButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                  obscureText: _obscure,
                  validator: (v) => (v == null || v.length < 6)
                      ? 'Password must be at least 6 characters long'
                      : null,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: canSubmit ? _register : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Sign up',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Back to login',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
