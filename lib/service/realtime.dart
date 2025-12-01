import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

enum InventoryUpdateType {
  updated, // INVENTORY_UPDATED
  consumed, // ITEM_CONSUMED
  alert, // ALERT_CREATED
  expired, // ITEM_EXPIRED
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
    final typeStr = json['type'] as String;
    final type = _parseEventType(typeStr);

    return InventoryUpdateEvent(
      type: type,
      message: _generateMessage(type, json['payload']),
      payload: json['payload'] ?? {},
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  static InventoryUpdateType _parseEventType(String typeStr) {
    switch (typeStr) {
      case 'INVENTORY_UPDATED':
        return InventoryUpdateType.updated;
      case 'ITEM_CONSUMED':
        return InventoryUpdateType.consumed;
      case 'ALERT_CREATED':
        return InventoryUpdateType.alert;
      case 'ITEM_EXPIRED':
        return InventoryUpdateType.expired;
      default:
        return InventoryUpdateType.updated;
    }
  }

  static String _generateMessage(
      InventoryUpdateType type, Map<String, dynamic>? payload) {
    switch (type) {
      case InventoryUpdateType.updated:
        return 'Inventaire mis à jour depuis le kiosk';
      case InventoryUpdateType.consumed:
        final productName = payload?['product_name'] ?? 'Un produit';
        return '$productName a été consommé';
      case InventoryUpdateType.alert:
        return 'Nouvelle alerte créée';
      case InventoryUpdateType.expired:
        final productName = payload?['product_name'] ?? 'Un produit';
        return '$productName a expiré';
    }
  }
}

class RealtimeService {
  final String baseUrl;
  final String accessToken;
  final int fridgeId;

  http.Client? _client;
  StreamController<InventoryUpdateEvent>? _controller;

  RealtimeService({
    required this.baseUrl,
    required this.accessToken,
    required this.fridgeId,
  });

  Stream<InventoryUpdateEvent> listenToInventoryUpdates() {
    _controller = StreamController<InventoryUpdateEvent>();
    _client = http.Client();

    _startListening();

    return _controller!.stream;
  }

  Future<void> _startListening() async {
    try {
      final request = http.Request(
        'GET',
        Uri.parse('$baseUrl/fridges/$fridgeId/events/all'),
      );
      request.headers['Authorization'] = 'Bearer $accessToken';
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request);

      if (response.statusCode == 200) {
        response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
            if (line.startsWith('data:')) {
              try {
                final jsonStr = line.substring(5).trim();
                final json = jsonDecode(jsonStr);
                final event = InventoryUpdateEvent.fromJson(json);
                _controller?.add(event);
              } catch (e) {
                // Ignorer les erreurs de parsing
              }
            }
          },
          onError: (error) {
            _controller?.addError(error);
          },
          onDone: () {
            Future.delayed(const Duration(seconds: 5), _startListening);
          },
        );
      } else {
        _controller?.addError(
          Exception('Failed to connect: ${response.statusCode}'),
        );
      }
    } catch (e) {
      _controller?.addError(e);
      Future.delayed(const Duration(seconds: 5), _startListening);
    }
  }

  void dispose() {
    _controller?.close();
    _client?.close();
  }
}

extension RealtimeServiceExtension on RealtimeService {
  Stream<void> onInventoryUpdate() {
    return listenToInventoryUpdates()
        .where((event) =>
    event.type == InventoryUpdateType.updated ||
        event.type == InventoryUpdateType.consumed)
        .map((_) {});
  }

  Stream<void> onAlertCreated() {
    return listenToInventoryUpdates()
        .where((event) => event.type == InventoryUpdateType.alert)
        .map((_) {});
  }
}