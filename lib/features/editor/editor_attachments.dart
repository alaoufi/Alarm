import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:record/record.dart';

import '../../core/l10n/app_strings.dart';
import '../../services/file_service.dart';

/// أدوات إرفاق الوسائط (صورة، PDF، فتح ملف).
class EditorAttachments {
  static final ImagePicker _picker = ImagePicker();

  /// يختار صورة من المعرض أو الكاميرا، وينسخها لمجلد المرفقات. يعيد المسار.
  static Future<String?> pickImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('المعرض'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('الكاميرا'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return null;

    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return null;
    return FileService.instance.importFile(picked.path, extension: '.jpg');
  }

  /// يختار ملف PDF وينسخه لمجلد المرفقات. يعيد المسار.
  static Future<String?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return FileService.instance.importFile(path, extension: '.pdf');
  }

  static Future<void> openFile(String path) async {
    await OpenFilex.open(path);
  }
}

/// مكوّن تسجيل/تشغيل ملاحظة صوتية.
class AudioNoteWidget extends StatefulWidget {
  final String? existingPath;
  final ValueChanged<String> onRecorded;

  const AudioNoteWidget({
    super.key,
    required this.existingPath,
    required this.onRecorded,
  });

  @override
  State<AudioNoteWidget> createState() => _AudioNoteWidgetState();
}

class _AudioNoteWidgetState extends State<AudioNoteWidget> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _recording = false;
  bool _playing = false;
  String? _path;

  @override
  void initState() {
    super.initState();
    _path = widget.existingPath;
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() {
        _recording = false;
        if (path != null) _path = path;
      });
      if (path != null) widget.onRecorded(path);
      return;
    }

    if (!await _recorder.hasPermission()) return;
    final dest = await FileService.instance.newAttachmentPath('m4a');
    await _recorder.start(const RecordConfig(), path: dest);
    setState(() {
      _recording = true;
      _path = dest;
    });
  }

  Future<void> _togglePlay() async {
    if (_path == null) return;
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(_path!));
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hasAudio = _path != null && File(_path!).existsSync();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (hasAudio && !_recording)
                IconButton.filled(
                  iconSize: 34,
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  onPressed: _togglePlay,
                ),
              const SizedBox(width: 16),
              IconButton.filled(
                iconSize: 34,
                style: IconButton.styleFrom(
                  backgroundColor: _recording ? scheme.error : scheme.primary,
                ),
                icon: Icon(_recording ? Icons.stop : Icons.mic),
                onPressed: _toggleRecord,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_recording
              ? 'جارٍ التسجيل...'
              : (hasAudio ? s.t('note_audio') : 'اضغط للتسجيل')),
        ],
      ),
    );
  }
}
