import 'package:flutter_gemma/flutter_gemma.dart';
import 'ai_service.dart';

const String _modelUrl =
    'https://huggingface.co/aspect-build/gemma-3-1b-it-tflite/resolve/main/gemma3-1b-it-int4.task';
const String _hfToken = 'YOUR_HF_TOKEN_HERE';

class LocalAIService implements AIService {
  InferenceChat? _chat;

  @override
  Future<void> initialize({void Function(double)? onProgress}) async {
    await FlutterGemma.initialize();

    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromNetwork(_modelUrl, token: _hfToken)
        .withProgress((p) => onProgress?.call(p / 100))
        .install();

    final model = await FlutterGemma.getActiveModel(
      maxTokens: 1024,
      preferredBackend: PreferredBackend.gpu,
    );
    _chat = await model.createChat();
  }

  @override
  Stream<String> generateResponseStream(String prompt) async* {
    final chat = _chat;
    if (chat == null) throw StateError('LocalAIService not initialized');

    await chat.addQuery(Message.text(text: prompt, isUser: true));
    await for (final chunk in chat.generateChatResponseAsync()) {
      if (chunk is TextResponse) yield chunk.token;
    }
  }

  @override
  Future<void> dispose() async {
    _chat = null;
  }
}
