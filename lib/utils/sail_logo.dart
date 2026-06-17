// lib/utils/sail_logo.dart
// SAIL logo — uses assets/images/app_icon.png with base64 fallback
// Usage: SailLogo.widget(size: 48)

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class SailLogo {
  // Base64 fallback kept for cases where asset isn't available
  static const String _b64 = '/9j/4AAQSkZJRgABAQAAAQABAAD/4gHYSUNDX1BST0ZJTEUAAQEAAAHIAAAAAAQwAABtbnRyUkdCIFhZWiAH4AABAAEAAAAAAABhY3NwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAA9tYAAQAAAADTLQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlkZXNjAAAA8AAAACRyWFlaAAABFAAAABRnWFlaAAABKAAAABRiWFlaAAABPAAAABR3dHB0AAABUAAAABRyVFJDAAABZAAAAChnVFJDAAABZAAAAChiVFJDAAABZAAAAChjcHJ0AAABjAAAADxtbHVjAAAAAAAAAAEAAAAMZW5VUwAAAAgAAAAcAHMAUgBHAEJYWVogAAAAAAAAb6IAADj1AAADkFhZWiAAAAAAAABimQAAt4UAABjaWFlaIAAAAAAAACSgAAAPhAAAts9YWVogAAAAAAAA9tYAAQAAAADTLXBhcmEAAAAAAAQAAAACZmYAAPKnAAANWQAAE9AAAApbAAAAAAAAAABtbHVjAAAAAAAAAAEAAAAMZW5VUwAAACAAAAAcAEcAbwBvAGcAbABlACAASQBuAGMALgAgADIAMAAxADb/2wBDAAUDBAQEAwUEBAQFBQUGBwwIBwcHBw8LCwkMEQ8SEhEPERETFhwXExQaFRERGCEYGh0dHx8fExciJCIeJBweHx7/2wBDAQUFBQcGBw4ICA4eFBEUHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh7/wAARCAFfAWoDASIAAhEBAxEB/8QAHQAAAgIDAQEBAAAAAAAAAAAAAAECAwQFCAYHCf/EAA==';

  static Uint8List get bytes => base64Decode(_b64);

  /// Returns a circular SAIL logo widget — uses app_icon.png asset.
  static Widget widget({double size = 48, Color? bgColor}) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor ?? Colors.white,
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.12),
          blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/app_icon.png',
          width: size, height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Image.memory(
            bytes, width: size, height: size, fit: BoxFit.contain),
        ),
      ),
    );
  }

  /// Small icon version — no clip, just sized image.
  static Widget icon({double size = 32}) {
    return Image.asset(
      'assets/images/app_icon.png',
      width: size, height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Image.memory(
        bytes, width: size, height: size, fit: BoxFit.contain),
    );
  }
}
