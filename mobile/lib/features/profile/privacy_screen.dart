import 'package:flutter/material.dart';

import '../../ui/components.dart';
import '../../ui/theme.dart';

/// Account operations are supplied by the app's active account scope.
/// This route never pops after deletion; the auth gate owns that transition.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({
    super.key,
    required this.isCloudAccount,
    this.onExportData,
    this.onDeleteAccount,
  });

  final bool isCloudAccount;
  final Future<void> Function(BuildContext context)? onExportData;
  final Future<void> Function()? onDeleteAccount;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _exporting = false;
  bool _confirming = false;
  bool _deleting = false;
  bool _deleted = false;
  String? _exportMessage;
  String? _deleteError;
  bool _exportFailed = false;

  bool get _busy => _exporting || _confirming || _deleting || _deleted;

  Future<void> _export() async {
    final export = widget.onExportData;
    if (_busy || export == null) return;
    setState(() {
      _exporting = true;
      _exportMessage = null;
      _exportFailed = false;
    });
    try {
      await export(context);
      if (mounted) setState(() => _exportMessage = 'Хуулбар бэлэн боллоо.');
    } catch (_) {
      if (mounted) {
        setState(() {
          _exportFailed = true;
          _exportMessage =
              'Мэдээллээ бэлтгэж чадсангүй. Холболтоо шалгаад дахин оролдоорой.';
        });
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _confirmDeletion() async {
    final delete = widget.onDeleteAccount;
    if (_busy || !widget.isCloudAccount || delete == null) return;
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) return;
    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    try {
      await delete();
      if (mounted) setState(() => _deleted = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _deleteError =
              'Устгал дууссан эсэхийг баталгаажуулж чадсангүй. '
              'Холболтоо шалгаад дахин оролдоорой.';
        });
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting && !_deleted,
    child: Scaffold(
      appBar: AppBar(title: const Text('Нууцлал ба мэдээлэл')),
      body: ListView(
        key: const Key('privacyList'),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        children: [
          SoftCard(
            color: AppColors.blush,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline_rounded, color: AppColors.pink),
                const SizedBox(height: 14),
                const Text(
                  'Таны мэдээлэл, таны сонголт',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.isCloudAccount
                      ? 'Өөрийн болзоо, дурсамж зэрэг хадгалсан мэдээлэл '
                            'энэ төхөөрөмж болон үүлэн хадгалалтад байна. '
                            'Аппыг устгах нь бүртгэлийг устгахгүй.'
                      : 'Та төхөөрөмж дээрээ ашиглаж байна. Зураг, тэмдэглэл '
                            'энэ төхөөрөмжид хадгалагдана. Аппыг устгахаас '
                            'өмнө мэдээллийнхээ хуулбарыг аваарай.',
                  style: const TextStyle(height: 1.6),
                ),
              ],
            ),
          ),
          if (widget.isCloudAccount) ...[
            const SectionLabel('Хэн харж болох вэ?'),
            const _PrivacyNote(
              icon: Icons.person_outline_rounded,
              title: 'Хувийн мэдээлэл',
              body: 'Хуваалцаагүй зүйлс зөвхөн таны бүртгэлд харагдана.',
            ),
            const SizedBox(height: 12),
            const _PrivacyNote(
              icon: Icons.favorite_border_rounded,
              title: 'Хоёуланд харагдах зүйлс',
              body:
                  'Хосоор холбогдсоны дараа хуваалцсан мэдээллээ хоёулаа харна. '
                  'Хосын мэдээллийг энэ утсанд байнга хадгалахгүй. '
                  'Аппыг арын горимд оруулах эсвэл холболтоо салгахад '
                  'түүний мэдээлэл харагдахаа болино.',
            ),
          ],
          const SectionLabel('Миний хуулбар'),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Мэдээллээ авч үлдэе',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  'Өөрийн бүртгэлүүд болон тэдгээрт холбосон зургуудыг '
                  'нэг ZIP файлаар авна. Тэмдэглэлүүд JSON хэлбэртэй байна.'
                  '${widget.isCloudAccount ? ' Хосын тань үүсгэсэн мэдээлэл хуулбарт орохгүй.' : ''}',
                  style: const TextStyle(color: AppColors.muted, height: 1.6),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Хуулбар хувийн мэдээлэл агуулна. Хадгалах эсвэл илгээх '
                  'газраа өөрөө сонгоорой.',
                  style: TextStyle(color: AppColors.muted, height: 1.6),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('exportAccountData'),
                    onPressed: _busy || widget.onExportData == null
                        ? null
                        : _export,
                    icon: _exporting
                        ? const _BusyIndicator()
                        : const Icon(Icons.download_outlined),
                    label: Text(
                      _exporting
                          ? 'Хуулбар бэлтгэж байна…'
                          : _exportFailed
                          ? 'Дахин бэлтгэх'
                          : 'Мэдээллийн хуулбар авах',
                    ),
                  ),
                ),
                if (_exportMessage != null) ...[
                  const SizedBox(height: 12),
                  _StatusMessage(
                    message: _exportMessage!,
                    isError: _exportFailed,
                  ),
                ],
              ],
            ),
          ),
          const SectionLabel('Төхөөрөмжийн зөвшөөрөл'),
          const _PrivacyNote(
            icon: Icons.notifications_none_rounded,
            title: 'Зураг ба сануулга',
            body:
                'Таны сонгосон болзооны сануулгыг энэ төхөөрөмж үзүүлнэ. '
                'Зураг сонгох болон мэдэгдлийн зөвшөөрлийг утасныхаа '
                'тохиргооноос өөрчилж болно.',
          ),
          if (widget.isCloudAccount && widget.onDeleteAccount != null) ...[
            const SectionLabel('Бүртгэлээ удирдах'),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Бүртгэлээ бүрмөсөн устгах',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Хамтдаа аппын бүртгэл, таны үүсгэсэн мэдээлэл, зураг, '
                    'сэтгэгдэл болон хариу үйлдлүүд устаж, хосын холболт сална. '
                    'Хосын тань өөрөө үүсгэсэн мэдээлэл хэвээр үлдэнэ.',
                    style: TextStyle(color: AppColors.muted, height: 1.6),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Өмнө нь татсан эсвэл бусдад илгээсэн хуулбаруудыг '
                    'апп буцааж устгах боломжгүй. Moch.mn дээрх Bolzoo, '
                    'Flowertoi худалдан авалтад энэ үйлдэл хамаарахгүй.',
                    style: TextStyle(color: AppColors.muted, height: 1.6),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('deleteAccountButton'),
                      onPressed: _busy ? null : _confirmDeletion,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: _deleting
                          ? const _BusyIndicator()
                          : const Icon(Icons.delete_outline_rounded),
                      label: Text(
                        _deleting
                            ? 'Устгаж байна…'
                            : _deleted
                            ? 'Бүртгэл устлаа'
                            : 'Бүртгэл устгах',
                      ),
                    ),
                  ),
                  if (_deleteError != null) ...[
                    const SizedBox(height: 12),
                    _StatusMessage(message: _deleteError!, isError: true),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.pink, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(body, style: const TextStyle(color: AppColors.muted, height: 1.6)),
      ],
    ),
  );
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: TextStyle(
        color: isError ? Theme.of(context).colorScheme.error : AppColors.muted,
        height: 1.5,
      ),
    ),
  );
}

class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 18,
    width: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  String _confirmation = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Бүртгэлээ устгах уу?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Энэ үйлдлийг буцаах боломжгүй. Хэрэгтэй мэдээллээ эхлээд '
          'хуулбарлаж аваарай. Устгахын тулд доор УСТГАХ гэж бичнэ үү.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 18),
        TextField(
          key: const Key('deleteAccountConfirmation'),
          onChanged: (value) => setState(() => _confirmation = value),
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'УСТГАХ'),
        ),
      ],
    ),
    actions: [
      TextButton(
        key: const Key('cancelAccountDeletion'),
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Болих'),
      ),
      FilledButton(
        key: const Key('confirmAccountDeletion'),
        onPressed: _confirmation.trim() == 'УСТГАХ'
            ? () => Navigator.of(context).pop(true)
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        child: const Text('Бүрмөсөн устгах'),
      ),
    ],
  );
}
