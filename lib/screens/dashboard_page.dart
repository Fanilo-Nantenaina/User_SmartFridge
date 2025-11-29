import 'package:flutter/material.dart';
import 'package:user_smartfridge/main.dart';

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
      _showError('Erreur: $e');
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
      _showError('Erreur de chargement des statistiques');
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
        title: const Text('Tableau de bord'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddFridgeDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _showPairingDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFridgeSelector(),
              const SizedBox(height: 24),
              _buildStatsCards(),
              const SizedBox(height: 24),
              _buildQuickActions(),
              const SizedBox(height: 24),
              _buildRecentActivity(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFridgeSelector() {
    if (_fridges.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.kitchen_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Aucun frigo configuré',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ajoutez votre premier frigo pour commencer',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showAddFridgeDialog,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un frigo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade400, Colors.purple.shade600],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                child: const Icon(Icons.kitchen, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Frigo actuel',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      _selectedFridge?['name'] ?? 'Mon frigo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (_fridges.length > 1)
                PopupMenuButton<Map<String, dynamic>>(
                  icon: const Icon(Icons.swap_horiz, color: Colors.white),
                  onSelected: (fridge) {
                    setState(() => _selectedFridge = fridge);
                    _loadStats();
                  },
                  itemBuilder: (context) => _fridges
                      .map<PopupMenuEntry<Map<String, dynamic>>>(
                        (f) => PopupMenuItem<Map<String, dynamic>>(
                      value: f,
                      child: Text(f['name']),
                    ),
                  )
                      .toList(),
                ),
            ],
          ),
          if (_selectedFridge?['location'] != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Text(
                  _selectedFridge!['location'],
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Articles',
            _stats['total_items']?.toString() ?? '0',
            Icons.inventory_2,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Alertes',
            _stats['pending_alerts']?.toString() ?? '0',
            Icons.notification_important,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'À consommer',
            _stats['expiring_soon']?.toString() ?? '0',
            Icons.warning,
            Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
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
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actions rapides',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                'Scanner',
                Icons.camera_alt,
                Colors.deepPurple,
                    () {/* Navigate to vision scan */},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                'Liste de courses',
                Icons.shopping_cart,
                Colors.green,
                    () {/* Navigate to shopping list */},
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(
      String label,
      IconData icon,
      Color color,
      VoidCallback onTap,
      ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Activité récente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            TextButton(
              onPressed: () {/* Navigate to events */},
              child: const Text('Voir tout'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.deepPurple.withOpacity(0.1),
                child: const Icon(Icons.history, color: Colors.deepPurple),
              ),
              title: const Text('Activité récente'),
              subtitle: const Text('Il y a quelques minutes'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddFridgeDialog() async {
    final nameController = TextEditingController();
    final locationController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau frigo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nom',
                prefixIcon: Icon(Icons.kitchen),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(
                labelText: 'Emplacement',
                prefixIcon: Icon(Icons.location_on),
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
                await _api.createFridge(
                  name: nameController.text,
                  location: locationController.text.isEmpty
                      ? null
                      : locationController.text,
                );
                Navigator.pop(context);
                _loadData();
              } catch (e) {
                _showError('Erreur: $e');
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPairingDialog() async {
    final codeController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jumeler un appareil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Entrez le code affiché sur le frigo:'),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Code à 6 chiffres',
                prefixIcon: Icon(Icons.pin),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
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
                await _api.pairDevice(codeController.text);
                Navigator.pop(context);
                _showSuccess('Appareil jumelé avec succès!');
              } catch (e) {
                _showError('Code invalide ou expiré');
              }
            },
            child: const Text('Jumeler'),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
}
