/// Global toggle for printer/BLE debug logging.
/// Set to `true` during development, `false` for production builds.
const bool kPrinterDebug = true;

void printerLog(String message) {
  if (kPrinterDebug) {
    // ignore: avoid_print
    print('[PrinterDebug] $message');
  }
}
