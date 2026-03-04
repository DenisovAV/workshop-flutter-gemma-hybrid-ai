import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

const String _embeddingModelUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite';
const String _tokenizerUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';
const String _hfToken = 'YOUR_HF_TOKEN_HERE';

const List<String> _cityFiles = [
  'paris',
  'tokyo',
  'new_york',
  'barcelona',
  'istanbul',
  'sydney',
  'rio',
  'marrakech',
  'prague',
  'singapore',
];

class RagService {
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize({void Function(String status)? onStatus}) async {
    onStatus?.call('Installing embedding model...');
    await FlutterGemma.installEmbedder()
        .modelFromNetwork(_embeddingModelUrl, token: _hfToken)
        .tokenizerFromNetwork(_tokenizerUrl, token: _hfToken)
        .install();

    onStatus?.call('Initializing vector store...');
    await FlutterGemmaPlugin.instance.initializeVectorStore('rag.db');

    onStatus?.call('Loading tourist data...');
    await _loadTouristData();

    _isInitialized = true;
    onStatus?.call('RAG ready');
  }

  Future<void> _loadTouristData() async {
    for (final city in _cityFiles) {
      final jsonString =
          await rootBundle.loadString('assets/tourist_data/$city.json');
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      final description = data['description'] as String;
      final name = data['name'] as String;
      final country = data['country'] as String;
      final attractions = (data['attractions'] as List).join(', ');
      final cuisine = (data['cuisine'] as List).join(', ');
      final bestTime = data['best_time'] as String;
      final funFact = data['fun_fact'] as String;

      final content = '$description\n\n'
          'Top attractions: $attractions.\n'
          'Local cuisine: $cuisine.\n'
          'Best time to visit: $bestTime.\n'
          'Fun fact: $funFact';

      await FlutterGemmaPlugin.instance.addDocument(
        id: city,
        content: content,
        metadata: jsonEncode({'city': name, 'country': country}),
      );
    }
  }

  Future<int> getDocumentCount() async {
    final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
    return stats.documentCount;
  }
}
