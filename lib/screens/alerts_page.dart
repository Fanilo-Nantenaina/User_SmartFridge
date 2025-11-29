import 'package:flutter/material.dart';
import 'package:user_smartfridge/main.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({Key? key}) : super(key: key);

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  final ClientApiService _api = ClientApiService();
  List<dynamic> _alerts = [];
  bool _isLoading = true;
  String _filter = 'pending';

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();
      if (fridges.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final alerts = await _api.getAlerts(fridges[0]['id'], status: _filter);

      setState(() {
        _alerts = alerts;
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
        title: const Text('Alertes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAlerts,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _alerts.isEmpty
                ? _buildEmptyState()
                : _buildAlertsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('En attente', 'pending'),
            const SizedBox(width: 8),
            _buildFilterChip('Toutes', ''),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _filter = value);
          _loadAlerts();
        }
      },
      backgroundColor: Colors.white,
      selectedColor: Colors.deepPurple.withOpacity(0.1),
      checkmarkColor: Colors.deepPurple,
      labelStyle: TextStyle(
        color: isSelected ? Colors.deepPurple : Colors.black87,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 100, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Aucune alerte',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Tout va bien ! 👍',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsList() {
    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _alerts.length,
        itemBuilder: (context, index) => _buildAlertCard(_alerts[index]),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final type = alert['type'] ?? '';
    final color = _getAlertColor(type);
    final icon = _getAlertIcon(type);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          _getAlertTitle(type),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(alert['message'] ?? ''),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            alert['status'] ?? 'pending',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Color _getAlertColor(String type) {
    switch (type) {
      case 'EXPIRED':
        return Colors.red;
      case 'EXPIRY_SOON':
        return Colors.orange;
      case 'LOST_ITEM':
        return Colors.yellow.shade700;
      case 'LOW_STOCK':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getAlertIcon(String type) {
    switch (type) {
      case 'EXPIRED':
        return Icons.dangerous;
      case 'EXPIRY_SOON':
        return Icons.warning;
      case 'LOST_ITEM':
        return Icons.search_off;
      case 'LOW_STOCK':
        return Icons.trending_down;
      default:
        return Icons.notification_important;
    }
  }

  String _getAlertTitle(String type) {
    switch (type) {
      case 'EXPIRED':
        return 'Produit expiré';
      case 'EXPIRY_SOON':
        return 'Expiration proche';
      case 'LOST_ITEM':
        return 'Objet non détecté';
      case 'LOW_STOCK':
        return 'Stock faible';
      default:
        return 'Alerte';
    }
  }
}
