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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _isAuthenticated ? const HomePage() : const LoginPage();
  }
}

class HomePage extends StatefulWidget {
  final int initialIndex;

  const HomePage({super.key, this.initialIndex = 0});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _currentIndex;
  int _pendingShoppingListsCount = 0;
  int _pendingAlertsCount = 0; // ✅ NOUVEAU
  int _expiringItemsCount = 0; // ✅ NOUVEAU
  int? _selectedFridgeId; // ✅ NOUVEAU

  final List<Widget> _pages = const [
    DashboardPage(),
    InventoryPage(),
    RecipesPage(),
    ShoppingListsPage(),
    AlertsPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _initializeFridgeAndBadges(); // ✅ NOUVEAU
    _listenToFridgeChanges(); // ✅ NOUVEAU
  }

  // ✅ NOUVEAU : Initialiser le frigo au démarrage
  Future<void> _initializeFridgeAndBadges() async {
    try {
      final api = ClientApiService();
      final fridges = await api.getFridges();

      if (fridges.isEmpty) return;

      // Récupérer le frigo sauvegardé ou prendre le premier
      final fridgeService = FridgeService();
      int? savedFridgeId = await fridgeService.getSelectedFridge();

      if (savedFridgeId != null &&
          fridges.any((f) => f['id'] == savedFridgeId)) {
        _selectedFridgeId = savedFridgeId;
      } else {
        _selectedFridgeId = fridges[0]['id'];
        await fridgeService.setSelectedFridge(_selectedFridgeId!);
      }

      // Charger tous les badges
      await _loadAllBadges();
    } catch (e) {
      print('❌ Erreur initialisation: $e');
    }
  }

  // ✅ NOUVEAU : Écouter les changements de frigo
  void _listenToFridgeChanges() {
    FridgeService().fridgeStream.listen((fridgeId) {
      if (fridgeId != null && fridgeId != _selectedFridgeId) {
        _selectedFridgeId = fridgeId;
        _loadAllBadges(); // Recharger tous les badges
      }
    });
  }

  // ✅ NOUVEAU : Charger tous les badges
  Future<void> _loadAllBadges() async {
    await Future.wait([
      _loadPendingShoppingListsCount(),
      _loadPendingAlertsCount(),
      _loadExpiringItemsCount(),
    ]);
  }

  Future<void> _loadPendingShoppingListsCount() async {
    if (_selectedFridgeId == null) return;

    try {
      final api = ClientApiService();
      final lists = await api.getShoppingLists(fridgeId: _selectedFridgeId);

      int count = 0;
      for (var list in lists) {
        final items = list['items'] as List? ?? [];
        if (items.any((item) => item['status'] == 'pending')) {
          count++;
        }
      }

      if (mounted) {
        setState(() => _pendingShoppingListsCount = count);
      }
    } catch (e) {
      print('❌ Erreur chargement shopping lists: $e');
    }
  }

  // ✅ NOUVEAU : Charger les alertes en attente
  Future<void> _loadPendingAlertsCount() async {
    if (_selectedFridgeId == null) return;

    try {
      final api = ClientApiService();
      final alerts = await api.getAlerts(_selectedFridgeId!, status: 'pending');

      if (mounted) {
        setState(() => _pendingAlertsCount = alerts.length);
      }
    } catch (e) {
      print('❌ Erreur chargement alertes: $e');
    }
  }

  // ✅ NOUVEAU : Charger les items expirant bientôt
  Future<void> _loadExpiringItemsCount() async {
    if (_selectedFridgeId == null) return;

    try {
      final api = ClientApiService();
      final inventory = await api.getInventory(_selectedFridgeId!);

      final expiringCount = inventory.where((item) {
        final status = item['freshness_status'];
        return status == 'expiring_soon' || status == 'expires_today';
      }).length;

      if (mounted) {
        setState(() => _expiringItemsCount = expiringCount);
      }
    } catch (e) {
      print('❌ Erreur chargement inventaire: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);

          // Recharger les badges quand on change d'onglet
          if (index == 1) _loadExpiringItemsCount(); // Inventaire
          if (index == 3) _loadPendingShoppingListsCount(); // Courses
          if (index == 4) _loadPendingAlertsCount(); // Alertes
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Accueil',
          ),
          // ✅ Badge pour inventaire
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _expiringItemsCount > 0,
              label: Text('$_expiringItemsCount'),
              child: const Icon(Icons.inventory_2_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _expiringItemsCount > 0,
              label: Text('$_expiringItemsCount'),
              child: const Icon(Icons.inventory_2),
            ),
            label: 'Inventaire',
          ),
          const NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Recettes',
          ),
          // ✅ Badge pour courses
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
          // ✅ Badge pour alertes
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _pendingAlertsCount > 0,
              label: Text('$_pendingAlertsCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _pendingAlertsCount > 0,
              label: Text('$_pendingAlertsCount'),
              child: const Icon(Icons.notifications),
            ),
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
