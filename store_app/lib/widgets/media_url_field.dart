import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/media_uploader.dart';

/// خانة رابط صورة أو فيديو، ويمها زر يختار من الموبايل ويرفع.
class MediaUrlField extends StatefulWidget {
  final TextEditingController controller;
  final MediaKind kind;
  final String label;
  final String? helperText;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onChanged;

  const MediaUrlField({
    super.key,
    required this.controller,
    required this.kind,
    required this.label,
    this.helperText,
    this.validator,
    this.onChanged,
  });

  @override
  State<MediaUrlField> createState() => _MediaUrlFieldState();
}

class _MediaUrlFieldState extends State<MediaUrlField> {
  bool _uploading = false;

  Future<void> _upload() async {
    final uploader = context.read<MediaUploader>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final url = await uploader.pickAndUpload(widget.kind);
      if (url != null) {
        widget.controller.text = url;
        widget.onChanged?.call();
      }
    } on UploadException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('ما كدرنا نفتح المعرض')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploader = context.read<MediaUploader>();
    final isImage = widget.kind == MediaKind.image;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (uploader.enabled) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(isImage ? Icons.add_photo_alternate_outlined : Icons.video_library_outlined),
            label: Text(
              _uploading
                  ? 'جاري الرفع...'
                  : (isImage ? 'اختار صورة من الموبايل' : 'اختار فيديو من الموبايل'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: widget.controller,
          enabled: !_uploading,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: uploader.enabled ? '${widget.label} (أو الصق رابط)' : widget.label,
            hintText: 'https://...',
            helperText: widget.helperText,
            helperMaxLines: 2,
          ),
          onChanged: (_) => widget.onChanged?.call(),
          validator: widget.validator,
        ),
      ],
    );
  }
}
