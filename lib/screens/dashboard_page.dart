// ============================================================================
// lib/screens/dashboard_page.dart - VERSION REFACTORISÉE
// ============================================================================
// ✅ Cohérent avec le nouveau système de pairing
// ✅ Dialog simplifié sans création manuelle de frigo
// ============================================================================

import 'package:flutter/material.dart';
import 'package:user_smartfridge/screens/search_inventory_page.dart';
import 'package:user_smartfridge/service/api_service.dart';
import '../main.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ClientApiService _api = ClientApiService();
  List<dynamic> _fridges = [];
  Map<String, dynamic>? _selectedFridge;
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();
      setState(() {
        _fridges = fridges;
        if (fridges.isNotEmpty) {
          _selectedFridge = fridges[0];
          _loadStats();
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _handleError(e);
    }
  }

  Future<void> _loadStats() async {
    if (_selectedFridge == null) return;

    try {
      final inventory = await _api.getInventory(_selectedFridge!['id']);
      final alerts = await _api.getAlerts(_selectedFridge!['id'], status: 'pending');

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
      _showError('Erreur de chargement');
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
                    _buildQuickActions(),
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
      backgroundColor: Colors.white,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bonjour 👋',
            style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 2),
          Text(
            'Tableau de bord',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          child: IconButton.filled(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _showPairingDialog,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.kitchen_outlined,
                size: 64,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aucun frigo connecté',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Entrez le code de votre kiosk\npour connecter votre premier frigo',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showPairingDialog,
                icon: const Icon(Icons.link, size: 20),
                label: const Text('Connecter un frigo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFridgeCard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withOpacity(0.3),
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
                  child: const Icon(Icons.kitchen, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Frigo actif',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedFridge?['name'] ?? 'Mon frigo',
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
            if (_selectedFridge?['location'] != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _selectedFridge!['location'],
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
              const Color(0xFF3B82F6),
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

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
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
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Actions rapides',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // ✅ NOUVEAU : Recherche vocale
              Expanded(
                child: _buildActionCard(
                  'Rechercher',
                  'Commande vocale',
                  Icons.mic_outlined,
                  const Color(0xFF3B82F6),
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
                      () {},
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
                  'Créer une liste',
                  Icons.shopping_cart_outlined,
                  const Color(0xFF10B981),
                      () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  'Alertes',
                  'Voir les alertes',
                  Icons.notifications_outlined,
                  const Color(0xFFF59E0B),
                      () {
                    // Navigation vers AlertsPage
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
      String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
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
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // ✅ NOUVEAU : DIALOG DE PAIRING SIMPLIFIÉ
  // ============================================================================

  Future<void> _showPairingDialog() async {
    final codeController = TextEditingController();
    final nameController = TextEditingController(text: 'Mon Frigo');
    final locationController = TextEditingController();
    bool isProcessing = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.link, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Connecter un frigo',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Color(0xFF64748B)),
                          SizedBox(width: 8),
                          Text(
                            'Comment ça marche ?',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. Regardez le code à 6 chiffres sur le kiosk\n'
                            '2. Entrez-le ci-dessous\n'
                            '3. Personnalisez le nom de votre frigo',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: codeController,
                  decoration: InputDecoration(
                    labelText: 'Code à 6 chiffres *',
                    hintText: '123456',
                    prefixIcon: const Icon(Icons.pin),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  enabled: !isProcessing,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Nom du frigo *',
                    hintText: 'Ex: Frigo Cuisine',
                    prefixIcon: const Icon(Icons.kitchen_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  enabled: !isProcessing,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: locationController,
                  decoration: InputDecoration(
                    labelText: 'Localisation (optionnel)',
                    hintText: 'Ex: Cuisine, Bureau',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  enabled: !isProcessing,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton.icon(
              onPressed: isProcessing
                  ? null
                  : () async {
                if (codeController.text.length != 6) {
                  _showError('Le code doit contenir 6 chiffres');
                  return;
                }
                if (nameController.text.isEmpty) {
                  _showError('Donnez un nom à votre frigo');
                  return;
                }

                setState(() => isProcessing = true);

                try {
                  // ✅ APPEL SIMPLIFIÉ : Une seule route fait tout
                  final result = await _api.pairFridge(
                    pairingCode: codeController.text,
                    fridgeName: nameController.text,
                    fridgeLocation: locationController.text.isEmpty
                        ? null
                        : locationController.text,
                  );

                  Navigator.pop(context);

                  // Afficher confirmation
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Color(0xFF10B981),
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('Frigo connecté !'),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Votre frigo "${result['fridge_name']}" est maintenant connecté.',
                            style: const TextStyle(fontSize: 15),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                _buildInfoRow(Icons.kitchen, 'Nom',
                                    result['fridge_name']),
                                if (result['fridge_location'] != null) ...[
                                  const SizedBox(height: 8),
                                  _buildInfoRow(Icons.location_on, 'Lieu',
                                      result['fridge_location']),
                                ],
                                const SizedBox(height: 8),
                                _buildInfoRow(Icons.tag, 'ID',
                                    '#${result['fridge_id']}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _loadData();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Commencer'),
                        ),
                      ],
                    ),
                  );
                } catch (e) {
                  setState(() => isProcessing = false);
                  _showError(e.toString().replaceAll('Exception: ', ''));
                }
              },
              icon: isProcessing
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Icon(Icons.link),
              label: Text(isProcessing ? 'Connexion...' : 'Connecter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(120, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }
}