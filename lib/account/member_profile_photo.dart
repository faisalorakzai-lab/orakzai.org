import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../app/app_language.dart';
import '../app/app_theme.dart';
import '../auth/account_api.dart';
import '../auth/auth_controller.dart';
import 'account_strings.dart';

class MemberProfilePhoto extends StatefulWidget {
  const MemberProfilePhoto({
    required this.auth,
    required this.language,
    required this.userId,
    required this.fullName,
    super.key,
  });
  final AuthController auth;
  final AppLanguage language;
  final String userId;
  final String fullName;

  @override
  State<MemberProfilePhoto> createState() => _MemberProfilePhotoState();
}

class _MemberProfilePhotoState extends State<MemberProfilePhoto> {
  late Future<Uint8List?>? _photo;
  bool _busy = false;
  String t(String key) => AccountStrings.text(widget.language, key);
  @override
  void initState() {
    super.initState();
    _photo = _hasPhoto ? AccountApi(widget.auth.api).avatar() : null;
  }

  bool get _hasPhoto => widget.auth.user?.profile['hasProfilePhoto'] == true;
  bool get _canUpload => widget.auth.capabilities['avatarAvailable'] == true;
  @override
  void didUpdateWidget(covariant MemberProfilePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.auth.user?.profile['hasProfilePhoto'] != _hasPhoto) {
      _photo = _hasPhoto ? AccountApi(widget.auth.api).avatar() : null;
    }
  }

  Future<void> _choosePhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final chosen = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (chosen == null || !context.mounted) return;
      final raw = await File(chosen.path).readAsBytes();
      if (!context.mounted) return;
      final bytes = await showDialog<Uint8List>(
        // The picker and file read above have both rechecked this context.
        // ignore: use_build_context_synchronously
        context: context,
        barrierDismissible: false,
        builder: (_) => _CropDialog(bytes: raw, language: widget.language),
      );
      if (bytes == null) return;
      if (!context.mounted) return;
      await AccountApi(widget.auth.api).uploadAvatar(bytes);
      await widget.auth.refreshUser();
      if (!context.mounted) return;
      setState(() => _photo = Future.value(bytes));
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text(t('photoUploaded'))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('err_file'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: _canUpload,
      label: '${t('photo')}: ${widget.fullName}. ${t('changePhoto')}',
      child: Tooltip(
        message: t('changePhoto'),
        child: InkWell(
          onTap: _busy || !_canUpload ? null : _choosePhoto,
          customBorder: const CircleBorder(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.ivory,
                child: FutureBuilder<Uint8List?>(
                  future: _photo,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    if (data != null) {
                      return ClipOval(
                        child: Image.memory(
                          data,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallback(),
                        ),
                      );
                    }
                    return _fallback();
                  },
                ),
              ),
              if (_canUpload)
                PositionedDirectional(
                  end: -2,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: AppColors.gold,
                    child: _busy
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.add_a_photo_outlined,
                            size: 14,
                            color: AppColors.navyDeep,
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback() => ClipOval(
    child: Image.asset(
      'assets/images/orakzai_emblem.png',
      width: 64,
      height: 64,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.person_outline_rounded,
        color: AppColors.navyDeep,
        size: 30,
      ),
    ),
  );
}

class _CropDialog extends StatefulWidget {
  const _CropDialog({required this.bytes, required this.language});
  final Uint8List bytes;
  final AppLanguage language;
  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  static const _size = 280.0;
  final _crop = GlobalKey();
  final _transform = TransformationController();
  late final Future<ui.Image> _decoded = ui
      .instantiateImageCodec(
        widget.bytes,
        targetWidth: 2048,
        targetHeight: 2048,
        allowUpscaling: false,
      )
      .then((codec) async {
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      });
  bool _saving = false;
  String t(String key) => AccountStrings.text(widget.language, key);
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('cropTitle')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t('cropHint')),
        const SizedBox(height: 15),
        FutureBuilder<ui.Image>(
          future: _decoded,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox.square(
                dimension: _size,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final image = snapshot.data!;
            final scale = math.max(_size / image.width, _size / image.height);
            final width = image.width * scale, height = image.height * scale;
            return RepaintBoundary(
              key: _crop,
              child: ClipOval(
                child: SizedBox.square(
                  dimension: _size,
                  child: ColoredBox(
                    color: AppColors.navyDeep,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      constrained: false,
                      panEnabled: true,
                      scaleEnabled: true,
                      minScale: 0.55,
                      maxScale: 5,
                      boundaryMargin: const EdgeInsets.all(_size),
                      child: Image.memory(
                        widget.bytes,
                        width: width,
                        height: height,
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text(t('cancel')),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(t('usePhoto')),
      ),
    ],
  );
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _crop.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('The crop is not ready.');
      final image = await boundary.toImage(pixelRatio: 512 / _size);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('The image could not be encoded.');
        if (mounted) {
          Navigator.pop(context, data.buffer.asUint8List());
        }
      } finally {
        image.dispose();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('err_file'))));
      }
    }
  }
}
