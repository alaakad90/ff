import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/contact.dart';
import '../services/media_uploader.dart';
import '../services/note_attachments.dart';

/// أزرار "صورة" و"فويس" تحت ملاحظة المنتج. الملف ينرفع أول ما يختاره الزبون.
class NoteAttachmentsField extends StatefulWidget {
  final String imageUrl;
  final String voiceUrl;
  final void Function({required String imageUrl, required String voiceUrl}) onChanged;

  /// true بينما ينرفع ملف أو يتسجل فويس، حتى نوكف زر "أضف للسلة".
  final ValueChanged<bool> onBusy;

  const NoteAttachmentsField({
    super.key,
    required this.imageUrl,
    required this.voiceUrl,
    required this.onChanged,
    required this.onBusy,
  });

  @override
  State<NoteAttachmentsField> createState() => _NoteAttachmentsFieldState();
}

class _NoteAttachmentsFieldState extends State<NoteAttachmentsField> {
  late final _attachments = context.read<NoteAttachments>();
  bool _uploadingImage = false;
  bool _uploadingVoice = false;
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) _attachments.cancelRecording();
    super.dispose();
  }

  void _busy() => widget.onBusy(_uploadingImage || _uploadingVoice || _recording);

  void _error(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e is UploadException ? e.message : 'ما كدرنا نرفع الملف. حاول مرة ثانية.')));
  }

  Future<void> _pickImage() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('صوّر بالكاميرا'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختار من الصور'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (camera == null) return;
    setState(() => _uploadingImage = true);
    _busy();
    try {
      final url = await _attachments.pickImage(camera: camera);
      if (url != null) widget.onChanged(imageUrl: url, voiceUrl: widget.voiceUrl);
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
      _busy();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _attachments.startRecording()) {
        _error(UploadException('اسمح للتطبيق يستخدم المايكروفون حتى تسجل فويس'));
        return;
      }
    } catch (e) {
      _error(e);
      return;
    }
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
    _busy();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= SupabaseNoteAttachments.maxVoice) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    setState(() {
      _recording = false;
      _uploadingVoice = true;
    });
    try {
      final url = await _attachments.stopRecording();
      if (url != null) widget.onChanged(imageUrl: widget.imageUrl, voiceUrl: url);
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => _uploadingVoice = false);
      _busy();
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    await _attachments.cancelRecording();
    setState(() => _recording = false);
    _busy();
  }

  String get _time => '${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (!_attachments.enabled) return const SizedBox.shrink();
    final theme = Theme.of(context);

    if (_recording) {
      return Card(
        color: theme.colorScheme.secondaryContainer,
        child: ListTile(
          leading: Icon(Icons.mic, color: theme.colorScheme.secondary),
          title: Text('جاري التسجيل… $_time'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(tooltip: 'إلغاء', icon: const Icon(Icons.close), onPressed: _cancelRecording),
              IconButton.filled(tooltip: 'خلص', icon: const Icon(Icons.check), onPressed: _stopRecording),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: widget.imageUrl.isNotEmpty
                  ? _Attached(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          widget.imageUrl,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.image_outlined, size: 36),
                        ),
                      ),
                      label: 'الصورة',
                      onOpen: () => openLink(widget.imageUrl),
                      onRemove: () => widget.onChanged(imageUrl: '', voiceUrl: widget.voiceUrl),
                    )
                  : OutlinedButton.icon(
                      onPressed: _uploadingImage ? null : _pickImage,
                      icon: _uploadingImage ? const _Spinner() : const Icon(Icons.add_a_photo_outlined),
                      label: const Text('أرفق صورة'),
                    ),
            ),
            if (_attachments.supportsVoice) ...[
              const SizedBox(width: 8),
              Expanded(
                child: widget.voiceUrl.isNotEmpty
                    ? _Attached(
                        leading: const Icon(Icons.graphic_eq),
                        label: 'الفويس',
                        onOpen: () => openLink(widget.voiceUrl),
                        onRemove: () => widget.onChanged(imageUrl: widget.imageUrl, voiceUrl: ''),
                      )
                    : OutlinedButton.icon(
                        onPressed: _uploadingVoice ? null : _startRecording,
                        icon: _uploadingVoice ? const _Spinner() : const Icon(Icons.mic_none),
                        label: const Text('سجّل فويس'),
                      ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
}

class _Attached extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _Attached({required this.leading, required this.label, required this.onOpen, required this.onRemove});

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 8),
            Expanded(child: Text('✓ $label')),
            IconButton(tooltip: 'شيل $label', icon: const Icon(Icons.close, size: 18), onPressed: onRemove),
          ],
        ),
      ),
    ),
  );
}
