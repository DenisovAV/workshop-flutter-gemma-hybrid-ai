import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../services/ai_service.dart';
import '../services/firebase_ai_service.dart';
import '../services/local_ai_service.dart';
import '../widgets/message_bubble.dart';

enum AIMode { cloud, local }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];
  bool _isGenerating = false;
  bool _isInitializing = true;
  double _downloadProgress = 0;
  String _statusMessage = 'Initializing...';

  late final FirebaseAIService _cloudService;
  late final LocalAIService _localService;

  AIMode _mode = AIMode.cloud;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    _cloudService = FirebaseAIService();
    _localService = LocalAIService();

    try {
      setState(() => _statusMessage = 'Connecting to cloud AI...');
      await _cloudService.initialize();

      setState(() => _statusMessage = 'Downloading local model...');
      await _localService.initialize(
        onProgress: (progress) {
          setState(() => _downloadProgress = progress);
        },
      );

      setState(() {
        _isInitializing = false;
        _statusMessage = 'Ready';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _statusMessage = 'Ready (some services may be unavailable)';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _cloudService.dispose();
    _localService.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  AIService get _activeService =>
      _mode == AIMode.cloud ? _cloudService : _localService;

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating) return;

    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messages.add(ChatMessage(text: '', isUser: false));
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      final buffer = StringBuffer();
      await for (final chunk
          in _activeService.generateResponseStream(text)) {
        buffer.write(chunk);
        setState(() {
          _messages.last = ChatMessage(
            text: buffer.toString(),
            isUser: false,
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages.last = ChatMessage(
          text: 'Error: $e',
          isUser: false,
        );
      });
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Mode picker
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SegmentedButton<AIMode>(
              segments: const [
                ButtonSegment(
                  value: AIMode.cloud,
                  label: Text('Cloud'),
                  icon: Icon(Icons.cloud),
                ),
                ButtonSegment(
                  value: AIMode.local,
                  label: Text('Local'),
                  icon: Icon(Icons.phone_android),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selected) {
                setState(() => _mode = selected.first);
              },
            ),
          ),

          // Initialization progress
          if (_isInitializing)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_statusMessage),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                      value:
                          _downloadProgress > 0 ? _downloadProgress : null),
                ],
              ),
            ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Send a message to start chatting',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: _messages[index]);
                    },
                  ),
          ),

          // Generating indicator
          if (_isGenerating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Generating...',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),

          // Input field
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isGenerating ? null : _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
