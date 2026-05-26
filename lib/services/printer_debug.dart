const bool kPrinterDebug = true;

void printerLog(String message) {
  if (kPrinterDebug) {
    print('[PrinterDebug] $message');
  }
}
