# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Linux laptop users running KDE Plasma 6 who want to inspect and change battery charging policy without opening a terminal.

## Product Purpose

Expose the installed `batctl` capabilities, battery state, presets, and persistence through a compact Plasma panel widget. Success means the user can understand the active thresholds and apply any preset offered by `batctl` in one click.

## Positioning

The widget is deliberately a presentation layer over `batctl`: hardware support, preset availability, and threshold adaptation remain owned by `batctl` rather than duplicated in the GUI.

## Operating Context

The widget lives in a Plasma panel, opens as a small popup, refreshes battery state periodically, and delegates privileged changes to the system copy of `batctl` through Polkit.

## Capabilities and Constraints

- Plasma 6 plasmoid built with QML, Kirigami, and a small Qt/C++ backend.
- Supports every battery backend detected by the installed `batctl` version.
- Discovers preset identifiers from `batctl set --help`; it does not define its own presets.
- Reads status from `batctl status` and hardware identity from `batctl detect`.
- Requires a root-owned `/usr/bin/batctl` for passwordless active-session Polkit authorization.
- Re-saves an already-enabled persistent configuration after changing a preset.

## Evidence on Hand

`batctl` is installed on the development machine and detects a Lenovo ThinkPad backend with charge threshold and behavior support.

## Product Principles

- `batctl` is the single source of truth.
- Keep the panel interaction fast and legible.
- Surface failures with a recovery action.
- Follow native Plasma behavior and theming.

## Accessibility & Inclusion

Use native controls, keyboard focus, system colors, scalable typography, and text labels in addition to icons.
