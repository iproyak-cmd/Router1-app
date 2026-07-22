// Fabula companion client; OpenRouter credentials stay on the server.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    required String assistantName,
    required String assistantGender,
    required String birthday,
    required String sign,
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
          'assistant_name': assistantName,
          'assistant_gender': assistantGender,
          'birthday': birthday,
          'sign': sign,
          'messages': messages.takeLast(24).map((item) => item.toJson()).toList(),
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
    required this.assistantName,
    required this.assistantGender,
    required this.birthday,
    required this.sign,
    required this.onChooseAssistantName,
  });

  final FabulaCompanionApi api;
  final String installationId;
  final String name;
  final String assistantName;
  final String assistantGender;
  final String birthday;
  final String sign;
  final Future<void> Function() onChooseAssistantName;

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
    if (widget.assistantName.isEmpty) {
      await widget.onChooseAssistantName();
      return;
    }
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
        assistantName: widget.assistantName,
        assistantGender: widget.assistantGender,
        birthday: widget.birthday,
        sign: widget.sign,
        messages: _messages,
      );
      if (!mounted) return;
      setState(() => _messages.add(FabulaChatMessage(role: 'assistant', text: answer)));
      await _save();
    } on HttpException catch (error) {
      if (mounted) {
        final message = switch (error.message) {
          'chat_429' => 'Дневной лимит сообщений на сегодня исчерпан.',
          'chat_503' => 'Ассистент временно недоступен. Попробуйте позже.',
          'chat_401' => 'Версия Fabula устарела. Установите обновление.',
          'chat_404' => 'Сервер чата ещё не подключён к приложению.',
          _ => 'Ошибка сервера (${error.message}). Попробуйте ещё раз.',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Нет связи с сервером: ${error.runtimeType}.'),
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

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение скопировано')),
      );
    }
  }

  Future<void> _pasteMessage() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : _controller.text.length;
    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
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
                      Text(
                        widget.assistantName.isEmpty
                            ? 'Ассистент'
                            : widget.assistantName,
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
                  Text('Ассистент отвечает…', style: TextStyle(color: _muted)),
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
            child: Text(
              widget.assistantName.isEmpty
                  ? 'Сначала выберите имя своему личному ассистенту — спокойному и внимательному собеседнику.'
                  : 'Здесь не нужно подбирать правильные слова. Расскажите, что тревожит, радует или не даёт принять решение. ${widget.assistantName} выслушает и поможет посмотреть на ситуацию спокойнее.',
              style: TextStyle(fontSize: 17, height: 1.5, color: _ink),
            ),
          ),
          const SizedBox(height: 18),
          if (widget.assistantName.isEmpty)
            FilledButton(
              onPressed: widget.onChooseAssistantName,
              child: const Text('Выбрать имя ассистента'),
            ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.text,
                    style: TextStyle(
                      color: mine ? Colors.white : _ink,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Копировать',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _copyMessage(message.text),
                      icon: Icon(
                        Icons.copy_outlined,
                        size: 16,
                        color: mine ? Colors.white70 : _muted,
                      ),
                    ),
                  ),
                ],
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
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.enter): _send,
                  const SingleActivator(LogicalKeyboardKey.numpadEnter): _send,
                },
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
            ),
            IconButton(
              tooltip: 'Вставить из буфера',
              onPressed: _busy ? null : _pasteMessage,
              icon: const Icon(Icons.content_paste_outlined),
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
