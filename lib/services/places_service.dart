import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/place_prediction.dart';

class PlacesService {
  // Using the key found in AndroidManifest.xml
  static const String _apiKey = 'AIzaSyDS0jNofvgOG3romY33T3wSDhplM1kvhRs';
  
  // Cache required for autocomplete to avoid excessive API calls
  final Map<String, List<PlacePrediction>> _cache = {};

  Future<List<PlacePrediction>> getAutocompletePredictions(String query) async {
    if (query.trim().isEmpty) return [];
    
    // Check cache
    if (_cache.containsKey(query)) {
      return _cache[query]!;
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(query)}'
      '&key=$_apiKey'
    );

    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          final predictions = (data['predictions'] as List)
              .map((item) => PlacePrediction.fromJson(item))
              .toList();
          
          _cache[query] = predictions;
          return predictions;
        } else {
          debugPrint('Places API Error: ${data['status']} - ${data['error_message']}');
          return [];
        }
      } else {
        debugPrint('Places API HTTP Error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching places: $e');
      return [];
    }
  }

  Future<String?> getPlaceUrl(String placeId) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId'
      '&fields=url,geometry'
      '&key=$_apiKey'
    );

    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          
          // Prefer the official Google Maps URL
          if (result['url'] != null) {
            return result['url'];
          }
          
          // Fallback to constructing URL from coordinates
          final location = result['geometry']?['location'];
          if (location != null) {
            final lat = location['lat'];
            final lng = location['lng'];
            return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching place details: $e');
    }
    return null;
  }
}
