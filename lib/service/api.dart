import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ClientApiService {
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1';
  static const Duration timeout = Duration(seconds: 30);

  String? _accessToken;
  String? _refreshToken;
  bool _isInitialized = false;
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;

  static final ClientApiService _instance = ClientApiService._internal();
  factory ClientApiService() => _instance;
  ClientApiService._internal();

  Function()? onSessionExpired;

  Future<void> init() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
    _isInitialized = true;
    if (kDebugMode) print('✅ API Service initialized - Token present: ${_accessToken != null}');
  }

  Future<bool> isAuthenticated() async {
    await init();
    return _accessToken != null && _accessToken!.isNotEmpty;
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    await init();
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw AuthException('Non authentifié - Reconnectez-vous');
    }
    return {'Content-Type': 'application/json', 'Authorization': 'Bearer $_accessToken'};
  }

  Future<bool> _refreshAccessToken() async {
    if (_isRefreshing && _refreshCompleter != null) {
      return await _refreshCompleter!.future;
    }

    if (_refreshToken == null || _refreshToken!.isEmpty) {
      return false;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<bool>();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh_token': _refreshToken}),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveTokens(data['access_token'], data['refresh_token']);
        _refreshCompleter!.complete(true);
        return true;
      } else {
        _refreshCompleter!.complete(false);
        return false;
      }
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  Future<void> register({required String email, required String password, required String name}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password, 'name': name}),
      ).timeout(timeout);

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        await _saveTokens(data['access_token'], data['refresh_token']);
      } else if (response.statusCode == 400) {
        throw Exception('Email déjà utilisé');
      } else {
        throw Exception(json.decode(response.body)['detail'] ?? 'Erreur d\'inscription');
      }
    } on TimeoutException { throw Exception('Délai d\'attente dépassé'); }
    on http.ClientException { throw Exception('Impossible de contacter le serveur'); }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveTokens(data['access_token'], data['refresh_token']);
      } else if (response.statusCode == 401) {
        throw Exception('Email ou mot de passe incorrect');
      } else {
        throw Exception(json.decode(response.body)['detail'] ?? 'Erreur de connexion');
      }
    } on TimeoutException { throw Exception('Délai d\'attente dépassé'); }
    on http.ClientException { throw Exception('Impossible de contacter le serveur'); }
  }

  Future<void> _saveTokens(String accessToken, String refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _isInitialized = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
    await prefs.setString('refresh_token', refreshToken);
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _isInitialized = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('selected_fridge_id');
  }

  Future<http.Response> _makeAuthenticatedRequest(
      Future<http.Response> Function(Map<String, String> headers) request,
      {int retryCount = 0}
      ) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await request(headers);

      if (response.statusCode == 401 && retryCount == 0) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) return await _makeAuthenticatedRequest(request, retryCount: 1);
        else {
          await logout();
          onSessionExpired?.call();
          throw SessionExpiredException('Session expirée - Reconnectez-vous');
        }
      }
      return response;
    } on AuthException { rethrow; }
    on SessionExpiredException { rethrow; }
    catch (e) { rethrow; }
  }

  // ================== USER ==================
  Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await _makeAuthenticatedRequest((headers) => http.get(Uri.parse('$baseUrl/users/me'), headers: headers).timeout(timeout));
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Erreur ${response.statusCode}');
  }

  Future<Map<String, dynamic>> updateUser({String? name, String? preferredCuisine, List<String>? dietaryRestrictions, String? timezone}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (preferredCuisine != null) body['preferred_cuisine'] = preferredCuisine;
    if (dietaryRestrictions != null) body['dietary_restrictions'] = dietaryRestrictions;
    if (timezone != null) body['timezone'] = timezone;

    final response = await _makeAuthenticatedRequest((headers) => http.put(Uri.parse('$baseUrl/users/me'), headers: headers, body: json.encode(body)).timeout(timeout));
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Échec de mise à jour');
  }

  // ================== FRIDGE ==================
  Future<Map<String, dynamic>> pairFridge({required String pairingCode, String? fridgeName, String? fridgeLocation}) async {
    final response = await _makeAuthenticatedRequest((headers) => http.post(
      Uri.parse('$baseUrl/fridges/pair'),
      headers: headers,
      body: json.encode({'pairing_code': pairingCode, 'fridge_name': fridgeName ?? 'Mon Frigo', 'fridge_location': fridgeLocation}),
    ).timeout(timeout));

    if (response.statusCode == 200) return json.decode(response.body);
    else if (response.statusCode == 404) throw Exception('Code invalide ou expiré');
    else throw Exception(json.decode(response.body)['detail'] ?? 'Erreur de pairing');
  }

  Future<List<dynamic>> getFridges() async {
    final response = await _makeAuthenticatedRequest((headers) => http.get(Uri.parse('$baseUrl/fridges'), headers: headers).timeout(timeout));
    if (response.statusCode == 200) { final data = json.decode(response.body); return data is List ? data : []; }
    throw Exception('Erreur ${response.statusCode}');
  }

  Future<Map<String, dynamic>> getFridge(int fridgeId) async {
    final response = await _makeAuthenticatedRequest((headers) => http.get(Uri.parse('$baseUrl/fridges/$fridgeId'), headers: headers).timeout(timeout));
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Frigo non trouvé');
  }

  // ================== INVENTORY ==================
  Future<List<dynamic>> getInventory(int fridgeId) async {
    final response = await _makeAuthenticatedRequest((headers) => http.get(Uri.parse('$baseUrl/fridges/$fridgeId/inventory'), headers: headers).timeout(timeout));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data is List ? data : [];
    }
    throw Exception('Erreur ${response.statusCode}');
  }

  /// 🆕 NOUVELLE MÉTHODE: Ajouter un item avec création de produit possible
  Future<Map<String, dynamic>> addInventoryItem({
    required int fridgeId,
    int? productId,
    String? productName,
    String? category,
    required double quantity,
    String? unit,
    DateTime? expiryDate,
  }) async {
    final body = <String, dynamic>{
      'quantity': quantity,
    };

    // Mode 1: Produit existant
    if (productId != null) {
      body['product_id'] = productId;
    }
    // Mode 2: Nouveau produit
    else if (productName != null && productName.isNotEmpty) {
      body['product_name'] = productName;
      if (category != null) body['category'] = category;
    }

    if (unit != null) body['unit'] = unit;
    if (expiryDate != null) body['expiry_date'] = expiryDate.toIso8601String().split('T')[0];

    final response = await _makeAuthenticatedRequest((headers) => http.post(
      Uri.parse('$baseUrl/fridges/$fridgeId/inventory'),
      headers: headers,
      body: json.encode(body),
    ).timeout(timeout));

    if (response.statusCode == 201) return json.decode(response.body);

    final error = json.decode(response.body);
    throw Exception(error['detail'] ?? 'Échec d\'ajout');
  }

  Future<void> updateInventoryItem({required int fridgeId, required int itemId, double? quantity, DateTime? expiryDate}) async {
    final body = <String, dynamic>{};
    if (quantity != null) body['quantity'] = quantity;
    if (expiryDate != null) body['expiry_date'] = expiryDate.toIso8601String().split('T')[0];
    final response = await _makeAuthenticatedRequest((headers) => http.put(Uri.parse('$baseUrl/fridges/$fridgeId/inventory/$itemId'), headers: headers, body: json.encode(body)).timeout(timeout));
    if (response.statusCode != 200) throw Exception('Échec de mise à jour');
  }

  Future<void> consumeItem({required int fridgeId, required int itemId, required double quantityConsumed}) async {
    final response = await _makeAuthenticatedRequest((headers) => http.post(Uri.parse('$baseUrl/fridges/$fridgeId/inventory/$itemId/consume'), headers: headers, body: json.encode({'quantity_consumed': quantityConsumed})).timeout(timeout));
    if (response.statusCode != 200) throw Exception('Échec de consommation');
  }

  Future<void> deleteInventoryItem({required int fridgeId, required int itemId}) async {
    final response = await _makeAuthenticatedRequest((headers) => http.delete(Uri.parse('$baseUrl/fridges/$fridgeId/inventory/$itemId'), headers: headers).timeout(timeout));
    if (response.statusCode != 204) throw Exception('Échec de suppression');
  }

  // ================== PRODUCTS ==================
  Future<List<dynamic>> getProducts({String? search}) async {
    var url = '$baseUrl/products?limit=200';
    if (search != null && search.isNotEmpty) url += '&search=${Uri.encodeComponent(search)}';
    final response = await _makeAuthenticatedRequest((headers) => http.get(Uri.parse(url), headers: headers).timeout(timeout));
    if (response.statusCode == 200) { final data = json.decode(response.body); return data is List ? data : []; }
    throw Exception('Erreur ${response.statusCode}');
  }

  // ================== ALERTS ==================
  Future<List<dynamic>> getAlerts(int fridgeId, {String? status}) async {
    var url = '$baseUrl/fridges/$fridgeId/alerts';
    if (status != null) url += '?status=$status';
    final response = await _makeAuthenticatedRequest((headers) => http.get(Uri.parse(url), headers: headers).timeout(timeout));
    if (response.statusCode == 200) { final data = json.decode(response.body); return data is List ? data : []; }
    throw Exception('Erreur ${response.statusCode}');
  }

  Future<void> updateAlertStatus({required int fridgeId, required int alertId, required String status}) async {
    final response = await _makeAuthenticatedRequest((headers) => http.put(Uri.parse('$baseUrl/fridges/$fridgeId/alerts/$alertId'), headers: headers, body: json.encode({'status': status})).timeout(timeout));
    if (response.statusCode != 200) throw Exception('Échec de mise à jour');
  }

  // ================== RECIPES ==================

  Future<Map<String, dynamic>> saveSuggestedRecipe(Map<String, dynamic> suggestion) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.post(
          Uri.parse('$baseUrl/recipes/save-suggested'),
          headers: headers,
          body: json.encode(suggestion),
        ).timeout(timeout)
    );

    if (response.statusCode == 201) return json.decode(response.body);
    throw Exception('Échec de sauvegarde de la recette');
  }

  Future<List<dynamic>> getRecipes() async {
    final response = await _makeAuthenticatedRequest((headers) => http.get(Uri.parse('$baseUrl/recipes?limit=100'), headers: headers).timeout(timeout));
    if (response.statusCode == 200) { final data = json.decode(response.body); return data is List ? data : []; }
    throw Exception('Erreur ${response.statusCode}');
  }

  Future<List<dynamic>> getFeasibleRecipes(int fridgeId) async {
    final response = await _makeAuthenticatedRequest((headers) => http.get(Uri.parse('$baseUrl/recipes/fridges/$fridgeId/feasible'), headers: headers).timeout(timeout));
    if (response.statusCode == 200) { final data = json.decode(response.body); return data is List ? data : []; }
    throw Exception('Erreur ${response.statusCode}');
  }

  Future<List<dynamic>> getFavoriteRecipes() async {
    final response = await _makeAuthenticatedRequest((headers) => http.get(Uri.parse('$baseUrl/recipes/favorites/mine'), headers: headers).timeout(timeout));
    if (response.statusCode == 200) { final data = json.decode(response.body); return data is List ? data : []; }
    throw Exception('Erreur ${response.statusCode}');
  }

  Future<void> addRecipeToFavorites(int recipeId) async {
    final response = await _makeAuthenticatedRequest((headers) => http.post(Uri.parse('$baseUrl/recipes/$recipeId/favorite'), headers: headers).timeout(timeout));
    if (response.statusCode != 201) throw Exception('Échec d\'ajout');
  }

  Future<void> removeRecipeFromFavorites(int recipeId) async {
    final response = await _makeAuthenticatedRequest((headers) => http.delete(Uri.parse('$baseUrl/recipes/$recipeId/favorite'), headers: headers).timeout(timeout));
    if (response.statusCode != 204) throw Exception('Échec de suppression');
  }

  Future<Map<String, dynamic>> suggestRecipe(int fridgeId) async {
    final response = await _makeAuthenticatedRequest((headers) => http.post(
      Uri.parse('$baseUrl/recipes/fridges/$fridgeId/suggest'),
      headers: headers,
    ).timeout(const Duration(seconds: 60)));

    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Échec de suggestion: ${response.statusCode}');
  }

  // ================== SHOPPING LIST ==================
  Future<Map<String, dynamic>> generateShoppingList({required int fridgeId, List<int>? recipeIds}) async {
    final body = <String, dynamic>{'fridge_id': fridgeId};
    if (recipeIds != null) body['recipe_ids'] = recipeIds;
    final response = await _makeAuthenticatedRequest((headers) => http.post(Uri.parse('$baseUrl/shopping-lists/generate'), headers: headers, body: json.encode(body)).timeout(timeout));
    if (response.statusCode == 201) return json.decode(response.body);
    throw Exception('Échec de génération');
  }

  Future<Map<String, dynamic>> generateShoppingListFromIngredients({
    required int fridgeId,
    required List<Map<String, dynamic>> ingredients,
    int? recipeId,  // ✅ NOUVEAU paramètre
  }) async {
    final body = {
      'fridge_id': fridgeId,
      'ingredients': ingredients,
    };

    // ✅ Ajouter recipe_id si fourni
    if (recipeId != null) {
      body['recipe_id'] = recipeId;
    }

    final response = await _makeAuthenticatedRequest((headers) => http.post(
      Uri.parse('$baseUrl/shopping-lists/generate-from-ingredients'),
      headers: headers,
      body: json.encode(body),
    ).timeout(timeout));

    if (response.statusCode == 201) return json.decode(response.body);
    throw Exception('Échec de génération');
  }

  String? get accessToken => _accessToken;

  Future<String?> getFreshAccessToken() async {
    await init();
    if (_accessToken == null) return null;
    try {
      await _refreshAccessToken();
    } catch (e) { /* Ignorer */ }
    return _accessToken;
  }

  // ================== SHOPPING LISTS ==================

  /// Récupère toutes les listes de courses de l'utilisateur
  Future<List<dynamic>> getShoppingLists({int? fridgeId}) async {
    var url = '$baseUrl/shopping-lists';
    if (fridgeId != null) url += '?fridge_id=$fridgeId';

    final response = await _makeAuthenticatedRequest((headers) =>
        http.get(Uri.parse(url), headers: headers).timeout(timeout)
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data is List ? data : [];
    }
    throw Exception('Erreur ${response.statusCode}');
  }

  /// Récupère une liste de courses spécifique
  Future<Map<String, dynamic>> getShoppingList(int listId) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.get(
          Uri.parse('$baseUrl/shopping-lists/$listId'),
          headers: headers,
        ).timeout(timeout)
    );

    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Liste non trouvée');
  }

  /// Crée une liste de courses manuelle vide
  Future<Map<String, dynamic>> createEmptyShoppingList(int fridgeId) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.post(
          Uri.parse('$baseUrl/shopping-lists'),
          headers: headers,
          body: json.encode({
            'fridge_id': fridgeId,
            'items': [],
          }),
        ).timeout(timeout)
    );

    if (response.statusCode == 201) return json.decode(response.body);
    throw Exception('Échec de création');
  }

  /// Ajoute un article à une liste existante
  Future<void> addItemToShoppingList({
    required int listId,
    required int productId,
    required double quantity,
    required String unit,
  }) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.post(
          Uri.parse('$baseUrl/shopping-lists/$listId/items'),
          headers: headers,
          body: json.encode({
            'product_id': productId,
            'quantity': quantity,
            'unit': unit,
          }),
        ).timeout(timeout)
    );

    if (response.statusCode != 201) throw Exception('Échec d\'ajout');
  }

  /// Met à jour le statut d'un article (pending, purchased, cancelled)
  Future<void> updateShoppingListItemStatus({
    required int listId,
    required int itemId,
    required String status,
  }) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.put(
          Uri.parse('$baseUrl/shopping-lists/$listId/items/$itemId/status'),
          headers: headers,
          body: json.encode({'status': status}),  // ✅ Envoyer en JSON
        ).timeout(timeout)
    );

    if (response.statusCode != 200) throw Exception('Échec de mise à jour');
  }

  /// Supprime un article d'une liste
  Future<void> deleteShoppingListItem({
    required int listId,
    required int itemId,
  }) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.delete(
          Uri.parse('$baseUrl/shopping-lists/$listId/items/$itemId'),
          headers: headers,
        ).timeout(timeout)
    );

    if (response.statusCode != 204) throw Exception('Échec de suppression');
  }

  /// Supprime une liste complète
  Future<void> deleteShoppingList({required int listId}) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.delete(
          Uri.parse('$baseUrl/shopping-lists/$listId'),
          headers: headers,
        ).timeout(timeout)
    );

    if (response.statusCode != 204) throw Exception('Échec de suppression');
  }

  /// Marque tous les articles d'une liste comme achetés
  Future<void> markAllAsPurchased(int listId) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.post(
          Uri.parse('$baseUrl/shopping-lists/$listId/mark-all-purchased'),
          headers: headers,
        ).timeout(timeout)
    );

    if (response.statusCode != 200) {
      throw Exception('Échec de l\'opération');
    }
  }

  /// Génère une liste automatique basée sur l'inventaire faible
  Future<Map<String, dynamic>> generateAutoShoppingList(int fridgeId) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.post(
          Uri.parse('$baseUrl/shopping-lists/generate'),
          headers: headers,
          body: json.encode({
            'fridge_id': fridgeId,
          }),
        ).timeout(timeout)
    );

    if (response.statusCode == 201) return json.decode(response.body);
    throw Exception('Échec de génération');
  }

  // Dans api.dart - Remplacez la méthode createShoppingListWithItems

  /// Crée une liste de courses avec des articles (existants ou personnalisés)
  Future<Map<String, dynamic>> createShoppingListWithItems({
    required int fridgeId,
    required List<Map<String, dynamic>> items,
  }) async {
    // Construire les items au format attendu par l'API
    final formattedItems = items.map((item) {
      final Map<String, dynamic> formattedItem = {
        'quantity': (item['quantity'] as num).toDouble(),
        'unit': item['unit'] ?? 'pièce',
      };

      // ✅ Si c'est un produit existant (sélectionné), envoyer product_id
      if (item['product_id'] != null) {
        formattedItem['product_id'] = item['product_id'];
      }
      // ✅ Si c'est un produit personnalisé (saisie libre), envoyer product_name
      else if (item['custom_name'] != null || item['product_name'] != null) {
        formattedItem['product_name'] = item['custom_name'] ?? item['product_name'];
      }

      return formattedItem;
    }).toList();

    print('📤 Sending to API: fridge_id=$fridgeId, items=$formattedItems');

    final response = await _makeAuthenticatedRequest((headers) =>
        http.post(
          Uri.parse('$baseUrl/shopping-lists'),
          headers: headers,
          body: json.encode({
            'fridge_id': fridgeId,
            'items': formattedItems,
          }),
        ).timeout(timeout)
    );

    print('📥 Response: ${response.statusCode} - ${response.body}');

    if (response.statusCode == 201) {
      return json.decode(response.body);
    }

    // Afficher l'erreur détaillée
    final error = json.decode(response.body);
    throw Exception(error['detail'] ?? 'Échec de création: ${response.statusCode}');
  }

  Future<void> addItemToShoppingListWithName({
    required int listId,
    required String productName,
    required double quantity,
    required String unit,
  }) async {
    final response = await _makeAuthenticatedRequest((headers) =>
        http.post(
          Uri.parse('$baseUrl/shopping-lists/$listId/items'),
          headers: headers,
          body: json.encode({
            'product_name': productName,
            'quantity': quantity,
            'unit': unit,
          }),
        ).timeout(timeout)
    );

    if (response.statusCode != 201) {
      final error = json.decode(response.body);
      throw Exception(error['detail'] ?? 'Échec d\'ajout');
    }
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException(this.message);
  @override
  String toString() => message;
}