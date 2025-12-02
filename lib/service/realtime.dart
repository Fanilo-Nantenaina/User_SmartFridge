import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum InventoryUpdateType {
  updated,
  consumed,
  alert,
  expired,
  added,
  removed,
}

class InventoryUpdateEvent {
  final InventoryUpdateType type;
  final String message;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  InventoryUpdateEvent({
    required this.type,
    required this.message,
    required this.payload,
    required this.timestamp,
  });

  factory InventoryUpdateEvent.fromJson(Map<String, dynamic> json) {
    // ✅ CORRECTION: Gestion sécurisée des valeurs null
    final typeStr = json['type']?.toString() ?? 'INVENTORY_UPDATED';
    final type = _parseEventType(typeStr);

    return InventoryUpdateEvent(
      type: type,
      message: json['message']?.toString() ?? _generateMessage(type, json['payload']),
      payload: (json['payload'] is Map<String, dynamic>)
          ? json['payload']
          : <String, dynamic>{},
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static InventoryUpdateType _parseEventType(String typeStr) {
    switch (typeStr) {
      case 'INVENTORY_UPDATED':
      case 'ITEM_DETECTED':
      case 'QUANTITY_UPDATED':
        return InventoryUpdateType.updated;
      case 'ITEM_ADDED':
        return InventoryUpdateType.added;
      case 'ITEM_CONSUMED':
        return InventoryUpdateType.consumed;
      case 'ITEM_REMOVED':
        return InventoryUpdateType.removed;
      case 'ALERT_CREATED':
        return InventoryUpdateType.alert;
      case 'ITEM_EXPIRED':
      case 'EXPIRY_UPDATED':
        return InventoryUpdateType.expired;
      default:
        return InventoryUpdateType.updated;
    }
  }

  static String _generateMessage(InventoryUpdateType type, dynamic payload) {
    final Map<String, dynamic> safePayload =
    (payload is Map<String, dynamic>) ? payload : {};

    final productName = safePayload['product_name']?.toString() ?? 'Un produit';
    final quantity = safePayload['quantity']?.toString() ?? '';
    final unit = safePayload['unit']?.toString() ?? '';

    switch (type) {
      case InventoryUpdateType.added:
        return '$productName ajouté ($quantity $unit)'.trim();
      case InventoryUpdateType.updated:
        return 'Inventaire mis à jour';
      case InventoryUpdateType.consumed:
        return '$productName consommé';
      case InventoryUpdateType.removed:
        return '$productName retiré de l\'inventaire';
      case InventoryUpdateType.alert:
        return 'Nouvelle alerte créée';
      case InventoryUpdateType.expired:
        return '$productName a expiré';
    }
  }
}

class RealtimeService {
  final String baseUrl;
  final int fridgeId;
  final Future<String?> Function() getAccessToken;

  http.Client? _client;
  StreamController<InventoryUpdateEvent>? _controller;
  bool _isActive = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _baseReconnectDelay = Duration(seconds: 3);

  RealtimeService({
    required this.baseUrl,
    required this.fridgeId,
    required this.getAccessToken,
  });

  factory RealtimeService.fromApiService({
    required String baseUrl,
    required int fridgeId,
    required Future<String?> Function() tokenProvider,
  }) {
    return RealtimeService(
      baseUrl: baseUrl,
      fridgeId: fridgeId,
      getAccessToken: tokenProvider,
    );
  }

  Stream<InventoryUpdateEvent> listenToInventoryUpdates() {
    if (_controller != null && !_controller!.isClosed) {
      return _controller!.stream;
    }

    _controller = StreamController<InventoryUpdateEvent>.broadcast(
      onCancel: () {
        if (kDebugMode) print('📡 SSE stream cancelled by listener');
      },
    );
    _client = http.Client();
    _isActive = true;
    _reconnectAttempts = 0;

    _startListening();

    return _controller!.stream;
  }

  Future<void> _startListening() async {
    if (!_isActive) return;

    try {
      final accessToken = await getAccessToken();

      if (accessToken == null || accessToken.isEmpty) {
        if (kDebugMode) print('❌ No access token for SSE connection');
        if (_controller != null && !_controller!.isClosed) {
          _controller!.addError(Exception('Token non disponible'));
        }
        return;
      }

      if (kDebugMode) print('🔄 Starting SSE connection for fridge $fridgeId...');

      final request = http.Request(
        'GET',
        Uri.parse('$baseUrl/fridges/$fridgeId/events/all'),
      );

      request.headers['Authorization'] = 'Bearer $accessToken';
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      request.headers['Connection'] = 'keep-alive';

      final response = await _client!.send(request);

      if (response.statusCode == 200) {
        if (kDebugMode) print('✅ SSE connection established');
        _reconnectAttempts = 0;

        response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
            if (!_isActive) return;

            if (line.startsWith('data:')) {
              try {
                final jsonStr = line.substring(5).trim();
                if (jsonStr.isEmpty) return;

                final json = jsonDecode(jsonStr);

                // ✅ CORRECTION: Vérification que json est une Map valide
                if (json is! Map<String, dynamic>) {
                  if (kDebugMode) print('⚠️ Invalid JSON structure: $json');
                  return;
                }

                final event = InventoryUpdateEvent.fromJson(json);

                if (_controller != null && !_controller!.isClosed) {
                  _controller!.add(event);
                }

                if (kDebugMode) print('📨 Event received: ${event.type} - ${event.message}');
              } catch (e, stackTrace) {
                // ✅ CORRECTION: Ne pas crasher sur erreur de parsing
                if (kDebugMode) {
                  print('⚠️ Error parsing event: $e');
                  print('Line was: $line');
                  print('Stack: $stackTrace');
                }
                // Ne pas propager l'erreur - continuer à écouter
              }
            }
          },
          onError: (error) {
            if (kDebugMode) print('❌ SSE stream error: $error');
            if (_controller != null && !_controller!.isClosed) {
              _controller!.addError(error);
            }
            _scheduleReconnect();
          },
          onDone: () {
            if (kDebugMode) print('⚠️ SSE stream closed');
            _scheduleReconnect();
          },
          cancelOnError: false,
        );
      } else if (response.statusCode == 401) {
        if (kDebugMode) print('🔄 SSE 401 - Token expired, will retry with fresh token');
        _scheduleReconnect();
      } else {
        if (kDebugMode) print('❌ SSE connection failed: ${response.statusCode}');
        if (_controller != null && !_controller!.isClosed) {
          _controller!.addError(Exception('Failed to connect: ${response.statusCode}'));
        }
        _scheduleReconnect();
      }
    } catch (e) {
      if (kDebugMode) print('❌ SSE connection error: $e');
      if (_controller != null && !_controller!.isClosed) {
        _controller!.addError(e);
      }
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_isActive) return;

    _reconnectAttempts++;

    if (_reconnectAttempts > _maxReconnectAttempts) {
      if (kDebugMode) print('❌ Max reconnect attempts reached, stopping SSE');
      if (_controller != null && !_controller!.isClosed) {
        _controller!.addError(Exception('Connexion impossible après $_maxReconnectAttempts tentatives'));
      }
      return;
    }

    final baseDelay = _baseReconnectDelay.inSeconds * _reconnectAttempts;
    final jitter = (baseDelay * 0.2 * (DateTime.now().millisecond / 1000)).round();
    final delay = Duration(seconds: (baseDelay + jitter).clamp(3, 60));

    if (kDebugMode) {
      print('🔄 Reconnecting SSE in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)...');
    }

    Future.delayed(delay, () {
      if (_isActive) {
        _startListening();
      }
    });
  }

  void reset() {
    _reconnectAttempts = 0;
    _client?.close();
    _client = http.Client();

    if (_isActive) {
      _startListening();
    }
  }

  void dispose() {
    _isActive = false;
    _controller?.close();
    _client?.close();

    if (kDebugMode) print('🛑 RealtimeService disposed');
  }
}

extension RealtimeServiceExtension on RealtimeService {
  Stream<InventoryUpdateEvent> onInventoryChange() {
    return listenToInventoryUpdates().where((event) =>
    event.type == InventoryUpdateType.updated ||
        event.type == InventoryUpdateType.consumed ||
        event.type == InventoryUpdateType.added ||
        event.type == InventoryUpdateType.removed);
  }

  Stream<InventoryUpdateEvent> onAlertCreated() {
    return listenToInventoryUpdates()
        .where((event) => event.type == InventoryUpdateType.alert);
  }
}