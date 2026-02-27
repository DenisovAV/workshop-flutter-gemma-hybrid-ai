import 'package:firebase_ai/firebase_ai.dart';
import 'ai_service.dart';

class FirebaseAIService implements AIService {
  GenerativeModel? _model;

  @override
  Future<void> initialize() async {
    final ai = FirebaseAI.googleAI();
    _model = ai.generativeModel(model: 'gemini-2.5-flash');
  }

  @override
  Stream<String> generateResponseStream(String prompt) async* {
    final model = _model;
    if (model == null) throw StateError('FirebaseAIService not initialized');

    final stream = model.generateContentStream([Content.text(prompt)]);
    await for (final chunk in stream) {
      if (chunk.text != null) yield chunk.text!;
    }
  }

  @override
  Future<void> dispose() async {
    _model = null;
  }
}
