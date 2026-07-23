// lib/widgets/modern_bottom_nav.dart
// Beautiful, modern bottom navigation bar with multiple styles
// Supports animations, badges, and haptic feedback

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum BottomNavStyle {
  floating,    // Floating pill-style navbar with rounded corners
  glass,       // Glassmorphic with blur effect
  minimal,     // Clean minimal design with subtle animations
  bubble,      // Bubbles that grow on selection
  morphing,    // Morphing indicator that flows between items
}

class ModernBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavItem> items;
  final BottomNavStyle style;
  final Color? backgroundColor;
  final Color? selectedColor;
  final Color? unselectedColor;
  final bool showLabels;
  final bool enableHaptic;
  final double? elevation;
  final EdgeInsets? padding;
  final bool isDark;

  const ModernBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.style = BottomNavStyle.floating,
    this.backgroundColor,
    this.selectedColor,
    this.unselectedColor,
    this.showLabels = true,
    this.enableHaptic = true,
    this.elevation,
    this.padding,
    this.isDark = false,
  });

  @override
  State<ModernBottomNav> createState() => _ModernBottomNavState();
}

class _ModernBottomNavState extends State<ModernBottomNav>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOutCubic,
    );
    _previousIndex = widget.currentIndex;
  }

  @override
  void didUpdateWidget(ModernBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      _animController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleTap(int index) {
    if (widget.enableHaptic) {
      HapticFeedback.selectionClick();
    }
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.style) {
      case BottomNavStyle.floating:
        return _buildFloatingNav();
      case BottomNavStyle.glass:
        return _buildGlassNav();
      case BottomNavStyle.minimal:
        return _buildMinimalNav();
      case BottomNavStyle.bubble:
        return _buildBubbleNav();
      case BottomNavStyle.morphing:
        return _buildMorphingNav();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  FLOATING PILL STYLE - Modern, elevated, rounded
  // ═══════════════════════════════════════════════════════════════
  Widget _buildFloatingNav() {
    final primaryColor = widget.selectedColor ?? Theme.of(context).primaryColor;
    final bgColor = widget.backgroundColor ??
        (widget.isDark ? const Color(0xFF1E1B3A) : Colors.white);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 65,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(widget.items.length, (index) {
              final item = widget.items[index];
              final isSelected = widget.currentIndex == index;

              return Expanded(
                child: _FloatingNavItem(
                  item: item,
                  isSelected: isSelected,
                  primaryColor: primaryColor,
                  onTap: () => _handleTap(index),
                  showLabel: widget.showLabels,
                  isDark: widget.isDark,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  GLASS MORPHIC STYLE - Frosted glass with blur
  // ═══════════════════════════════════════════════════════════════
  Widget _buildGlassNav() {
    final primaryColor = widget.selectedColor ?? Theme.of(context).primaryColor;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: widget.isDark
                ? const Color(0xFF1E1B3A).withOpacity(0.7)
                : Colors.white.withOpacity(0.7),
            border: Border(
              top: BorderSide(
                color: widget.isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            child: SizedBox(
              height: 65,
              child: Row(
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final isSelected = widget.currentIndex == index;

                  return Expanded(
                    child: _GlassNavItem(
                      item: item,
                      isSelected: isSelected,
                      primaryColor: primaryColor,
                      onTap: () => _handleTap(index),
                      showLabel: widget.showLabels,
                      isDark: widget.isDark,
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  MINIMAL STYLE - Clean and subtle
  // ═══════════════════════════════════════════════════════════════
  Widget _buildMinimalNav() {
    final primaryColor = widget.selectedColor ?? Theme.of(context).primaryColor;
    final bgColor = widget.backgroundColor ??
        (widget.isDark ? const Color(0xFF1E1B3A) : Colors.white);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: widget.isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(widget.items.length, (index) {
              final item = widget.items[index];
              final isSelected = widget.currentIndex == index;

              return Expanded(
                child: _MinimalNavItem(
                  item: item,
                  isSelected: isSelected,
                  primaryColor: primaryColor,
                  onTap: () => _handleTap(index),
                  showLabel: widget.showLabels,
                  isDark: widget.isDark,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUBBLE STYLE - Playful bubbles
  // ═══════════════════════════════════════════════════════════════
  Widget _buildBubbleNav() {
    final primaryColor = widget.selectedColor ?? Theme.of(context).primaryColor;
    final bgColor = widget.backgroundColor ??
        (widget.isDark ? const Color(0xFF1E1B3A) : Colors.white);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(widget.items.length, (index) {
              final item = widget.items[index];
              final isSelected = widget.currentIndex == index;

              return _BubbleNavItem(
                item: item,
                isSelected: isSelected,
                primaryColor: primaryColor,
                onTap: () => _handleTap(index),
                isDark: widget.isDark,
              );
            }),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  MORPHING STYLE - Flowing indicator
  // ═══════════════════════════════════════════════════════════════
  Widget _buildMorphingNav() {
    final primaryColor = widget.selectedColor ?? Theme.of(context).primaryColor;
    final bgColor = widget.backgroundColor ??
        (widget.isDark ? const Color(0xFF1E1B3A) : Colors.white);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 65,
          child: Stack(
            children: [
              // Animated indicator
              AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  final itemWidth = MediaQuery.of(context).size.width / widget.items.length;
                  final from = _previousIndex * itemWidth;
                  final to = widget.currentIndex * itemWidth;
                  final offset = from + (to - from) * _animation.value;

                  return Positioned(
                    left: offset + itemWidth * 0.2,
                    right: MediaQuery.of(context).size.width - (offset + itemWidth * 0.8),
                    bottom: 8,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Items
              Row(
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final isSelected = widget.currentIndex == index;

                  return Expanded(
                    child: _MorphingNavItem(
                      item: item,
                      isSelected: isSelected,
                      primaryColor: primaryColor,
                      onTap: () => _handleTap(index),
                      showLabel: widget.showLabels,
                      isDark: widget.isDark,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  NAV ITEM DATA MODEL
// ═══════════════════════════════════════════════════════════════
class BottomNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final int? badgeCount;
  final Color? badgeColor;

  const BottomNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.badgeCount,
    this.badgeColor,
  });
}

// ═══════════════════════════════════════════════════════════════
//  INDIVIDUAL NAV ITEM WIDGETS
// ═══════════════════════════════════════════════════════════════

class _FloatingNavItem extends StatefulWidget {
  final BottomNavItem item;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;
  final bool showLabel;
  final bool isDark;

  const _FloatingNavItem({
    required this.item,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
    required this.showLabel,
    required this.isDark,
  });

  @override
  State<_FloatingNavItem> createState() => _FloatingNavItemState();
}

class _FloatingNavItemState extends State<_FloatingNavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isSelected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_FloatingNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? widget.primaryColor.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          gradient: widget.isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.primaryColor.withOpacity(0.2),
                    widget.primaryColor.withOpacity(0.1),
                  ],
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedScale(
                  scale: widget.isSelected ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    widget.isSelected
                        ? (widget.item.activeIcon ?? widget.item.icon)
                        : widget.item.icon,
                    size: 24,
                    color: widget.isSelected
                        ? widget.primaryColor
                        : (widget.isDark
                            ? Colors.white70
                            : Colors.black54),
                  ),
                ),
                if (widget.item.badgeCount != null && widget.item.badgeCount! > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: widget.item.badgeColor ?? Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (widget.item.badgeColor ?? Colors.red)
                                .withOpacity(0.4),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        widget.item.badgeCount! > 99
                            ? '99+'
                            : widget.item.badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.showLabel) ...[
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: widget.isSelected ? 11 : 10,
                  fontWeight:
                      widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isSelected
                      ? widget.primaryColor
                      : (widget.isDark ? Colors.white70 : Colors.black54),
                ),
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Glass Nav Item
class _GlassNavItem extends StatelessWidget {
  final BottomNavItem item;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;
  final bool showLabel;
  final bool isDark;

  const _GlassNavItem({
    required this.item,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
    required this.showLabel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withOpacity(0.15)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSelected ? (item.activeIcon ?? item.icon) : item.icon,
              size: 24,
              color: isSelected
                  ? primaryColor
                  : (isDark ? const Color(0xFFCBD5E1) : Colors.black54),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? primaryColor
                    : (isDark ? const Color(0xFFCBD5E1) : Colors.black54),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Minimal Nav Item
class _MinimalNavItem extends StatelessWidget {
  final BottomNavItem item;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;
  final bool showLabel;
  final bool isDark;

  const _MinimalNavItem({
    required this.item,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
    required this.showLabel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSelected ? (item.activeIcon ?? item.icon) : item.icon,
            size: 24,
            color: isSelected
                ? primaryColor
                : (isDark ? Colors.white54 : Colors.black38),
          ),
          if (showLabel) ...[
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 6 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Bubble Nav Item
class _BubbleNavItem extends StatefulWidget {
  final BottomNavItem item;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;
  final bool isDark;

  const _BubbleNavItem({
    required this.item,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_BubbleNavItem> createState() => _BubbleNavItemState();
}

class _BubbleNavItemState extends State<_BubbleNavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _bubbleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bubbleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    if (widget.isSelected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_BubbleNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward(from: 0);
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _bubbleAnimation,
        builder: (context, child) {
          final scale = 1.0 + (_bubbleAnimation.value * 0.2);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? widget.primaryColor
                    : (widget.isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.05)),
                shape: BoxShape.circle,
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: widget.primaryColor.withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                widget.isSelected
                    ? (widget.item.activeIcon ?? widget.item.icon)
                    : widget.item.icon,
                size: 24,
                color: widget.isSelected
                    ? Colors.white
                    : (widget.isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Morphing Nav Item
class _MorphingNavItem extends StatelessWidget {
  final BottomNavItem item;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;
  final bool showLabel;
  final bool isDark;

  const _MorphingNavItem({
    required this.item,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
    required this.showLabel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSelected ? (item.activeIcon ?? item.icon) : item.icon,
            size: 24,
            color: isSelected
                ? primaryColor
                : (isDark ? Colors.white54 : Colors.black38),
          ),
          if (showLabel) ...[
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? primaryColor
                    : (isDark ? Colors.white54 : Colors.black38),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
