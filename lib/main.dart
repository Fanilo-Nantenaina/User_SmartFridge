import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:user_smartfridge/screens/alerts.dart';
import 'package:user_smartfridge/screens/auth.dart';
import 'package:user_smartfridge/screens/dashboard.dart';
import 'package:user_smartfridge/screens/inventory.dart';
import 'package:user_smartfridge/screens/profile.dart';
import 'package:user_smartfridge/screens/recipes.dart';
import 'package:user_smartfridge/screens/shopping_list.dart';
import 'package:user_smartfridge/service/api.dart';
import 'package:user_smartfridge/service/fridge.dart';
import 'package:user_smartfridge/service/notification.dart';
import 'package:user_smartfridge/service/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  tz.initializeTimeZones();
  await NotificationService().initialize();

  await ThemeSwitcher().init();
  await FridgeService().initialize();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SmartFridgeClientApp());
}

class SmartFridgeClientApp extends StatelessWidget {
  const SmartFridgeClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeSwitcher(),
      builder: (context, child) {
        return MaterialApp(
          title: 'Smart Fridge',
          debugShowCheckedModeBanner: false,

          theme: ThemeSwitcher.lightTheme,
          darkTheme: ThemeSwitcher.darkTheme,
          themeMode: ThemeSwitcher().themeMode,

          home: const AuthWrapper(),
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    setState(() {
      _isAuthenticated = token != null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _isAuthenticated ? const HomePage() : const LoginPage();
  }
}

class HomePage extends StatefulWidget {
  final int initialIndex;

  const HomePage({super.key, this.initialIndex=0});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _currentIndex;
  int _pendingShoppingListsCount = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadPendingShoppingListsCount();
  }

  Future<void> _loadPendingShoppingListsCount() async {
    try {
      final api = ClientApiService();
      final lists = await api.getShoppingLists();

      // Compter les listes avec des items pending
      int count = 0;
      for (var list in lists) {
        final items = list['items'] as List? ?? [];
        if (items.any((item) => item['status'] == 'pending')) {
          count++;
        }
      }

      if (mounted) {
        setState(() {
          _pendingShoppingListsCount = count;
        });
      }
    } catch (e) {
      // Ignorer les erreurs silencieusement
    }
  }

  final List<Widget> _pages = [
    const DashboardPage(),
    const InventoryPage(),
    const RecipesPage(),
    const ShoppingListsPage(),
    const AlertsPage(),
    const ProfilePage(),
  ];

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          if (index == 3) {
            _loadPendingShoppingListsCount();
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Accueil',
          ),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventaire',
          ),
          const NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Recettes',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _pendingShoppingListsCount > 0,
              label: Text('$_pendingShoppingListsCount'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _pendingShoppingListsCount > 0,
              label: Text('$_pendingShoppingListsCount'),
              child: const Icon(Icons.shopping_cart),
            ),
            label: 'Courses',
          ),
          const NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alertes',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}