# DesignKit Package

DesignKit is a Lazarus package that provides a set of visual and non‑visual components to enhance application UI design.  
All components are installed on the **Common Controls** tab of the component palette.

## Requirements

- **Lazarus** (tested with 4.8) / **Free Pascal Compiler** 3.2.2 or newer.
- **LCL** – included with Lazarus.
- **IDEIntf** – included with Lazarus.
- **[Helpers](https://github.com/plainlib/helpers)** – common utility units used by the spell‑checker (available in plainlib).
- **[Toolkit](https://github.com/plainlib/toolkit)** – general‑purpose utility classes (available in plainlib).
- **Windows 8 or later** is required only for the native `WinSpellChecker` backend. The **HunSpell** backend works on all platforms (Windows, Linux, macOS) and does not need any OS‑specific API.

---

## TCalendarLite Modified (Common Controls ![calendarlite](img/TCalendarLite.png))

![sample_calendar](img/sample_calendar.png)

`TCalendarLite` is a lightweight, resizable calendar component - a
`TGraphicControl` descendant, so it has no native counterpart and
behaves identically on Windows, Linux, and macOS. It is used in DesignKit
as a drop-in replacement for the original Lazarus CCR calendar, extended
with independent single/range selection, per-day events, mouse-wheel
month navigation, and full localization.

The component draws a standard month grid with a header (month/year
caption, navigation arrows), a row of weekday names, the six date rows,
and an optional "today" footer row that shows the current day and the
currently selected range.

### Selection

Single and range selections are kept separately and do not interfere
with each other. The rules are:

- **Single click** on a day toggles its single selection. Clicking the
  selected day again clears it. The range (if any) is left untouched.
- **Shift+click** builds a new range from the current single selection
  to the clicked cell. The anchor is fixed for the whole Shift-held
  sequence, so subsequent Shift+clicks keep extending from the original
  cell. Single selection jumps to the end of the range.
- **Drag** (press and move the mouse) builds a new range from the press
  cell to the release cell. While dragging, the single selection
  follows the mouse. Releasing on the same cell as the press does not
  create a range - it falls back to a plain single toggle.
- **Double-click** on the same cell: if a range exists, it is cleared;
  if not, a range is built from the single selection to the clicked
  cell (or just sets the single selection if nothing was selected).
  Rapid double-clicks that hit *different* cells are treated as two
  plain clicks, which guards against false double-clicks after view
  navigation.
- **Arrow keys** move the single selection; **Shift+arrow** extends
  the range from the current anchor.
- A range always contains at least two days; attempting to narrow it
  to one cell simply removes the range.
- **Mouse wheel** scrolls the view to the previous/next month without
  touching the current selection. The scroll rate is throttled so the
  grid moves at a comfortable pace.

### Events

Each day can carry any number of user events. An event is a date, a
caption, and a colour; events are displayed as small coloured squares
under the day number and can be clicked individually.

```pascal
Calendar.Events.Add(Now, 'Pay bills', clRed);
```

### Colors

All drawing colours are exposed through the `Colors: TCalColors`
sub-property. The most relevant entries are `SelectedDateColor` (single
selection), `SelectedRangeColor` (range), `TodayFrameColor`, and
`EventFocusColor` (hovered event square).

### Localization

The `Languages` property switches day names, month names, and format
strings between the built-in languages (`lgEnglish`, `lgFrench`,
`lgGerman`, `lgHebrew`, `lgSpanish`, `lgItalian`, `lgPolish`,
`lgFinnish`, `lgGreek`, `lgRussian`). Use `lgCustom` together with
`DayNames`, `MonthNames`, and `DisplayTexts` to supply your own.

### Key Properties

| Property              | Default       | Description |
|-----------------------|---------------|-------------|
| `Date`                | `Now`         | Currently focused date. |
| `MultiSelect`         | `False`       | Enables multi-select mode (range, Shift/drag, etc.). |
| `Languages`           | `lgEnglish`   | Built-in localization preset. |
| `Options`             | see code      | Set of `TCalOption` flags: today frame/row, weekends, holidays, borders, etc. |
| `Colors`              | see code      | All drawing colours (see `TCalColors`). |
| `Events`              | empty         | User event list (`TCalEventList`). |
| `StartingDayOfWeek`   | `dowSunday`   | First column of the week. |
| `WeekendDays`         | `[dowSunday]` | Days rendered with the weekend colour. |
| `ButtonWidth` / `ButtonHeight` | `0`   | Arrow button sizes (0 = auto). |
| `EventSquareSize`     | `6`           | Side length of the event marker square. |
| `EventSquareBottom`   | `5`           | Bottom margin for event markers. |
| `DayNames`, `MonthNames`, `DisplayTexts` | empty | Custom strings used with `lgCustom`. |

### Key Events

| Event                | Description |
|----------------------|-------------|
| `OnDateChange`       | Fired when the focused date changes. |
| `OnMonthChange`      | Fired when the focused month changes (view navigation). |
| `OnRangeSelected`    | Fired when a multi-day range is created or cleared. |
| `OnEventClick`       | Fired when a user event square is clicked. |
| `OnGetHolidays`      | Supply per-month holidays as a bit mask. |
| `OnGetDayText`       | Override the day-number caption. |
| `OnPrepareCanvas`    | Adjust the canvas per cell before drawing. |
| `OnDrawCell`         | Fully custom-draw a day cell. |
| `OnHint`             | Provide a hint for a day under the mouse. |

### Notes on this fork

The component originates from the Lazarus CCR (Community Components
Repository) and is bundled with DesignKit in a modified form. All
DesignKit-specific changes (independent single/range selection, events,
mouse-wheel navigation, localization presets, colour extensions, and
the today-row range display) are tracked in the project git history:
<https://github.com/plainlib/designkit>. The original license and
authorship are preserved below.

### TCalendarLite license

`TCalendarLite` is free software distributed under the **GNU Library
General Public License, version 2 or later**, with a special linking
exception that permits linking it with independent modules. The original
license notice from the component's source header is reproduced below as
required by its terms:

{ TCalendarLite is a lightweight calendar component, a TGraphiccontrol
  descendant, which is consequently not dependent on any widgetset.
  It is not a fixed-size component, as are most calendars, but will align
  and resize as needed

  Originator    : H Page-Clark, 2013/2016
  Contributions : Ariel Rodriguez, 2013
                  Werner Pamler, 2013/2016
                  John Greetham, 2016

  This library is free software; you can redistribute it and/or modify it
  under the terms of the GNU Library General Public License as published by
  the Free Software Foundation; either version 2 of the License, or (at your
  option) any later version with the following modification:

  As a special exception, the copyright holders of this library give you
  permission to link this library with independent modules to produce an
  executable, regardless of the license terms of these independent modules,and
  to copy and distribute the resulting executable under terms of your choice,
  provided that you also meet, for each linked independent module, the terms
  and conditions of the license of that module. An independent module is a
  module which is not derived from or based on this library. If you modify
  this library, you may extend this exception to your version of the library,
  but you are not obligated to do so. If you do not wish to do so, delete this
  exception statement from your version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
  for more details.

  You should have received a copy of the GNU Library General Public License
  along with this library; if not, write to the Free Software Foundation,
  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

  Modified by Alexander Tverskoy (plaintool), 2026.
  All changes are tracked in the project git history:
  https://github.com/plainlib/designkit
}

---

## TFormGrip (Common Controls ![formgrip](img/TFormGrip.png))

`TFormGrip` is a visual control that draws a size grip in a selected corner
of its parent (a form or a panel) and resizes that parent when the grip is
dragged. It behaves like the grip found in a `StatusBar`, but can be placed
in any corner and styled freely.

The component does not hook or override any events of its parent. All mouse
handling, painting, and resizing are performed inside the control itself, so
the parent form's own `OnPaint`, `OnMouseDown`, `OnMouseMove`, `OnMouseUp`,
and `OnResize` handlers remain untouched.

### Features

- Works with any `TWinControl` parent, not only with forms.
- Grip can be placed in any of the four corners of the parent.
- The control automatically snaps to the chosen corner and cannot be moved
  away from it; resizing or repositioning the parent keeps the grip in place.
- Multiple grip drawing styles: dots (triangular arrangement), lines, grid,
  or solid triangle.
- Background can either follow the parent colour (`ParentColor = True`, the
  default) or use its own `Color`.
- Two independent offsets, named after the CSS box model:
  `GripMargin` moves the whole control away from the parent corner, while
  `GripPadding` insets the drawn pattern inside the control.
- Resizing respects configurable minimum parent width and height.
- Double buffered painting with `csOpaque`, so the grip redraws cleanly
  during parent resize without flicker or black artefacts.
- In design time the grip is drawn but does not resize the parent.

### Key Properties

| Property          | Default          | Description |
|-------------------|------------------|-------------|
| `Visible`         | `True`           | Shows or hides the grip. |
| `ShowGrip`        | `True`           | Controls drawing of the grip pattern. |
| `GripCorner`      | `gcBottomRight`  | Corner of the parent: `gcBottomRight`, `gcBottomLeft`, `gcTopRight`, or `gcTopLeft`. |
| `GripMargin`      | `0`              | Outer offset - distance between the control and the parent's corner (in pixels). |
| `GripPadding`     | `2`              | Inner offset - distance between the control's edge and the drawn pattern (in pixels). |
| `GripColor`       | `clActiveBorder` | Colour used to draw the grip pattern. |
| `GripStyle`       | `gsDots`         | Drawing style: `gsDots`, `gsLines`, `gsGrid`, or `gsSolid`. |
| `DotSize`         | `2`              | Size of the dots (for `gsDots` and `gsGrid`). |
| `DotSpacing`      | `3`              | Distance between dots. |
| `MinParentWidth`  | `100`            | Minimum parent width allowed during resizing. |
| `MinParentHeight` | `100`            | Minimum parent height allowed during resizing. |
| `ParentColor`     | `True`           | When `True`, background follows `Parent.Color`; otherwise uses `Color`. |
| `Color`           | `clBtnFace`      | Background colour used when `ParentColor` is `False`. |
| `Width`, `Height` | `16`, `16`       | Size of the grip control in pixels. |

### Usage

1. Drop a `TFormGrip` component from the **Common Controls** palette onto a
   form or a panel.
2. Choose the desired corner using `GripCorner` and adjust the remaining
   properties in the Object Inspector.
3. At runtime the grip appears in the selected corner and resizes its parent
   when dragged.

Example code to create and configure `TFormGrip` at runtime:

```pascal
var
  Grip: TFormGrip;
begin
  Grip := TFormGrip.Create(Self); // Self is the parent control
  Grip.Parent := Self;
  Grip.GripCorner := gcBottomRight;
  Grip.GripStyle := gsLines;
  Grip.GripColor := clGray;
  Grip.GripMargin := 0;
  Grip.GripPadding := 3;
  Grip.Width := 16;
  Grip.Height := 16;
end;
```

### Class hierarchy

The component is split into two classes following the standard Lazarus
convention:

- `TCustomFormGrip` - base class that implements all behaviour. Inherit
  from it to create custom variants with your own published properties.
- `TFormGrip` - ready-to-use component that publishes the most useful
  properties of `TCustomFormGrip` and of the inherited `TControl`.

---

## TFlatButton (Common Controls ![flatbutton](img/TFlatButton.png))

`TFlatButton` is a custom `TSpeedButton` descendant that always draws a flat, themed button (similar to toolbar buttons) and provides integrated tooltip support with extensive customisation.

### Features

- Always flat (inherited `Flat` property is hidden and forced to `True`).
- Uses the native theme (via `ThemeServices`) for normal, hot, and pressed states.
- Can optionally disable the pressed state drawing (`DrawPressed`).
- Allows vertical offset of the caption relative to the icon (`OffsetY`).
- Built‑in tooltip system with delay, size, colour, and auto‑hide duration.
- Tooltips are displayed using `TOneShotTooltip` and automatically hide when the button is clicked or the tooltip is dismissed.

### Key Properties

| Property            | Default     | Description |
|---------------------|-------------|-------------|
| `DrawPressed`       | `True`      | If `False`, the button never appears pressed (visual state is always normal or hot). |
| `OffsetY`           | `0`         | Vertical pixel offset for the caption relative to the centre of the icon (positive moves text down). |
| `Tooltip`           | `''`        | The tooltip text to display (translatable caption). |
| `TooltipDelay`      | `0`         | Delay in milliseconds before the tooltip appears after a click (0 = immediate). |
| `TooltipWidth`      | `0`         | Width of the tooltip window (0 = auto‑size). |
| `TooltipHeight`     | `0`         | Height of the tooltip window (0 = auto‑size). |
| `TooltipColor`      | `clDefault` | Background colour of the tooltip (`clDefault` uses system default). |
| `TooltipDuration`   | `0`         | Time in milliseconds after which the tooltip auto‑hides (0 = no auto‑hide). |

### Usage

Place a `TFlatButton` on a form, set an `Images` or `Glyph` for the icon, adjust `Caption`, and configure the tooltip properties.

Example:

```pascal
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(Self);
  Btn.Parent := Self;
  Btn.Caption := 'Save';
  Btn.ImageIndex := 0; // assume an ImageList assigned
  Btn.Tooltip := 'Save the current document';
  Btn.TooltipDelay := 500;
  Btn.TooltipDuration := 3000;
  Btn.OffsetY := 2; // move text slightly down
end;
```

---

## Installation

1. Open the package file (`designkit.lpk`) in Lazarus.
2. Click **Use** → **Install**.
3. Rebuild the IDE.

The components will appear on the **Common Controls** tab of the component palette.

## Licensing

DesignKit as a whole is distributed under the **MIT License** - see
[LICENSE](LICENSE).

The module `src/calendarlite.pas` and the resource
`src/calendarlite_icon.res` are third-party code from the Lazarus CCR
`TCalendarLite` component and are distributed under the **Modified LGPL
(with linking exception)**, the same license as the Lazarus LCL:

- Linking exception: [LICENSE.CalendarLite.txt](LICENSE.CalendarLite.txt)
- Full LGPL v2 text: [COPYING.LGPL.txt](COPYING.LGPL.txt)
- Original authors' notice: [README.CalendarLite.txt](README.CalendarLite.txt)

The linking exception permits using these files together with
MIT-licensed code without affecting the licensing of the rest of
DesignKit.

---

*DesignKit Package © 2026 by Alexander Tverskoy*  
*Licensed under the MIT License – see the individual source files for details.*