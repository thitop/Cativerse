// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'pages/root_app.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/formscreen.dart';
import 'pages/edit_profile_page.dart';
import 'pages/cat_edit_and_match_page.dart';

// ธีม
import 'theme/app_theme.dart';

/// ===============================
///   Background handler (จำเป็นต้องเป็น top-level function)
/// ===============================
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ต้อง initialize Firebase อีกครั้งใน background
  await Firebase.initializeApp();
  // ถ้าจะทำอะไรเพิ่มตอน background ก็ใส่ตรงนี้ได้
  debugPrint('Handling a background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // ตั้ง handler สำหรับข้อความที่เด้งตอนแอปปิด / background
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ฟังการเปลี่ยนธีมทั้งแอป
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Cativerse',

          // ใช้ธีมจาก AppTheme (Material 3 + Light/Dark)
          themeMode: themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,

          // เส้นทางหลักที่แอปใช้อยู่
          routes: {
            '/login': (_) => const LoginPage(),
            '/register': (_) => const RegisterPage(),
            '/root': (_) => const RootApp(),
            '/home': (_) => const RootApp(),

            // ชี้ไปแท็บ Explore/Chat/Account โดยตรง
            '/explore': (_) => const RootApp(initialIndex: 0),
            '/chat':    (_) => const RootApp(initialIndex: 1),
            '/account': (_) => const RootApp(initialIndex: 2),

            '/cats/add': (_) => const AddCatForm(),
            '/profile/edit': (_) => const EditProfilePage(),
            '/cats/editAndMatch': (_) => const CatEditAndMatchPage(),
          },

          onUnknownRoute: (_) =>
              MaterialPageRoute(builder: (_) => const RootApp()),

          // Auth gate แยกเป็น widget ชัด ๆ
          home: const AuthGate(),
        );
      },
    );
  }
}

/// ===============================
///   AuthGate: เช็คว่าล็อกอินหรือยัง
///   ถ้าล็อกอินแล้ว -> ห่อ RootApp ด้วย NotificationInitializer
/// ===============================
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.active) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;
        if (user == null) {
          // ยังไม่ล็อกอิน
          return const LoginPage();
        }

        // ล็อกอินแล้ว -> เตรียมระบบแจ้งเตือน แล้วเข้า RootApp
        return const NotificationInitializer(
          child: RootApp(),
        );
      },
    );
  }
}

/// ===============================
///   NotificationInitializer:
///   - ขอ permission แจ้งเตือน
///   - ดึง / อัปเดต FCM token ไปที่ users/{uid}.fcmToken
///   - ตั้ง listener เวลาได้รับ notification
/// ===============================
class NotificationInitializer extends StatefulWidget {
  final Widget child;
  const NotificationInitializer({super.key, required this.child});

  @override
  State<NotificationInitializer> createState() =>
      _NotificationInitializerState();
}

class _NotificationInitializerState extends State<NotificationInitializer> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _setupPushNotifications();
  }

  Future<void> _setupPushNotifications() async {
    if (_initialized) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;

    // ขอสิทธิการแจ้งเตือน
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('User granted permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // ผู้ใช้ไม่ยอมให้สิทธิแจ้งเตือน ก็ข้ามไป
      return;
    }

    // ดึง token ครั้งแรก
    final token = await messaging.getToken();
    debugPrint('FCM Token: $token');

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
    }

    // ถ้า token เปลี่ยน เช่น ลบแอป ลงใหม่
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('FCM Token refreshed: $newToken');
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && newToken != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'fcmToken': newToken}, SetOptions(merge: true));
      }
    });

    // Listener ขณะ app เปิดอยู่ (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final data = message.data;

      debugPrint('Foreground message: ${message.messageId}');
      debugPrint('Data: $data');

      if (notification != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notification.title != null
                  ? '${notification.title}: ${notification.body ?? ""}'
                  : (notification.body ?? 'คุณมีการแจ้งเตือนใหม่'),
            ),
          ),
        );
      }

      // แยกตาม type ที่ส่งมาจาก Cloud Functions (message / match)
      if (data['type'] == 'message') {
        // ถ้าอยากเด้งไปหน้าแชทแบบ auto ก็สามารถทำได้ เช่น:
        // final roomId = data['roomId'];
        // Navigator.pushNamed(context, '/chat', arguments: roomId);
      } else if (data['type'] == 'match') {
        // แจ้งว่ามีแมชใหม่ หรือเด้งไปหน้า /explore หรือหน้า match
        // Navigator.pushNamed(context, '/chat');
      }
    });

    // เวลากด notification แล้วเปิดแอป (จาก background / terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final data = message.data;
      debugPrint('onMessageOpenedApp: $data');

      if (!mounted) return;

      if (data['type'] == 'message') {
        // final roomId = data['roomId'];
        // Navigator.pushNamed(context, '/chat', arguments: roomId);
        Navigator.pushNamed(context, '/chat');
      } else if (data['type'] == 'match') {
        // อาจจะพาไปหน้า match / หน้า chat ก็แล้วแต่ UX
        Navigator.pushNamed(context, '/chat');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // แค่ห่อ child ไว้เฉย ๆ
    return widget.child;
  }
}
