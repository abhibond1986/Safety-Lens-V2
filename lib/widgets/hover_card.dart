// lib/widgets/hover_card.dart
// Beautiful hover-enabled card widget with smooth animations
// Supports multiple hover effects: scale, elevation, glow, tilt

import 'package:flutter/material.dart';

enum HoverEffect {
  scale,      // Grows slightly on hover
  elevation,  // Increases shadow
  glow,       // Adds colored glow
  lift,       // Elevates with scale
  tilt,       // 3D tilt effect (desktop only)
}

class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final Color? hoverColor;
  final Color? glowColor;
  final BorderRadius? borderRadius;
  final Border? border;
  final List<BoxShadow>? shadows;
  final double? width;
  final double? height;
  final Set<HoverEffect> effects;
  final Duration duration;
  final Curve curve;
  final bool enabled;

  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
    this.color,
    this.hoverColor,
    this.glowColor,
    this.borderRadius,
    this.border,
    this.shadows,
    this.width,
    this.height,
    this.effects = const {HoverEffect.scale, HoverEffect.elevation},
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOutCubic,
    this.enabled = true,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _elevationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHoverChanged(bool isHovered) {
    if (!widget.enabled) return;
    setState(() => _isHovered = isHovered);
    if (isHovered) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _onTapDown(TapDownDetails details) {
    if (!widget.enabled) return;
    setState(() => _isPressed = true);
  }

  void _onTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    setState(() => _isPressed = false);
  }

  void _onTapCancel() {
    if (!widget.enabled) return;
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onHoverChanged(true),
      onExit: (_) => _onHoverChanged(false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Calculate transforms based on enabled effects
            final scale = widget.effects.contains(HoverEffect.scale) ||
                    widget.effects.contains(HoverEffect.lift)
                ? _scaleAnimation.value
                : 1.0;

            // Build shadow based on hover state
            final defaultShadows = [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ];

            final hoverShadows = [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ];

            final shadows = widget.shadows ??
                (widget.effects.contains(HoverEffect.elevation) ||
                        widget.effects.contains(HoverEffect.lift)
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(
                              0.08 + (_elevationAnimation.value * 0.04)),
                          blurRadius: 8 + (_elevationAnimation.value * 12),
                          offset: Offset(0, 2 + (_elevationAnimation.value * 6)),
                        ),
                      ]
                    : defaultShadows);

            // Glow effect
            final glowShadow = widget.effects.contains(HoverEffect.glow) &&
                    _isHovered
                ? [
                    BoxShadow(
                      color: (widget.glowColor ?? Theme.of(context).primaryColor)
                          .withOpacity(0.3 * _glowAnimation.value),
                      blurRadius: 20 * _glowAnimation.value,
                      spreadRadius: 2 * _glowAnimation.value,
                    ),
                  ]
                : <BoxShadow>[];

            final allShadows = [...shadows, ...glowShadow];

            // Build the card
            return Transform.scale(
              scale: _isPressed ? scale * 0.98 : scale,
              child: Container(
                width: widget.width,
                height: widget.height,
                margin: widget.margin,
                decoration: BoxDecoration(
                  color: _isHovered && widget.hoverColor != null
                      ? widget.hoverColor
                      : widget.color,
                  borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
                  border: widget.border,
                  boxShadow: allShadows,
                ),
                child: Container(
                  padding: widget.padding,
                  child: child,
                ),
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Pre-configured hover card variants for common use cases

class HoverStatCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Color? glowColor;

  const HoverStatCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: onTap,
      color: color ?? Theme.of(context).cardColor,
      glowColor: glowColor,
      effects: const {HoverEffect.lift, HoverEffect.glow},
      borderRadius: BorderRadius.circular(16),
      child: child,
    );
  }
}

class HoverActionCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsets? padding;

  const HoverActionCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: onTap,
      color: color ?? Theme.of(context).cardColor,
      padding: padding ?? const EdgeInsets.all(12),
      effects: const {HoverEffect.scale, HoverEffect.elevation},
      borderRadius: BorderRadius.circular(14),
      duration: const Duration(milliseconds: 150),
      child: child,
    );
  }
}

class HoverListCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Color? hoverColor;
  final Border? border;
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  const HoverListCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.hoverColor,
    this.border,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: onTap,
      color: color ?? Theme.of(context).cardColor,
      hoverColor: hoverColor,
      border: border,
      padding: padding ?? const EdgeInsets.all(12),
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      effects: const {HoverEffect.scale, HoverEffect.elevation},
      borderRadius: BorderRadius.circular(12),
      child: child,
    );
  }
}
