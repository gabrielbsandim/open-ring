# Design Tokens and Accessibility Rules

Single source for colours, theme modes and text scaling. The Flutter theme and
the design prototype both follow this file.

## Theme modes

Three choices in Settings: follow the system (default), dark, light. Dark is the
design reference, light is a first-class peer, not an inverted afterthought.
Widgets follow the same choice unless the widget's own setting overrides it.

## Colour tokens

| Token | Dark | Light | Use |
| :--- | :--- | :--- | :--- |
| `background` | `#0E0F13` | `#F6F7F9` | Screen background |
| `surface` | `#171920` | `#FFFFFF` | Cards |
| `surfaceBorder` | `#242833` | `#E3E6EC` | Card border, dividers |
| `surfaceInner` | `#1F222B` | `#EEF0F4` | Inset rows, secondary buttons |
| `strongBorder` | `#2E3340` | `#CDD2DB` | Secondary button border |
| `track` | `#262A34` | `#E3E6EC` | Progress and chart tracks |
| `navBar` | `#12141A` | `#FFFFFF` | Bottom navigation |
| `textPrimary` | `#ECEEF2` | `#14161C` | Main text, readiness |
| `textSecondary` | `#C9CED8` | `#3D4350` | Body copy |
| `textLabel` | `#9AA1AE` | `#5A6170` | Labels, captions |
| `sleep` | `#A78BFA` | `#6D4FD8` | Sleep family |
| `heart` | `#FF7A6B` | `#C8372B` | Heart rate, HRV, destructive |
| `activity` | `#4ADE80` | `#15803D` | Steps, workouts, success |
| `oxygen` | `#22D3EE` | `#0E7490` | SpO2 |
| `stress` | `#FBBF24` | `#B45309` | Stress, warnings |
| `onAccent` | `#0E0F13` | `#FFFFFF` | Text on an accent fill |

Sleep stages (dark / light): awake `#E5E7EB` / `#9CA3AF`, REM `#C4B5FD` /
`#A78BFA`, light `#8B6CF0` / `#7C5CE6`, deep `#6D50E6` / `#4C2FB8`.

Rules:

- Every accent used as text reaches 4.5:1 on `background` and on `surface` of
  its own mode. A unit test enforces it for both modes.
- Colours that must be told apart also differ in lightness, not hue alone.
- No colour literal outside the theme. Screens read tokens through the theme.

## Text scaling

The app must work from 85% up to 200% system font size (Android "Font size"
plus "Display size", iOS Dynamic Type up to AX sizes, capped at 200% in layout
tests).

- Never clamp the user's text scale below what they chose.
- No fixed height on anything that contains text. Heights come from content;
  fixed sizes are allowed only for icons, charts and touch targets (minimum
  48 dp).
- Rows of metrics wrap: two-column grids become one column when the text scale
  is above 1.3. Label and value pairs move to two lines instead of truncating.
- Numbers never truncate. Long labels may wrap to two lines, never ellipsize
  a value.
- Bottom navigation keeps icons at fixed size; labels scale and may wrap to two
  lines; at 200% the bar grows in height instead of hiding labels.
- Charts keep their geometry; their axis labels scale and drop to every other
  tick when they would collide.
- Every screen has widget tests at text scale 1.0, 1.3 and 2.0, in dark and
  light, in English and in the longest locale (German), and fails on any
  layout overflow.
