import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef SharePayloadHandler = void Function({
  required String? url,
  required String? text,
  required String? subject,
});

/// Registers the native share method channel before [runApp] so cold-start
/// shares are not dropped while the widget tree is still mounting.
class ShareIntentController {
  ShareIntentController._();

  static const _channel = MethodChannel('com.collectio.app/share_extension');
  static SharePayloadHandler? _handler;
  static ({String? url, String? text, String? subject})? _queued;

  static void install() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'shareReceived') return;
      _dispatch(_parsePayload(call.arguments));
    });
  }

  static void attach(SharePayloadHandler handler) {
    _handler = handler;
    if (_queued != null) {
      final pending = _queued!;
      _queued = null;
      handler(url: pending.url, text: pending.text, subject: pending.subject);
    }
  }

  static void detach() {
    _handler = null;
  }

  static void _dispatch(
    ({String? url, String? text, String? subject}) payload,
  ) {
    if (payload.url == null &&
        (payload.text == null || payload.text!.isEmpty)) {
      return;
    }

    debugPrint(
      '[Share] native shareReceived '
      'url=${payload.url ?? "(null)"} '
      'text=${payload.text ?? "(null)"} '
      'subject=${payload.subject ?? "(null)"}',
    );

    final handler = _handler;
    if (handler == null) {
      _queued = payload;
      return;
    }
    handler(
      url: payload.url,
      text: payload.text,
      subject: payload.subject,
    );
  }

  static ({String? url, String? text, String? subject}) _parsePayload(
    Object? arguments,
  ) {
    if (arguments is String) {
      final trimmed = arguments.trim();
      return (url: trimmed.isEmpty ? null : trimmed, text: null, subject: null);
    }

    if (arguments is Map) {
      final payload = Map<Object?, Object?>.from(arguments);
      final text = _readString(payload['text']);
      final subject = _readString(payload['subject']);
      final url = _readString(payload['url']) ?? text;
      return (url: url, text: text, subject: subject);
    }

    return (url: null, text: null, subject: null);
  }

  static String? _readString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
