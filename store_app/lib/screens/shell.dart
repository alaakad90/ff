import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import 'account/account_screen.dart';
import 'cart_screen.dart';
import 'categories_screen.dart';
import 'home_screen.dart';
import 'reels_screen.dart';

/// الأزرار اللي جوه. "طلباتي" و"عن المتجر" داخل صفحة الحساب،
/// لأن أكثر من 5 أزرار تصير زحمة على شاشة الموبايل.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// يبدل للتبويب المطلوب من أي مكان، مثل زر "روح للسلة".
  static void goTo(BuildContext context, ShellTab tab) =>
      context.findAncestorStateOfType<_AppShellState>()?._select(tab.index);

  @override
  State<AppShell> createState() => _AppShellState();
}

enum ShellTab { home, categories, reels, cart, account }

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _visited = <int>{0};

  void _select(int i) => setState(() {
        _index = i;
        _visited.add(i);
      });

  Widget _page(int i) => switch (ShellTab.values[i]) {
        ShellTab.home => const HomeScreen(),
        ShellTab.categories => const CategoriesScreen(),
        ShellTab.reels => ReelsScreen(visible: _index == ShellTab.reels.index),
        ShellTab.cart => const CartScreen(),
        ShellTab.account => const AccountScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final count = context.watch<Cart>().count;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        // الصفحات تنبني أول مرة تنفتح، وبعدها تبقى محفوظة.
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < ShellTab.values.length; i++)
              _visited.contains(i) ? _page(i) : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'الرئيسية',
            ),
            const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'الأقسام',
            ),
            const NavigationDestination(
              icon: Icon(Icons.play_circle_outline),
              selectedIcon: Icon(Icons.play_circle),
              label: 'ريلز',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: const Icon(Icons.shopping_bag),
              ),
              label: 'السلة',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'الحساب',
            ),
          ],
        ),
      ),
    );
  }
}
