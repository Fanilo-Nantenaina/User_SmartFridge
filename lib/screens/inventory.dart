import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:user_smartfridge/screens/auth.dart';
import 'package:user_smartfridge/screens/shopping_list.dart';
import 'package:user_smartfridge/service/api.dart';
import 'package:user_smartfridge/service/fridge.dart';
import 'package:user_smartfridge/service/realtime.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage>
    with SingleTickerProviderStateMixin {
  final ClientApiService _api = ClientApiService();
  RealtimeService? _realtimeService;

  List<dynamic> _inventory = [];
  List<dynamic> _filteredInventory = [];
  bool _isLoading = true;
  int? _selectedFridgeId;
  String _searchQuery = '';
  late TabController _tabController;

  final _fridgeService = FridgeService();
  StreamSubscription<int?>? _fridgeSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => _filterInventory());
    _api.onSessionExpired = _handleSessionExpired;
    _fridgeSubscription = _fridgeService.fridgeStream.listen((fridgeId) {
      if (fridgeId != null && fridgeId != _selectedFridgeId) {
        print('Frigo changé -> $fridgeId');
        _selectedFridgeId = fridgeId;
        _loadInventory();
      }
    });

    _loadInventory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _realtimeService?.dispose();
    _fridgeSubscription?.cancel();
    super.dispose();
  }

  void _handleSessionExpired() {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  Future<void> _loadInventory({
    bool showLoading = true,
    bool initRealtime = true,
  }) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final fridges = await _api.getFridges();

      if (!mounted) return;

      if (fridges.isEmpty) {
        setState(() {
          _inventory = [];
          _filteredInventory = [];
          _selectedFridgeId = null;
          _isLoading = false;
        });
        return;
      }

      int? savedFridgeId = await _fridgeService.getSelectedFridge();

      if (savedFridgeId != null &&
          fridges.any((f) => f['id'] == savedFridgeId)) {
        _selectedFridgeId = savedFridgeId;
      } else {
        _selectedFridgeId = fridges[0]['id'];
        await _fridgeService.setSelectedFridge(_selectedFridgeId!);
      }

      if (kDebugMode) {
        print(
          'Loading inventory for fridge $_selectedFridgeId',
        );
      }

      final inventory = await _api.getInventory(_selectedFridgeId!);

      if (!mounted) return;

      setState(() {
        _inventory = inventory;
        _filterInventory();
        _isLoading = false;
      });
    } on SessionExpiredException {
      _handleSessionExpired();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _handleError(e);
    }
  }

  void _filterInventory() {
    setState(() {
      List<dynamic> filtered = _inventory;

      if (_searchQuery.isNotEmpty) {
        filtered = filtered.where((item) {
          final productName =
              item['product_name'] ?? 'Produit #${item['product_id']}';
          return productName.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();
      }

      switch (_tabController.index) {
        case 0:
          _filteredInventory = filtered;
          break;
        case 1:
          _filteredInventory = filtered.where((item) {
            final status = item['freshness_status'];
            return status == 'expiring_soon' || status == 'expires_today';
          }).toList();
          break;
        case 2:
          _filteredInventory = filtered.where((item) {
            return item['freshness_status'] == 'expired';
          }).toList();
          break;
      }
    });
  }

  void _handleError(dynamic e) {
    final errorMsg = e.toString();
    if (errorMsg.contains('Session expirée') ||
        errorMsg.contains('Non authentifié') ||
        errorMsg.contains('401')) {
      _api.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } else {
      _showError('Erreur: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _selectedFridgeId != null
          ? FloatingActionButton.extended(
              onPressed: _showAddProductDialog,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            )
          : null,
      body: Column(
        children: [
          _buildAppBar(),
          _buildSearchBar(),
          _buildTabBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedFridgeId == null
                ? _buildNoFridgeState()
                : _inventory.isEmpty
                ? _buildEmptyState()
                : _buildInventoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFridgeState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
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
              'Connectez un frigo depuis le tableau de bord\npour voir votre inventaire',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inventaire',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${_inventory.length} produits',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        fontSize: 14,
                      ),
                    ),
                    if (_selectedFridgeId != null) ...[
                      Text(
                        ' • Frigo #$_selectedFridgeId',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ShoppingListsPage(),
                ),
              );
            },
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: 'Créer une liste',
            color: const Color(0xFF10B981),
          ),
          IconButton(
            onPressed: () => _loadInventory(),
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: TextField(
        onChanged: (value) {
          setState(() => _searchQuery = value);
          _filterInventory();
        },
        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        decoration: InputDecoration(
          hintText: 'Rechercher un produit...',
          hintStyle: TextStyle(
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withOpacity(0.5),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Theme.of(context).iconTheme.color,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    // Compter les items à consommer
    final expiringCount = _inventory.where((item) {
      final status = item['freshness_status'];
      return status == 'expiring_soon' || status == 'expires_today';
    }).length;

    // Compter les items expirés
    final expiredCount = _inventory.where((item) {
      return item['freshness_status'] == 'expired';
    }).length;

    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TabBar(
        controller: _tabController,
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color,
        indicatorColor: Theme.of(context).colorScheme.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        tabs: [
          const Tab(text: 'Tous'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('À consommer'),
                if (expiringCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$expiringCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Expirés'),
                if (expiredCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$expiredCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryItem(Map<String, dynamic> item) {
    final productName =
        item['product_name'] ?? 'Produit #${item['product_id']}';
    final category = item['product_category'] ?? '';
    final freshnessStatus = item['freshness_status'] ?? 'unknown';
    final freshnessLabel = item['freshness_label'];
    final isOpened = item['is_opened'] ?? false;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (freshnessStatus) {
      case 'expired':
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.cancel_outlined;
        statusText = freshnessLabel ?? 'Expiré';
        break;
      case 'expires_today':
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.warning_outlined;
        statusText = freshnessLabel ?? 'Expire aujourd\'hui';
        break;
      case 'expiring_soon':
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.schedule_outlined;
        statusText = freshnessLabel ?? 'Expire bientôt';
        break;
      case 'fresh':
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.check_circle_outline;
        statusText = freshnessLabel ?? 'Frais';
        break;
      default:
        statusColor = const Color(0xFF64748B);
        statusIcon = Icons.help_outline;
        statusText = 'Date inconnue';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showItemDetails(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.shopping_basket_outlined,
                    color: statusColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              productName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                          if (isOpened)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Ouvert',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (category.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          category,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${item['quantity'] ?? 0} ${item['unit'] ?? ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                color: statusColor,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (item['expiry_date'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatExpiryDate(item['expiry_date']),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: Theme.of(context).iconTheme.color,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _showEditQuantityDialog(item);
                        break;
                      case 'consume':
                        _showConsumeDialog(item);
                        break;
                      case 'delete':
                        _confirmDeleteItem(item);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('Modifier'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'consume',
                      child: Row(
                        children: [
                          Icon(Icons.remove_circle_outline, size: 20),
                          SizedBox(width: 12),
                          Text('Consommer'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Colors.red,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Supprimer',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showItemDetails(Map<String, dynamic> item) {
    final productName =
        item['product_name'] ?? 'Produit #${item['product_id']}';
    final category = item['product_category'] ?? '';
    final freshnessLabel = item['freshness_label'] ?? 'Inconnu';
    final isOpened = item['is_opened'] ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              productName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            if (category.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                category,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ],
            const SizedBox(height: 24),
            _buildDetailRow(
              'Quantité',
              '${item['quantity'] ?? 0} ${item['unit'] ?? ''}',
            ),
            _buildDetailRow('Statut', freshnessLabel),
            if (item['expiry_date'] != null)
              _buildDetailRow(
                'Expiration',
                _formatExpiryDate(item['expiry_date']),
              ),
            if (item['added_at'] != null)
              _buildDetailRow('Ajouté le', _formatDate(item['added_at'])),
            _buildDetailRow(
              'Source',
              item['source'] == 'vision' ? 'Scan automatique' : 'Ajout manuel',
            ),
            if (isOpened) _buildDetailRow('État', 'Ouvert'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showEditQuantityDialog(item);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showConsumeDialog(item);
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Consommer'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucun produit',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scannez des produits depuis le frigo\nou ajoutez-en manuellement',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddProductDialog,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un produit'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryList() {
    if (_filteredInventory.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Aucun résultat',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Aucun produit ne correspond à "$_searchQuery"'
                    : 'Aucun produit dans cette catégorie',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadInventory(showLoading: false, initRealtime: false),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredInventory.length,
        itemBuilder: (context, index) =>
            _buildInventoryItem(_filteredInventory[index]),
      ),
    );
  }

  String _formatExpiryDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return 'Expire le ${DateFormat('d MMM yyyy', 'fr_FR').format(date)}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('d MMM yyyy', 'fr_FR').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _showAddProductDialog() async {
    if (_selectedFridgeId == null) {
      _showError('Aucun frigo sélectionné');
      return;
    }

    final nameController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    final unitController = TextEditingController(text: 'pièce');
    String selectedCategory = 'Divers';
    DateTime? selectedExpiryDate;
    final categories = [
      'Divers',
      'Produit laitier',
      'Viande',
      'Poisson',
      'Fruit',
      'Légume',
      'Boisson',
      'Condiment',
      'Plat préparé',
      'Surgelé',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Ajouter un produit',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: 'Nom du produit *',
                            hintText: 'Ex: Lait, Œufs, Tomates...',
                            prefixIcon: const Icon(
                              Icons.shopping_basket_outlined,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: selectedCategory,
                          decoration: InputDecoration(
                            labelText: 'Catégorie',
                            prefixIcon: const Icon(Icons.category_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: categories
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (v) => setStateDialog(
                            () => selectedCategory = v ?? 'Divers',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: quantityController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Quantité *',
                                  prefixIcon: const Icon(Icons.numbers),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: unitController,
                                decoration: InputDecoration(
                                  labelText: 'Unité',
                                  hintText: 'pièce, kg, L...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now().add(
                                const Duration(days: 7),
                              ),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365 * 2),
                              ),
                            );
                            if (date != null) {
                              setStateDialog(() => selectedExpiryDate = date);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  color: Theme.of(context).iconTheme.color,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    selectedExpiryDate != null
                                        ? 'Expire le ${DateFormat('dd/MM/yyyy').format(selectedExpiryDate!)}'
                                        : 'Date d\'expiration (optionnel)',
                                    style: TextStyle(
                                      color: selectedExpiryDate != null
                                          ? Theme.of(
                                              context,
                                            ).textTheme.bodyLarge?.color
                                          : Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ),
                                if (selectedExpiryDate != null)
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () => setStateDialog(
                                      () => selectedExpiryDate = null,
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      final qty = double.tryParse(quantityController.text);
                      if (name.isEmpty) {
                        _showError('Entrez un nom de produit');
                        return;
                      }
                      if (qty == null || qty <= 0) {
                        _showError('Quantité invalide');
                        return;
                      }
                      try {
                        await _api.addInventoryItem(
                          fridgeId: _selectedFridgeId!,
                          productName: name,
                          category: selectedCategory,
                          quantity: qty,
                          unit: unitController.text.trim().isEmpty
                              ? 'pièce'
                              : unitController.text.trim(),
                          expiryDate: selectedExpiryDate,
                        );
                        Navigator.pop(context);
                        _showSuccess('$name ajouté !');
                        _loadInventory(showLoading: false);
                      } catch (e) {
                        _showError('Erreur: $e');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Ajouter'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditQuantityDialog(Map<String, dynamic> item) async {
    if (_selectedFridgeId == null) return;

    final productName =
        item['product_name'] ?? 'Produit #${item['product_id']}';
    final quantityController = TextEditingController(
      text: item['quantity']?.toString() ?? '0',
    );
    final unitController = TextEditingController(text: item['unit'] ?? 'pièce');
    DateTime? selectedExpiryDate;

    if (item['expiry_date'] != null) {
      try {
        selectedExpiryDate = DateTime.parse(item['expiry_date']);
      } catch (e) {
        if (kDebugMode) print('Error parsing expiry date: $e');
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                        Icons.edit_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Modifier le produit',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            productName,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: quantityController,
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Quantité *',
                                  prefixIcon: const Icon(Icons.numbers),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: unitController,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Unité',
                                  hintText: 'pièce, kg, L...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate:
                                  selectedExpiryDate ??
                                  DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365 * 2),
                              ),
                            );
                            if (date != null) {
                              setStateDialog(() => selectedExpiryDate = date);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  color: Theme.of(context).iconTheme.color,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    selectedExpiryDate != null
                                        ? 'Expire le ${DateFormat('dd/MM/yyyy').format(selectedExpiryDate!)}'
                                        : 'Date d\'expiration (optionnel)',
                                    style: TextStyle(
                                      color: selectedExpiryDate != null
                                          ? Theme.of(
                                              context,
                                            ).textTheme.bodyLarge?.color
                                          : Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ),
                                if (selectedExpiryDate != null)
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () => setStateDialog(
                                      () => selectedExpiryDate = null,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Informations du produit',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildInfoRowCompact(
                                'Catégorie',
                                item['product_category'] ?? 'Non catégorisé',
                              ),
                              _buildInfoRowCompact(
                                'Source',
                                item['source'] == 'vision'
                                    ? 'Scan auto'
                                    : 'Manuel',
                              ),
                              if (item['added_at'] != null)
                                _buildInfoRowCompact(
                                  'Ajouté',
                                  _formatDate(item['added_at']),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final qty = double.tryParse(quantityController.text);
                          if (qty == null || qty < 0) {
                            _showError('Quantité invalide');
                            return;
                          }

                          try {
                            await _api.updateInventoryItem(
                              fridgeId: _selectedFridgeId!,
                              itemId: item['id'],
                              quantity: qty,
                              expiryDate: selectedExpiryDate,
                            );
                            Navigator.pop(context);
                            _showSuccess('Produit mis à jour');
                            _loadInventory(showLoading: false);
                          } catch (e) {
                            _showError('Erreur: $e');
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Enregistrer'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRowCompact(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showConsumeDialog(Map<String, dynamic> item) async {
    if (_selectedFridgeId == null) return;

    final controller = TextEditingController();
    final productName =
        item['product_name'] ?? 'Produit #${item['product_id']}';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          'Consommer',
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              productName,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                labelText: 'Quantité (${item['unit'] ?? ''})',
                hintText: 'Max: ${item['quantity'] ?? 0}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final qty = double.tryParse(controller.text);
                if (qty == null || qty <= 0) {
                  _showError('Quantité invalide');
                  return;
                }
                await _api.consumeItem(
                  fridgeId: _selectedFridgeId!,
                  itemId: item['id'],
                  quantityConsumed: qty,
                );
                Navigator.pop(context);
                _showSuccess('Article consommé');
                _loadInventory(showLoading: false);
              } catch (e) {
                _showError('Erreur: $e');
              }
            },
            style: ElevatedButton.styleFrom(elevation: 0),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteItem(Map<String, dynamic> item) async {
    if (_selectedFridgeId == null) return;

    final productName =
        item['product_name'] ?? 'Produit #${item['product_id']}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce produit ?'),
        content: Text('$productName sera retiré de votre inventaire.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _api.deleteInventoryItem(
          fridgeId: _selectedFridgeId!,
          itemId: item['id'],
        );
        _showSuccess('Produit supprimé');
        _loadInventory(showLoading: false);
      } catch (e) {
        _showError('Erreur: $e');
      }
    }
  }
}
