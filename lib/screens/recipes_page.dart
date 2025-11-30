import 'package:flutter/material.dart';
import 'package:user_smartfridge/main.dart';
import 'package:user_smartfridge/service/api_service.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({Key? key}) : super(key: key);

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> with SingleTickerProviderStateMixin {
  final ClientApiService _api = ClientApiService();
  late TabController _tabController;
  List<dynamic> _allRecipes = [];
  List<dynamic> _feasibleRecipes = [];
  List<dynamic> _favoriteRecipes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRecipes();
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
      final allRecipes = await _api.getRecipes();
      final favoriteRecipes = await _api.getFavoriteRecipes();

      List<dynamic> feasible = [];
      if (fridges.isNotEmpty) {
        feasible = await _api.getFeasibleRecipes(fridges[0]['id']);
      }

      setState(() {
        _allRecipes = allRecipes;
        _feasibleRecipes = feasible;
        _favoriteRecipes = favoriteRecipes;
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildAppBar(),
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
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recettes',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_feasibleRecipes.length} réalisables',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.tune,
              color: Color(0xFF64748B),
              size: 20,
            ),
          ),
        ],
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
          Tab(text: 'Réalisables'),
          Tab(text: 'Toutes'),
          Tab(text: 'Favorites'),
        ],
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allRecipes.length,
      itemBuilder: (context, index) => _buildRecipeCard(_allRecipes[index]),
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _favoriteRecipes.length,
      itemBuilder: (context, index) => _buildRecipeCard(_favoriteRecipes[index]),
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
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeCard(
      Map<String, dynamic> recipe, {
        bool? canMake,
        double? matchPercentage,
        List<dynamic>? missingIngredients,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showRecipeDetails(recipe, missingIngredients: missingIngredients),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image header
              Stack(
                children: [
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF3B82F6).withOpacity(0.8),
                          const Color(0xFF8B5CF6).withOpacity(0.8),
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
                  Positioned(
                    top: 12,
                    right: 12,
                    child: InkWell(
                      onTap: () => _toggleFavorite(recipe),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _favoriteRecipes.any((r) => r['id'] == recipe['id'])
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _favoriteRecipes.any((r) => r['id'] == recipe['id'])
                              ? Colors.red
                              : const Color(0xFF64748B),
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
                          color: canMake
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
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
              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe['title'] ?? 'Recette',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (recipe['description'] != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        recipe['description'],
                        style: const TextStyle(
                          color: Color(0xFF64748B),
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
                          _buildInfoChip(
                            Icons.signal_cellular_alt,
                            recipe['difficulty'],
                          ),
                        const Spacer(),
                        if (matchPercentage != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 14,
                                  color: Color(0xFF3B82F6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${matchPercentage.toInt()}%',
                                  style: const TextStyle(
                                    color: Color(0xFF3B82F6),
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
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateShoppingList(Map<String, dynamic> recipe) async {
    try {
      // Récupérer le premier frigo
      final fridges = await _api.getFridges();
      if (fridges.isEmpty) {
        _showError('Aucun frigo disponible');
        return;
      }

      // Générer la liste de courses
      final result = await _api.generateShoppingList(
        fridgeId: fridges[0]['id'],
        recipeIds: [recipe['id']],
      );

      if (!mounted) return;

      // Afficher un résumé
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF10B981)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Liste générée')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Votre liste de courses a été créée avec succès !',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 12),
                    Text(
                      '${(result['items'] as List).length} article(s)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
                // Naviguer vers la liste de courses (à implémenter)
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text('Voir la liste'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('Erreur: $e');
    }
  }

  Future<void> _toggleFavorite(Map<String, dynamic> recipe) async {
    try {
      final isFavorite = _favoriteRecipes.any((r) => r['id'] == recipe['id']);

      if (isFavorite) {
        await _api.removeRecipeFromFavorites(recipe['id']);
        _showSuccess('Retiré des favoris');
      } else {
        await _api.addRecipeToFavorites(recipe['id']);
        _showSuccess('Ajouté aux favoris');
      }

      _loadRecipes();
    } catch (e) {
      _showError('Erreur: $e');
    }
  }

  void _showRecipeDetails(Map<String, dynamic> recipe, {List<dynamic>? missingIngredients}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                          color: const Color(0xFFE2E8F0),
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
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _favoriteRecipes.any((r) => r['id'] == recipe['id'])
                                ? Icons.favorite
                                : Icons.favorite_border,
                          ),
                          color: _favoriteRecipes.any((r) => r['id'] == recipe['id'])
                              ? Colors.red
                              : null,
                          onPressed: () => _toggleFavorite(recipe),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_outlined),
                          onPressed: () {
                            // Partager la recette
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
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        recipe['description'],
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF64748B),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    const Text(
                      'Instructions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      recipe['steps'] ?? 'Pas d\'instructions disponibles',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
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
                            ...missingIngredients.map((ing) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${ing['product_name']}',
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 14,
                                ),
                              ),
                            )),
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
                  color: Colors.white,
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
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
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
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

}