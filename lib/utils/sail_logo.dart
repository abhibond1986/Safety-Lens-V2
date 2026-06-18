// lib/utils/sail_logo.dart
// SAIL logo — minimalist, no backdrop/container/shadow.
// Just displays assets/images/app_icon.png directly.
// Usage: SailLogo.widget(size: 48)

import 'package:flutter/material.dart';

class SailLogo {
  /// Returns the SAIL logo — plain image, no decoration.
  static Widget widget({double size = 48}) {
    return Image.asset(
      'assets/images/app_icon.png',
      width: size, height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.shield_outlined,
        size: size * 0.7,
        color: Colors.grey,
      ),
    );
  }

  /// Alias kept for backward compat — same as widget().
  static Widget icon({double size = 32}) {
    return widget(size: size);
  }
}
