import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class FileSaver {
  // ─────────────────────────────────────────────────────────────────────────
  /// Opens a native PDF preview using the printing package.
  /// This is the recommended way to display PDFs — no black screen.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> previewPdf(
    BuildContext context,
    String filename,
    Uint8List bytes,
  ) async {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: filename,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  /// Shows a bottom sheet with Preview / Save & Share options.
  /// Call this instead of directly calling previewPdf or saveAndSharePdf.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> showPdfOptions(
    BuildContext context, {
    required String filename,
    required Uint8List bytes,
  }) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF15171D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'PDF Report',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filename,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.visibility_outlined, color: Color(0xFFC68E65)),
              title: const Text('Preview PDF', style: TextStyle(color: Colors.white)),
              subtitle: const Text('View in full-screen PDF viewer',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                FileSaver.previewPdf(context, filename, bytes);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: Color(0xFF4CAF50)),
              title: const Text('Save & Share', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Save to Downloads and share',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                FileSaver.saveAndSharePdf(filename, bytes, context: context);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.white54),
              title: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  /// Saves bytes to a PDF file and triggers a system share dialog.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String?> saveAndSharePdf(
    String fileName,
    List<int> bytes, {
    BuildContext? context,
  }) async {
    try {
      Directory? directory;

      if (kIsWeb) return null;

      if (Platform.isAndroid) {
        // On Android 13+ (API 33+) READ_EXTERNAL_STORAGE is not needed for app-own dirs
        final status = await Permission.storage.request();
        directory = status.isGranted
            ? (await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory())
            : await getApplicationDocumentsDirectory();
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        directory =
            await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final savedFile = File('${directory.path}/$fileName');
      await savedFile.writeAsBytes(bytes);
      debugPrint('[FileSaver] Saved: ${savedFile.path}');

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(savedFile.path)],
          subject: 'Report: $fileName',
          text: 'Exported from TSR Site Manager Pro',
        ),
      );

      return savedFile.path;
    } catch (e) {
      debugPrint('[FileSaver] Error: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: const Color(0xFFE57373),
          ),
        );
      }
      return null;
    }
  }
}
