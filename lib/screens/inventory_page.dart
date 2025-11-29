import 'package:flutter/material.dart';
import 'package:user_smartfridge/main.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({Key? key}) : super(key: key);

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final ClientApiService _api = ClientApiService();
  List<dynamic> _inventory = [];
  bool _isLoading = true;
  int? _selectedFridgeId;

  @override
  void initState() {
    super.initState();
    _loadInventory();
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

      setState(() {
        _inventory = inventory;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erreur: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Inventaire'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {/* Implement search */},
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {/* Implement filter */},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _inventory.isEmpty
          ? _buildEmptyState()
          : _buildInventoryList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddItemDialog,
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 100, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Aucun produit',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Commencez par ajouter des produits',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddItemDialog,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un produit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryList() {
    // Group by expiry status
    final expired = _inventory.where((item) {
      if (item['expiry_date'] == null) return false;
      return DateTime.parse(item['expiry_date']).isBefore(DateTime.now());
    }).toList();

    final expiringSoon = _inventory.where((item) {
      if (item['expiry_date'] == null) return false;
      final expiry = DateTime.parse(item['expiry_date']);
      final days = expiry.difference(DateTime.now()).inDays;
      return days >= 0 && days <= 3;
    }).toList();

    final others = _inventory.where((item) {
      if (item['expiry_date'] == null) return true;
      final expiry = DateTime.parse(item['expiry_date']);
      return expiry.difference(DateTime.now()).inDays > 3;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadInventory,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (expired.isNotEmpty) ...[
            _buildSectionHeader('Expirés', expired.length, Colors.red),
            ...expired.map((item) => _buildInventoryItem(item, Colors.red)),
            const SizedBox(height: 16),
          ],
          if (expiringSoon.isNotEmpty) ...[
            _buildSectionHeader('À consommer rapidement', expiringSoon.length, Colors.orange),
            ...expiringSoon.map((item) => _buildInventoryItem(item, Colors.orange)),
            const SizedBox(height: 16),
          ],
          if (others.isNotEmpty) ...[
            _buildSectionHeader('Tous les produits', others.length, Colors.green),
            ...others.map((item) => _buildInventoryItem(item, Colors.green)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryItem(Map<String, dynamic> item, Color accentColor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.shopping_basket, color: accentColor),
        ),
        title: Text(
          'Produit #${item['product_id']}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${item['quantity']} ${item['unit']}'),
            if (item['expiry_date'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: accentColor),
                  const SizedBox(width: 4),
                  Text(
                    _formatExpiryDate(item['expiry_date']),
                    style: TextStyle(color: accentColor, fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'consume',
              child: Row(
                children: [
                  Icon(Icons.remove_circle_outline),
                  SizedBox(width: 8),
                  Text('Consommer'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit),
                  SizedBox(width: 8),
                  Text('Modifier'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Supprimer', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) => _handleItemAction(value.toString(), item),
        ),
      ),
    );
  }

  String _formatExpiryDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final diff = date.difference(now).inDays;

    if (diff < 0) return 'Expiré';
    if (diff == 0) return 'Expire aujourd\'hui';
    if (diff == 1) return 'Expire demain';
    return 'Expire dans $diff jours';
  }

  void _handleItemAction(String action, Map<String, dynamic> item) {
    switch (action) {
      case 'consume':
        _showConsumeDialog(item);
        break;
      case 'edit':
      // Implement edit
        break;
      case 'delete':
      // Implement delete
        break;
    }
  }

  Future<void> _showConsumeDialog(Map<String, dynamic> item) async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Consommer'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Quantité (${item['unit']})',
            hintText: 'Max: ${item['quantity']}',
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
                await _api.consumeItem(
                  fridgeId: _selectedFridgeId!,
                  itemId: item['id'],
                  quantityConsumed: double.parse(controller.text),
                );
                Navigator.pop(context);
                _loadInventory();
              } catch (e) {
                _showError('Erreur: $e');
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddItemDialog() async {
    // Implement add item dialog
  }
}