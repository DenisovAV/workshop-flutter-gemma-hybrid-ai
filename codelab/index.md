author: Sasha Denisov
summary: Hybrid AI in Flutter — From Cloud to On-Device
id: hybrid-ai-flutter
categories: flutter, ai, gemma, firebase
environments: web, android, ios
status: Published
analytics account: UA-XXXXXXXX-X

# Hybrid AI in Flutter: From Cloud to On-Device

## Overview
Duration: 5

### What you'll build

A Flutter chat application that progressively integrates AI capabilities:

1. **Cloud Chat** — Streaming responses from Gemini via Firebase AI Logic
2. **Local Inference** — On-device AI with Gemma 3 1B via flutter\_gemma
3. **Hybrid Strategy** — Automatic fallback between cloud and local
4. **Embeddings** — Semantic vector representations with EmbeddingGemma
5. **RAG** — Context-augmented generation using a local tourist guide

### What you'll learn

- How to integrate Firebase AI Logic (Gemini API) into a Flutter app
- How to run AI models locally on device with flutter\_gemma
- How to implement fallback strategies between cloud and local AI
- How text embeddings work and how to store them in a VectorStore
- How to build a RAG (Retrieval-Augmented Generation) pipeline

### What you'll need

- Flutter 3.38+ installed
- Firebase CLI (`firebase-tools`)
- A Google account (for Firebase)
- A HuggingFace account (for model downloads)
- Android device/emulator, iOS simulator, or Chrome (for web)
- ~1GB free disk space (for the AI model)

### Architecture

```
┌─────────────────────────────────────┐
│           Flutter App               │
├─────────────────────────────────────┤
│         HybridAIService             │
├────────────────┬────────────────────┤
│ FirebaseAI     │  flutter_gemma     │
│ (Cloud)        │  (Local)           │
├────────────────┼────────────────────┤
│ Gemini 2.5     │  Gemma 3 1B        │
│ Flash          │  + EmbeddingGemma  │
└────────────────┴────────────────────┘
```

## Step 1: Starter Project
Duration: 5

### Clone the repository

```bash
git clone git@github.com:DenisovAV/workshop-flutter-gemma-hybrid-ai.git
cd workshop-flutter-gemma-hybrid-ai
git checkout step-00-starter
```

### Explore the project

Open the project in your IDE. The starter includes:

- **`lib/main.dart`** — App entry point with Material 3 theme
- **`lib/screens/chat_screen.dart`** — Chat UI with TextField, ListView, send button
- **`lib/widgets/message_bubble.dart`** — Styled message bubbles (user right, AI left)
- **`lib/models/message_model.dart`** — Simple `ChatMessage` data class
- **`lib/services/ai_service.dart`** — Abstract `AIService` interface
- **`assets/tourist_data/`** — 10 JSON files with city descriptions (for RAG later)

### The AIService interface

This is the contract all our AI services will implement:

```dart
abstract class AIService {
  Future<void> initialize();
  Stream<String> generateResponseStream(String prompt);
  Future<void> dispose();
}
```

Key design decision: `generateResponseStream` returns a `Stream<String>` for streaming token-by-token responses.

### Run the starter

```bash
flutter run
```

You should see a chat screen. Messages are echoed back with "(AI service not connected yet)". That's what we'll fix next.

### Checkpoint

- [ ] Project clones and runs
- [ ] Chat UI shows echo responses
- [ ] You can see the tourist data JSON files in `assets/tourist_data/`

## Step 2: Firebase Setup
Duration: 10

### Create a Firebase project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **Add project**
3. Name it (e.g., `workshop-hybrid-ai`)
4. Disable Google Analytics (optional for workshop)
5. Click **Create project**

### Enable Gemini API

1. In Firebase Console, go to **AI Logic** (left sidebar)
2. Follow the setup wizard
3. Enable the **Gemini API** for your project

### Install FlutterFire CLI

```bash
dart pub global activate flutterfire_cli
```

### Configure Firebase in your app

```bash
flutterfire configure --project=YOUR_PROJECT_ID
```

This generates `lib/firebase_options.dart` with your project configuration.

### Add dependencies

In `pubspec.yaml`, uncomment the Firebase dependencies:

```yaml
dependencies:
  # Step 2-3: Cloud AI
  firebase_core: ^4.4.0
  firebase_ai: ^3.8.0
```

Then run:

```bash
flutter pub get
```

### Checkpoint

- [ ] Firebase project created
- [ ] Gemini API enabled in Firebase Console
- [ ] `firebase_options.dart` generated
- [ ] Dependencies resolve without errors

## Step 3: Cloud Chat
Duration: 15

### Create FirebaseAIService

Create `lib/services/firebase_ai_service.dart`:

```dart
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
```

**Key points:**
- `FirebaseAI.googleAI()` uses the Google AI backend (free tier available)
- `generateContentStream` returns streaming chunks
- Each chunk may contain `text` — we yield it to the caller

### Update main.dart

Add Firebase initialization:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}
```

### Wire to chat screen

Update `chat_screen.dart` to use FirebaseAIService instead of the echo stub:

```dart
late final FirebaseAIService _aiService;

@override
void initState() {
  super.initState();
  _initServices();
}

Future<void> _initServices() async {
  _aiService = FirebaseAIService();
  await _aiService.initialize();
  setState(() => _isInitializing = false);
}
```

Update `_sendMessage` to use streaming:

```dart
Future<void> _sendMessage() async {
  final text = _controller.text.trim();
  if (text.isEmpty || _isGenerating) return;
  _controller.clear();

  setState(() {
    _messages.add(ChatMessage(text: text, isUser: true));
    _messages.add(ChatMessage(text: '', isUser: false));
    _isGenerating = true;
  });

  try {
    final buffer = StringBuffer();
    await for (final chunk in _aiService.generateResponseStream(text)) {
      buffer.write(chunk);
      setState(() {
        _messages.last = ChatMessage(text: buffer.toString(), isUser: false);
      });
    }
  } catch (e) {
    setState(() {
      _messages.last = ChatMessage(text: 'Error: $e', isUser: false);
    });
  } finally {
    setState(() => _isGenerating = false);
  }
}
```

**The streaming trick:** We create an empty assistant message, then update it in-place as tokens arrive. This gives the user a real-time typing effect.

### Run and test

```bash
flutter run
```

Ask something like "What is Flutter?" — you should see a streaming response from Gemini.

### Reference

To see the complete code for this step:

```bash
git checkout step-01-firebase-ai
```

### Troubleshooting

- **"No Firebase App"**: Make sure `Firebase.initializeApp()` is called before `runApp()`
- **"Permission denied"**: Check that Gemini API is enabled in Firebase Console
- **Web CORS errors**: Run with `flutter run -d chrome --web-browser-flag "--disable-web-security"`

### Checkpoint

- [ ] Cloud chat works with streaming responses
- [ ] You can ask questions and get answers from Gemini

## Step 4: Local Inference
Duration: 20

### Why local inference?

| | Cloud | Local |
|---|---|---|
| Latency | 200-500ms | 50-100ms |
| Privacy | Data leaves device | Stays on device |
| Cost | Per token | Free after download |
| Offline | No | Yes |

### Add flutter\_gemma dependency

In `pubspec.yaml`, uncomment:

```yaml
  # Step 4: Local AI
  flutter_gemma: ^0.12.4
```

```bash
flutter pub get
```

### Platform setup

#### iOS

In `ios/Podfile`, set minimum iOS version:

```ruby
platform :ios, '16.0'
use_frameworks! :linkage => :static
```

Add to `ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.kernel.extended-virtual-addressing</key>
<true/>
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

#### Android

Add to `android/app/src/main/AndroidManifest.xml` inside `<application>`:

```xml
<uses-native-library android:name="libOpenCL.so" android:required="false"/>
<uses-native-library android:name="libOpenCL-car.so" android:required="false"/>
<uses-native-library android:name="libOpenCL-pixel.so" android:required="false"/>
```

#### Web

Add to `web/index.html` before `</body>`:

```html
<script type="module">
import { FilesetResolver, LlmInference } from
  'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@latest';
window.FilesetResolver = FilesetResolver;
window.LlmInference = LlmInference;
</script>
```

### Get a HuggingFace token

1. Go to [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)
2. Create a new token with **Read** access
3. Copy the token

### Create LocalAIService

Create `lib/services/local_ai_service.dart`:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'ai_service.dart';

const String _modelUrl =
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task';
const String _hfToken = 'YOUR_HF_TOKEN_HERE'; // <-- paste your token here

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
```

**Key points:**
- `FlutterGemma.initialize()` sets up the plugin
- `installModel()` downloads the model (~500MB) with progress tracking
- `getActiveModel()` creates a model instance with GPU acceleration
- `createChat()` creates a chat session that maintains context
- `Message.text(text:, isUser: true)` — **critical**: `isUser: true` marks it as a user message

### Update chat screen

Add a mode picker to switch between Cloud and Local:

```dart
enum AIMode { cloud, local }

// In state:
AIMode _mode = AIMode.cloud;
late final LocalAIService _localService;

// Add SegmentedButton to UI:
SegmentedButton<AIMode>(
  segments: const [
    ButtonSegment(value: AIMode.cloud, label: Text('Cloud'), icon: Icon(Icons.cloud)),
    ButtonSegment(value: AIMode.local, label: Text('Local'), icon: Icon(Icons.phone_android)),
  ],
  selected: {_mode},
  onSelectionChanged: (s) => setState(() => _mode = s.first),
)
```

### Run and test

```bash
flutter run
```

The first run will download the model (~500MB). After download, switch to "Local" mode and ask a question. Notice the response comes without any network call.

### Reference

```bash
git checkout step-02-flutter-gemma
```

### Troubleshooting

- **"Model download fails"**: Check your HuggingFace token is correct
- **Slow first response**: The model needs to load into memory (~5-10s first time)
- **Out of memory**: Try on a device with more RAM, or reduce `maxTokens`
- **iOS build fails**: Make sure minimum iOS is 16.0 and entitlements are added

### Checkpoint

- [ ] Model downloads successfully
- [ ] Local inference works (you can switch to Local mode)
- [ ] Try airplane mode — local still works!

## Step 5: Hybrid Strategy
Duration: 15

### The idea

Instead of manually switching, let the app decide:

```
localFirst:  Try local → if fails → fall back to cloud
cloudFirst:  Try cloud → if fails → fall back to local
localOnly:   Local only (offline mode)
cloudOnly:   Cloud only
```

### Create HybridAIService

Create `lib/services/hybrid_ai_service.dart`:

```dart
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
```

**Key insight:** The `yield*` keyword forwards the entire stream from the inner service. If the primary service throws, the `catch` block switches to the fallback.

### Update chat screen

Replace the 2-mode picker with a 4-strategy picker:

```dart
SegmentedButton<AIStrategy>(
  segments: const [
    ButtonSegment(value: AIStrategy.cloudOnly, label: Text('Cloud'), icon: Icon(Icons.cloud)),
    ButtonSegment(value: AIStrategy.localOnly, label: Text('Local'), icon: Icon(Icons.phone_android)),
    ButtonSegment(value: AIStrategy.localFirst, label: Text('Local+Cloud'), icon: Icon(Icons.swap_horiz)),
    ButtonSegment(value: AIStrategy.cloudFirst, label: Text('Cloud+Local'), icon: Icon(Icons.swap_horiz)),
  ],
  selected: {_strategy},
  onSelectionChanged: (s) {
    setState(() {
      _strategy = s.first;
      _hybridService.strategy = s.first;
    });
  },
)
```

### Test the fallback

1. Set strategy to **Local+Cloud**
2. Turn on airplane mode
3. Send a message — it will use local model
4. Turn off airplane mode, set to **Cloud+Local**
5. Send a message — it will use cloud, with local as backup

### Reference

```bash
git checkout step-03-hybrid
```

### Checkpoint

- [ ] All 4 strategies work
- [ ] Fallback triggers when primary fails
- [ ] Offline mode works with localOnly/localFirst

## Step 6: Embeddings + VectorStore
Duration: 20

### What are embeddings?

Embeddings convert text into vectors (lists of numbers) that capture meaning:

```
"cat"    → [0.2, 0.8, 0.1, ...]
"kitten" → [0.3, 0.7, 0.2, ...]  ← similar to "cat"
"car"    → [0.9, 0.1, 0.7, ...]  ← very different
```

Similar meanings = similar vectors. This is the foundation of semantic search.

### What is a VectorStore?

A database optimized for storing and searching vectors. We'll use SQLite with BLOB storage — it works on Android, iOS, and Web.

### Install embedding model

Create `lib/services/rag_service.dart`:

```dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

const String _embeddingModelUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite';
const String _tokenizerUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';
const String _hfToken = 'YOUR_HF_TOKEN_HERE';

const List<String> _cityFiles = [
  'paris', 'tokyo', 'new_york', 'barcelona', 'istanbul',
  'sydney', 'rio', 'marrakech', 'prague', 'singapore',
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
        metadata: jsonEncode({
          'city': data['name'],
          'country': data['country'],
        }),
      );
    }
  }

  Future<int> getDocumentCount() async {
    final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
    return stats.documentCount;
  }
}
```

**Key points:**
- `installEmbedder()` downloads the embedding model and tokenizer
- `initializeVectorStore('rag.db')` creates a SQLite database
- `addDocument(id:, content:, metadata:)` **automatically generates the embedding** — no need to call the embedder manually
- Each tourist city becomes a searchable document

### Wire to chat screen

Initialize the RagService after local model is ready:

```dart
late final RagService _ragService;

// In _initServices():
_ragService = RagService();
await _ragService.initialize(
  onStatus: (status) => setState(() => _statusMessage = status),
);
final docCount = await _ragService.getDocumentCount();
```

Add a document count banner to the UI to confirm loading:

```dart
if (_documentCount > 0)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: Text('VectorStore: $_documentCount documents loaded'),
  ),
```

### Reference

```bash
git checkout step-04-embeddings
```

### Checkpoint

- [ ] Embedding model downloads successfully
- [ ] VectorStore initializes
- [ ] "10 documents loaded" shown in UI

## Step 7: RAG Query + Generation
Duration: 20

### What is RAG?

**Retrieval-Augmented Generation** — give the model relevant context before asking it to answer:

```
Query: "Where can I see cherry blossoms?"
  ↓
Embed query → Search VectorStore → Find Tokyo document
  ↓
Augmented prompt: "Based on: [Tokyo info]... Answer: Where can I see cherry blossoms?"
  ↓
Model generates grounded answer about Tokyo's sakura season
```

**Why RAG?** Without it, the model might hallucinate or give generic answers. With RAG, it answers based on your actual data.

### Add search to RagService

Add these methods to your `RagService` class:

```dart
Future<RagResult> searchAndBuildContext(String query) async {
  if (!_isInitialized) throw StateError('RagService not initialized');

  final results = await FlutterGemmaPlugin.instance.searchSimilar(
    query: query,
    topK: 3,
    threshold: 0.5,
  );

  if (results.isEmpty) {
    return RagResult(
      augmentedPrompt: query,
      retrievedContext: '',
      sources: [],
    );
  }

  final context = results.map((r) => r.content).join('\n\n');
  final sources = results.map((r) {
    final metadata = r.metadata != null
        ? jsonDecode(r.metadata!) as Map<String, dynamic>
        : <String, dynamic>{};
    return '${metadata['city'] ?? r.id} (${(r.similarity * 100).toStringAsFixed(0)}%)';
  }).toList();

  final augmentedPrompt =
      'Based on the following travel information:\n\n$context\n\n'
      'Answer the question: $query';

  return RagResult(
    augmentedPrompt: augmentedPrompt,
    retrievedContext: context,
    sources: sources,
  );
}
```

And the result class:

```dart
class RagResult {
  final String augmentedPrompt;
  final String retrievedContext;
  final List<String> sources;

  const RagResult({
    required this.augmentedPrompt,
    required this.retrievedContext,
    required this.sources,
  });

  bool get hasContext => retrievedContext.isNotEmpty;
}
```

**Key points:**
- `searchSimilar(query:)` **automatically embeds the query** — just pass the text
- `topK: 3` returns the 3 most similar documents
- `threshold: 0.5` filters out low-similarity results
- We build an augmented prompt with the retrieved context prepended

### Add RAG toggle to UI

Add a Switch in the AppBar:

```dart
appBar: AppBar(
  title: const Text('AI Chat'),
  actions: [
    Row(
      children: [
        const Text('RAG', style: TextStyle(fontSize: 12)),
        Switch(
          value: _ragEnabled,
          onChanged: _ragService.isInitialized
              ? (value) => setState(() => _ragEnabled = value)
              : null,
        ),
      ],
    ),
  ],
),
```

### Use RAG in message sending

In `_sendMessage`, add RAG context before generating:

```dart
String prompt = text;

if (_ragEnabled && _ragService.isInitialized) {
  final ragResult = await _ragService.searchAndBuildContext(text);
  if (ragResult.hasContext) {
    prompt = ragResult.augmentedPrompt;
    setState(() => _lastRagSources = ragResult.sources);
  }
}

// Use 'prompt' instead of 'text' for generation
await for (final chunk in _activeService.generateResponseStream(prompt)) {
  // ...
}
```

### Show sources

Display which documents were used:

```dart
if (_lastRagSources.isNotEmpty)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Text('Sources: ${_lastRagSources.join(', ')}'),
  ),
```

### Test RAG queries

Try these with RAG enabled:

| Query | Expected source |
|-------|----------------|
| "Where can I see cherry blossoms?" | Tokyo |
| "Best Mediterranean food?" | Barcelona, Istanbul |
| "Ancient architecture?" | Prague, Istanbul |
| "Beach vacation?" | Rio, Sydney, Barcelona |
| "Night markets and street food?" | Marrakech, Singapore |

Compare answers with RAG on vs. off — RAG answers will be grounded in your tourist data.

### Reference

```bash
git checkout step-05-rag
```

### Checkpoint

- [ ] RAG toggle works
- [ ] Sources banner shows matched cities
- [ ] Answers are grounded in tourist data when RAG is on
- [ ] Without RAG, answers are generic

## Step 8: Polish
Duration: 10

### Error handling

Make sure all service calls are wrapped in try/catch. The starter already handles this in `_sendMessage`, but verify edge cases:

- What happens if you send a message before initialization completes?
- What happens if the model download is interrupted?
- What happens if you switch strategies mid-generation?

### Loading states

The app shows:
- `LinearProgressIndicator` during model download
- `CircularProgressIndicator` during message generation
- Status messages during RAG initialization

### Test on multiple platforms

```bash
# Android
flutter run -d android

# iOS
flutter run -d ios

# Web
flutter run -d chrome
```

### Checkpoint

- [ ] Error messages are user-friendly
- [ ] Loading states are visible
- [ ] App works on at least 2 platforms

## Step 9: Conclusion
Duration: 5

### What we built

A Flutter app with 5 AI capabilities:

1. **Cloud Chat** — Gemini 2.5 Flash via Firebase AI Logic
2. **Local Inference** — Gemma 3 1B running on device
3. **Hybrid Strategy** — Automatic fallback between cloud and local
4. **Embeddings** — Semantic vectors with EmbeddingGemma
5. **RAG** — Context-augmented generation from local tourist data

All of this runs **on device** (except cloud calls), with **no data leaving the device** when using local mode.

### What's next?

- **Multimodal**: Add image input with Gemma 3 Nano (supports text + images)
- **Function Calling**: Let the model call your app's functions
- **Thinking Mode**: See the reasoning process with DeepSeek models
- **Fine-tuning**: Apply LoRA weights for domain-specific responses
- **Desktop**: macOS, Windows, Linux support via LiteRT-LM

### Resources

- **flutter\_gemma**: [pub.dev/packages/flutter\_gemma](https://pub.dev/packages/flutter_gemma)
- **Firebase AI Logic**: [firebase.google.com/docs/ai-logic](https://firebase.google.com/docs/ai-logic)
- **Workshop repo**: [github.com/DenisovAV/workshop-flutter-gemma-hybrid-ai](https://github.com/DenisovAV/workshop-flutter-gemma-hybrid-ai)
- **Gemma models**: [ai.google.dev/gemma](https://ai.google.dev/gemma)

### Thank you!

If you found this workshop useful, star the repo and share with your team.

Questions? Open an issue on GitHub or reach out on social media.
