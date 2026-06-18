// lib/widgets/hazard_annotated_image.dart
// ✅ v17: Shows FULL image at natural aspect ratio with hazard bounding boxes.
// No zoom, no crop — entire uploaded image visible with clear hazard markings.
//
// Each hazard's `bbox` is expected as [yMin, xMin, yMax, xMax] normalized 0–1000
// (Gemini Vision format) OR as [x, y, w, h] normalized 0–1.

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';

class HazardAnnotatedImage extends StatelessWidget {
  final Uint8List imageBytes;
  final List hazards;
  final void Function(int index)? onHazardTap;

  const HazardAnnotatedImage({
    super.key,
    required this.imageBytes,
    required this.hazards,
    this.onHazardTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Show full image with bounding boxes overlaid using Stack + Positioned
        return Stack(
          children: [
            // Full image — takes its natural aspect ratio
            Image.memory(
              imageBytes,
              width: constraints.maxWidth,
              fit: BoxFit.contain,
              // Use a builder to get the actual rendered image size
            ),
            // Overlay bounding boxes using AspectRatio + custom paint
            Positioned.fill(
              child: _BboxOverlay(
                hazards: hazards,
                onHazardTap: onHazardTap,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BboxOverlay extends StatelessWidget {
  final List hazards;
  final void Function(int index)? onHazardTap;

  const _BboxOverlay({required this.hazards, this.onHazardTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          children: hazards.asMap().entries.map((entry) {
            final i = entry.key;
            final hazard = Map<String, dynamic>.from(entry.value as Map);
            final bbox = hazard['bbox'];
            if (bbox == null) return const SizedBox.shrink();

            final List<num> box = (bbox is List)
                ? bbox.map((e) => (e is num) ? e : num.tryParse(e.toString()) ?? 0).toList()
                : [];

            if (box.length < 4) return const SizedBox.shrink();

            // Determine format: Gemini returns [yMin, xMin, yMax, xMax] in 0-1000 range
            // OR some APIs return [x, y, width, height] in 0-1 range
            double left, top, right, bottom;

            if (box.every((v) => v <= 1.1)) {
              // Normalized 0-1 format: [x, y, w, h]
              left   = box[0].toDouble() * w;
              top    = box[1].toDouble() * h;
              right  = (box[0].toDouble() + box[2].toDouble()) * w;
              bottom = (box[1].toDouble() + box[3].toDouble()) * h;
            } else {
              // Gemini 0-1000 format: [yMin, xMin, yMax, xMax]
              top    = (box[0].toDouble() / 1000) * h;
              left   = (box[1].toDouble() / 1000) * w;
              bottom = (box[2].toDouble() / 1000) * h;
              right  = (box[3].toDouble() / 1000) * w;
            }

            // Clamp to valid range
            left   = left.clamp(0, w);
            top    = top.clamp(0, h);
            right  = right.clamp(0, w);
            bottom = bottom.clamp(0, h);

            final boxWidth  = (right - left).clamp(20, w);
            final boxHeight = (bottom - top).clamp(20, h);

            final severity = (hazard['severity']?.toString() ?? 'MEDIUM').toUpperCase();
            final color = _sevColor(severity);
            final name = hazard['name']?.toString() ?? 'Hazard ${i + 1}';

            return Positioned(
              left: left,
              top: top,
              width: boxWidth,
              height: boxHeight,
              child: GestureDetector(
                onTap: () => onHazardTap?.call(i),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: 2.5),
                    borderRadius: BorderRadius.circular(4),
                    color: color.withOpacity(0.08),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Label at top of box
                      Positioned(
                        top: -1,
                        left: -1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              bottomRight: Radius.circular(6),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxWidth: boxWidth * 0.7),
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    height: 1,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Color _sevColor(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL': return const Color(0xFFDC2626);
      case 'HIGH':     return const Color(0xFFEF4444);
      case 'MEDIUM':   return const Color(0xFFF59E0B);
      case 'LOW':      return const Color(0xFF10B981);
      default:         return const Color(0xFFF59E0B);
    }
  }
}
