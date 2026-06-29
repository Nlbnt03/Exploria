import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/place_suggestion.dart';

class PlaceSuggestionService {
  PlaceSuggestionService()
      : _col = FirebaseFirestore.instance.collection('placeSuggestions');

  final CollectionReference<Map<String, dynamic>> _col;

  Future<void> submitSuggestion(PlaceSuggestion suggestion) async {
    await _col.add(suggestion.toFirestore());
  }
}
