// lib/widgets/hazard_annotated_image.dart
// ✅ v17: Shows FULL image at natural aspect ratio with hazard bounding boxes.
// No zoom, no crop — entire uploaded image visible with clear hazard markings.
//
// Each hazard's `bbox` is expected as [yMin, xMin, yMax, xMax] normalized 0–1000
// (Gemini Vision format) OR as [x, y, w, h] normalized 0–1.

// No additional imports needed — LinearGradient comes from material.dart
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';

class HazardAnnotatedImage extends StatefulWidget {
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
  State<HazardAnnotatedImage> createState() => _HazardAnnotatedImageState();
}

class _HazardAnnotatedImageState extends State<HazardAnnotatedImage> {
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _resolveImageSize();
  }

  @override
  void didUpdateWidget(HazardAnnotatedImage old) {
    super.didUpdateWidget(old);
    if (old.imageBytes != widget.imageBytes) _resolveImageSize();
  }

  void _resolveImageSize() {
    final img = MemoryImage(widget.imageBytes);
    final stream = img.resolve(const ImageConfiguration());
    stream.addListener(
      ImageStreamListener(
        (info, _) {
          if (mounted) {
            setState(() {
              _imageSize = Size(
                info.image.width.toDouble(),
                info.image.height.toDouble(),
              );
            });
          }
        },
        onError: (e, _) {
          // Fallback if image resolution fails (e.g., on web)
          if (mounted) {
            setState(() {
              _imageSize = const Size(1024, 768); // assume 4:3
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerW = constraints.maxWidth;

        // Calculate actual rendered image dimensions (BoxFit.contain)
        double imageRenderW = containerW;
        double imageRenderH;
        double offsetX = 0;
        double offsetY = 0;

        if (_imageSize != null && _imageSize!.width > 0 && _imageSize!.height > 0) {
          final aspect = _imageSize!.width / _imageSize!.height;
          imageRenderH = containerW / aspect;
        } else {
          // Fallback: assume 4:3 until image loads
          imageRenderH = containerW * 0.75;
        }

        return SizedBox(
          width: containerW,
          height: imageRenderH,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Full image
              Image.memory(
                widget.imageBytes,
                width: containerW,
                height: imageRenderH,
                fit: BoxFit.contain,
              ),
              // Overlay bounding boxes — constrained to image area
              Positioned(
                left: offsetX,
                top: offsetY,
                width: imageRenderW,
                height: imageRenderH,
                child: _BboxOverlay(
                  hazards: widget.hazards,
                  onHazardTap: widget.onHazardTap,
                ),
              ),
            ],
          ),
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
          clipBehavior: Clip.hardEdge,
          children: [
            // ✅ LOF Zone overlays (rendered BELOW bboxes)
            ...hazards.asMap().entries
                .where((e) =>
                    (e.value as Map)['type']?.toString().toLowerCase() ==
                        'line of fire' &&
                    (e.value as Map)['lofZone'] != null)
                .map((entry) {
              final hazard = Map<String, dynamic>.from(entry.value as Map);
              final zone = hazard['lofZone'] as Map;
              final x1 = (num.tryParse(zone['x1']?.toString() ?? '') ?? 0).toDouble();
              final y1 = (num.tryParse(zone['y1']?.toString() ?? '') ?? 0).toDouble();
              final x2 = (num.tryParse(zone['x2']?.toString() ?? '') ?? 0).toDouble();
              final y2 = (num.tryParse(zone['y2']?.toString() ?? '') ?? 0).toDouble();
              return Positioned.fill(
                child: CustomPaint(
                  painter: _LofZonePainter(
                    x1: x1, y1: y1, x2: x2, y2: y2,
                    containerW: w, containerH: h,
                  ),
                ),
              );
            }),
            // ✅ Bbox overlays
            ...hazards.asMap().entries.map((entry) {
            final i = entry.key;
            final hazard = Map<String, dynamic>.from(entry.value as Map);
            final bbox = hazard['bbox'];
            if (bbox == null) return const SizedBox.shrink();

            // ✅ v17: Handle bbox as Map {x, y, w, h} OR List [x1, y1, x2, y2]
            final List<num> box;
            if (bbox is Map) {
              // Gemini prompt asks for {x, y, w, h} format
              final x = num.tryParse(bbox['x']?.toString() ?? '') ?? 0;
              final y = num.tryParse(bbox['y']?.toString() ?? '') ?? 0;
              final bw = num.tryParse(bbox['w']?.toString() ?? bbox['width']?.toString() ?? '') ?? 0;
              final bh = num.tryParse(bbox['h']?.toString() ?? bbox['height']?.toString() ?? '') ?? 0;
              box = [x, y, bw, bh];
            } else if (bbox is List) {
              box = bbox.map((e) => (e is num) ? e : num.tryParse(e.toString()) ?? 0).toList();
            } else {
              return const SizedBox.shrink();
            }

            if (box.length < 4) return const SizedBox.shrink();

            // Determine format: Gemini returns [yMin, xMin, yMax, xMax] in 0-1000 range
            // OR some APIs return [x, y, width, height] in 0-1 range
            double left, top, right, bottom;

            if (bbox is Map || box.every((v) => v <= 1.1)) {
              // Normalized 0-1 format: [x, y, w, h] (from Map or List)
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

            final double boxWidth  = (right - left).clamp(20.0, w).toDouble();
            final double boxHeight = (bottom - top).clamp(20.0, h).toDouble();

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
          ],
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

/// ✅ Custom painter for Line of Fire shaded danger zone
/// Draws a semi-transparent red/orange shaded rectangular region covering
/// the approximate area where energy/material could strike a person.
/// (x1,y1) = top-left of zone, (x2,y2) = bottom-right of zone (normalized 0-1)
class _LofZonePainter extends CustomPainter {
  final double x1, y1, x2, y2;
  final double containerW, containerH;

  _LofZonePainter({
    required this.x1, required this.y1,
    required this.x2, required this.y2,
    required this.containerW, required this.containerH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Convert normalized coords to pixel coords
    final left   = x1 * containerW;
    final top    = y1 * containerH;
    final right  = x2 * containerW;
    final bottom = y2 * containerH;

    final zoneRect = Rect.fromLTRB(
      left.clamp(0, containerW),
      top.clamp(0, containerH),
      right.clamp(0, containerW),
      bottom.clamp(0, containerH),
    );

    if (zoneRect.width < 5 || zoneRect.height < 5) return;

    // Gradient fill: red-orange, ~20% opacity (visible but not obscuring)
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x30FF5722), // orange-red ~19% opacity
          Color(0x28E53935), // red ~16% opacity
        ],
      ).createShader(zoneRect)
      ..style = PaintingStyle.fill;

    final rrect = RRect.fromRectAndRadius(zoneRect, const Radius.circular(6));
    canvas.drawRRect(rrect, fillPaint);

    // Dashed-style border (hatched pattern feel)
    final borderPaint = Paint()
      ..color = const Color(0x88E53935) // ~53% opacity red border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(rrect, borderPaint);

    // Diagonal hatch lines for "danger zone" feel
    canvas.save();
    canvas.clipRRect(rrect);
    final hatchPaint = Paint()
      ..color = const Color(0x18E53935) // very subtle hatch
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    const spacing = 12.0;
    for (double d = -zoneRect.height; d < zoneRect.width + zoneRect.height; d += spacing) {
      canvas.drawLine(
        Offset(zoneRect.left + d, zoneRect.top),
        Offset(zoneRect.left + d - zoneRect.height, zoneRect.bottom),
        hatchPaint,
      );
    }
    canvas.restore();

    // "LOF" label in the zone
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '⚠ LINE OF FIRE',
        style: TextStyle(
          color: Color(0xBBD32F2F),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Position label at top-center of zone
    final labelX = zoneRect.center.dx - textPainter.width / 2;
    final labelY = zoneRect.top + 4;

    // Label background
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(labelX - 4, labelY - 2,
          textPainter.width + 8, textPainter.height + 4),
      const Radius.circular(3),
    );
    canvas.drawRRect(labelRect, Paint()..color = const Color(0xCCFFFFFF));
    canvas.drawRRect(labelRect, Paint()
      ..color = const Color(0x66E53935)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5);

    textPainter.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant _LofZonePainter old) =>
      x1 != old.x1 || y1 != old.y1 || x2 != old.x2 || y2 != old.y2;
}
