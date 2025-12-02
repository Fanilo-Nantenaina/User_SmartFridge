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
  Set<int> _favoriteRecipeIds = {};

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
    // Vérifier après un court délai pour laisser le temps aux prefs de se mettre à jour
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _checkAndReloadIfNeeded();
    });
  }

  Future<void> _checkAndReloadIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFridgeId = prefs.getInt('selected_fridge_id');

    if (kDebugMode) {
      print('🔄 RecipesPage: Checking fridge - saved=$savedFridgeId, current=$_selectedFridgeId');
    }

    // Recharger si le frigo a changé OU si on n'a pas encore de frigo sélectionné
    if (savedFridgeId != _selectedFridgeId) {
      if (kDebugMode) {
        print('🔄 RecipesPage: Fridge changed! Reloading...');
      }
      _loadRecipes();
    }
  }

  void refresh() {
    _loadRecipes();
  }

  Future<void> _saveSuggestedRecipe(Map<String, dynamic> suggestion) async {
    try {
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
      Navigator.pop(context);

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
                Navigator.pop(context);
                Navigator.pop(context);
                _loadRecipes();
                _tabController.animateTo(1);
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
      Navigator.pop(context);
      _showError('Erreur lors de la sauvegarde: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndReloadIfNeeded();
    }
  }

  Future<void> _loadRecipes() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final fridges = await _api.getFridges();
      final prefs = await SharedPreferences.getInstance();
      int? savedFridgeId = prefs.getInt('selected_fridge_id');

      // Déterminer le frigo actif
      if (fridges.isNotEmpty) {
        if (savedFridgeId != null && fridges.any((f) => f['id'] == savedFridgeId)) {
          _selectedFridgeId = savedFridgeId;
        } else {
          _selectedFridgeId = fridges[0]['id'];
          await prefs.setInt('selected_fridge_id', _selectedFridgeId!);
        }
      } else {
        _selectedFridgeId = null;
      }

      if (kDebugMode) {
        print('🍳 RecipesPage: Loading recipes for fridge $_selectedFridgeId');
      }

      List<dynamic> allRecipes = [];
      List<dynamic> feasibleRecipes = [];
      List<dynamic> favoriteRecipes = [];

      if (_selectedFridgeId != null) {
        // ✅ Charger en parallèle UNIQUEMENT pour le frigo sélectionné
        final results = await Future.wait([
          _api.getRecipes(),
          _api.getFeasibleRecipes(_selectedFridgeId!),  // Spécifique au frigo
          _api.getFavoriteRecipes(),
        ]);

        allRecipes = results[0];
        feasibleRecipes = results[1];
        favoriteRecipes = results[2];
      } else {
        // Pas de frigo : charger seulement les recettes globales
        final results = await Future.wait([
          _api.getRecipes(),
          _api.getFavoriteRecipes(),
        ]);

        allRecipes = results[0];
        favoriteRecipes = results[1];
        feasibleRecipes = [];  // ✅ Vide si pas de frigo
      }

      final favoriteIds = favoriteRecipes.map((r) => r['id'] as int).toSet();

      if (!mounted) return;

      setState(() {
        _allRecipes = allRecipes;
        _feasibleRecipes = feasibleRecipes;
        _favoriteRecipes = favoriteRecipes;
        _favoriteRecipeIds = favoriteIds;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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

  Future<void> _toggleFavorite(Map<String, dynamic> recipe) async {
    final recipeId = recipe['id'] as int;
    final isFavorite = _favoriteRecipeIds.contains(recipeId);

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

  Future<void> _generateShoppingListFromSuggestion(Map<String, dynamic> suggestion) async {
    if (_selectedFridgeId == null) {
      _showError('Aucun frigo sélectionné');
      return;
    }

    try {
      // ✅ ÉTAPE 1 : Sauvegarder la recette d'abord pour obtenir son ID
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
                  Text('Création de la liste...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Sauvegarder la recette
      final savedRecipe = await _api.saveSuggestedRecipe(suggestion);
      final recipeId = savedRecipe['id'] as int;

      if (kDebugMode) {
        print('✅ Recette sauvegardée avec ID: $recipeId');
      }

      // ✅ ÉTAPE 2 : Créer la liste de courses AVEC le recipe_id
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
        recipeId: recipeId,  // ✅ NOUVEAU : Passer le recipe_id
      );

      if (!mounted) return;
      Navigator.pop(context); // Fermer le loading

      final itemsCount = (result['items'] as List?)?.length ?? 0;

      _showSuccess('Liste créée avec $itemsCount article(s) !');

      // Recharger les recettes pour mettre à jour les statuts
      _loadRecipes();

    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
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
        heroTag: 'recipes_shopping_fab',
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
                      const Text(
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
                            // ✅ Bouton "Sauvegarder" seulement
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _saveSuggestedRecipe(suggestion);
                                },
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
                            // ✅ Bouton "Autre idée"
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
                            // ✅ Bouton principal : Liste de courses OU Je cuisine
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.pop(context);

                                  final hasMissingIngredients =
                                      (suggestion['missing_ingredients'] as List?)?.isNotEmpty == true;

                                  if (hasMissingIngredients) {
                                    // ✅ NOUVEAU FLUX : Sauvegarder la recette + créer liste liée
                                    await _generateShoppingListFromSuggestion(suggestion);

                                    // Naviguer vers les listes de courses
                                    if (mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const ShoppingListsPage(),
                                        ),
                                      );
                                    }
                                  } else {
                                    // Pas d'ingrédients manquants : juste sauvegarder
                                    await _saveSuggestedRecipe(suggestion);
                                    _showSuccess('Recette sauvegardée ! Bon appétit ! 🍽️');
                                  }
                                },
                                icon: Icon(
                                  (suggestion['missing_ingredients'] as List?)?.isNotEmpty == true
                                      ? Icons.shopping_cart_outlined
                                      : Icons.restaurant,
                                ),
                                label: Text(
                                  (suggestion['missing_ingredients'] as List?)?.isNotEmpty == true
                                      ? 'Créer liste'
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

  // Dans recipes.dart - Remplacez _buildRecipeCard par cette version corrigée :

  Widget _buildRecipeCard(
      Map<String, dynamic> recipe, {
        bool? canMake,
        double? matchPercentage,
        List<dynamic>? missingIngredients,
        String? shoppingListStatus,
        int? shoppingListId,
        bool? ingredientsComplete,
        double? combinedPercentage,
        int? purchasedMissingCount,
        int? totalMissingCount,
      }) {
    final recipeId = recipe['id'] as int;
    final isFavorite = _favoriteRecipeIds.contains(recipeId);

    // ✅ LOGIQUE CORRIGÉE : Déterminer le statut global
    // - isComplete si tout est dans le frigo (canMake)
    // - OU si ingredientsComplete est true (frigo + courses complétées)
    // - OU si la liste de courses est "completed"
    final bool isComplete = canMake == true ||
        ingredientsComplete == true ||
        shoppingListStatus == 'completed';

    // ✅ Pourcentage à afficher
    final double displayPercentage = isComplete
        ? 100.0
        : (combinedPercentage ?? matchPercentage ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isComplete
              ? const Color(0xFF10B981)
              : Theme.of(context).colorScheme.outline,
          width: isComplete ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showRecipeDetails(
            recipe,
            missingIngredients: missingIngredients,
            shoppingListStatus: shoppingListStatus,
            shoppingListId: shoppingListId,
            ingredientsComplete: isComplete,  // ✅ Passer le statut calculé
            combinedPercentage: displayPercentage,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header avec image
              Stack(
                children: [
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isComplete
                            ? [
                          const Color(0xFF10B981),
                          const Color(0xFF059669),
                        ]
                            : [
                          Theme.of(context).colorScheme.primary.withOpacity(0.8),
                          Theme.of(context).colorScheme.secondary.withOpacity(0.8),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Center(
                      child: Icon(
                        isComplete ? Icons.check_circle_outline : Icons.restaurant,
                        size: 64,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ),

                  // Badge favori
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

                  // ✅ Badge principal - Adapté selon le statut
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isComplete
                            ? const Color(0xFF10B981)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isComplete ? Icons.check_circle : Icons.pie_chart,
                            color: isComplete ? Colors.white : Theme.of(context).colorScheme.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isComplete
                                ? 'Ingrédients complets !'
                                : '${displayPercentage.toInt()}% prêt',
                            style: TextStyle(
                              color: isComplete ? Colors.white : Theme.of(context).colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Contenu
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

                    // Infos temps / difficulté
                    Row(
                      children: [
                        if (recipe['preparation_time'] != null) ...[
                          _buildInfoChip(Icons.schedule_outlined, '${recipe['preparation_time']} min'),
                          const SizedBox(width: 8),
                        ],
                        if (recipe['difficulty'] != null)
                          _buildInfoChip(Icons.signal_cellular_alt, recipe['difficulty']),
                      ],
                    ),

                    // ✅ Barre de progression (seulement si pas complet)
                    if (!isComplete) ...[
                      const SizedBox(height: 16),
                      _buildCombinedProgressBar(
                        fridgePercentage: matchPercentage ?? 0,
                        combinedPercentage: displayPercentage,
                        purchasedCount: purchasedMissingCount ?? 0,
                        totalMissing: totalMissingCount ?? 0,
                      ),
                    ],

                    // ✅ Message "Ingrédients complets" avec contexte
                    if (isComplete) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.celebration, color: Color(0xFF059669), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                // ✅ Message adapté selon la source
                                canMake == true
                                    ? 'Tout est dans votre frigo !'
                                    : shoppingListStatus == 'completed'
                                    ? 'Frigo + courses = prêt à cuisiner !'
                                    : 'Tous les ingrédients sont disponibles !',
                                style: const TextStyle(
                                  color: Color(0xFF065F46),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ✅ Statut des courses (si pas complet ET liste existe)
                    if (!isComplete && shoppingListStatus != null) ...[
                      const SizedBox(height: 10),
                      _buildShoppingListStatusChip(shoppingListStatus),
                    ],

                    // ✅ Ingrédients manquants (si pas complet ET pas de liste OU liste non complète)
                    if (!isComplete &&
                        missingIngredients != null &&
                        missingIngredients.isNotEmpty &&
                        shoppingListStatus != 'completed') ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shopping_basket_outlined, color: Color(0xFFF59E0B), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                shoppingListStatus == 'in_progress'
                                    ? '${(totalMissingCount ?? 0) - (purchasedMissingCount ?? 0)} article(s) restant(s)'
                                    : '${missingIngredients.length} ingrédient(s) à acheter',
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

  Widget _buildCombinedProgressBar({
    required double fridgePercentage,
    required double combinedPercentage,
    required int purchasedCount,
    required int totalMissing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Barre de progression
        Stack(
          children: [
            // Fond
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Progression combinée (frigo + courses)
            FractionallySizedBox(
              widthFactor: combinedPercentage / 100,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      const Color(0xFF10B981),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // Séparateur (limite frigo)
            if (fridgePercentage < combinedPercentage)
              Positioned(
                left: (fridgePercentage / 100) * MediaQuery.of(context).size.width * 0.85,
                child: Container(
                  width: 2,
                  height: 8,
                  color: Colors.white,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Légende
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${fridgePercentage.toInt()}% frigo',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            if (purchasedCount > 0) ...[
              const SizedBox(width: 12),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '+$purchasedCount acheté(s)',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildShoppingListStatusChip(String status) {
    Color backgroundColor;
    Color textColor;
    IconData icon;
    String message;

    switch (status) {
      case 'completed':
        backgroundColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF065F46);
        icon = Icons.check_circle;
        message = '✓ Courses terminées';
        break;
      case 'in_progress':
        backgroundColor = const Color(0xFFDBEAFE);
        textColor = const Color(0xFF1E40AF);
        icon = Icons.shopping_cart;
        message = 'Courses en cours...';
        break;
      case 'pending':
        backgroundColor = const Color(0xFFE0E7FF);
        textColor = const Color(0xFF3730A3);
        icon = Icons.list_alt;
        message = 'Liste de courses créée';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 16),
          const SizedBox(width: 6),
          Text(
            message,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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

  // Remplacez la signature de _showRecipeDetails par celle-ci :

  void _showRecipeDetails(
      Map<String, dynamic> recipe, {
        List<dynamic>? missingIngredients,
        String? shoppingListStatus,
        int? shoppingListId,
        bool? ingredientsComplete,      // ✅ AJOUTÉ
        double? combinedPercentage,     // ✅ AJOUTÉ
      }) {
    final recipeId = recipe['id'] as int;

    // ✅ Utiliser les nouveaux paramètres pour afficher le statut
    final bool isComplete = ingredientsComplete == true;

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
                  // Header
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
                            IconButton(
                              icon: Icon(
                                isFavorite ? Icons.favorite : Icons.favorite_border,
                                color: isFavorite ? Colors.red : Theme.of(context).iconTheme.color,
                              ),
                              onPressed: () {
                                _toggleFavorite(recipe);
                                setModalState(() {});
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Contenu scrollable
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(24),
                      children: [
                        // ✅ NOUVEAU : Badge "Ingrédients complets"
                        if (isComplete) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1FAE5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.celebration, color: Color(0xFF10B981), size: 24),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Prêt à cuisiner !',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Color(0xFF065F46),
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Tous les ingrédients sont disponibles',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF065F46),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ✅ SECTION 1 : Statut de la liste de courses
                        if (shoppingListStatus != null && !isComplete) ...[
                          _buildShoppingStatusSection(shoppingListStatus),
                          const SizedBox(height: 20),
                        ],

                        // ✅ SECTION 2 : Ingrédients manquants (seulement si pas complet)
                        if (!isComplete && missingIngredients != null && missingIngredients.isNotEmpty) ...[
                          _buildMissingIngredientsSection(missingIngredients),
                          const SizedBox(height: 20),
                        ],

                        // Description
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

                        // Instructions
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
                      ],
                    ),
                  ),

                  // Footer avec boutons
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
                          // ✅ Bouton adapté selon le statut
                          if (isComplete) ...[
                            // Recette complète : bouton "Je cuisine"
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showSuccess('Bon appétit ! 🍳');
                                },
                                icon: const Icon(Icons.restaurant),
                                label: const Text('Je cuisine !'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ] else if (missingIngredients != null && missingIngredients.isNotEmpty) ...[
                            // Ingrédients manquants : bouton liste de courses
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: shoppingListStatus != null
                                    ? () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const ShoppingListsPage(),
                                    ),
                                  );
                                }
                                    : () {
                                  Navigator.pop(context);
                                  _generateShoppingList(recipe);
                                },
                                icon: Icon(
                                  shoppingListStatus != null
                                      ? Icons.visibility
                                      : Icons.add_shopping_cart,
                                ),
                                label: Text(
                                  shoppingListStatus != null
                                      ? 'Voir la liste'
                                      : 'Créer liste de courses',
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            // Cas par défaut
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showSuccess('Bon appétit ! 🍳');
                                },
                                icon: const Icon(Icons.restaurant),
                                label: const Text('Je cuisine !'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
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
                        ],
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

  Widget _buildShoppingStatusSection(String status) {
    Color backgroundColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String title;
    String subtitle;

    switch (status) {
      case 'completed':
        backgroundColor = const Color(0xFFD1FAE5);
        borderColor = const Color(0xFF10B981);
        textColor = const Color(0xFF065F46);
        icon = Icons.check_circle;
        title = 'Courses terminées !';
        subtitle = 'Vous avez acheté tous les ingrédients manquants';
        break;
      case 'in_progress':
        backgroundColor = const Color(0xFFDBEAFE);
        borderColor = const Color(0xFF3B82F6);
        textColor = const Color(0xFF1E40AF);
        icon = Icons.shopping_cart;
        title = 'Courses en cours';
        subtitle = 'Certains articles ont déjà été achetés';
        break;
      case 'pending':
        backgroundColor = const Color(0xFFE0E7FF);
        borderColor = const Color(0xFF6366F1);
        textColor = const Color(0xFF3730A3);
        icon = Icons.list_alt;
        title = 'Liste de courses créée';
        subtitle = 'Les articles sont prêts à être achetés';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: borderColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: borderColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMissingIngredientsSection(List<dynamic> missingIngredients) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.kitchen,
                  color: Color(0xFFF59E0B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pas dans le frigo',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB45309),
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${missingIngredients.length} ingrédient(s) non détecté(s)',
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFFB45309).withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFFF59E0B), height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: missingIngredients.take(6).map((ing) {
              final name = ing['product_name'] ?? ing['name'] ?? 'Ingrédient';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                  ),
                ),
              );
            }).toList(),
          ),
          if (missingIngredients.length > 6) ...[
            const SizedBox(height: 8),
            Text(
              '+ ${missingIngredients.length - 6} autre(s)',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFFB45309).withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeasibleRecipes() {
    if (_selectedFridgeId == null) {
      return _buildEmptyState(
        Icons.kitchen_outlined,
        'Aucun frigo sélectionné',
        'Sélectionnez un frigo depuis le tableau de bord\npour voir les recettes réalisables',
      );
    }

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

          // ✅ DEBUG : Afficher la structure des données
          if (kDebugMode && index == 0) {
            print('🔍 Structure item: ${item.keys.toList()}');
            print('🔍 recipe type: ${item['recipe'].runtimeType}');
            print('🔍 can_make: ${item['can_make']}');
            print('🔍 match_percentage: ${item['match_percentage']}');
            print('🔍 shopping_list_status: ${item['shopping_list_status']}');
            print('🔍 ingredients_complete: ${item['ingredients_complete']}');
            print('🔍 combined_percentage: ${item['combined_percentage']}');
          }

          // ✅ Le backend retourne "recipe" comme objet imbriqué
          final recipe = item['recipe'] as Map<String, dynamic>;

          // Données de faisabilité
          final canMake = item['can_make'] as bool? ?? false;
          final matchPercentage = _toDouble(item['match_percentage']);
          final missingIngredients = item['missing_ingredients'] as List<dynamic>? ?? [];

          // Infos liste de courses
          final shoppingListStatus = item['shopping_list_status'] as String?;
          final shoppingListId = item['shopping_list_id'] as int?;

          // Statut combiné - ✅ avec valeurs par défaut correctes
          final ingredientsComplete = item['ingredients_complete'] as bool? ?? canMake;
          final combinedPercentage = _toDouble(item['combined_percentage']) > 0
              ? _toDouble(item['combined_percentage'])
              : matchPercentage;
          final purchasedMissingCount = item['purchased_missing_count'] as int? ?? 0;
          final totalMissingCount = item['total_missing_count'] as int? ?? missingIngredients.length;

          if (kDebugMode) {
            print('📊 ${recipe['title']}: complete=$ingredientsComplete, combined=$combinedPercentage%, status=$shoppingListStatus');
          }

          return _buildRecipeCard(
            recipe,
            canMake: canMake,
            matchPercentage: matchPercentage,
            missingIngredients: missingIngredients,
            shoppingListStatus: shoppingListStatus,
            shoppingListId: shoppingListId,
            ingredientsComplete: ingredientsComplete,
            combinedPercentage: combinedPercentage,
            purchasedMissingCount: purchasedMissingCount,
            totalMissingCount: totalMissingCount,
          );
        },
      ),
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
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
        itemBuilder: (context, index) => _buildSimpleRecipeCard(_allRecipes[index]),
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
        itemBuilder: (context, index) => _buildSimpleRecipeCard(_favoriteRecipes[index]),
      ),
    );
  }


  Widget _buildSimpleRecipeCard(Map<String, dynamic> recipe) {
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
          onTap: () => _showRecipeDetails(recipe),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header avec image
              Stack(
                children: [
                  Container(
                    height: 150,
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
                        size: 48,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ),
                  // Badge favori
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
                ],
              ),
              // Contenu
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
                    // Infos temps / difficulté
                    Row(
                      children: [
                        if (recipe['preparation_time'] != null) ...[
                          _buildInfoChip(Icons.schedule_outlined, '${recipe['preparation_time']} min'),
                          const SizedBox(width: 8),
                        ],
                        if (recipe['difficulty'] != null)
                          _buildInfoChip(Icons.signal_cellular_alt, recipe['difficulty']),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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