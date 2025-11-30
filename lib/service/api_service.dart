// ============================================================================
// lib/services/api_service.dart - VERSION REFACTORISÉE COMPLÈTE
// ============================================================================
// ✅ Cohérent avec le nouveau backend (fridges.py)
// ✅ Gestion correcte du pairing simplifié
// ✅ Gestion d'erreurs robuste avec timeouts
// ============================================================================

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ClientApiService {
  // ⚠️ CONFIGURATION : Remplacer par l'IP réelle de votre backend
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1';
  static const Duration timeout = Duration(seconds: 30);

  String? _accessToken;
  String? _refreshToken;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    if (_accessToken == null) {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString('access_token');
    }

    if (_accessToken == null || _accessToken!.isEmpty) {
      throw Exception('Non authentifié - Reconnectez-vous');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_accessToken',
    };
  }

  // ============================================================================
  // AUTHENTICATION
  // ============================================================================

  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'name': name,
        }),
      )
          .timeout(timeout);

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _accessToken!);
        await prefs.setString('refresh_token', _refreshToken!);
      } else if (response.statusCode == 400) {
        throw Exception('Email déjà utilisé');
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Erreur d\'inscription';
        throw Exception(error);
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé. Vérifiez votre connexion.');
    } on http.ClientException {
      throw Exception('Impossible de contacter le serveur');
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
        }),
      )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _accessToken!);
        await prefs.setString('refresh_token', _refreshToken!);
      } else if (response.statusCode == 401) {
        throw Exception('Email ou mot de passe incorrect');
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Erreur de connexion';
        throw Exception(error);
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    } on http.ClientException {
      throw Exception('Impossible de contacter le serveur');
    }
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  // ============================================================================
  // USER MANAGEMENT
  // ============================================================================

  Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await http
        .get(
      Uri.parse('$baseUrl/users/me'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception('Session expirée - Reconnectez-vous');
    }
    throw Exception('Erreur ${response.statusCode}');
  }

  Future<Map<String, dynamic>> updateUser({
    String? name,
    String? preferredCuisine,
    List<String>? dietaryRestrictions,
    String? timezone,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (preferredCuisine != null) body['preferred_cuisine'] = preferredCuisine;
    if (dietaryRestrictions != null) body['dietary_restrictions'] = dietaryRestrictions;
    if (timezone != null) body['timezone'] = timezone;

    final response = await http
        .put(
      Uri.parse('$baseUrl/users/me'),
      headers: await _getAuthHeaders(),
      body: json.encode(body),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Échec de mise à jour');
  }

  // ============================================================================
  // FRIDGE MANAGEMENT - ✅ NOUVEAU SYSTÈME DE PAIRING
  // ============================================================================

  /// ✅ NOUVEAU : Pairing unifié (crée automatiquement le frigo)
  ///
  /// Flow simplifié :
  /// 1. Le kiosk affiche un code 6 chiffres
  /// 2. L'utilisateur entre ce code dans l'app
  /// 3. Cette route crée le frigo ET le lie à l'utilisateur
  Future<Map<String, dynamic>> pairFridge({
    required String pairingCode,
    String? fridgeName,
    String? fridgeLocation,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse('$baseUrl/fridges/pair'),
        headers: await _getAuthHeaders(),
        body: json.encode({
          'pairing_code': pairingCode,
          'fridge_name': fridgeName ?? 'Mon Frigo',
          'fridge_location': fridgeLocation,
        }),
      )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Code invalide ou expiré');
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Erreur de pairing';
        throw Exception(error);
      }
    } on TimeoutException {
      throw Exception('Délai d\'attente dépassé');
    }
  }

  /// Liste tous les frigos de l'utilisateur
  Future<List<dynamic>> getFridges() async {
    final response = await http
        .get(
      Uri.parse('$baseUrl/fridges'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception('Non autorisé');
    }
    throw Exception('Erreur ${response.statusCode}');
  }

  /// Récupère les détails d'un frigo
  Future<Map<String, dynamic>> getFridge(int fridgeId) async {
    final response = await http
        .get(
      Uri.parse('$baseUrl/fridges/$fridgeId'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Frigo non trouvé');
  }

  /// Met à jour le nom/localisation du frigo
  Future<Map<String, dynamic>> updateFridge({
    required int fridgeId,
    String? name,
    String? location,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (location != null) body['location'] = location;

    final response = await http
        .put(
      Uri.parse('$baseUrl/fridges/$fridgeId'),
      headers: await _getAuthHeaders(),
      body: json.encode(body),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Échec de mise à jour');
  }

  /// Délie un frigo (unpair)
  Future<void> unpairFridge(int fridgeId) async {
    final response = await http
        .delete(
      Uri.parse('$baseUrl/fridges/$fridgeId'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode != 204) {
      throw Exception('Échec de suppression');
    }
  }

  // ============================================================================
  // INVENTORY MANAGEMENT
  // ============================================================================

  Future<List<dynamic>> getInventory(int fridgeId) async {
    final response = await http
        .get(
      Uri.parse('$baseUrl/fridges/$fridgeId/inventory'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Erreur de chargement');
  }

  Future<void> consumeItem({
    required int fridgeId,
    required int itemId,
    required double quantityConsumed,
  }) async {
    final response = await http
        .post(
      Uri.parse('$baseUrl/fridges/$fridgeId/inventory/$itemId/consume'),
      headers: await _getAuthHeaders(),
      body: json.encode({'quantity_consumed': quantityConsumed}),
    )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Échec de consommation');
    }
  }

  // ============================================================================
  // PRODUCTS
  // ============================================================================

  Future<List<dynamic>> getProducts({String? search}) async {
    var url = '$baseUrl/products?limit=100';
    if (search != null && search.isNotEmpty) {
      url += '&search=$search';
    }

    final response = await http
        .get(
      Uri.parse(url),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Erreur de chargement');
  }

  // ============================================================================
  // ALERTS
  // ============================================================================

  Future<List<dynamic>> getAlerts(int fridgeId, {String? status}) async {
    var url = '$baseUrl/fridges/$fridgeId/alerts';
    if (status != null) url += '?status=$status';

    final response = await http
        .get(
      Uri.parse(url),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Erreur de chargement');
  }

  Future<void> updateAlertStatus({
    required int fridgeId,
    required int alertId,
    required String status,
  }) async {
    final response = await http
        .put(
      Uri.parse('$baseUrl/fridges/$fridgeId/alerts/$alertId'),
      headers: await _getAuthHeaders(),
      body: json.encode({'status': status}),
    )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Échec de mise à jour');
    }
  }

  // ============================================================================
  // RECIPES
  // ============================================================================

  Future<List<dynamic>> getRecipes() async {
    final response = await http
        .get(
      Uri.parse('$baseUrl/recipes'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Erreur de chargement');
  }

  Future<List<dynamic>> getFeasibleRecipes(int fridgeId) async {
    final response = await http
        .get(
      Uri.parse('$baseUrl/fridges/$fridgeId/feasible'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Erreur de chargement');
  }

  Future<List<dynamic>> getFavoriteRecipes() async {
    final response = await http
        .get(
      Uri.parse('$baseUrl/recipes/favorites/mine'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Erreur de chargement');
  }

  Future<void> addRecipeToFavorites(int recipeId) async {
    final response = await http
        .post(
      Uri.parse('$baseUrl/recipes/$recipeId/favorite'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode != 201) {
      throw Exception('Échec d\'ajout');
    }
  }

  Future<void> removeRecipeFromFavorites(int recipeId) async {
    final response = await http
        .delete(
      Uri.parse('$baseUrl/recipes/$recipeId/favorite'),
      headers: await _getAuthHeaders(),
    )
        .timeout(timeout);

    if (response.statusCode != 204) {
      throw Exception('Échec de suppression');
    }
  }

  // ============================================================================
  // SHOPPING LISTS
  // ============================================================================

  Future<Map<String, dynamic>> generateShoppingList({
    required int fridgeId,
    List<int>? recipeIds,
  }) async {
    final body = <String, dynamic>{'fridge_id': fridgeId};
    if (recipeIds != null) body['recipe_ids'] = recipeIds;

    final response = await http
        .post(
      Uri.parse('$baseUrl/shopping-lists/generate'),
      headers: await _getAuthHeaders(),
      body: json.encode(body),
    )
        .timeout(timeout);

    if (response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception('Échec de génération');
  }
}