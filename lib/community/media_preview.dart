import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../app/app_theme.dart';
import 'community_controller.dart';

class MediaAttachmentTile extends StatelessWidget {
  const MediaAttachmentTile({
    required this.controller,
    required this.media,
    super.key,
  });

  final CommunityController controller;
  final Map<String, dynamic> media;

  @override
  Widget build(BuildContext context) {
    final contentType = media['contentType'] as String? ?? '';
    final icon = contentType.startsWith('image/')
        ? Icons.image_outlined
        : contentType.startsWith('video/')
            ? Icons.videocam_outlined
            : contentType.startsWith('audio/')
                ? Icons.mic_none_rounded
                : Icons.description_outlined;
    final name = media['name'] as String? ?? 'Attached file';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => MediaPreviewDialog(controller: controller, media: media),
      ),
      child: Container(
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 230),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.green),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    _fileSize(media['byteSize']),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.visibility_outlined, size: 17),
          ],
        ),
      ),
    );
  }

  String _fileSize(Object? value) {
    final bytes = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class MediaPreviewDialog extends StatefulWidget {
  const MediaPreviewDialog({
    required this.controller,
    required this.media,
    super.key,
  });

  final CommunityController controller;
  final Map<String, dynamic> media;

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  Uint8List? _bytes;
  String? _localPath;
  String? _error;
  double? _progress;
  bool _loading = true;
  VideoPlayerController? _video;
  final AudioPlayer _audio = AudioPlayer();

  String get _contentType => widget.media['contentType'] as String? ?? '';
  bool get _isImage => _contentType.startsWith('image/');
  bool get _isVideo => _contentType.startsWith('video/');
  bool get _isAudio => _contentType.startsWith('audio/');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final id = widget.media['id'] as String?;
      if (id == null) throw StateError('File identifier is missing.');
      final bytes = await widget.controller.downloadMedia(
        id,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = (received / total).clamp(0, 1));
        },
      );
      if (_isImage) {
        if (mounted) {
          setState(() {
            _bytes = bytes;
            _loading = false;
          });
        }
        return;
      }
      final directory = await getTemporaryDirectory();
      final extension = _extension(widget.media['name'] as String? ?? '');
      final file = File('${directory.path}/orakzai-$id$extension');
      await file.writeAsBytes(bytes, flush: true);
      if (_isVideo) {
        final video = VideoPlayerController.file(file);
        await video.initialize();
        if (!mounted) {
          await video.dispose();
          return;
        }
        setState(() {
          _localPath = file.path;
          _video = video;
          _loading = false;
        });
      } else if (_isAudio) {
        await _audio.setFilePath(file.path);
        if (mounted) {
          setState(() {
            _localPath = file.path;
            _loading = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _localPath = file.path;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.media['name'] as String? ?? 'Community attachment';
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(child: _content(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_loading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            _progress == null
                ? 'Securely loading file…'
                : 'Downloading ${(_progress! * 100).round()}%',
          ),
        ],
      );
    }
    if (_error != null) {
      return Center(
        child: Text('File is unavailable: $_error'),
      );
    }
    if (_isImage && _bytes != null) {
      return InteractiveViewer(
        child: Image.memory(
          _bytes!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image_outlined, size: 52),
        ),
      );
    }
    if (_isVideo && _video != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: _video!.value.aspectRatio,
            child: VideoPlayer(_video!),
          ),
          IconButton.filled(
            onPressed: () => setState(() {
              _video!.value.isPlaying ? _video!.pause() : _video!.play();
            }),
            icon: Icon(_video!.value.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ],
      );
    }
    if (_isAudio) {
      return StreamBuilder<PlayerState>(
        stream: _audio.playerStateStream,
        builder: (context, snapshot) {
          final playing = snapshot.data?.playing ?? false;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.graphic_eq_rounded, size: 48, color: AppColors.green),
              const SizedBox(height: 8),
              Text(widget.media['name'] as String? ?? 'Voice message'),
              IconButton.filled(
                onPressed: () => playing ? _audio.pause() : _audio.play(),
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
            ],
          );
        },
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.description_outlined, size: 48, color: AppColors.green),
        const SizedBox(height: 10),
        const Text('Document preview is provided by your device.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _localPath == null
              ? null
              : () async {
                  await OpenFilex.open(_localPath!);
                },
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Open document'),
        ),
      ],
    );
  }

  String _extension(String name) {
    final match = RegExp(r'\.[A-Za-z0-9]{1,8}$').firstMatch(name);
    return match?.group(0)?.toLowerCase() ?? '.bin';
  }
}
