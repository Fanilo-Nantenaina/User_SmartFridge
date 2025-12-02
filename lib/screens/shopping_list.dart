import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_smartfridge/screens/auth.dart';
import 'package:user_smartfridge/service/api.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class ShoppingListsPage extends StatefulWidget {
  const ShoppingListsPage({super.key});

  @override
  State<ShoppingListsPage> createState() => _ShoppingListsPageState();
}

class _ShoppingListsPageState extends State<ShoppingListsPage>
    with SingleTickerProviderStateMixin {
  final ClientApiService _api = ClientApiService();
  late TabController _tabController;

  List<dynamic> _allLists = [];
  List<dynamic> _activeLists = [];
  List<dynamic> _completedLists = [];
  bool _isLoading = true;
  int? _selectedFridgeId;

  @override
  void initState() {
    super.initState();
    _initializeDateFormatting();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => _filterLists());
    _loadShoppingLists();
  }

  Future<void> _initializeDateFormatting() async {
    await initializeDateFormatting('fr_FR', null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAndReloadIfNeeded();
  }

  Future<void> _checkAndReloadIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFridgeId = prefs.getInt('selected_fridge_id');

    if (savedFridgeId != null &&
        savedFridgeId != _selectedFridgeId &&
        !_isLoading) {
      _loadShoppingLists();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShoppingLists() async {
    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();

      if (fridges.isEmpty) {
        setState(() {
          _allLists = [];
          _selectedFridgeId = null;
          _isLoading = false;
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      int? savedFridgeId = prefs.getInt('selected_fridge_id');

      if (savedFridgeId != null &&
          fridges.any((f) => f['id'] == savedFridgeId)) {
        _selectedFridgeId = savedFridgeId;
      } else {
        _selectedFridgeId = fridges[0]['id'];
        await prefs.setInt('selected_fridge_id', _selectedFridgeId!);
      }

      final lists = await _api.getShoppingLists(fridgeId: _selectedFridgeId);

      setState(() {
        _allLists = lists;
        _filterLists();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _handleError(e);
    }
  }

  void _filterLists() {
    setState(() {
      _activeLists = _allLists.where((list) {
        final items = list['items'] as List? ?? [];
        return items.any((item) => item['status'] == 'pending');
      }).toList();

      _completedLists = _allLists.where((list) {
        final items = list['items'] as List? ?? [];
        return items.isNotEmpty &&
            items.every((item) => item['status'] == 'purchased');
      }).toList();
    });
  }

  void _handleError(dynamic e) {
    if (e.toString().contains('Non autorisé') ||
        e.toString().contains('401')) {
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _selectedFridgeId != null
          ? FloatingActionButton.extended(
        onPressed: _showCreateListDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle liste'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      )
          : null,
      body: Column(
        children: [
          _buildAppBar(),
          _buildTabBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedFridgeId == null
                ? _buildNoFridgeState()
                : _buildListsView(),
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
              'Connectez un frigo depuis le tableau de bord\npour créer des listes de courses',
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
                  'Listes de courses',
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
                      '${_allLists.length} liste(s)',
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
            icon: Icon(Icons.refresh,
                color: Theme.of(context).iconTheme.color),
            onPressed: _loadShoppingLists,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
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
          Tab(text: 'En cours (${_activeLists.length})'),
          Tab(text: 'Terminées (${_completedLists.length})'),
        ],
      ),
    );
  }

  Widget _buildListsView() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildActiveListsTab(),
        _buildCompletedListsTab(),
      ],
    );
  }

  Widget _buildActiveListsTab() {
    if (_activeLists.isEmpty) {
      return _buildEmptyState(
        Icons.shopping_cart_outlined,
        'Aucune liste en cours',
        'Créez une nouvelle liste de courses\npour commencer',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadShoppingLists,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _activeLists.length,
        itemBuilder: (context, index) =>
            _buildListCard(_activeLists[index], isCompleted: false),
      ),
    );
  }

  Widget _buildCompletedListsTab() {
    if (_completedLists.isEmpty) {
      return _buildEmptyState(
        Icons.check_circle_outline,
        'Aucune liste terminée',
        'Vos listes complétées\napparaîtront ici',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadShoppingLists,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _completedLists.length,
        itemBuilder: (context, index) =>
            _buildListCard(_completedLists[index], isCompleted: true),
      ),
    );
  }

  Widget _buildListCard(Map<String, dynamic> list,
      {required bool isCompleted}) {
    final items = list['items'] as List? ?? [];
    final pendingCount =
        items.where((item) => item['status'] == 'pending').length;
    final purchasedCount =
        items.where((item) => item['status'] == 'purchased').length;
    final totalCount = items.length;

    final createdAt = DateTime.parse(list['created_at']);
    final generatedBy = list['generated_by'] ?? 'manual';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFF10B981).withOpacity(0.3)
              : Theme.of(context).colorScheme.outline,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showListDetails(list, isCompleted: isCompleted),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color(0xFF10B981).withOpacity(0.1)
                            : Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isCompleted
                            ? Icons.check_circle
                            : Icons.shopping_cart,
                        color: isCompleted
                            ? const Color(0xFF10B981)
                            : Theme.of(context).colorScheme.primary,
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
                                  'Liste du ${_formatDate(createdAt)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color,
                                  ),
                                ),
                              ),
                              _buildGeneratedByBadge(generatedBy),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.inventory_2,
                                  size: 14,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color),
                              const SizedBox(width: 4),
                              Text(
                                '$totalCount article(s)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color,
                                ),
                              ),
                              if (!isCompleted) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.pending_outlined,
                                    size: 14,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color),
                                const SizedBox(width: 4),
                                Text(
                                  '$pendingCount restant(s)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert,
                          color: Theme.of(context).iconTheme.color),
                      onSelected: (value) {
                        switch (value) {
                          case 'view':
                            _showListDetails(list, isCompleted: isCompleted);
                            break;
                          case 'delete':
                            _confirmDeleteList(list);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Row(
                            children: [
                              Icon(Icons.visibility_outlined, size: 20),
                              SizedBox(width: 12),
                              Text('Voir détails'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red),
                              SizedBox(width: 12),
                              Text('Supprimer',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!isCompleted && totalCount > 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: purchasedCount / totalCount,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      color: const Color(0xFF10B981),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${((purchasedCount / totalCount) * 100).toInt()}% complété',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneratedByBadge(String generatedBy) {
    IconData icon;
    Color color;
    String label;

    switch (generatedBy) {
      case 'ai_suggestion':
        icon = Icons.auto_awesome;
        color = const Color(0xFF8B5CF6);
        label = 'IA';
        break;
      case 'auto_recipe':
        icon = Icons.restaurant;
        color = const Color(0xFFF59E0B);
        label = 'Recette';
        break;
      default:
        icon = Icons.edit;
        color = Theme.of(context).colorScheme.primary;
        label = 'Manuel';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showListDetails(Map<String, dynamic> list,
      {required bool isCompleted}) {
    final items = List<Map<String, dynamic>>.from(list['items'] ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
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
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.primary,
                                Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isCompleted
                                ? Icons.check_circle
                                : Icons.shopping_cart,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Liste du ${_formatDate(DateTime.parse(list['created_at']))}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color,
                                ),
                              ),
                              Text(
                                '${items.length} article(s)',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isCompleted)
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            color: Theme.of(context).colorScheme.primary,
                            onPressed: () {
                              Navigator.pop(context);
                              _showAddItemDialog(list['id']);
                            },
                            tooltip: 'Ajouter un article',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                  child: Text(
                    'Aucun article dans cette liste',
                    style: TextStyle(
                      color:
                      Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildListItemTile(
                      item,
                      list['id'],
                      isCompleted,
                      onStatusChanged: () {
                        // ✅ Mettre à jour l'état local ET le modal
                        setModalState(() {
                          item['status'] = item['status'] == 'purchased'
                              ? 'pending'
                              : 'purchased';
                        });
                        setState(() {});  // ✅ Rafraîchir la liste principale
                      },
                    );
                  },
                ),
              ),
              if (!isCompleted && items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
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
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await _api.markAllAsPurchased(list['id']);
                            Navigator.pop(context);
                            _showSuccess('Tous les articles marqués comme achetés');
                            await _loadShoppingLists();  // ✅ Recharger
                          } catch (e) {
                            _showError('Erreur: $e');
                          }
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Tout marquer comme acheté'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListItemTile(
      Map<String, dynamic> item,
      int listId,
      bool isCompleted,
      {VoidCallback? onStatusChanged}
      ) {
    final status = item['status'] ?? 'pending';
    final isPurchased = status == 'purchased';
    final productName = item['product_name'] ?? 'Article';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPurchased
              ? const Color(0xFF10B981).withOpacity(0.3)
              : Colors.transparent,
        ),
      ),
      child: CheckboxListTile(
        value: isPurchased,
        onChanged: isCompleted
            ? null
            : (value) async {
          try {
            final newStatus = value! ? 'purchased' : 'pending';

            // ✅ Appeler l'API avec le bon format
            await _api.updateShoppingListItemStatus(
              listId: listId,
              itemId: item['id'],
              status: newStatus,
            );

            // ✅ Notifier le changement
            onStatusChanged?.call();

          } catch (e) {
            _showError('Erreur: $e');
          }
        },
        activeColor: const Color(0xFF10B981),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          productName,
          style: TextStyle(
            decoration: isPurchased ? TextDecoration.lineThrough : null,
            color: isPurchased
                ? Theme.of(context).textTheme.bodyMedium?.color
                : Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: isPurchased ? FontWeight.normal : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${item['quantity']} ${item['unit']}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        secondary: isCompleted
            ? null
            : IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          color: Colors.red,
          onPressed: () => _confirmDeleteItem(listId, item['id']),
        ),
      ),
    );
  }

  Future<void> _showCreateListDialog() async {
    if (_selectedFridgeId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Theme.of(context).cardColor,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.add_shopping_cart,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Nouvelle liste')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comment voulez-vous créer votre liste ?',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 20),
            _buildCreateOptionButton(
              icon: Icons.auto_awesome,
              title: 'Génération IA',
              subtitle: 'Basée sur votre inventaire',
              color: const Color(0xFF8B5CF6),
              onTap: () {
                Navigator.pop(context);
                _generateAIList();
              },
            ),
            const SizedBox(height: 12),
            _buildCreateOptionButton(
              icon: Icons.restaurant,
              title: 'Depuis des recettes',
              subtitle: 'Sélectionner des recettes',
              color: const Color(0xFFF59E0B),
              onTap: () {
                Navigator.pop(context);
                _showRecipeSelectionDialog();
              },
            ),
            const SizedBox(height: 12),
            _buildCreateOptionButton(
              icon: Icons.edit,
              title: 'Liste manuelle',
              subtitle: 'Ajouter manuellement',
              color: Theme.of(context).colorScheme.primary,
              onTap: () {
                Navigator.pop(context);
                _createManualList();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateOptionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
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
            Icon(Icons.arrow_forward_ios, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAIList() async {
    // TODO: Implémenter la génération IA
    _showError('Fonctionnalité en développement');
  }

  Future<void> _showRecipeSelectionDialog() async {
    // TODO: Implémenter la sélection de recettes
    _showError('Fonctionnalité en développement');
  }

  Future<void> _createManualList() async {
    // Créer une liste vide
    try {
      // TODO: Adapter selon votre API
      _showSuccess('Liste créée ! Ajoutez des articles.');
      _loadShoppingLists();
    } catch (e) {
      _showError('Erreur: $e');
    }
  }

  Future<void> _showAddItemDialog(int listId) async {
    // TODO: Implémenter l'ajout d'article
    _showError('Fonctionnalité en développement');
  }

  Future<void> _confirmDeleteItem(int listId, int itemId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l\'article'),
        content: const Text('Voulez-vous retirer cet article de la liste ?'),
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
        await _api.deleteShoppingListItem(listId: listId, itemId: itemId);
        _showSuccess('Article supprimé');
        _loadShoppingLists();
      } catch (e) {
        _showError('Erreur: $e');
      }
    }
  }

  Future<void> _confirmDeleteList(Map<String, dynamic> list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer la liste'),
        content: Text(
          'Voulez-vous supprimer cette liste de courses ?\n\n'
              '${list['items'].length} article(s) seront également supprimés.',
        ),
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
        await _api.deleteShoppingList(listId: list['id']);
        _showSuccess('Liste supprimée');
        _loadShoppingLists();
      } catch (e) {
        _showError('Erreur: $e');
      }
    }
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
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
                icon,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
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

  String _formatDate(DateTime date) {
    try {
      return DateFormat('d MMMM yyyy', 'fr_FR').format(date);
    } catch (e) {
      // Fallback si l'initialisation échoue
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}