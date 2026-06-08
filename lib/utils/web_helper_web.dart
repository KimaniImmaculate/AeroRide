import 'dart:ui_web' as ui_web;
import 'dart:html' as html;

/// Implementation for web platform view registration.
/// Uses [ui_web.platformViewRegistry] introduced in modern Flutter versions.
void registerWebPlatformView() {
  ui_web.platformViewRegistry.registerViewFactory(
    'recaptcha-container',
    (int viewId) => html.DivElement()..id = 'recaptcha-container',
  );
}
