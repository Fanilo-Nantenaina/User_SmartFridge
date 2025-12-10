import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:user_smartfridge/screens/auth.dart';
import 'package:user_smartfridge/service/api.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:user_smartfridge/service/fridge.dart';

class ShoppingListsPage extends StatefulWidget {
  const ShoppingListsPage({super.key});

  @override
  State<ShoppingListsPage> createState() => _ShoppingListsPageState();
}

class _ShoppingListsPageState extends State<ShoppingListsPage>
    with SingleTickerProviderStateMixin {
  final ClientApiService _api = ClientApiService();
  late TabController _tabController;

  final _fridgeService = FridgeService();
  StreamSubscription<int?>? _fridgeSubscription;

  String _currentSort = 'date';
  String _sortOrder = 'desc';

  List<dynamic> _allLists = [];
  List<dynamic> _activeLists = [];
  List<dynamic> _completedLists = [];
  bool _isLoading = true;
  int? _selectedFridgeId;

  bool _isDiscovering = false;

  static const List<String> _availableUnits = [
    'pièce',
    'g',
    'kg',
    'ml',
    'L',
    'cl',
    'sachet',
    'boîte',
    'paquet',
    'bouteille',
    'pot',
    'tranche',
    'portion',
    'cuillère à café',
    'cuillère à soupe',
  ];

  @override
  void initState() {
    super.initState();
    _initializeDateFormatting();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => _filterLists());

    _fridgeSubscription = _fridgeService.fridgeStream.listen((fridgeId) {
      if (fridgeId != null && fridgeId != _selectedFridgeId) {
        _selectedFridgeId = fridgeId;
        _loadShoppingLists();
      }
    });

    _loadShoppingLists();
  }

  Future<void> _initializeDateFormatting() async {
    await initializeDateFormatting('fr_FR', null);
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Trier par date'),
              trailing: _currentSort == 'date' ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _currentSort = 'date');
                Navigator.pop(context);
                _loadShoppingLists();
              },
            ),
            ListTile(
              leading: const Icon(Icons.label),
              title: const Text('Trier par nom'),
              trailing: _currentSort == 'name' ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _currentSort = 'name');
                Navigator.pop(context);
                _loadShoppingLists();
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: Text(
                'Ordre: ${_sortOrder == 'desc' ? 'Décroissant' : 'Croissant'}',
              ),
              onTap: () {
                setState(
                  () => _sortOrder = _sortOrder == 'desc' ? 'asc' : 'desc',
                );
                Navigator.pop(context);
                _loadShoppingLists();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fridgeSubscription?.cancel();
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

      final lists = await _api.getShoppingLists(
        fridgeId: _selectedFridgeId,
        sortBy: _currentSort,
        sortOrder: _sortOrder,
      );
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

  bool _isListEditable(Map<String, dynamic> list) {
    final generatedBy = list['generated_by'] ?? 'manual';
    return generatedBy == 'manual';
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
            icon: const Icon(Icons.sort),
            onPressed: _showSortOptions,
            tooltip: 'Trier',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
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
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('En cours'),
                if (_activeLists.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_activeLists.length}',
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
                const Text('Terminées'),
                if (_completedLists.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_completedLists.length}',
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

  Widget _buildListsView() {
    return TabBarView(
      controller: _tabController,
      children: [_buildActiveListsTab(), _buildCompletedListsTab()],
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

  Widget _buildListCard(
    Map<String, dynamic> list, {
    required bool isCompleted,
  }) {
    final items = list['items'] as List? ?? [];
    final pendingCount = items
        .where((item) => item['status'] == 'pending')
        .length;
    final purchasedCount = items
        .where((item) => item['status'] == 'purchased')
        .length;
    final totalCount = items.length;
    final createdAt = DateTime.parse(list['created_at']);
    final generatedBy = list['generated_by'] ?? 'manual';
    final listName = list['name'] ?? 'Liste du ${_formatDate(createdAt)}';

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
                            : Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check_circle : Icons.shopping_cart,
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
                                  listName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color,
                                  ),
                                ),
                              ),
                              _buildGeneratedByBadge(generatedBy),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2,
                                size: 14,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$totalCount article(s)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.color,
                                ),
                              ),
                              if (!isCompleted) ...[
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.pending_outlined,
                                  size: 14,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.color,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$pendingCount restant(s)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ],
                          ),
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
                if (!isCompleted && totalCount > 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: purchasedCount / totalCount,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
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

  Future<void> _showCreateListDialog() async {
    if (_selectedFridgeId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
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
                              Theme.of(context).colorScheme.secondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.add_shopping_cart,
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
                              'Nouvelle liste',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                            Text(
                              'Choisissez comment créer votre liste',
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
            // Options
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildCreateOptionTile(
                      icon: Icons.auto_awesome,
                      title: 'Génération intelligente',
                      subtitle:
                          'L\'IA analyse votre inventaire et suggère les produits manquants',
                      color: const Color(0xFF8B5CF6),
                      onTap: () {
                        Navigator.pop(context);
                        _generateAIList();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildCreateOptionTile(
                      icon: Icons.restaurant_menu,
                      title: 'Depuis des recettes',
                      subtitle:
                          'Sélectionnez des recettes pour générer la liste des ingrédients',
                      color: const Color(0xFFF59E0B),
                      onTap: () {
                        Navigator.pop(context);
                        _showRecipeSelectionDialog();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildCreateOptionTile(
                      icon: Icons.edit_note,
                      title: 'Liste manuelle',
                      subtitle:
                          'Créez votre propre liste en ajoutant les articles un par un',
                      color: const Color(0xFF10B981),
                      onTap: () {
                        Navigator.pop(context);
                        _createManualList();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isDisabled = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createManualList() async {
    if (_selectedFridgeId == null) {
      _showError('Aucun frigo sélectionné');
      return;
    }

    List<Map<String, dynamic>> tempItems = [];
    String listName = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
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
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.edit_note,
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
                                'Liste manuelle',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              Text(
                                '${tempItems.length} article(s) ajouté(s)',
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  onChanged: (value) => setDialogState(() => listName = value),
                  decoration: InputDecoration(
                    labelText: 'Nom de la liste',
                    hintText: 'Ex: Courses hebdomadaires',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.label_outline),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final item = await _showAddItemDialog();
                      if (item != null) {
                        setDialogState(() => tempItems.add(item));
                      }
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Ajouter un article'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: tempItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart_outlined,
                              size: 64,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            const Text('Ajoutez des articles à votre liste'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: tempItems.length,
                        itemBuilder: (context, index) {
                          final item = tempItems[index];
                          final name =
                              item['custom_name'] ?? item['product_name'];
                          return ListTile(
                            leading: const Icon(Icons.shopping_bag_outlined),
                            title: Text(name),
                            subtitle: Text(
                              '${item['quantity']} ${item['unit']}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () => setDialogState(
                                () => tempItems.removeAt(index),
                              ),
                            ),
                          );
                        },
                      ),
              ),
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
                      onPressed: tempItems.isEmpty || listName.trim().isEmpty
                          ? null
                          : () {
                              Navigator.pop(context);
                              _saveManualList(tempItems, listName.trim());
                            },
                      icon: const Icon(Icons.save),
                      label: const Text('Créer la liste'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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

  Future<void> _saveManualList(
    List<Map<String, dynamic>> items,
    String name,
  ) async {
    if (items.isEmpty) {
      _showError('Ajoutez au moins un article à la liste');
      return;
    }

    final String finalName = name.trim().isNotEmpty == true
        ? name.trim()
        : 'Liste manuelle du ${_formatDate(DateTime.now())}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Création de la liste...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _api.createShoppingListWithItems(
        fridgeId: _selectedFridgeId!,
        items: items,
        name: finalName,
      );

      if (!mounted) return;

      Navigator.pop(context);
      Navigator.pop(context);

      _showSuccess('Liste "$finalName" créée !');

      await _loadShoppingLists();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Erreur : $e');
    }
  }

  Future<void> _saveSuggestedList(Map<String, dynamic> suggestion) async {
    if (_selectedFridgeId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Création de la liste...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final products = (suggestion['suggested_products'] as List).map((p) {
        return {
          'product_name': p['name'],
          'quantity': (p['quantity'] as num).toDouble(),
          'unit': p['unit'] ?? 'pièce',
        };
      }).toList();

      await _api.createShoppingListWithItems(
        fridgeId: _selectedFridgeId!,
        items: products,
        name: 'Liste variée IA',
      );

      if (!mounted) return;
      Navigator.pop(context); // Fermer le loading

      _showSuccess('Liste créée avec ${products.length} produits variés !');
      await _loadShoppingLists();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Erreur : $e');
    }
  }

  Future<void> _showSuggestedProductsDialog(
    Map<String, dynamic> suggestion,
  ) async {
    final suggestedProducts =
        suggestion['suggested_products'] as List<dynamic>? ?? [];
    final diversityNote = suggestion['diversity_note'] as String? ?? '';

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
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
                            color: const Color(0xFF8B5CF6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
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
                                'Suggestions IA',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              Text(
                                '${suggestedProducts.length} produits variés',
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
                      ],
                    ),
                    if (diversityNote.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF8B5CF6).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lightbulb_outline,
                              color: Color(0xFF8B5CF6),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                diversityNote,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),

              // Liste des produits suggérés
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: suggestedProducts.length,
                  itemBuilder: (context, index) {
                    final product = suggestedProducts[index];
                    final name = product['name'] ?? 'Produit';
                    final category = product['category'] ?? 'Divers';
                    final quantity = product['quantity'] ?? 1;
                    final unit = product['unit'] ?? 'pièce';
                    final reason = product['reason'] ?? '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF8B5CF6).withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF8B5CF6,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _getCategoryIcon(category),
                                  color: const Color(0xFF8B5CF6),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                    Text(
                                      category,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF8B5CF6,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$quantity $unit',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF8B5CF6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (reason.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              reason,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Actions
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
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _generateAIList();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Autre suggestion'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                            ),
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
                            _saveSuggestedList(suggestion);
                          },
                          icon: const Icon(Icons.save),
                          label: const Text('Enregistrer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    final categoryLower = category.toLowerCase();

    if (categoryLower.contains('fruit')) {
      return Icons.apple;
    } else if (categoryLower.contains('légume') ||
        categoryLower.contains('legume')) {
      return Icons.local_florist;
    } else if (categoryLower.contains('viande') ||
        categoryLower.contains('poisson')) {
      return Icons.restaurant;
    } else if (categoryLower.contains('lait') ||
        categoryLower.contains('fromage')) {
      return Icons.egg;
    } else if (categoryLower.contains('pain') ||
        categoryLower.contains('céréale')) {
      return Icons.bakery_dining;
    } else if (categoryLower.contains('boisson')) {
      return Icons.local_drink;
    } else {
      return Icons.shopping_basket;
    }
  }

  Future<Map<String, dynamic>?> _showAddItemDialog() async {
    List<dynamic> products = [];
    try {
      products = await _api.getProducts();
    } catch (e) {
      // Ignorer l'erreur, on permet la saisie libre
    }

    bool isCustomInput = false;
    Map<String, dynamic>? selectedProduct;
    final customNameController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    String selectedUnit = 'pièce';

    return await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: const BoxConstraints(maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_shopping_cart,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Ajouter un article',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setDialogState(() {
                              isCustomInput = false;
                              customNameController.clear();
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !isCustomInput
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Sélectionner',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: !isCustomInput
                                      ? Colors.white
                                      : Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setDialogState(() {
                              isCustomInput = true;
                              selectedProduct = null;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isCustomInput
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Saisie libre',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isCustomInput
                                      ? Colors.white
                                      : Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isCustomInput)
                          TextField(
                            controller: customNameController,
                            decoration: InputDecoration(
                              labelText: 'Nom de l\'article *',
                              hintText: 'Ex: Lait, Pain, Tomates...',
                              prefixIcon: const Icon(Icons.edit),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            autofocus: true,
                          )
                        else
                          DropdownButtonFormField<Map<String, dynamic>>(
                            value: selectedProduct,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Produit *',
                              prefixIcon: const Icon(
                                Icons.shopping_basket_outlined,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: products
                                .map<DropdownMenuItem<Map<String, dynamic>>>((
                                  product,
                                ) {
                                  return DropdownMenuItem<Map<String, dynamic>>(
                                    value: product,
                                    child: Text(
                                      product['name'] ?? 'Produit',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                })
                                .toList(),
                            onChanged: (value) => setDialogState(() {
                              selectedProduct = value;
                              if (value != null &&
                                  value['default_unit'] != null) {
                                final defaultUnit =
                                    value['default_unit'] as String;
                                if (_availableUnits.contains(defaultUnit)) {
                                  selectedUnit = defaultUnit;
                                }
                              }
                            }),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: quantityController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
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
                              child: DropdownButtonFormField<String>(
                                value: selectedUnit,
                                decoration: InputDecoration(
                                  labelText: 'Unité',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                items: _availableUnits
                                    .map(
                                      (unit) => DropdownMenuItem(
                                        value: unit,
                                        child: Text(unit),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setDialogState(
                                  () => selectedUnit = value ?? 'pièce',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Actions
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final quantity = double.tryParse(
                              quantityController.text,
                            );
                            if (quantity == null || quantity <= 0) {
                              _showError('Quantité invalide');
                              return;
                            }

                            if (isCustomInput) {
                              final name = customNameController.text.trim();
                              if (name.isEmpty) {
                                _showError('Entrez un nom d\'article');
                                return;
                              }
                              Navigator.pop(context, {
                                'custom_name': name,
                                'product_name': name,
                                'quantity': quantity,
                                'unit': selectedUnit,
                                'is_custom': true,
                              });
                            } else {
                              if (selectedProduct == null) {
                                _showError('Sélectionnez un produit');
                                return;
                              }
                              Navigator.pop(context, {
                                'product_id': selectedProduct!['id'],
                                'product_name': selectedProduct!['name'],
                                'quantity': quantity,
                                'unit': selectedUnit,
                                'is_custom': false,
                              });
                            }
                          },
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Ajouter'),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showListDetails(
    Map<String, dynamic> list, {
    required bool isCompleted,
  }) {
    final items = List<Map<String, dynamic>>.from(list['items'] ?? []);
    final isEditable = _isListEditable(list);
    final generatedBy = list['generated_by'] ?? 'manual';

    final listName =
        list['name'] ??
        'Liste du ${_formatDate(DateTime.parse(list['created_at']))}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
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
                                Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.8),
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      listName,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                  ),
                                  _buildGeneratedByBadge(generatedBy),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${items.length} article(s)',
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
                        if (!isCompleted && isEditable)
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            color: Theme.of(context).colorScheme.primary,
                            onPressed: () async {
                              Navigator.pop(context);
                              await _showAddItemToExistingList(list['id']);
                              _loadShoppingLists();
                            },
                            tooltip: 'Ajouter un article',
                          ),
                      ],
                    ),
                    if (!isEditable) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Cette liste a été générée automatiquement et ne peut pas être modifiée.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'Aucun article dans cette liste',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.color,
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
                            isEditable: isEditable,
                            onStatusChanged: () {
                              setModalState(() {
                                item['status'] = item['status'] == 'purchased'
                                    ? 'pending'
                                    : 'purchased';
                              });
                              setState(() {});
                            },
                          );
                        },
                      ),
              ),
              // Footer
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
                            _showSuccess(
                              'Tous les articles marqués comme achetés',
                            );
                            await _loadShoppingLists();
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
    bool isCompleted, {
    required bool isEditable,
    VoidCallback? onStatusChanged,
  }) {
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
                  await _api.updateShoppingListItemStatus(
                    listId: listId,
                    itemId: item['id'],
                    status: newStatus,
                  );
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
        secondary: (isCompleted || !isEditable)
            ? null
            : IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.red,
                onPressed: () => _confirmDeleteItem(listId, item['id']),
              ),
      ),
    );
  }

  Future<void> _showAddItemToExistingList(int listId) async {
    final item = await _showAddItemDialog();
    if (item == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    try {
      if (item['is_custom'] == true) {
        final productName = item['custom_name'] ?? item['product_name'];

        final products = await _api.getProducts(search: productName);

        int productId;

        final existingProduct = products.firstWhere(
          (p) =>
              (p['name'] as String).toLowerCase() ==
              productName.toString().toLowerCase(),
          orElse: () => null,
        );

        if (existingProduct != null) {
          productId = existingProduct['id'];
        } else {
          await _api.addItemToShoppingListWithName(
            listId: listId,
            productName: productName,
            quantity: item['quantity'],
            unit: item['unit'],
          );

          if (!mounted) return;
          Navigator.pop(context);
          _showSuccess('Article "$productName" ajouté !');
          _loadShoppingLists();
          return;
        }

        await _api.addItemToShoppingList(
          listId: listId,
          productId: productId,
          quantity: item['quantity'],
          unit: item['unit'],
        );
      } else {
        await _api.addItemToShoppingList(
          listId: listId,
          productId: item['product_id'],
          quantity: item['quantity'],
          unit: item['unit'],
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      _showSuccess('Article ajouté !');
      _loadShoppingLists();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Erreur: $e');
    }
  }

  Future<void> _generateAIList() async {
    if (_selectedFridgeId == null) {
      _showError('Aucun frigo sélectionné');
      return;
    }

    setState(() => _isDiscovering = true);

    try {
      final suggestion = await _api.suggestDiverseProducts(_selectedFridgeId!);

      setState(() => _isDiscovering = false);

      if (!mounted) return;

      final suggestedProducts =
          suggestion['suggested_products'] as List<dynamic>? ?? [];

      if (suggestedProducts.isEmpty) {
        _showError(suggestion['message'] ?? 'Aucune suggestion disponible');
        return;
      }

      _showSuggestedProductsDialog(suggestion);
    } catch (e) {
      setState(() => _isDiscovering = false);
      _showError('Erreur : $e');
    }
  }

  Future<void> _showRecipeSelectionDialog() async {
    if (_selectedFridgeId == null) return;

    List<dynamic> recipes = [];
    Set<int> selectedRecipeIds = {};

    try {
      recipes = await _api.getFeasibleRecipes(_selectedFridgeId!);
      final totalRecipes = recipes.length;

      if (kDebugMode) {
        print('Total recettes récupérées: $totalRecipes');
        print(
          'IDs des recettes: ${recipes.map((r) => r['id']).toList()}',
        );
      }

      final shoppingLists = await _api.getShoppingLists(
        fridgeId: _selectedFridgeId,
      );

      if (kDebugMode) {
        print('Total listes de courses: ${shoppingLists.length}');
        print('Contenu des listes:');
        for (var list in shoppingLists) {
          print(
            '   - Liste ID: ${list['id']}, '
            'recipe_id: ${list['recipe_id']}, '
            'status: ${list['status']}, '
            'generated_by: ${list['generated_by']}',
          );
        }
      }

      final activeLists = shoppingLists.where((list) {
        final status = list['status'] as String?;
        return status != 'cancelled';
      }).toList();

      final Set<int> recipesWithActiveLists = activeLists
          .where((list) => list['recipe_id'] != null)
          .map<int>((list) => list['recipe_id'] as int)
          .toSet();

      if (kDebugMode) {
        print(
          'Recipe IDs avec liste active: $recipesWithActiveLists',
        );
      }

      recipes = recipes.where((recipe) {
        final recipeId = recipe['id'] as int;
        final hasActiveListe = recipesWithActiveLists.contains(recipeId);

        if (kDebugMode) {
          print(
            'Recette ${recipe['title']} (ID: $recipeId) '
            '- A liste active: $hasActiveListe',
          );
        }

        return !hasActiveListe;
      }).toList();

      if (kDebugMode) {
        print('Recettes après filtrage: ${recipes.length}');
        print(
          'IDs des recettes filtrées: ${recipes.map((r) => r['id']).toList()}',
        );
      }

      if (recipes.isEmpty) {
        _showError(
          'Aucune recette disponible.\n'
          'Toutes vos $totalRecipes recette(s) ont déjà une liste de courses active.\n'
          'Astuce : Supprimez ou terminez les anciennes listes pour libérer les recettes.',
        );
        return;
      }

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.restaurant, color: Color(0xFFF59E0B)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Choisir des recettes'),
                      Text(
                        '${recipes.length}/$totalRecipes recette(s) disponible(s)', // ✅ Affichage du total
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectedRecipeIds.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFFF59E0B),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${selectedRecipeIds.length} recette(s) sélectionnée(s)',
                            style: const TextStyle(
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: recipes.length,
                      itemBuilder: (context, index) {
                        final recipe = recipes[index];
                        final recipeId = recipe['id'] as int;
                        final isSelected = selectedRecipeIds.contains(recipeId);

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) => setDialogState(() {
                            value == true
                                ? selectedRecipeIds.add(recipeId)
                                : selectedRecipeIds.remove(recipeId);
                          }),
                          activeColor: const Color(0xFFF59E0B),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  recipe['title'] ?? 'Recette',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: recipe['description'] != null
                              ? Text(
                                  recipe['description'],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                onPressed: selectedRecipeIds.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(context);
                        await _generateListFromRecipes(
                          selectedRecipeIds.toList(),
                        );
                      },
                icon: const Icon(Icons.check),
                label: const Text('Générer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      _showError('Erreur de chargement des recettes : $e');
      return;
    }
  }

  Future<void> _generateListFromRecipes(List<int> recipeIds) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Génération de la liste...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await _api.generateShoppingList(
        fridgeId: _selectedFridgeId!,
        recipeIds: recipeIds,
      );
      if (!mounted) return;
      Navigator.pop(context);

      final itemsCount = (result['items'] as List?)?.length ?? 0;
      _showSuccess('Liste créée avec $itemsCount article(s) !');
      _loadShoppingLists();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Erreur : $e');
    }
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
          'Voulez-vous supprimer cette liste de courses ?\n\n${list['items'].length} article(s) seront également supprimés.',
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
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
