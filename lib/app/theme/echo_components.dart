import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:flutter/material.dart';

class EchoTopBar extends StatelessWidget implements PreferredSizeWidget {
  const EchoTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(62);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: EchoColors.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (onBack != null) ...[
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: onBack,
                        icon: const Icon(
                          Icons.arrow_back,
                          color: EchoColors.navy,
                        ),
                        tooltip: 'Back',
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EchoColors.navy,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          actions[i],
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: EchoColors.border),
        ],
      ),
    );
  }
}

class EchoStatusPill extends StatelessWidget {
  const EchoStatusPill({
    super.key,
    required this.label,
    this.icon = Icons.info_outline,
    this.containerColor = EchoColors.surfaceAlt,
    this.borderColor = EchoColors.pillBorder,
    this.contentColor = EchoColors.primary,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color containerColor;
  final Color borderColor;
  final Color contentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: contentColor),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: contentColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: pill,
    );
  }
}

class EchoCard extends StatelessWidget {
  const EchoCard({
    super.key,
    required this.child,
    this.borderColor = EchoColors.border,
    this.containerColor = EchoColors.surface,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  final Widget child;
  final Color borderColor;
  final Color containerColor;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: EchoColors.primary.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return card;
  }
}

class EchoPrimaryButton extends StatelessWidget {
  const EchoPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    this.backgroundColor = EchoColors.primary,
  });

  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: EchoColors.surfaceAlt,
          disabledForegroundColor: EchoColors.light,
          elevation: 0,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EchoOutlinedPillButton extends StatelessWidget {
  const EchoOutlinedPillButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    this.containerColor = EchoColors.surfaceAlt,
    this.borderColor = EchoColors.pillBorder,
    this.contentColor = EchoColors.primary,
  });

  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;
  final Color containerColor;
  final Color borderColor;
  final Color contentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: enabled ? containerColor : EchoColors.bg,
          foregroundColor: enabled ? contentColor : EchoColors.light,
          side: BorderSide(color: enabled ? borderColor : EchoColors.border),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EchoIconBadge extends StatelessWidget {
  const EchoIconBadge({
    super.key,
    required this.icon,
    this.size = 48,
    this.iconSize = 24,
    this.isCircle = false,
    this.containerColor = EchoColors.surfaceAlt,
    this.tint = EchoColors.primary,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final bool isCircle;
  final Color containerColor;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: containerColor,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(12),
      ),
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}

class EchoChoiceChip extends StatelessWidget {
  const EchoChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leadingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? EchoColors.primary : EchoColors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? EchoColors.primary : EchoColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(
                leadingIcon,
                size: 16,
                color: selected ? Colors.white : EchoColors.navy,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? Colors.white : EchoColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
