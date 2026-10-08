import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../account/cloudflare_account_export.dart';
import '../../cloudflare/cloudflare_auth_repository.dart';
import '../../cloudflare/cloudflare_transport.dart';

class CloudflareAccountScreen extends StatefulWidget {
  const CloudflareAccountScreen({super.key, required this.auth});
  final CloudflareAuthRepository auth;
  @override
  State<CloudflareAccountScreen> createState() =>
      _CloudflareAccountScreenState();
}

class _CloudflareAccountScreenState extends State<CloudflareAccountScreen> {
  bool _busy = false;
  String? _message;
  late final CloudflareCredential? _credential;
  late final StreamSubscription<dynamic> _sessions;

  @override
  void initState() {
    super.initState();
    _credential = widget.auth.credential;
    _sessions = widget.auth.sessions.listen((_) {
      if (mounted && !_current) {
        setState(() {
          _busy = false;
          _message = null;
        });
      }
    });
  }

  bool get _current {
    final credential = _credential;
    return mounted && credential != null && widget.auth.accepts(credential);
  }

  @override
  void dispose() {
    unawaited(_sessions.cancel());
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String path,
    Map<String, dynamic> input,
    CloudflareCredential credential,
  ) async {
    if (!widget.auth.accepts(credential))
      throw const FormatException('session_changed');
    final response = await widget.auth.transport.send(
      'POST',
      '/v1/account/$path',
      token: credential.token,
      body: input,
    );
    if (!widget.auth.accepts(credential))
      throw const FormatException('session_changed');
    if (response.status == 401) {
      await widget.auth.reject(credential);
      throw const FormatException('session_changed');
    }
    if (response.status != 200 || response.body['ok'] != true) {
      final code = response.body['code'];
      throw FormatException(code is String ? code : 'unavailable');
    }
    return response.body;
  }

  Future<void> _export() async {
    final credential = _credential;
    if (_busy || credential == null || !_current) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    Directory? directory;
    try {
      final pages = <Map<String, dynamic>>[];
      var totalBytes = 0;
      for (final section in [
        'profile',
        'calendar',
        'daily_answers',
        'billing_orders',
        'billing_subscriptions',
      ]) {
        String? cursor;
        final seen = <String>{};
        do {
          if (!_current || pages.length >= 200)
            throw const FormatException('incomplete_export');
          final response = await _call('export', {
            if (section != 'profile') 'section': section,
            if (cursor != null) 'cursor': cursor,
          }, credential);
          final page = response['export'];
          if (page is! Map<String, dynamic> ||
              page['schema_version'] != 1 ||
              page['section'] != section ||
              !page.containsKey('next_cursor')) {
            throw const FormatException('invalid_export');
          }
          if (section == 'profile') {
            cloudflareExportPair(page, credential);
            final account = page['account'];
            if (account is! Map || account['id'] != credential.scope.userId) {
              throw const FormatException('invalid_export');
            }
          } else if (page['data'] is! List) {
            throw const FormatException('invalid_export');
          }
          totalBytes += utf8.encode(jsonEncode(page)).length;
          if (totalBytes > 32 * 1024 * 1024)
            throw const FormatException('export_limit');
          pages.add(page);
          final next = page['next_cursor'];
          if (next != null &&
              (next is! String ||
                  next.isEmpty ||
                  next.length > 1200 ||
                  section == 'profile')) {
            throw const FormatException('invalid_cursor');
          }
          cursor = next as String?;
          if (cursor != null && !seen.add(cursor))
            throw const FormatException('cursor_loop');
        } while (cursor != null);
      }
      if (!_current) return;
      final temporary = await getTemporaryDirectory();
      if (!_current) return;
      directory = await buildCloudflareAccountExport(
        auth: widget.auth,
        credential: credential,
        pages: pages,
        temporaryDirectory: temporary,
        isCurrent: () => _current,
      );
      final file = File('${directory.path}/hamtdaa-data.zip');
      if (!mounted || !_current) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/zip')],
          subject: 'Хамтдаа — миний мэдээлэл',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (_current)
        setState(
          () => _message =
              'Мэдээлэл бэлэн. Хуваалцах цэснээс файл болгон хадгалаарай.',
        );
    } catch (_) {
      if (_current)
        setState(
          () => _message =
              'Мэдээлэл татаж чадсангүй. Холболтоо шалгаад дахин оролдоорой.',
        );
    } finally {
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final credential = _credential;
    if (_busy || credential == null || !_current) return;
    final confirmation = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Бүртгэлээ устгах уу?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Таны нэр, имэйл, бичсэн болзоо, хариунууд устаж, хосын холбоос сална. Бүх утаснаас гаргана. Буцаах боломжгүй.\n\nApple, Google захиалгаа дэлгүүрээс тусад нь цуцлаарай. Хувийн мэдээлэлгүй төлбөрийн лавлагаа үлдэнэ.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmation,
                decoration: const InputDecoration(
                  labelText: 'УСТГАХ гэж бичнэ үү',
                ),
                autocorrect: false,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Болих'),
          ),
          TextButton(
            onPressed: () {
              if (confirmation.text.trim() == 'УСТГАХ')
                Navigator.pop(dialogContext, true);
            },
            child: const Text('Устгах'),
          ),
        ],
      ),
    );
    // The dialog's route transition still uses its text controller briefly.
    Future<void>.delayed(const Duration(seconds: 1), confirmation.dispose);
    if (accepted != true || !mounted || !widget.auth.accepts(credential))
      return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await _call('delete', {
        'confirmation': 'УСТГАХ',
      }, credential);
      if (response['deleted'] != true)
        throw const FormatException('unconfirmed_deletion');
      // Deletion already revokes server sessions. Clear only this exact login.
      await widget.auth.reject(credential);
    } on FormatException catch (error) {
      if (_current) {
        if (error.message == 'reauthentication_required') {
          setState(
            () => _message =
                'Аюулгүй байдлын үүднээс гараад, имэйл кодоор дахин нэвтэрсний дараах 10 минутын дотор устгана уу.',
          );
        } else {
          setState(
            () => _message =
                'Устгалтыг баталгаажуулж чадсангүй. Дахин оролдоорой.',
          );
        }
      }
    } catch (_) {
      if (_current)
        setState(
          () => _message =
              'Серверийн хариу ирсэнгүй. Дахин нэвтэрч бүртгэлийн төлөвөө шалгаарай.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _legal(String path) async {
    final transport = widget.auth.transport;
    if (transport is! HttpCloudflareTransport) return;
    if (!await launchUrl(
          transport.baseUri.resolve(path),
          mode: LaunchMode.externalApplication,
        ) &&
        mounted) {
      setState(() => _message = 'Хуудсыг нээж чадсангүй.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Миний бүртгэл')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Таны мэдээлэл, таны сонголт',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        const Text(
          'Хуанли болон асуултын хариугаа одоо холбогдсон хостойгоо хуваалцана. Өдрийн хариу хоёулаа хариулсны дараа нээгдэнэ.',
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _busy || !_current ? null : _export,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Мэдээллээ татах'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Хуулбарт таны мэдээлэл, одоогийн хостойгоо үүсгэсэн өөрийн зурагт дурсамж, хүсэл болон дарсан зүрхүүд орно.',
        ),
        const SizedBox(height: 12),
        ListTile(
          title: const Text('Нууцлал'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _legal('/privacy'),
        ),
        ListTile(
          title: const Text('Үйлчилгээний нөхцөл'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _legal('/terms'),
        ),
        const Divider(),
        const ListTile(
          title: Text('Тусламж'),
          subtitle: Text('gbuyandelger277@gmail.com'),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _busy || !_current ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Бүртгэл устгах'),
        ),
        TextButton(
          onPressed: _busy || !_current
              ? null
              : () async {
                  try {
                    await widget.auth.signOut();
                  } catch (_) {}
                },
          child: const Text('Гарах'),
        ),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(_message!, key: const Key('accountMessage')),
          ),
      ],
    ),
  );
}
