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
import 'package:user_smartfridge/screens/search_inventory.dart';
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
  int _pendingAlertsCount = 0;
  int _expiringItemsCount = 0;
  int? _selectedFridgeId;

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
    _initializeFridgeAndBadges();
    _listenToFridgeChanges();
  }

  Future<void> _initializeFridgeAndBadges() async {
    try {
      final api = ClientApiService();
      final fridges = await api.getFridges();

      if (fridges.isEmpty) return;

      final fridgeService = FridgeService();
      int? savedFridgeId = await fridgeService.getSelectedFridge();

      if (savedFridgeId != null &&
          fridges.any((f) => f['id'] == savedFridgeId)) {
        _selectedFridgeId = savedFridgeId;
      } else {
        _selectedFridgeId = fridges[0]['id'];
        await fridgeService.setSelectedFridge(_selectedFridgeId!);
      }

      await _loadAllBadges();
    } catch (e) {
      print('❌ Erreur initialisation: $e');
    }
  }

  void _listenToFridgeChanges() {
    FridgeService().fridgeStream.listen((fridgeId) {
      if (fridgeId != null && fridgeId != _selectedFridgeId) {
        _selectedFridgeId = fridgeId;
        _loadAllBadges();
      }
    });
  }

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

  Future<void> _loadExpiringItemsCount() async {
    if (_selectedFridgeId == null) return;

    try {
      final api = ClientApiService();
      final inventory = await api.getInventory(_selectedFridgeId!);

      final criticalCount = inventory.where((item) {
        final status = item['freshness_status'];
        return status == 'expiring_soon' ||
            status == 'expires_today' ||
            status == 'expired';
      }).length;

      if (mounted) {
        setState(() => _expiringItemsCount = criticalCount);
      }
    } catch (e) {
      print('❌ Erreur chargement inventaire: $e');
    }
  }

  // ✅ NOUVEAU : Navigation vers la recherche vocale
  void _navigateToSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchInventoryPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      // ✅ NOUVEAU : Floating Action Button pour le micro
      floatingActionButton: _buildFloatingMicButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      // ✅ NOUVEAU : BottomAppBar avec encoche
      bottomNavigationBar: _buildBottomAppBar(),
    );
  }

  // ✅ NOUVEAU : Bouton micro flottant
  Widget _buildFloatingMicButton() {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withOpacity(0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _navigateToSearch,
          customBorder: const CircleBorder(),
          child: const Icon(Icons.mic, color: Colors.white, size: 32),
        ),
      ),
    );
  }

  // ✅ NOUVEAU : BottomAppBar personnalisé
  Widget _buildBottomAppBar() {
    return BottomAppBar(
      height: 70,
      padding: EdgeInsets.zero,
      color: Theme.of(context).cardColor,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Première moitié (3 icônes)
          _buildNavItem(
            Icons.dashboard_outlined,
            Icons.dashboard,
            'Accueil',
            0,
          ),
          _buildNavItem(
            Icons.inventory_2_outlined,
            Icons.inventory_2,
            'Inventaire',
            1,
            badge: _expiringItemsCount,
          ),
          _buildNavItem(
            Icons.restaurant_menu_outlined,
            Icons.restaurant_menu,
            'Recettes',
            2,
          ),

          // Espace pour le FAB
          const SizedBox(width: 70),

          // Deuxième moitié (3 icônes)
          _buildNavItem(
            Icons.shopping_cart_outlined,
            Icons.shopping_cart,
            'Courses',
            3,
            badge: _pendingShoppingListsCount,
          ),
          _buildNavItem(
            Icons.notifications_outlined,
            Icons.notifications,
            'Alertes',
            4,
            badge: _pendingAlertsCount,
          ),
          _buildNavItem(Icons.person_outline, Icons.person, 'Profil', 5),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    IconData selectedIcon,
    String label,
    int index, {
    int? badge,
  }) {
    final isSelected = _currentIndex == index;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentIndex = index);

          // Recharger les badges quand on change d'onglet
          if (index == 1) _loadExpiringItemsCount();
          if (index == 3) _loadPendingShoppingListsCount();
          if (index == 4) _loadPendingAlertsCount();
        },
        child: Container(
          height: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              badge != null && badge > 0
                  ? Badge(
                      label: Text('$badge'),
                      child: Icon(
                        isSelected ? selectedIcon : icon,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                    )
                  : Icon(
                      isSelected ? selectedIcon : icon,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
