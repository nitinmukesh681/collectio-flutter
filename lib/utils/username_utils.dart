import 'package:flutter/services.dart';

/// Shared username normalization and validation.
class UsernameUtils {
  UsernameUtils._();

  static final RegExp pattern = RegExp(r'^[a-z0-9_]+$');

  static String normalize(String username) => username.trim().toLowerCase();

  static String? validate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a username';
    }
    final normalized = normalize(value);
    if (normalized.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (!pattern.hasMatch(normalized)) {
      return 'Only lowercase letters, numbers, and underscores allowed';
    }
    return null;
  }

  static List<TextInputFormatter> get inputFormatters => [
        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
      ];
}
