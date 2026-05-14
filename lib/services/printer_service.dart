import 'dart:convert';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Sends the composite photo strip to an XPrinter via the browser print dialog.
///
/// The page is formatted for 80 mm thermal paper (the standard XPrinter roll).
/// A popup window is opened with the image embedded as a base-64 data URL;
/// a short-lived <script> triggers [window.print()] once the image has loaded,
/// then closes the popup automatically.
class PrinterService {
  // ── Public API ────────────────────────────────────────────────────────────

  /// Prints [imageBytes] (PNG) to the XPrinter.
  ///
  /// [paperWidthMm] defaults to 80 mm. Change to 58 for 58 mm rolls.
  ///
  /// Throws [PrinterException] if the browser blocks the popup or if the
  /// image cannot be embedded.
  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthMm = 80,
  }) async {
    final base64Str = base64Encode(imageBytes);
    final dataUrl = 'data:image/png;base64,$base64Str';

    final htmlContent = _buildPrintPage(dataUrl, paperWidthMm);

    // Open a minimal popup — many browsers need a user-gesture origin for
    // window.open(); the PRINT button tap satisfies that requirement.
    final popup = web.window.open(
      '',
      '_blank',
      'popup,width=500,height=720,scrollbars=no,toolbar=no,'
          'menubar=no,location=no,status=no',
    );

    if (popup == null) {
      throw PrinterException(
        'Print popup was blocked.\n'
        'Please allow pop-ups for this site in your browser settings, '
        'then tap PRINT again.',
      );
    }

    popup.document.write(htmlContent);
    popup.document.close();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _buildPrintPage(String dataUrl, int widthMm) {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MyReceipt — Printing…</title>
  <style>
    /* ── Print page geometry ── */
    @page {
      size: ${widthMm}mm auto;  /* thermal roll: width fixed, height auto  */
      margin: 0;
    }

    *, *::before, *::after {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    html, body {
      background: #ffffff;
      width: ${widthMm}mm;
    }

    /* ── Receipt image ── */
    #receipt-img {
      width:   100%;
      height:  auto;
      display: block;
    }

    /* ── Status overlay (hidden when printing) ── */
    #overlay {
      position:   fixed;
      inset:      0;
      display:    flex;
      flex-direction: column;
      align-items:    center;
      justify-content: center;
      gap:        12px;
      background: #f8f8f8;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      font-size:  13px;
      color:      #555;
      z-index:    9999;
    }

    .spinner {
      width:  32px;
      height: 32px;
      border: 3px solid #ddd;
      border-top-color: #333;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
    }

    @keyframes spin { to { transform: rotate(360deg); } }

    /* Hide overlay and show image only when printing */
    @media print {
      #overlay { display: none !important; }
      #receipt-img { width: 100%; page-break-after: avoid; }
    }
  </style>
</head>
<body>
  <!-- Status overlay visible in the popup window -->
  <div id="overlay">
    <div class="spinner"></div>
    <span id="status-text">Preparing XPrinter job…</span>
  </div>

  <!-- The actual receipt image (hidden behind overlay until printing) -->
  <img id="receipt-img" src="$dataUrl" alt="Receipt photo strip">

  <script>
    var img    = document.getElementById('receipt-img');
    var status = document.getElementById('status-text');

    img.onload = function () {
      status.textContent = 'Sending to XPrinter…';
      // Small delay lets the browser paint before opening the print dialog.
      setTimeout(function () {
        window.print();
        // Close the popup after the user dismisses the print dialog.
        setTimeout(function () { window.close(); }, 1500);
      }, 350);
    };

    img.onerror = function () {
      status.textContent = '⚠ Image failed to load. Please try again.';
    };

    // Fallback: if the image is served from cache it may fire before onload
    // is attached — check readyState explicitly.
    if (img.complete && img.naturalWidth > 0) {
      img.onload();
    }
  </script>
</body>
</html>''';
  }
}

// ── Exception type ────────────────────────────────────────────────────────────

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => 'PrinterException: $message';
}
