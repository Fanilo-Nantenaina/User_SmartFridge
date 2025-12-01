import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_smartfridge/main.dart';
import 'package:user_smartfridge/service/api.dart';
import 'package:user_smartfridge/service/realtime.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> with SingleTickerProviderStateMixin {
  final ClientApiService _api = ClientApiService();
  late RealtimeService _realtimeService;

  List<dynamic> _inventory = [];
  List<dynamic> _filteredInventory = [];
  List<dynamic> _products = [];
  bool _isLoading = true;
  int? _selectedFridgeId;
  String _searchQuery = '';
  late TabController _tabController;

  StreamSubscription<InventoryUpdateEvent>? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => _filterInventory());
    _loadInventory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _realtimeSubscription?.cancel();
    _realtimeService.dispose();
    super.dispose();
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();
      if (fridges.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      _selectedFridgeId = fridges[0]['id'];
      final inventory = await _api.getInventory(_selectedFridgeId!);
      final products = await _api.getProducts();

      setState(() {
        _inventory = inventory;
        _products = products;
        _filterInventory();
        _isLoading = false;
      });

      _startRealtimeListener();

    } catch (e) {
      setState(() => _isLoading = false);
      _handleError(e);
    }
  }

  Future<void> _startRealtimeListener() async {
    if (_selectedFridgeId == null) return;

    final prefs = await SharedPreferences.getInstance();
    var accessToken = prefs.getString('access_token');

    _realtimeService = RealtimeService(
      baseUrl: ClientApiService.baseUrl,
      accessToken: accessToken!,
      fridgeId: _selectedFridgeId!,
    );

    _realtimeSubscription = _realtimeService
        .listenToInventoryUpdates()
        .listen(
          (event) {
        if (kDebugMode) {
          print('Événement reçu: ${event.type}');
        }

        _showRealtimeNotification(event);

        _loadInventory();
      },
      onError: (error) {
        if (kDebugMode) {
          print('Erreur temps réel: $error');
        }
      },
    );
  }

  void _showRealtimeNotification(InventoryUpdateEvent event) {
    final icon = switch (event.type) {
      InventoryUpdateType.updated => Icons.update,
      InventoryUpdateType.consumed => Icons.remove_circle_outline,
      InventoryUpdateType.alert => Icons.warning,
      InventoryUpdateType.expired => Icons.dangerous,
    };

    final color = switch (event.type) {
      InventoryUpdateType.updated => Colors.blue,
      InventoryUpdateType.consumed => Colors.green,
      InventoryUpdateType.alert => Colors.orange,
      InventoryUpdateType.expired => Colors.red,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(event.message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _filterInventory() {
    final now = DateTime.now();
    setState(() {
      List<dynamic> filtered = _inventory;

      if (_searchQuery.isNotEmpty) {
        filtered = filtered.where((item) {
          final productName = _getProductName(item['product_id']);
          return productName.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();
      }

      switch (_tabController.index) {
        case 0:
          _filteredInventory = filtered;
          break;
        case 1:
          _filteredInventory = filtered.where((item) {
            if (item['expiry_date'] == null) return false;
            final expiry = DateTime.parse(item['expiry_date']);
            return expiry.difference(now).inDays <= 3 && expiry.isAfter(now);
          }).toList();
          break;
        case 2:
          _filteredInventory = filtered.where((item) {
            if (item['expiry_date'] == null) return false;
            return DateTime.parse(item['expiry_date']).isBefore(now);
          }).toList();
          break;
      }
    });
  }

  String _getProductName(int productId) {
    try {
      final product = _products.firstWhere((p) => p['id'] == productId);
      return product['name'] ?? 'Produit #$productId';
    } catch (e) {
      return 'Produit #$productId';
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
      _showError('Erreur: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildAppBar(),
          _buildSearchBar(),
          _buildTabBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _inventory.isEmpty
                ? _buildEmptyState()
                : _buildInventoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Inventaire',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_inventory.length} produits',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadInventory,
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
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
        decoration: InputDecoration(
          hintText: 'Rechercher un produit...',
          prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF3B82F6),
        unselectedLabelColor: const Color(0xFF64748B),
        indicatorColor: const Color(0xFF3B82F6),
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Tous'),
          Tab(text: 'À consommer'),
          Tab(text: 'Expirés'),
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
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aucun produit',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Scannez des produits depuis le frigo\npour remplir votre inventaire',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                height: 1.5,
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
              const Icon(
                Icons.search_off,
                size: 64,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(height: 16),
              const Text(
                'Aucun résultat',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Aucun produit ne correspond à "$_searchQuery"'
                    : 'Aucun produit dans cette catégorie',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInventory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredInventory.length,
        itemBuilder: (context, index) {
          return _buildInventoryItem(_filteredInventory[index]);
        },
      ),
    );
  }

  Widget _buildInventoryItem(Map<String, dynamic> item) {
    final expiryDate = item['expiry_date'] != null
        ? DateTime.parse(item['expiry_date'])
        : null;
    final daysUntilExpiry = expiryDate?.difference(DateTime.now()).inDays;

    Color statusColor = const Color(0xFF10B981);
    String statusText = 'Frais';
    IconData statusIcon = Icons.check_circle_outline;

    if (daysUntilExpiry != null) {
      if (daysUntilExpiry < 0) {
        statusColor = const Color(0xFFEF4444);
        statusText = 'Expiré';
        statusIcon = Icons.cancel_outlined;
      } else if (daysUntilExpiry == 0) {
        statusColor = const Color(0xFFEF4444);
        statusText = 'Expire aujourd\'hui';
        statusIcon = Icons.warning_outlined;
      } else if (daysUntilExpiry <= 3) {
        statusColor = const Color(0xFFF59E0B);
        statusText = 'Expire bientôt';
        statusIcon = Icons.schedule_outlined;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                      Text(
                        _getProductName(item['product_id']),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${item['quantity']} ${item['unit']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (expiryDate != null) ...[
                            const SizedBox(width: 8),
                            Icon(statusIcon, size: 14, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                color: statusColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (expiryDate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatExpiryDate(item['expiry_date']),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Color(0xFF94A3B8)),
                  onPressed: () => _showItemMenu(item),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatExpiryDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    return DateFormat('d MMM yyyy', 'fr_FR').format(date);
  }

  void _showItemDetails(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _getProductName(item['product_id']),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 24),
            _buildDetailRow('Quantité', '${item['quantity']} ${item['unit']}'),
            if (item['expiry_date'] != null)
              _buildDetailRow('Expiration', _formatExpiryDate(item['expiry_date'])),
            _buildDetailRow('Source', item['source'] ?? 'Manuel'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showConsumeDialog(item);
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Consommer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
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
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showItemMenu(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: Color(0xFF3B82F6)),
              title: const Text('Consommer'),
              onTap: () {
                Navigator.pop(context);
                _showConsumeDialog(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConsumeDialog(Map<String, dynamic> item) async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Consommer'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Quantité (${item['unit']})',
            hintText: 'Max: ${item['quantity']}',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
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
                _loadInventory();
              } catch (e) {
                _showError('Erreur: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }
}