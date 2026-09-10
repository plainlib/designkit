//-----------------------------------------------------------------------------------
//  DesignKit Package © 2026 by Alexander Tverskoy
//  Licensed under the MIT License
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//-----------------------------------------------------------------------------------

unit FormGrip;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics, LCLIntf, LCLType, LMessages, Types;

type
  // Style of grip drawing
  TGripStyle = (gsDots, gsLines, gsGrid, gsSolid);

  // Corner of the parent where the grip is placed
  TGripCorner = (gcBottomRight, gcBottomLeft, gcTopRight, gcTopLeft);

  // Base class for a size grip control. Draws a grip in the selected
  // corner of its parent and resizes the parent by dragging that grip.
  TCustomFormGrip = class(TCustomControl)
  private
    FShowGrip: boolean;
    FGripCorner: TGripCorner;
    FGripMargin: integer;
    FGripColor: TColor;
    FDotSize: integer;
    FDotSpacing: integer;
    FGripStyle: TGripStyle;
    FMinParentWidth: integer;
    FMinParentHeight: integer;
    FDragging: boolean;
    FUpdating: boolean;
    FStartMouse: TPoint;
    FStartWidth: integer;
    FStartHeight: integer;
    FStartParentLeft: integer;
    FStartParentTop: integer;

    procedure SetShowGrip(Value: boolean);
    procedure SetGripCorner(Value: TGripCorner);
    procedure SetGripMargin(Value: integer);
    procedure SetGripColor(Value: TColor);
    procedure SetDotSize(Value: integer);
    procedure SetDotSpacing(Value: integer);
    procedure SetGripStyle(Value: TGripStyle);
    procedure SetMinParentWidth(Value: integer);
    procedure SetMinParentHeight(Value: integer);

    procedure UpdatePosition;
    procedure DrawGrip;
    procedure DrawDots;
    procedure DrawLines;
    procedure DrawGrid;
    procedure DrawSolid;
  protected
    procedure Loaded; override;
    procedure SetParent(NewParent: TWinControl); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure WMEraseBkgnd(var Message: TLMEraseBkgnd); message LM_ERASEBKGND;

    property ShowGrip: boolean read FShowGrip write SetShowGrip default True;
    property GripCorner: TGripCorner read FGripCorner write SetGripCorner default gcBottomRight;
    property GripMargin: integer read FGripMargin write SetGripMargin default 2;
    property GripColor: TColor read FGripColor write SetGripColor default clActiveBorder;
    property GripStyle: TGripStyle read FGripStyle write SetGripStyle default gsDots;
    property DotSize: integer read FDotSize write SetDotSize default 2;
    property DotSpacing: integer read FDotSpacing write SetDotSpacing default 3;
    property MinParentWidth: integer read FMinParentWidth write SetMinParentWidth default 100;
    property MinParentHeight: integer read FMinParentHeight write SetMinParentHeight default 100;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: integer); override;
  end;

  // Published size grip component ready to be placed on a form or panel.
  TFormGrip = class(TCustomFormGrip)
  published
    property ShowGrip;
    property GripCorner;
    property GripMargin;
    property GripColor;
    property GripStyle;
    property DotSize;
    property DotSpacing;
    property MinParentWidth;
    property MinParentHeight;
    property Anchors;
    property Color;
    property ParentColor;
    property Cursor;
    property Height;
    property Width;
    property Visible;
  end;

implementation

constructor TCustomFormGrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowGrip := True;
  FGripCorner := gcBottomRight;
  FGripMargin := 2;
  FGripColor := clActiveBorder;
  FGripStyle := gsDots;
  FDotSize := 2;
  FDotSpacing := 3;
  FMinParentWidth := 100;
  FMinParentHeight := 100;
  FDragging := False;
  FUpdating := False;
  FStartMouse := Point(0, 0);
  FStartWidth := 0;
  FStartHeight := 0;
  FStartParentLeft := 0;
  FStartParentTop := 0;

  Width := 16;
  Height := 16;
  ParentColor := True;
  Color := clBtnFace;

  // Paint the whole area ourselves, no parent erase, no flicker
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;

  UpdatePosition;
end;

procedure TCustomFormGrip.Loaded;
begin
  inherited Loaded;
  UpdatePosition;
end;

procedure TCustomFormGrip.SetParent(NewParent: TWinControl);
begin
  inherited SetParent(NewParent);
  if not (csLoading in ComponentState) then
  begin
    UpdatePosition;
    if (NewParent <> nil) and not (csDesigning in ComponentState) then
      BringToFront;
  end;
end;

procedure TCustomFormGrip.SetBounds(ALeft, ATop, AWidth, AHeight: integer);
begin
  if FUpdating or (Parent = nil) or (csLoading in ComponentState) then
  begin
    inherited SetBounds(ALeft, ATop, AWidth, AHeight);
    Exit;
  end;

  // Honor the requested size, then force the position back to the corner
  FUpdating := True;
  try
    inherited SetBounds(ALeft, ATop, AWidth, AHeight);
  finally
    FUpdating := False;
  end;
  UpdatePosition;
end;

procedure TCustomFormGrip.WMEraseBkgnd(var Message: TLMEraseBkgnd);
begin
  // Background is fully painted in Paint, no need to erase it here
  Message.Result := 1;
end;

procedure TCustomFormGrip.UpdatePosition;
var
  NewAnchors: TAnchors;
  NewLeft, NewTop: integer;
  NewCursor: TCursor;
begin
  if FUpdating then
    Exit;
  if Parent = nil then
    Exit;

  FUpdating := True;
  try
    case FGripCorner of
      gcBottomRight:
      begin
        NewLeft := Parent.ClientWidth - Width;
        NewTop := Parent.ClientHeight - Height;
        NewCursor := crSizeNWSE;
        NewAnchors := [akRight, akBottom];
      end;
      gcBottomLeft:
      begin
        NewLeft := 0;
        NewTop := Parent.ClientHeight - Height;
        NewCursor := crSizeNESW;
        NewAnchors := [akLeft, akBottom];
      end;
      gcTopRight:
      begin
        NewLeft := Parent.ClientWidth - Width;
        NewTop := 0;
        NewCursor := crSizeNESW;
        NewAnchors := [akRight, akTop];
      end;
      gcTopLeft:
      begin
        NewLeft := 0;
        NewTop := 0;
        NewCursor := crSizeNWSE;
        NewAnchors := [akLeft, akTop];
      end;
    end;

    if NewLeft < 0 then
      NewLeft := 0;
    if NewTop < 0 then
      NewTop := 0;

    Anchors := NewAnchors;
    Cursor := NewCursor;
    SetBounds(NewLeft, NewTop, Width, Height);
  finally
    FUpdating := False;
  end;
end;

procedure TCustomFormGrip.SetShowGrip(Value: boolean);
begin
  if FShowGrip <> Value then
  begin
    FShowGrip := Value;
    Invalidate;
  end;
end;

procedure TCustomFormGrip.SetGripCorner(Value: TGripCorner);
begin
  if FGripCorner <> Value then
  begin
    FGripCorner := Value;
    UpdatePosition;
    Invalidate;
  end;
end;

procedure TCustomFormGrip.SetGripMargin(Value: integer);
begin
  if Value < 0 then
    Value := 0;
  if FGripMargin <> Value then
  begin
    FGripMargin := Value;
    Invalidate;
  end;
end;

procedure TCustomFormGrip.SetGripColor(Value: TColor);
begin
  if FGripColor <> Value then
  begin
    FGripColor := Value;
    Invalidate;
  end;
end;

procedure TCustomFormGrip.SetDotSize(Value: integer);
begin
  if Value < 1 then
    Value := 1;
  if FDotSize <> Value then
  begin
    FDotSize := Value;
    Invalidate;
  end;
end;

procedure TCustomFormGrip.SetDotSpacing(Value: integer);
begin
  if Value < 2 then
    Value := 2;
  if FDotSpacing <> Value then
  begin
    FDotSpacing := Value;
    Invalidate;
  end;
end;

procedure TCustomFormGrip.SetGripStyle(Value: TGripStyle);
begin
  if FGripStyle <> Value then
  begin
    FGripStyle := Value;
    Invalidate;
  end;
end;

procedure TCustomFormGrip.SetMinParentWidth(Value: integer);
begin
  if Value < 1 then
    Value := 1;
  FMinParentWidth := Value;
end;

procedure TCustomFormGrip.SetMinParentHeight(Value: integer);
begin
  if Value < 1 then
    Value := 1;
  FMinParentHeight := Value;
end;

procedure TCustomFormGrip.DrawDots;
var
  i, j: integer;
  x, y: integer;
  Count: integer;
  W, H, L, R, T, B: integer;
begin
  L := FGripMargin;
  T := FGripMargin;
  R := ClientWidth - FGripMargin;
  B := ClientHeight - FGripMargin;
  W := R - L;
  H := B - T;
  if (W < FDotSize) or (H < FDotSize) then
    Exit;

  Count := (W - FDotSize) div FDotSpacing + 1;
  if ((H - FDotSize) div FDotSpacing + 1) < Count then
    Count := (H - FDotSize) div FDotSpacing + 1;
  if Count < 1 then
    Exit;

  for i := 0 to Count - 1 do
  begin
    case FGripCorner of
      gcBottomRight:
      begin
        y := B - FDotSize - i * FDotSpacing;
        for j := 0 to (Count - 1 - i) do
        begin
          x := R - FDotSize - j * FDotSpacing;
          Canvas.Rectangle(x, y, x + FDotSize, y + FDotSize);
        end;
      end;
      gcBottomLeft:
      begin
        y := B - FDotSize - i * FDotSpacing;
        for j := 0 to (Count - 1 - i) do
        begin
          x := L + j * FDotSpacing;
          Canvas.Rectangle(x, y, x + FDotSize, y + FDotSize);
        end;
      end;
      gcTopRight:
      begin
        y := T + i * FDotSpacing;
        for j := 0 to (Count - 1 - i) do
        begin
          x := R - FDotSize - j * FDotSpacing;
          Canvas.Rectangle(x, y, x + FDotSize, y + FDotSize);
        end;
      end;
      gcTopLeft:
      begin
        y := T + i * FDotSpacing;
        for j := 0 to (Count - 1 - i) do
        begin
          x := L + j * FDotSpacing;
          Canvas.Rectangle(x, y, x + FDotSize, y + FDotSize);
        end;
      end;
    end;
  end;
end;

procedure TCustomFormGrip.DrawLines;
var
  i, d, L2: integer;
  Count: integer;
  W, H, Lft, R, T, B: integer;
begin
  L2 := 3;
  Lft := FGripMargin;
  T := FGripMargin;
  R := ClientWidth - FGripMargin;
  B := ClientHeight - FGripMargin;
  W := R - Lft;
  H := B - T;

  Count := W div L2;
  if (H div L2) < Count then
    Count := H div L2;
  if Count < 1 then
    Exit;

  for i := 0 to Count - 1 do
  begin
    d := (i + 1) * L2;
    case FGripCorner of
      gcBottomRight:
        Canvas.Line(R - d, B, R, B - d);
      gcBottomLeft:
        Canvas.Line(Lft + d, B, Lft, B - d);
      gcTopRight:
        Canvas.Line(R - d, T, R, T + d);
      gcTopLeft:
        Canvas.Line(Lft + d, T, Lft, T + d);
    end;
  end;
end;

procedure TCustomFormGrip.DrawGrid;
var
  x, y: integer;
  Lft, T, R, B: integer;
begin
  Lft := FGripMargin;
  T := FGripMargin;
  R := ClientWidth - FGripMargin;
  B := ClientHeight - FGripMargin;

  y := T;
  while y + FDotSize <= B do
  begin
    x := Lft;
    while x + FDotSize <= R do
    begin
      Canvas.Rectangle(x, y, x + FDotSize, y + FDotSize);
      Inc(x, FDotSpacing);
    end;
    Inc(y, FDotSpacing);
  end;
end;

procedure TCustomFormGrip.DrawSolid;
var
  Lft, T, R, B: integer;
begin
  Lft := FGripMargin;
  T := FGripMargin;
  R := ClientWidth - FGripMargin;
  B := ClientHeight - FGripMargin;

  Canvas.Pen.Style := psClear;
  case FGripCorner of
    gcBottomRight:
      Canvas.Polygon([Point(R, T), Point(R, B), Point(Lft, B)]);
    gcBottomLeft:
      Canvas.Polygon([Point(Lft, T), Point(R, B), Point(Lft, B)]);
    gcTopRight:
      Canvas.Polygon([Point(R, T), Point(R, B), Point(Lft, T)]);
    gcTopLeft:
      Canvas.Polygon([Point(Lft, T), Point(R, T), Point(Lft, B)]);
  end;
  Canvas.Pen.Style := psSolid;
end;

procedure TCustomFormGrip.DrawGrip;
begin
  Canvas.Pen.Color := FGripColor;
  Canvas.Brush.Color := FGripColor;
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;

  case FGripStyle of
    gsDots: DrawDots;
    gsLines: DrawLines;
    gsGrid: DrawGrid;
    gsSolid: DrawSolid;
  end;
end;

procedure TCustomFormGrip.Paint;
var
  bg: TColor;
begin
  if ParentColor and (Parent <> nil) then
    bg := Parent.Color
  else
    bg := Color;

  Canvas.Brush.Color := bg;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);

  if FShowGrip then
    DrawGrip;
end;

procedure TCustomFormGrip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if csDesigning in ComponentState then
    Exit;
  if (Button = mbLeft) and (Parent <> nil) then
  begin
    FDragging := True;
    FStartMouse := Mouse.CursorPos;
    FStartWidth := Parent.Width;
    FStartHeight := Parent.Height;
    FStartParentLeft := Parent.Left;
    FStartParentTop := Parent.Top;
    BringToFront;
    SetCapture(Handle);
  end;
end;

procedure TCustomFormGrip.MouseMove(Shift: TShiftState; X, Y: integer);
var
  P: TPoint;
  dx, dy: integer;
  NewWidth, NewHeight: integer;
  NewLeft, NewTop: integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging or (Parent = nil) then
    Exit;
  P := Mouse.CursorPos;
  dx := P.X - FStartMouse.X;
  dy := P.Y - FStartMouse.Y;

  NewWidth := FStartWidth;
  NewHeight := FStartHeight;
  NewLeft := FStartParentLeft;
  NewTop := FStartParentTop;

  case FGripCorner of
    gcBottomRight:
    begin
      NewWidth := FStartWidth + dx;
      NewHeight := FStartHeight + dy;
    end;
    gcBottomLeft:
    begin
      NewWidth := FStartWidth - dx;
      NewHeight := FStartHeight + dy;
      NewLeft := FStartParentLeft + dx;
    end;
    gcTopRight:
    begin
      NewWidth := FStartWidth + dx;
      NewHeight := FStartHeight - dy;
      NewTop := FStartParentTop + dy;
    end;
    gcTopLeft:
    begin
      NewWidth := FStartWidth - dx;
      NewHeight := FStartHeight - dy;
      NewLeft := FStartParentLeft + dx;
      NewTop := FStartParentTop + dy;
    end;
  end;

  if NewWidth < FMinParentWidth then
  begin
    if (FGripCorner = gcBottomLeft) or (FGripCorner = gcTopLeft) then
      NewLeft := FStartParentLeft + (FStartWidth - FMinParentWidth);
    NewWidth := FMinParentWidth;
  end;
  if NewHeight < FMinParentHeight then
  begin
    if (FGripCorner = gcTopLeft) or (FGripCorner = gcTopRight) then
      NewTop := FStartParentTop + (FStartHeight - FMinParentHeight);
    NewHeight := FMinParentHeight;
  end;

  Parent.SetBounds(NewLeft, NewTop, NewWidth, NewHeight);
  Parent.Update;
end;

procedure TCustomFormGrip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragging then
  begin
    FDragging := False;
    ReleaseCapture;
  end;
end;

end.
