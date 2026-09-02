# DesignKit Package

DesignKit is a Lazarus package that provides a set of visual and non‑visual components to enhance application UI design.

## TFormGrip Component (Common controls ![formgrip](img/TFormGrip.png))

`TFormGrip` is a non-visual component for Lazarus that paints a size grip in the bottom-right corner of its owner form. It allows the user to resize the form by dragging the grip, similar to the grip found in a `StatusBar`.

### Features

- Automatically hooks into the owner form's events for painting and mouse handling.
- Works at runtime; in design time it only draws the grip but does not interfere with the form designer.
- Multiple grip drawing styles: dots (triangular arrangement), lines, grid, or solid triangle.
- Customizable size, margin, color, dot size, spacing, and minimum form dimensions.

### Key Properties

| Property        | Default        | Description |
|-----------------|----------------|-------------|
| `Enabled`       | `True`         | Enables or disables the component. |
| `Active`        | `True`         | Allows resizing when `True`; when `False` the grip is drawn but not interactive. |
| `ShowGrip`      | `True`         | Controls visibility of the grip. |
| `GripSize`      | `10`           | Size of the grip area in pixels. |
| `GripMargin`    | `2`            | Offset from the right and bottom edges of the form. |
| `GripColor`     | `clActiveBorder` | Color used to draw the grip. |
| `GripStyle`     | `gsDots`       | Drawing style: `gsDots`, `gsLines`, `gsGrid`, or `gsSolid`. |
| `DotSize`       | `2`            | Diameter of the dots (for `gsDots` and `gsGrid`). |
| `DotSpacing`    | `3`            | Distance between dots. |
| `MinFormWidth`  | `100`          | Minimum width allowed during resizing. |
| `MinFormHeight` | `100`          | Minimum height allowed during resizing. |

### Usage

1. Drop a `TFormGrip` component onto a form from the component palette.
2. Adjust the properties as needed in the Object Inspector.
3. The grip will appear automatically in the bottom-right corner of the form and allow resizing at runtime.

Example code to create and configure `TFormGrip` at runtime:

```pascal
var
  Grip: TFormGrip;
begin
  Grip := TFormGrip.Create(Self); // Self is the form
  Grip.GripStyle := gsLines;
  Grip.GripColor := clGray;
  Grip.GripMargin := 3;
  Grip.Enabled := True;
end;
```