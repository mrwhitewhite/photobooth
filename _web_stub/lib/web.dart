// Minimal stub for package:web used only to satisfy pub for non-web builds.
// Provide no-op types that may be referenced transitively but are unused on mobile.

library web;

// Commonly used symbols are left empty or minimally defined.
class Blob {}
class File {
  File();
}

// JS interop placeholders
class JSObject {}
class JSAny {}

// Placeholder for other possible symbols
typedef Callback = void Function();
