import 'dart:async';
import 'package:flutter/material.dart';
import 'package:user_smartfridge/screens/auth.dart';
import 'package:user_smartfridge/screens/fridge_stats.dart';
import 'package:user_smartfridge/screens/search_inventory.dart';
import 'package:user_smartfridge/service/api.dart';
import 'package:user_smartfridge/service/fridge.dart';
import 'package:user_smartfridge/widgets/fridge_selector.dart';
import 'package:user_smartfridge/widgets/otp_input.dart';
import '../main.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ClientApiService _api = ClientApiService();
  List<dynamic> _fridges = [];
  int? _selectedFridgeId;
  Map<String, dynamic> _stats = {};
  Map<String, dynamic> _summary = {};
  List<dynamic> _recentEvents = [];
  bool _isLoading = true;

  final _fridgeService = FridgeService();
  StreamSubscription<int?>? _fridgeSubscription;

  @override
  void initState() {
    super.initState();
    _fridgeSubscription = _fridgeService.fridgeStream.listen((fridgeId) {
      if (fridgeId != null && fridgeId != _selectedFridgeId) {
        _selectedFridgeId = fridgeId;
        _loadData();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _fridgeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();
      setState(() {
        _fridges = fridges;
        _isLoading = false;
      });

      if (_selectedFridgeId != null) {
        await Future.wait([_loadStats(), _loadSummary(), _loadRecentEvents()]);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _handleError(e);
    }
  }

  Future<void> _loadStats() async {
    if (_selectedFridgeId == null) return;

    try {
      final inventory = await _api.getInventory(_selectedFridgeId!);
      final alerts = await _api.getAlerts(
        _selectedFridgeId!,
        status: 'pending',
      );

      setState(() {
        _stats = {
          'total_items': inventory.length,
          'pending_alerts': alerts.length,
          'expiring_soon': inventory.where((item) {
            if (item['expiry_date'] == null) return false;
            final expiryDate = DateTime.parse(item['expiry_date']);
            return expiryDate.difference(DateTime.now()).inDays <= 3;
          }).length,
        };
      });
    } catch (e) {
      _showError('Erreur de chargement des stats');
    }
  }

  Future<void> _loadSummary() async {
    if (_selectedFridgeId == null) return;

    try {
      final summary = await _api.getFridgeSummary(_selectedFridgeId!);
      setState(() => _summary = summary);
    } catch (e) {
      print('Erreur summary: $e');
    }
  }

  Future<void> _loadRecentEvents() async {
    if (_selectedFridgeId == null) return;

    try {
      final response = await _api.getEvents(
        fridgeId: _selectedFridgeId!,
        pageSize: 10, // Seulement les 10 derniers
      );
      setState(() => _recentEvents = response['items'] ?? []);
    } catch (e) {
      print('Erreur events: $e');
    }
  }

  void _handleError(dynamic e) {
    if (e.toString().contains('Non autorisé') || e.toString().contains('401')) {
      _api.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } else {
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        if (_fridges.isEmpty)
                          _buildEmptyFridgeState()
                        else ...[
                          _buildFridgeCard(),
                          _buildStatsGrid(),
                          if (_summary.isNotEmpty) _buildSummarySection(),
                          _buildQuickActions(),
                          if (_recentEvents.isNotEmpty) _buildRecentActivity(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      floating: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bonjour 👋',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tableau de bord',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        if (_fridges.isNotEmpty) ...[
          FridgeSelector(
            fridges: _fridges,
            selectedFridgeId: _selectedFridgeId,
          ),
          const SizedBox(width: 8),
        ],
        Container(
          margin: const EdgeInsets.only(right: 8),
          child: IconButton.filled(
            icon: const Icon(Icons.link, size: 20),
            onPressed: _showPairingDialog,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            tooltip: 'Jumeler un frigo',
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyFridgeState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.kitchen_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucun frigo connecté',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Entrez le code de votre kiosk\npour connecter votre premier frigo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showPairingDialog,
                icon: const Icon(Icons.link, size: 20),
                label: const Text('Connecter un frigo'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFridgeCard() {
    final selectedFridge = _fridges.firstWhere(
      (f) => f['id'] == _selectedFridgeId,
      orElse: () => _fridges.first,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.kitchen,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Frigo actif',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedFridge['name'] ?? 'Mon frigo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (selectedFridge['location'] != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    selectedFridge['location'],
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Articles',
              _stats['total_items']?.toString() ?? '0',
              Icons.inventory_2_outlined,
              Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Alertes',
              _stats['pending_alerts']?.toString() ?? '0',
              Icons.notifications_outlined,
              const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'À consommer',
              _stats['expiring_soon']?.toString() ?? '0',
              Icons.schedule_outlined,
              const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.insights,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Résumé',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            FridgeStatisticsPage(fridgeId: _selectedFridgeId!),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Voir plus'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_summary['critical_alerts'] != null)
              _buildSummaryRow(
                Icons.warning_amber,
                'Alertes critiques',
                _summary['critical_alerts'].toString(),
                const Color(0xFFEF4444),
              ),
            if (_summary['recent_events'] != null) ...[
              const SizedBox(height: 12),
              _buildSummaryRow(
                Icons.history,
                'Événements (30j)',
                _summary['recent_events'].toString(),
                Theme.of(context).colorScheme.primary,
              ),
            ],
            if (_summary['active_items'] != null) ...[
              const SizedBox(height: 12),
              _buildSummaryRow(
                Icons.inventory_2_outlined,
                'Articles actifs',
                _summary['active_items'].toString(),
                const Color(0xFF10B981),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actions rapides',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  'Rechercher',
                  'Commande vocale',
                  Icons.mic_outlined,
                  Theme.of(context).colorScheme.primary,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SearchInventoryPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  'Recettes',
                  'Voir les recettes',
                  Icons.restaurant_menu_outlined,
                  const Color(0xFF8B5CF6),
                  () => homePageKey.currentState?.changeTab(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  'Courses',
                  'Mes listes',
                  Icons.shopping_cart_outlined,
                  const Color(0xFF10B981),
                  () => homePageKey.currentState?.changeTab(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  'Alertes',
                  'Voir les alertes',
                  Icons.notifications_outlined,
                  const Color(0xFFF59E0B),
                  () => homePageKey.currentState?.changeTab(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.timeline,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Activité récente',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FridgeStatisticsPage(
                          fridgeId: _selectedFridgeId!,
                          initialTab: 1,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Tout voir'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._recentEvents.take(5).map((event) => _buildEventTile(event)),
          ],
        ),
      ),
    );
  }

  Widget _buildEventTile(Map<String, dynamic> event) {
    final type = event['type'] as String;
    final payload = event['payload'] as Map<String, dynamic>? ?? {};
    final createdAt = DateTime.parse(event['created_at']);
    final timeAgo = _formatTimeAgo(createdAt);

    IconData icon;
    Color color;
    String title;

    switch (type) {
      case 'ITEM_ADDED':
        icon = Icons.add_circle_outline;
        color = const Color(0xFF10B981);
        title = payload['product_name'] ?? 'Produit ajouté';
        break;
      case 'ITEM_CONSUMED':
        icon = Icons.remove_circle_outline;
        color = const Color(0xFF3B82F6);
        title = payload['product_name'] ?? 'Produit consommé';
        break;
      case 'ITEM_DETECTED':
        icon = Icons.camera_alt_outlined;
        color = const Color(0xFF8B5CF6);
        title = 'Scan IA détecté';
        break;
      case 'ALERT_CREATED':
        icon = Icons.warning_amber;
        color = const Color(0xFFF59E0B);
        title = 'Alerte créée';
        break;
      default:
        icon = Icons.circle_outlined;
        color = Theme.of(context).colorScheme.onSurfaceVariant;
        title = type.replaceAll('_', ' ');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                Text(
                  timeAgo,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);

    if (difference.inMinutes < 1) return 'À l\'instant';
    if (difference.inHours < 1) return 'Il y a ${difference.inMinutes}min';
    if (difference.inDays < 1) return 'Il y a ${difference.inHours}h';
    if (difference.inDays < 7) return 'Il y a ${difference.inDays}j';

    return 'Le ${dateTime.day}/${dateTime.month}';
  }

  Future<void> _showPairingDialog() async {
    final nameController = TextEditingController(text: 'Mon Frigo');
    final locationController = TextEditingController();
    bool isProcessing = false;
    String otpCode = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => WillPopScope(
          onWillPop: () async => !isProcessing,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(
                context,
              ).viewInsets.bottom, // ✅ AJOUT : Pousse au-dessus du clavier
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Header (reste identique)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.link,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connecter un frigo',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                  Text(
                                    isProcessing
                                        ? 'Génération en cours...'
                                        : 'Entrez le code du kiosk',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isProcessing)
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Content (avec SingleChildScrollView)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info box
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Comment ça marche ?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '1. Regardez le code à 6 chiffres sur le kiosk\n'
                                        '2. Entrez-le ci-dessous\n'
                                        '3. Personnalisez votre frigo',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // OTP Section
                          Row(
                            children: [
                              Icon(
                                Icons.pin,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Code à 6 chiffres *',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          OtpInput(
                            enabled: !isProcessing,
                            onCompleted: (code) {
                              setState(() => otpCode = code);
                            },
                          ),
                          const SizedBox(height: 32),

                          // Name field
                          TextField(
                            controller: nameController,
                            enabled: !isProcessing,
                            decoration: InputDecoration(
                              labelText: 'Nom du frigo *',
                              hintText: 'Ex: Frigo Cuisine',
                              prefixIcon: const Icon(Icons.kitchen_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Location field
                          TextField(
                            controller: locationController,
                            enabled: !isProcessing,
                            decoration: InputDecoration(
                              labelText: 'Localisation (optionnel)',
                              hintText: 'Ex: Cuisine, Bureau',
                              prefixIcon: const Icon(
                                Icons.location_on_outlined,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 20,
                          ), // ✅ Espacement supplémentaire
                        ],
                      ),
                    ),
                  ),

                  // Footer (reste identique)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          if (!isProcessing)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Annuler'),
                              ),
                            ),
                          if (!isProcessing) const SizedBox(width: 12),

                          // Connect button
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: isProcessing
                                  ? null
                                  : () async {
                                      // Validation
                                      if (otpCode.length != 6) {
                                        _showError(
                                          'Le code doit contenir 6 chiffres',
                                        );
                                        return;
                                      }
                                      if (nameController.text.isEmpty) {
                                        _showError(
                                          'Donnez un nom à votre frigo',
                                        );
                                        return;
                                      }

                                      setState(() => isProcessing = true);

                                      try {
                                        // API call
                                        final result = await _api.pairFridge(
                                          pairingCode: otpCode,
                                          fridgeName: nameController.text,
                                          fridgeLocation:
                                              locationController.text.isEmpty
                                              ? null
                                              : locationController.text,
                                        );

                                        Navigator.pop(context);

                                        // Success dialog
                                        // Success dialog
                                        showModalBottomSheet(
                                          context: context,
                                          backgroundColor: Colors.transparent,
                                          isDismissible: false,
                                          isScrollControlled:
                                              true, // ✅ IMPORTANT : Ajouter ceci
                                          builder: (context) => Container(
                                            height:
                                                MediaQuery.of(
                                                  context,
                                                ).size.height *
                                                0.5,
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).cardColor,
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(24),
                                                  ),
                                            ),
                                            child: Column(
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.all(
                                                    20,
                                                  ),
                                                  child: Column(
                                                    children: [
                                                      // Handle bar
                                                      Container(
                                                        width: 40,
                                                        height: 4,
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .outline
                                                                  .withOpacity(
                                                                    0.5,
                                                                  ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                2,
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),

                                                      // Success icon
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              20,
                                                            ),
                                                        decoration:
                                                            BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFF10B981,
                                                                  ).withOpacity(
                                                                    0.1,
                                                                  ),
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: const Icon(
                                                          Icons.check_circle,
                                                          color: Color(
                                                            0xFF10B981,
                                                          ),
                                                          size: 64,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),

                                                      // Success title
                                                      Text(
                                                        'Frigo connecté !',
                                                        style: TextStyle(
                                                          fontSize: 24,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyLarge
                                                                  ?.color,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),

                                                      // Success message
                                                      Text(
                                                        'Votre frigo "${result['fridge_name']}" est maintenant connecté.',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          color:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium
                                                                  ?.color,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // ✅ AJOUT : Expanded pour le contenu scrollable
                                                Expanded(
                                                  child: SingleChildScrollView(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 20,
                                                        ),
                                                    child: Column(
                                                      children: [
                                                        // Info box
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                16,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .surfaceContainerHighest,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          child: Column(
                                                            children: [
                                                              _buildInfoRow(
                                                                Icons.kitchen,
                                                                'Nom',
                                                                result['fridge_name'],
                                                              ),
                                                              if (result['fridge_location'] !=
                                                                  null) ...[
                                                                const SizedBox(
                                                                  height: 8,
                                                                ),
                                                                _buildInfoRow(
                                                                  Icons
                                                                      .location_on,
                                                                  'Lieu',
                                                                  result['fridge_location'],
                                                                ),
                                                              ],
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              _buildInfoRow(
                                                                Icons.tag,
                                                                'ID',
                                                                '#${result['fridge_id']}',
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 20,
                                                        ), // ✅ Espacement en bas
                                                      ],
                                                    ),
                                                  ),
                                                ),

                                                // Start button
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    20,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(
                                                      context,
                                                    ).cardColor,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.05),
                                                        blurRadius: 10,
                                                        offset: const Offset(
                                                          0,
                                                          -5,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: SafeArea(
                                                    child: SizedBox(
                                                      width: double.infinity,
                                                      child: ElevatedButton.icon(
                                                        onPressed: () {
                                                          Navigator.pop(
                                                            context,
                                                          );
                                                          _loadData();
                                                        },
                                                        icon: const Icon(
                                                          Icons.check,
                                                        ),
                                                        label: const Text(
                                                          'Commencer',
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              const Color(
                                                                0xFF10B981,
                                                              ),
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                vertical: 16,
                                                              ),
                                                          elevation: 0,
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      } catch (e) {
                                        setState(() => isProcessing = false);
                                        _showError(
                                          e.toString().replaceAll(
                                            'Exception: ',
                                            '',
                                          ),
                                        );
                                      }
                                    },
                              icon: isProcessing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Icon(Icons.link),
                              label: Text(
                                isProcessing ? 'Connexion...' : 'Connecter',
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ],
    );
  }
}
