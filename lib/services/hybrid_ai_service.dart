import 'ai_service.dart';
import 'firebase_ai_service.dart';
import 'local_ai_service.dart';

enum AIStrategy { localFirst, cloudFirst, localOnly, cloudOnly }

class HybridAIService implements AIService {
  final LocalAIService local;
  final FirebaseAIService cloud;
  AIStrategy strategy = AIStrategy.localFirst;

  HybridAIService({required this.local, required this.cloud});

  @override
  Future<void> initialize() async {
    await cloud.initialize();
    await local.initialize();
  }

  @override
  Stream<String> generateResponseStream(String prompt) async* {
    switch (strategy) {
      case AIStrategy.localFirst:
        try {
          yield* local.generateResponseStream(prompt);
        } catch (e) {
          yield* cloud.generateResponseStream(prompt);
        }
      case AIStrategy.cloudFirst:
        try {
          yield* cloud.generateResponseStream(prompt);
        } catch (e) {
          yield* local.generateResponseStream(prompt);
        }
      case AIStrategy.localOnly:
        yield* local.generateResponseStream(prompt);
      case AIStrategy.cloudOnly:
        yield* cloud.generateResponseStream(prompt);
    }
  }

  @override
  Future<void> dispose() async {
    await local.dispose();
    await cloud.dispose();
  }
}
