import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_smartfridge/screens/auth.dart';
import 'package:user_smartfridge/screens/shopping_list.dart';
import 'package:user_smartfridge/service/api.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> with SingleTickerProviderStateMixin {
  final ClientApiService _api = ClientApiService();
  late TabController _tabController;

  List<dynamic> _allRecipes = [];
  List<dynamic> _feasibleRecipes = [];
  List<dynamic> _favoriteRecipes = [];
  Set<int> _favoriteRecipeIds = {}; // ✅ Pour un accès rapide

  bool _isLoading = true;
  bool _isDiscovering = false;
  Map<String, dynamic>? _suggestedRecipe;
  int? _selectedFridgeId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRecipes();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAndReloadIfNeeded();
  }

  Future<void> _checkAndReloadIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFridgeId = prefs.getInt('selected_fridge_id');

    if (savedFridgeId != null && savedFridgeId != _selectedFridgeId && !_isLoading) {
      _loadRecipes();
    }
  }

  Future<void> _saveSuggestedRecipe(Map<String, dynamic> suggestion) async {
    try {
      // Afficher un indicateur de chargement
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
                  Text('Sauvegarde de la recette...'),
                ],
              ),
            ),
          ),
        ),
      );

      await _api.saveSuggestedRecipe(suggestion);

      if (!mounted) return;

      // Fermer l'indicateur de chargement
      Navigator.pop(context);

      // Afficher le succès
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bookmark_added,
                  color: Color(0xFF10B981),
                  size: 32,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Recette sauvegardée !')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La recette "${suggestion['title']}" a été ajoutée à votre collection.',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.restaurant_menu,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Vous la retrouverez dans l\'onglet "Toutes"',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context); // Fermer le dialog
                Navigator.pop(context); // Fermer la suggestion
                _loadRecipes(); // Recharger les recettes
                _tabController.animateTo(1); // Aller à l'onglet "Toutes"
              },
              icon: const Icon(Icons.visibility),
              label: const Text('Voir'),
              style: ElevatedButton.styleFrom(elevation: 0),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      // Fermer l'indicateur de chargement si encore ouvert
      Navigator.pop(context);

      _showError('Erreur lors de la sauvegarde: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipes() async {
    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();

      // Charger toutes les recettes et favoris en parallèle
      final results = await Future.wait([
        _api.getRecipes(),
        _api.getFavoriteRecipes(),
      ]);

      final allRecipes = results[0];
      final favoriteRecipes = results[1];

      // ✅ Construire le Set d'IDs de favoris
      final favoriteIds = favoriteRecipes.map((r) => r['id'] as int).toSet();

      final prefs = await SharedPreferences.getInstance();
      int? savedFridgeId = prefs.getInt('selected_fridge_id');

      List<dynamic> feasible = [];

      if (fridges.isNotEmpty) {
        if (savedFridgeId != null && fridges.any((f) => f['id'] == savedFridgeId)) {
          _selectedFridgeId = savedFridgeId;
        } else {
          _selectedFridgeId = fridges[0]['id'];
          await prefs.setInt('selected_fridge_id', _selectedFridgeId!);
        }

        if (kDebugMode) {
          print('🍳 RecipesPage: Loading recipes for fridge $_selectedFridgeId');
        }

        feasible = await _api.getFeasibleRecipes(_selectedFridgeId!);
      } else {
        _selectedFridgeId = null;
      }

      setState(() {
        _allRecipes = allRecipes;
        _feasibleRecipes = feasible;
        _favoriteRecipes = favoriteRecipes;
        _favoriteRecipeIds = favoriteIds;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      if (e.toString().contains('Non autorisé') || e.toString().contains('401')) {
        await _api.logout();
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
  }

  // ✅ MÉTHODE DE DÉCOUVERTE IA
  Future<void> _discoverRecipe() async {
    if (_selectedFridgeId == null) {
      _showError('Aucun frigo sélectionné. Connectez un frigo depuis le tableau de bord.');
      return;
    }

    setState(() => _isDiscovering = true);

    try {
      if (kDebugMode) {
        print('🍳 Requesting recipe suggestion for fridge $_selectedFridgeId');
      }

      final suggestion = await _api.suggestRecipe(_selectedFridgeId!);

      if (kDebugMode) {
        print('✅ Received suggestion: ${suggestion['title']}');
      }

      setState(() {
        _suggestedRecipe = suggestion;
        _isDiscovering = false;
      });

      _showSuggestedRecipeDialog(suggestion);
    } catch (e) {
      setState(() => _isDiscovering = false);
      if (kDebugMode) {
        print('❌ Error suggesting recipe: $e');
      }
      _showError('Erreur lors de la suggestion: $e');
    }
  }

  // ✅ TOGGLE FAVORI
  Future<void> _toggleFavorite(Map<String, dynamic> recipe) async {
    final recipeId = recipe['id'] as int;
    final isFavorite = _favoriteRecipeIds.contains(recipeId);

    // Optimistic update
    setState(() {
      if (isFavorite) {
        _favoriteRecipeIds.remove(recipeId);
        _favoriteRecipes.removeWhere((r) => r['id'] == recipeId);
      } else {
        _favoriteRecipeIds.add(recipeId);
        _favoriteRecipes.add(recipe);
      }
    });

    try {
      if (isFavorite) {
        await _api.removeRecipeFromFavorites(recipeId);
        _showSuccess('Retiré des favoris');
      } else {
        await _api.addRecipeToFavorites(recipeId);
        _showSuccess('Ajouté aux favoris');
      }
    } catch (e) {
      // Rollback en cas d'erreur
      setState(() {
        if (isFavorite) {
          _favoriteRecipeIds.add(recipeId);
          _favoriteRecipes.add(recipe);
        } else {
          _favoriteRecipeIds.remove(recipeId);
          _favoriteRecipes.removeWhere((r) => r['id'] == recipeId);
        }
      });
      _showError('Erreur: $e');
    }
  }

  // ✅ GÉNÉRATION DE LISTE DE COURSES
  Future<void> _generateShoppingListFromSuggestion(Map<String, dynamic> suggestion) async {
    if (_selectedFridgeId == null) {
      _showError('Aucun frigo sélectionné');
      return;
    }

    try {
      final missingIngredients = (suggestion['missing_ingredients'] as List? ?? [])
          .map<Map<String, dynamic>>((e) {
        if (e is Map<String, dynamic>) {
          return e;
        }
        return {'name': e.toString()};
      }).toList();

      final result = await _api.generateShoppingListFromIngredients(
        fridgeId: _selectedFridgeId!,
        ingredients: missingIngredients,
      );

      _showSuccess('Liste de courses créée avec ${(result['items'] as List?)?.length ?? 0} article(s)');
    } catch (e) {
      _showError('Erreur: $e');
    }
  }

  Future<void> _generateShoppingList(Map<String, dynamic> recipe) async {
    if (_selectedFridgeId == null) {
      _showError('Aucun frigo sélectionné');
      return;
    }

    try {
      final result = await _api.generateShoppingList(
        fridgeId: _selectedFridgeId!,
        recipeIds: [recipe['id']],
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Theme.of(context).cardColor,
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF10B981)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Liste générée',
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Votre liste de courses a été créée avec succès !',
                style: TextStyle(fontSize: 15, color: Theme.of(context).textTheme.bodyMedium?.color),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shopping_cart, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      '${(result['items'] as List).length} article(s)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ShoppingListsPage()),
                );
              },
              style: ElevatedButton.styleFrom(elevation: 0),
              child: const Text('Voir la liste'),
            ),
          ],
        ),
      );
    } catch (e) {
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'recipes_shopping_fab', // ✅ Tag unique
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ShoppingListsPage()),
          );
        },
        icon: const Icon(Icons.shopping_cart),
        label: const Text('Mes listes'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildAppBar(),
          _buildDiscoverButton(),
          _buildTabBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
              controller: _tabController,
              children: [
                _buildFeasibleRecipes(),
                _buildAllRecipes(),
                _buildFavoriteRecipes(),
              ],
            ),
          ),
        ],
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
                  'Recettes',
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
                      '${_feasibleRecipes.length} réalisables',
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
                    ] else ...[
                      Text(
                        ' • Aucun frigo',
                        style: TextStyle(
                          color: Colors.orange,
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
            onPressed: _loadRecipes,
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverButton() {
    final bool canDiscover = _selectedFridgeId != null && !_isDiscovering;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: InkWell(
        onTap: canDiscover ? _discoverRecipe : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: canDiscover
                  ? [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ]
                  : [Colors.grey.shade400, Colors.grey.shade500],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: canDiscover
                ? [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isDiscovering
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isDiscovering
                          ? 'Recherche en cours...'
                          : _selectedFridgeId != null
                          ? 'Découvrir une recette'
                          : 'Connectez un frigo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedFridgeId != null
                          ? 'IA suggère selon votre inventaire'
                          : 'Pour obtenir des suggestions',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withOpacity(0.8),
                size: 18,
              ),
            ],
          ),
        ),
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
        tabs: const [
          Tab(text: 'Réalisables'),
          Tab(text: 'Toutes'),
          Tab(text: 'Favorites'),
        ],
      ),
    );
  }

  // ✅ DIALOG DE SUGGESTION IA
  void _showSuggestedRecipeDialog(Map<String, dynamic> suggestion) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, scrollController) => Container(
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
                              Theme.of(context).colorScheme.secondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Suggestion intelligente',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              suggestion['title'] ?? 'Recette suggérée',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        onPressed: () => _saveSuggestedRecipe(suggestion),
                        tooltip: 'Sauvegarder',
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          Navigator.pop(context);
                          _discoverRecipe();
                        },
                        tooltip: 'Nouvelle suggestion',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                children: [
                  if (suggestion['match_percentage'] != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Color(0xFF10B981)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${(suggestion['match_percentage'] as num).toInt()}% des ingrédients disponibles',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                                if (suggestion['available_ingredients'] != null)
                                  Text(
                                    '${(suggestion['available_ingredients'] as List).length} ingrédients dans votre frigo',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (suggestion['description'] != null) ...[
                    Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      suggestion['description'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (suggestion['ingredients'] != null && (suggestion['ingredients'] as List).isNotEmpty) ...[
                    Text(
                      'Ingrédients',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...(suggestion['ingredients'] as List).map(
                          (ing) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              (suggestion['available_ingredients'] as List?)?.contains(ing['name']) == true
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: 18,
                              color: (suggestion['available_ingredients'] as List?)?.contains(ing['name']) == true
                                  ? const Color(0xFF10B981)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${ing['quantity'] ?? ''} ${ing['unit'] ?? ''} ${ing['name'] ?? ''}'.trim(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context).textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (suggestion['steps'] != null) ...[
                    Text(
                      'Instructions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      suggestion['steps'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (suggestion['missing_ingredients'] != null && (suggestion['missing_ingredients'] as List).isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.shopping_cart_outlined, color: Color(0xFFF59E0B), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Ingrédients manquants',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFF59E0B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...(suggestion['missing_ingredients'] as List).map(
                                (ing) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${ing['name'] ?? ing}',
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 14,
                                ),
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
            Container(
              padding: const EdgeInsets.all(24),
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
                          onPressed: () => _saveSuggestedRecipe(suggestion),
                          icon: const Icon(Icons.bookmark_add),
                          label: const Text('Sauvegarder'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                Expanded(
                child: OutlinedButton.icon(
                onPressed: () {
              Navigator.pop(context);
              _discoverRecipe();
              },
                icon: const Icon(Icons.refresh),
                label: const Text('Autre idée'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
                      if (suggestion['missing_ingredients'] != null &&
                          (suggestion['missing_ingredients'] as List).isNotEmpty) {
                        _generateShoppingListFromSuggestion(suggestion).then((_) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ShoppingListsPage(),
                            ),
                          );
                        });
                      } else {
                        _showSuccess('Bon appétit ! 🍽️');
                      }
                    },
                    icon: Icon(
                      (suggestion['missing_ingredients'] as List?)?.isNotEmpty == true
                          ? Icons.shopping_cart_outlined
                          : Icons.restaurant,
                    ),
                  label: Text(
                    (suggestion['missing_ingredients'] as List?)?.isNotEmpty == true
                        ? 'Liste de courses'
                        : 'Je cuisine !',
                  ),
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
              ),
            ),
                  ],
              ),
            ),
        ),
    );
  }

  // ✅ RECIPE CARD avec gestion des favoris
  Widget _buildRecipeCard(
      Map<String, dynamic> recipe, {
        bool? canMake,
        double? matchPercentage,
        List<dynamic>? missingIngredients,
      }) {
    final recipeId = recipe['id'] as int;
    final isFavorite = _favoriteRecipeIds.contains(recipeId);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showRecipeDetails(recipe, missingIngredients: missingIngredients),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.primary.withOpacity(0.8),
                          Theme.of(context).colorScheme.secondary.withOpacity(0.8),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.restaurant,
                        size: 64,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ),
                  // ✅ BOUTON FAVORI
                  Positioned(
                    top: 12,
                    right: 12,
                    child: InkWell(
                      onTap: () => _toggleFavorite(recipe),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? Colors.red : Theme.of(context).iconTheme.color,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  if (canMake != null)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: canMake ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              canMake ? Icons.check_circle : Icons.info,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              canMake ? 'Réalisable' : 'Incomplet',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe['title'] ?? 'Recette',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    if (recipe['description'] != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        recipe['description'],
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (recipe['preparation_time'] != null) ...[
                          _buildInfoChip(
                            Icons.schedule_outlined,
                            '${recipe['preparation_time']} min',
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (recipe['difficulty'] != null)
                          _buildInfoChip(Icons.signal_cellular_alt, recipe['difficulty']),
                        const Spacer(),
                        if (matchPercentage != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${matchPercentage.toInt()}%',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (missingIngredients != null && missingIngredients.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.shopping_cart_outlined,
                              color: Color(0xFFF59E0B),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${missingIngredients.length} ingrédient(s) manquant(s)',
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
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
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).iconTheme.color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
// ✅ DÉTAILS DE RECETTE avec favori
  void _showRecipeDetails(Map<String, dynamic> recipe, {List<dynamic>? missingIngredients}) {
    final recipeId = recipe['id'] as int;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isFavorite = _favoriteRecipeIds.contains(recipeId);

          return DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, scrollController) => Container(
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
                            Expanded(
                              child: Text(
                                recipe['title'] ?? 'Recette',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).textTheme.bodyLarge?.color,
                                ),
                              ),
                            ),
                            // ✅ BOUTON FAVORI DANS LE DIALOG
                            IconButton(
                              icon: Icon(
                                isFavorite ? Icons.favorite : Icons.favorite_border,
                                color: isFavorite ? Colors.red : Theme.of(context).iconTheme.color,
                              ),
                              onPressed: () {
                                _toggleFavorite(recipe);
                                setModalState(() {}); // Update dialog UI
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(24),
                      children: [
                        if (recipe['description'] != null) ...[
                          Text(
                            'Description',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            recipe['description'],
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Text(
                          'Instructions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          recipe['steps'] ?? 'Pas d\'instructions disponibles',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).textTheme.bodyMedium?.color,
                            height: 1.6,
                          ),
                        ),
                        if (missingIngredients != null && missingIngredients.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.shopping_cart_outlined,
                                      color: Color(0xFFF59E0B),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Ingrédients manquants',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ...missingIngredients.map(
                                      (ing) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '• ${ing['product_name']}',
                                      style: const TextStyle(
                                        color: Color(0xFFF59E0B),
                                        fontSize: 14,
                                      ),
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
                  Container(
                    padding: const EdgeInsets.all(24),
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
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _generateShoppingList(recipe);
                        },
                        icon: const Icon(Icons.shopping_cart_outlined),
                        label: const Text('Générer liste de courses'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          minimumSize: const Size(double.infinity, 0),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  Widget _buildFeasibleRecipes() {
    if (_feasibleRecipes.isEmpty) {
      return _buildEmptyState(
        Icons.restaurant_menu_outlined,
        'Aucune recette réalisable',
        'Ajoutez des produits à votre frigo\npour découvrir des recettes',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecipes,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _feasibleRecipes.length,
        itemBuilder: (context, index) {
          final item = _feasibleRecipes[index];
          final recipe = item['recipe'];
          final canMake = item['can_make'] ?? false;
          final matchPercentage = (item['match_percentage'] ?? 0.0).toDouble();
          return _buildRecipeCard(
            recipe,
            canMake: canMake,
            matchPercentage: matchPercentage,
            missingIngredients: item['missing_ingredients'] ?? [],
          );
        },
      ),
    );
  }
  Widget _buildAllRecipes() {
    if (_allRecipes.isEmpty) {
      return _buildEmptyState(
        Icons.book_outlined,
        'Aucune recette',
        'Les recettes seront bientôt disponibles',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRecipes,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allRecipes.length,
        itemBuilder: (context, index) => _buildRecipeCard(_allRecipes[index]),
      ),
    );
  }
  Widget _buildFavoriteRecipes() {
    if (_favoriteRecipes.isEmpty) {
      return _buildEmptyState(
        Icons.favorite_border,
        'Aucune recette favorite',
        'Marquez vos recettes préférées\nen appuyant sur le cœur',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRecipes,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _favoriteRecipes.length,
        itemBuilder: (context, index) => _buildRecipeCard(_favoriteRecipes[index]),
      ),
    );
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
}