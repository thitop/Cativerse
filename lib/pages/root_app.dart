// lib/pages/root_app.dart
import 'package:flutter/material.dart';
import 'package:cativerse/pages/account_page.dart';
import 'package:cativerse/pages/chat_page.dart';
import 'package:cativerse/pages/explore_page.dart';
import 'package:cativerse/widgets/active_cat_action.dart';

class RootApp extends StatefulWidget {
  const RootApp({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  late int _pageIndex;

  final List<Widget> _pages = const [ExplorePage(), ChatPage(), AccountPage()];
  final List<String> _titles = const ["Cativerse", "Messages", "Profile"];

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.initialIndex.clamp(0, _pages.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_pageIndex]),
        centerTitle: true,
        actions: [
          ActiveCatAction(), // 👈 เอา const ออก เพื่อให้สตรีมทำงาน
        ],
      ),
      body: IndexedStack(index: _pageIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _pageIndex,
        onTap: (i) => setState(() => _pageIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.local_fire_department),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
