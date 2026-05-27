import 'dart:typed_data';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailService {
  // ── Configure your SMTP credentials here ──────────────────────────────────
  static const String _smtpHost = 'smtp.gmail.com';
  static const int _smtpPort = 587;
  static const String _senderEmail = 'wuongzize5@gmail.com'; // <-- change this
  static const String _senderPassword =
      'rfxbmzcoshvpylwo'; // <-- change this (use Gmail App Password)
  static const String _senderName = 'MyReceipt Photobooth';
  // ──────────────────────────────────────────────────────────────────────────

  /// Sends [imageBytes] (PNG) to [recipientEmail].
  static Future<void> sendPhoto({
    required String recipientEmail,
    required Uint8List imageBytes,
  }) async {
    final smtpServer = SmtpServer(
      _smtpHost,
      port: _smtpPort,
      username: _senderEmail,
      password: _senderPassword,
      ssl: false,
      allowInsecure: false,
    );

    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'photobooth_$ts.png';

    final message = Message()
      ..from = const Address(_senderEmail, _senderName)
      ..recipients.add(recipientEmail)
      ..subject = '📸 Your Photobooth Photo!'
      ..html = '''
        <div style="font-family:sans-serif;max-width:520px;margin:auto;">
          <h2 style="color:#E8C8A0;">Your Photobooth Photo 📸</h2>
          <p>Here is your photo from the photobooth. Find it attached below!</p>
          <p style="color:#888;">Thank you for using <strong>MyReceipt Photobooth</strong>.</p>
        </div>
      '''
      ..attachments.add(
        StreamAttachment(
          Stream.fromIterable([imageBytes]),
          'image/png',
          fileName: fileName,
        ),
      );

    final sendReport = await send(message, smtpServer);
    if (sendReport.toString().isEmpty) {
      throw Exception('Failed to send email.');
    }
  }
}
