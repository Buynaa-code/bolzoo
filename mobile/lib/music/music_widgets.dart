import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'music_repository.dart';
import 'music_track.dart';

/// A user-initiated YouTube page keeps the official video, controls and attribution.
/// No hidden audio player, downloaded stream, or autoplay in the background.
Future<void> openInvitationMusic(BuildContext context, MusicTrack track) async {
  try {
    if (await launchUrl(track.watchUrl, mode: LaunchMode.inAppBrowserView)) {
      return;
    }
  } catch (_) {
    /* Try the installed YouTube app / browser below. */
  }
  try {
    if (await launchUrl(track.watchUrl, mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_) {
    /* Render a useful error without losing the invitation. */
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('YouTube нээгдсэнгүй. Дахин оролдоорой.')),
    );
  }
}

class MusicTrackCard extends StatelessWidget {
  const MusicTrackCard({
    super.key,
    required this.track,
    this.onRemove,
    this.onSelect,
    this.selected = false,
    this.onPlay,
  });
  final MusicTrack track;
  final VoidCallback? onRemove, onSelect, onPlay;
  final bool selected;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 5),
    color: selected ? AppColors.blush : Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          InkWell(
            onTap: onSelect,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    track.thumbnailUrl.toString(),
                    width: 96,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 96,
                      height: 64,
                      color: AppColors.blush,
                      child: const Icon(
                        Icons.music_note,
                        color: AppColors.pink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.channelTitle.isEmpty
                            ? 'YouTube'
                            : track.channelTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Дууг хасах',
                    key: const Key('removeInvitationMusic'),
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 20),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: const Key('playInvitationMusic'),
                  onPressed:
                      onPlay ?? () => openInvitationMusic(context, track),
                  icon: const Icon(Icons.play_circle_outline, size: 21),
                  label: const Text('YouTube дээр сонсох'),
                ),
              ),
              if (onSelect != null)
                TextButton(
                  key: ValueKey('selectMusic:${track.videoId}'),
                  onPressed: onSelect,
                  child: const Text('Сонгох'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class MusicPicker extends StatefulWidget {
  const MusicPicker({super.key, required this.repository});
  final MusicRepository repository;
  @override
  State<MusicPicker> createState() => _MusicPickerState();
}

class _MusicPickerState extends State<MusicPicker> {
  final _query = TextEditingController();
  List<MusicTrack> _tracks = const [];
  String? _error;
  bool _loading = false, _searched = false;
  int _epoch = 0;
  @override
  void dispose() {
    _epoch++;
    _query.dispose();
    super.dispose();
  }

  void _changed(String _) {
    // Editing invalidates in-flight searches, so an old title cannot replace results.
    _epoch++;
    setState(() {
      _loading = false;
      _tracks = const [];
      _error = null;
      _searched = false;
    });
  }

  Future<void> _search() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final query = _query.text.trim();
    final link = MusicTrack.fromYouTubeLink(query);
    if (link != null) {
      _select(link);
      return;
    }
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
      _tracks = const [];
      _searched = true;
    });
    try {
      final tracks = await widget.repository.search(query);
      if (!mounted || epoch != _epoch || !widget.repository.isCurrent) return;
      setState(() => _tracks = tracks);
    } on MusicFailure catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error.message);
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = const MusicFailure('network_error').message);
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  void _select(MusicTrack track) {
    if (!widget.repository.isCurrent) return;
    Navigator.of(context).pop(track);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Бидний болзооны дуу')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Нэг дуу, нэг нандин урилга',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Дуу эсвэл дуучны нэрээр хайгаад, та хоёрт утгатай дуугаа сонгоорой.',
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                TextField(
                  key: const Key('musicQuery'),
                  controller: _query,
                  onChanged: _changed,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Дуу, дуучин эсвэл YouTube холбоос',
                    prefixIcon: const Icon(Icons.music_note_outlined),
                    suffixIcon: IconButton(
                      key: const Key('searchMusic'),
                      tooltip: 'Дуу хайх',
                      onPressed: _loading ? null : _search,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'YouTube · Дууг дарж сонсоно.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                if (_error != null)
                  SoftCard(
                    color: AppColors.blush,
                    child: Column(
                      children: [
                        Text(_error!, key: const Key('musicSearchError')),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _search,
                          child: const Text('Дахин хайх'),
                        ),
                      ],
                    ),
                  ),
                if (!_loading && _error == null && _tracks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 45),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.library_music_outlined,
                          color: AppColors.pink,
                          size: 54,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _searched
                              ? 'Дуу олдсонгүй. Өөр нэрээр хайгаарай.'
                              : 'Та хоёрын дуртай дуу юу вэ?',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                for (final track in _tracks)
                  MusicTrackCard(track: track, onSelect: () => _select(track)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
