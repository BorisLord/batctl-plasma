# Design

## Direction

Native Plasma utility. The widget should feel shipped with the desktop: compact, restrained, theme-aware, and optimized for repeated operation rather than visual novelty.

## Structure

- Panel representation: battery icon plus the current threshold range when space permits.
- Popup: identity and refresh action, battery readings, preset actions, persistence state, then contextual feedback.
- Current thresholds remain visible while choosing a preset.

## Components

Use Plasma Components for controls and labels, Kirigami for icons and inline messages, and Plasma theme metrics for spacing. Avoid custom cards, fixed colors, decorative shadows, and non-native typography.

## Interaction

Refreshing and applying a preset expose a busy state. Preset buttons stay keyboard accessible and are disabled during writes. Success refreshes the displayed state; failure remains visible with a direct explanation.

## Responsive Behavior

The compact representation adapts to horizontal and vertical panels. The popup uses the system tray's available size and scrolls when multiple batteries expand its content.
