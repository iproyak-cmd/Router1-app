// Fabula companion client; OpenRouter credentials stay on the server.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _burgundy = Color(0xFF7A3045);
const _cream = Color(0xFFF6F2ED);
const _ink = Color(0xFF171717);
const _muted = Color(0xFF6F6B67);

class FabulaChatMessage {
  const FabulaChatMessage({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, String> toJson() => {'role': role, 'content': text};

  factory FabulaChatMessage.fromJson(Map<String, dynamic> value) =>
      FabulaChatMessage(
        role: value['role']?.toString() == 'assistant' ? 'assistant' : 'user',
        text: value['content']?.toString().trim() ?? '',
      );
}

class FabulaCompanionApi {
  const FabulaCompanionApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Future<String> reply({
    required String installationId,
    required String name,
    required List<FabulaChatMessage> messages,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl/fabula/chat'));
      request.headers.contentType = ContentType.json;
      if (token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.write(
        jsonEncode({
          'installation_id': installationId,
          'name': name,
          'messages': messages.takeLast(12).map((item) => item.toJson()).toList(),
        }),
      );
      final response = await request.close().timeout(const Duration(seconds: 45));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw HttpException('chat_${response.statusCode}');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final answer = decoded['reply']?.toString().trim() ?? '';
      if (answer.isEmpty) throw const FormatException('empty_reply');
      return answer;
    } finally {
      client.close(force: true);
    }
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList(growable: false);
    return values.skip(values.length > count ? values.length - count : 0);
  }
}

class FabulaCompanionPage extends StatefulWidget {
  const FabulaCompanionPage({
    super.key,
    required this.api,
    required this.installationId,
    required this.name,
  });

  final FabulaCompanionApi api;
  final String installationId;
  final String name;

  @override
  State<FabulaCompanionPage> createState() => _FabulaCompanionPageState();
}

class _FabulaCompanionPageState extends State<FabulaCompanionPage> {
  static const _storageKey = 'fabula_companion_messages_v1';
  static const _storage = FlutterSecureStorage();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<FabulaChatMessage> _messages = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored = decoded
          .whereType<Map>()
          .map((item) => FabulaChatMessage.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.text.isNotEmpty)
          .takeLast(40)
          .toList();
      if (mounted) setState(() => _messages.addAll(restored));
    } catch (_) {
      await _storage.delete(key: _storageKey);
    }
  }

  Future<void> _save() async {
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(
        _messages.takeLast(40).map((item) => item.toJson()).toList(),
      ),
    );
  }

  Future<void> _send([String? suggested]) async {
    if (_busy) return;
    final text = (suggested ?? _controller.text).trim();
    if (text.isEmpty) return;
    if (text.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение должно быть короче 2000 знаков.')),
      );
      return;
    }
    _controller.clear();
    setState(() {
      _messages.add(FabulaChatMessage(role: 'user', text: text));
      _busy = true;
    });
    await _save();
    _scrollToEnd();
    try {
      final answer = await widget.api.reply(
        installationId: widget.installationId,
        name: widget.name,
        messages: _messages,
      );
      if (!mounted) return;
      setState(() => _messages.add(FabulaChatMessage(role: 'assistant', text: answer)));
      await _save();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fabula пока не смогла ответить. Попробуйте ещё раз.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  Future<void> _clear() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить разговор?'),
        content: const Text('История будет удалена только с этого устройства.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (accepted != true) return;
    _messages.clear();
    await _storage.delete(key: _storageKey);
    if (mounted) setState(() {});
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fabula рядом',
                        style: TextStyle(fontFamily: 'serif', fontSize: 30, color: _ink),
                      ),
                      Text(
                        widget.name.isEmpty ? 'Можно просто рассказать, что происходит' : '${widget.name}, я слушаю',
                        style: const TextStyle(color: _muted),
                      ),
                    ],
                  ),
                ),
                if (_messages.isNotEmpty)
                  IconButton(
                    tooltip: 'Удалить историю',
                    onPressed: _busy ? null : _clear,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty ? _welcome() : _conversation(),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Fabula отвечает…', style: TextStyle(color: _muted)),
                ],
              ),
            ),
          SafeArea(top: false, child: _composer()),
        ],
      );

  Widget _welcome() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFE5DED7)),
            ),
            child: const Text(
              'Здесь не нужно подбирать правильные слова. Расскажите, что тревожит, радует или не даёт принять решение. Fabula выслушает и поможет посмотреть на ситуацию спокойнее.',
              style: TextStyle(fontSize: 17, height: 1.5, color: _ink),
            ),
          ),
          const SizedBox(height: 18),
          for (final prompt in const [
            'Мне нужно выговориться',
            'Помоги разобраться в чувствах',
            'Я стою перед сложным выбором',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: () => _send(prompt),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                ),
                child: Text(prompt),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Fabula не заменяет врача или психолога и не принимает решения за вас.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        ],
      );

  Widget _conversation() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          final mine = message.role == 'user';
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 330),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: mine ? _burgundy : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(mine ? 20 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 20),
                ),
                border: mine ? null : Border.all(color: const Color(0xFFE5DED7)),
              ),
              child: Text(
                message.text,
                style: TextStyle(color: mine ? Colors.white : _ink, height: 1.4),
              ),
            ),
          );
        },
      );

  Widget _composer() => Container(
        color: _cream,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Напишите, что происходит…',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _busy ? null : _send,
              style: IconButton.styleFrom(backgroundColor: _burgundy),
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      );
}
