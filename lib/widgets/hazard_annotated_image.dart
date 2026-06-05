// lib/widgets/hazard_annotated_image.dart
//
// Draws colored bounding boxes with labels over an image
// for each hazard returned by Gemini AI analysis.
//
// Usage:
//   HazardAnnotatedImage(
//     imageBytes: _imageBytes,
//     hazards: result['hazards'],
//     onHazardTap: (index) => _scrollToHazardRow(index),
//   )

import 'package:flutter/material.dart';
import '../main.dart'; // AppColors, SeverityBadge

class HazardAnnotatedImage extends StatefulWidget {
  final Uint8List imageBytes;
  final List<dynamic> hazards;
  final void Function(int index)? onHazardTap;

  const HazardAnnotatedImage({
    super.key,
    required this.imageBytes,
    required this.hazards,
    this.onHazardTap,
  });

  @override
  State<HazardAnnotatedImage> createState() => _HazardAnnotatedImageState();
}

class _HazardAnnotatedImageState extends State<HazardAnnotatedImage> {
  int? _selectedIndex;
  OverlayEntry? _tooltipOverlay;

  @override
  void dispose() {
    _tooltipOverlay?.remove();
    super.dispose();
  }

  // Parse bbox from hazard map — returns Rect with normalised 0.0–1.0 coords
  Rect? _parseBbox(Map<String, dynamic> hazard) {
    final bbox = hazard['bbox'];
    if (bbox == null) return null;
    try {
      final x = (bbox['x'] as num?)?.toDouble() ?? 0.05;
      final y = (bbox['y'] as num?)?.toDouble() ?? 0.05;
      final w = (bbox['w'] as num?)?.toDouble() ?? 0.9;
      final h = (bbox['h'] as num?)?.toDouble() ?? 0.9;
      // Clamp to valid range
      return Rect.fromLTWH(
        x.clamp(0.0, 0.95),
        y.clamp(0.0, 0.95),
        w.clamp(0.05, 1.0 - x),
        h.clamp(0.05, 1.0 - y),
      );
    } catch (_) {
      return null;
    }
  }

  Color _severityColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH':     return AppColors.red;
      case 'MEDIUM':   return AppColors.amber;
      default:         return AppColors.green;
    }
  }

  void _onTapHazard(int index) {
    setState(() => _selectedIndex = index == _selectedIndex ? null : index);
    widget.onHazardTap?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth  = constraints.maxWidth;
        // Keep 16:9 aspect by default; image will naturally size itself
        return Stack(
          children: [
            // Base image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                widget.imageBytes,
                width: imageWidth,
                fit: BoxFit.fitWidth,
              ),
            ),

            // Bounding box overlays
            Positioned.fill(
              child: LayoutBuilder(
                builder: (ctx, imgConstraints) {
                  final W = imgConstraints.maxWidth;
                  final H = imgConstraints.maxHeight;

                  return Stack(
                    children: List.generate(widget.hazards.length, (i) {
                      final hazard = Map<String, dynamic>.from(
                          widget.hazards[i] as Map);
                      final bbox = _parseBbox(hazard);
                      if (bbox == null) return const SizedBox.shrink();

                      final severity = hazard['severity']?.toString() ?? 'LOW';
                      final name     = hazard['name']?.toString() ?? 'Hazard';
                      final color    = _severityColor(severity);
                      final isSelected = _selectedIndex == i;

                      final left   = bbox.left * W;
                      final top    = bbox.top * H;
                      final width  = bbox.width * W;
                      final height = bbox.height * H;

                      return Positioned(
                        left: left,
                        top: top,
                        width: width,
                        height: height,
                        child: GestureDetector(
                          onTap: () => _onTapHazard(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: color,
                                width: isSelected ? 2.5 : 1.5,
                              ),
                              color: isSelected
                                  ? color.withOpacity(0.2)
                                  : color.withOpacity(0.08),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Label at top of box
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(3),
                                      bottomRight: Radius.circular(3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Number badge
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.3),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${i + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      // Hazard name — truncate if box is narrow
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: (width - 30).clamp(0, 200)),
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Tooltip when selected
                                if (isSelected && height > 60)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          hazard['description']?.toString() ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 7,
                                            height: 1.3,
                                          ),
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),

            // Legend strip at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.75),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: List.generate(widget.hazards.length, (i) {
                    final hazard   = Map<String, dynamic>.from(
                        widget.hazards[i] as Map);
                    final severity = hazard['severity']?.toString() ?? 'LOW';
                    final name     = hazard['name']?.toString() ?? 'Hazard';
                    final color    = _severityColor(severity);
                    final isSelected = _selectedIndex == i;

                    return GestureDetector(
                      onTap: () => _onTapHazard(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withOpacity(0.9)
                              : color.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: color,
                            width: isSelected ? 1.5 : 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.9),
                                fontSize: 8,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
