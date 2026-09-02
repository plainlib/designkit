//-----------------------------------------------------------------------------------
//  DesignKit Package © 2026 by Alexander Tverskoy
//  Licensed under the MIT License
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//-----------------------------------------------------------------------------------

unit FormGrip;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics, LCLIntf, LCLType, Types;

type
  // Style of grip drawing
  TGripStyle = (gsDots, gsLines, gsGrid, gsSolid);

  // Non-visual component that paints a size grip in the bottom-right corner
  // of the owner form and allows resizing the form by dragging that grip.
  TFormGrip = class(TComponent)
  private
    FEnabled: boolean;
    FActive: boolean;
    FShowGrip: boolean;
    FGripSize: integer;
    FGripMargin: integer;
    FGripColor: TColor;
    FDotSize: integer;
    FDotSpacing: integer;
    FGripStyle: TGripStyle;
    FMinFormWidth: integer;
    FMinFormHeight: integer;

    FOldOnPaint: TNotifyEvent;
    FOldOnMouseDown: TMouseEvent;
    FOldOnMouseMove: TMouseMoveEvent;
    FOldOnMouseUp: TMouseEvent;
    FOldOnResize: TNotifyEvent;
    FOldOnDestroy: TNotifyEvent;

    FForm: TForm;
    FDragging: boolean;
    FStartPoint: TPoint;
    FStartWidth: integer;
    FStartHeight: integer;
    FPrevCursor: TCursor;
    FPrevComposited: boolean;

    procedure SetEnabled(Value: boolean);
    procedure SetActive(Value: boolean);
    procedure SetShowGrip(Value: boolean);
    procedure SetGripSize(Value: integer);
    procedure SetGripMargin(Value: integer);
    procedure SetGripColor(Value: TColor);
    procedure SetDotSize(Value: integer);
    procedure SetDotSpacing(Value: integer);
    procedure SetGripStyle(Value: TGripStyle);
    procedure SetMinFormWidth(Value: integer);
    procedure SetMinFormHeight(Value: integer);

    procedure HookForm;
    procedure UnhookForm;
    procedure FormPaint(Sender: TObject);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure FormResize(Sender: TObject);
    procedure FormDestroy(Sender: TObject);

    function IsInGripArea(X, Y: integer): boolean;
    procedure DrawGrip(Canvas: TCanvas);
  protected
    procedure Loaded; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Enabled: boolean read FEnabled write SetEnabled default True;
    property Active: boolean read FActive write SetActive default True;
    property ShowGrip: boolean read FShowGrip write SetShowGrip default True;
    property GripSize: integer read FGripSize write SetGripSize default 10;
    property GripMargin: integer read FGripMargin write SetGripMargin default 2;
    property GripColor: TColor read FGripColor write SetGripColor default clActiveBorder;
    property GripStyle: TGripStyle read FGripStyle write SetGripStyle default gsDots;
    property DotSize: integer read FDotSize write SetDotSize default 2;
    property DotSpacing: integer read FDotSpacing write SetDotSpacing default 3;
    property MinFormWidth: integer read FMinFormWidth write SetMinFormWidth default 100;
    property MinFormHeight: integer read FMinFormHeight write SetMinFormHeight default 100;
  end;

implementation

uses controlshelper;

constructor TFormGrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := True;
  FActive := True;
  FShowGrip := True;
  FGripSize := 10;
  FGripMargin := 2;
  FGripColor := clActiveBorder;
  FGripStyle := gsDots;
  FDotSize := 2;
  FDotSpacing := 3;
  FMinFormWidth := 100;
  FMinFormHeight := 100;
  FDragging := False;
  FPrevCursor := crDefault;
  FPrevComposited := False;
end;

destructor TFormGrip.Destroy;
begin
  UnhookForm;
  inherited Destroy;
end;

procedure TFormGrip.Loaded;
begin
  inherited Loaded;
  if FEnabled and (Owner is TForm) then
    HookForm;
end;

procedure TFormGrip.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FForm) then
    UnhookForm;
end;

procedure TFormGrip.SetEnabled(Value: boolean);
begin
  if FEnabled <> Value then
  begin
    FEnabled := Value;
    if FEnabled then
    begin
      if Owner is TForm then
        HookForm;
    end
    else
      UnhookForm;
  end;
end;

procedure TFormGrip.SetActive(Value: boolean);
begin
  if FActive <> Value then
  begin
    FActive := Value;
    if FForm <> nil then
      FForm.Invalidate;
  end;
end;

procedure TFormGrip.SetShowGrip(Value: boolean);
begin
  if FShowGrip <> Value then
  begin
    FShowGrip := Value;
    if FForm <> nil then
      FForm.Invalidate;
  end;
end;

procedure TFormGrip.SetGripSize(Value: integer);
begin
  if FGripSize <> Value then
  begin
    FGripSize := Value;
    if FGripSize < 8 then
      FGripSize := 8;
    if FForm <> nil then
      FForm.Invalidate;
  end;
end;

procedure TFormGrip.SetGripMargin(Value: integer);
begin
  if FGripMargin <> Value then
  begin
    FGripMargin := Value;
    if FGripMargin < 0 then
      FGripMargin := 0;
    if FForm <> nil then
      FForm.Invalidate;
  end;
end;

procedure TFormGrip.SetGripColor(Value: TColor);
begin
  if FGripColor <> Value then
  begin
    FGripColor := Value;
    if FForm <> nil then
      FForm.Invalidate;
  end;
end;

procedure TFormGrip.SetDotSize(Value: integer);
begin
  if FDotSize <> Value then
  begin
    FDotSize := Value;
    if FDotSize < 1 then
      FDotSize := 1;
    if FForm <> nil then
      FForm.Invalidate;
  end;
end;

procedure TFormGrip.SetDotSpacing(Value: integer);
begin
  if FDotSpacing <> Value then
  begin
    FDotSpacing := Value;
    if FDotSpacing < 2 then
      FDotSpacing := 2;
    if FForm <> nil then
      FForm.Invalidate;
  end;
end;

procedure TFormGrip.SetGripStyle(Value: TGripStyle);
begin
  if FGripStyle <> Value then
  begin
    FGripStyle := Value;
    if FForm <> nil then
      FForm.Invalidate;
  end;
end;

procedure TFormGrip.SetMinFormWidth(Value: integer);
begin
  if FMinFormWidth <> Value then
  begin
    FMinFormWidth := Value;
    if FMinFormWidth < 1 then
      FMinFormWidth := 1;
  end;
end;

procedure TFormGrip.SetMinFormHeight(Value: integer);
begin
  if FMinFormHeight <> Value then
  begin
    FMinFormHeight := Value;
    if FMinFormHeight < 1 then
      FMinFormHeight := 1;
  end;
end;

procedure TFormGrip.HookForm;
begin
  if FForm <> nil then
    UnhookForm;
  if Owner is TForm then
  begin
    FForm := TForm(Owner);
    // Save original event handlers
    FOldOnPaint := FForm.OnPaint;
    FOldOnMouseDown := FForm.OnMouseDown;
    FOldOnMouseMove := FForm.OnMouseMove;
    FOldOnMouseUp := FForm.OnMouseUp;
    FOldOnResize := FForm.OnResize;
    FOldOnDestroy := FForm.OnDestroy;
    // Install our handlers
    FForm.OnPaint := @FormPaint;
    FForm.OnMouseDown := @FormMouseDown;
    FForm.OnMouseMove := @FormMouseMove;
    FForm.OnMouseUp := @FormMouseUp;
    FForm.OnResize := @FormResize;
    FForm.OnDestroy := @FormDestroy;
    FForm.Invalidate;
  end;
end;

procedure TFormGrip.UnhookForm;
begin
  if FForm <> nil then
  begin
    // Restore original event handlers
    FForm.OnPaint := FOldOnPaint;
    FForm.OnMouseDown := FOldOnMouseDown;
    FForm.OnMouseMove := FOldOnMouseMove;
    FForm.OnMouseUp := FOldOnMouseUp;
    FForm.OnResize := FOldOnResize;
    FForm.OnDestroy := FOldOnDestroy;
    FForm := nil;
  end;
end;

function TFormGrip.IsInGripArea(X, Y: integer): boolean;
begin
  if FForm = nil then
    Exit(False);
  Result := (X >= FForm.ClientWidth - FGripSize - FGripMargin) and (Y >= FForm.ClientHeight - FGripSize - FGripMargin);
end;

procedure TFormGrip.DrawGrip(Canvas: TCanvas);
var
  i, j: integer;
  x, y: integer;
  Count: integer;
  Right, Bottom: integer;
begin
  if FForm = nil then
    Exit;
  Canvas.Pen.Color := FGripColor;
  Canvas.Brush.Color := FGripColor;

  // Right and bottom bounds of the grip area (excluding margin)
  Right := FForm.ClientWidth - FGripMargin;
  Bottom := FForm.ClientHeight - FGripMargin;

  case FGripStyle of
    gsDots:
    begin
      // Draw a triangular arrangement of dots from the bottom-right corner
      Count := (FGripSize - FDotSize) div FDotSpacing + 1;
      for i := 0 to Count - 1 do
      begin
        y := Bottom - FDotSize - i * FDotSpacing;
        for j := 0 to (Count - i - 1) do
        begin
          x := Right - FDotSize - j * FDotSpacing;
          Canvas.Rectangle(x, y, x + FDotSize, y + FDotSize);
        end;
      end;
    end;

    gsLines:
    begin
      // Draw several diagonal lines
      Canvas.Pen.Width := 1;
      for i := 0 to 3 do
      begin
        x := i * 3;
        Canvas.Line(Right - x, Bottom,
          Right, Bottom - x);
      end;
    end;

    gsGrid:
    begin
      // Draw a grid of dots
      for i := 0 to (FGripSize - FDotSize) div FDotSpacing do
        for j := 0 to (FGripSize - FDotSize) div FDotSpacing do
        begin
          x := Right - FGripSize + j * FDotSpacing;
          y := Bottom - FGripSize + i * FDotSpacing;
          Canvas.Rectangle(x, y, x + FDotSize, y + FDotSize);
        end;
    end;

    gsSolid:
    begin
      // Draw solid triangle
      Canvas.Pen.Style := psClear;
      Canvas.Polygon([Point(Right, Bottom - FGripSize), Point(Right, Bottom),
        Point(Right - FGripSize, Bottom)]);
      Canvas.Pen.Style := psSolid;
    end;
  end;
end;

procedure TFormGrip.FormPaint(Sender: TObject);
begin
  if FEnabled and FShowGrip and (FForm <> nil) then
    DrawGrip(FForm.Canvas);
  // Call original handler if assigned
  if Assigned(FOldOnPaint) then
    FOldOnPaint(Sender);
end;

procedure TFormGrip.FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  if csDesigning in ComponentState then
  begin
    // In design-time just call original handler and do nothing
    if Assigned(FOldOnMouseDown) then
      FOldOnMouseDown(Sender, Button, Shift, X, Y);
    Exit;
  end;

  if FEnabled and FActive and FShowGrip and (Button = mbLeft) and IsInGripArea(X, Y) then
  begin
    FDragging := True;
    FStartPoint := Point(X, Y);
    FStartWidth := FForm.Width;
    FStartHeight := FForm.Height;
    // Save and enable double buffering to reduce flicker
    FPrevComposited := FForm.Composited;
    FForm.Composited := True;
    SetCapture(FForm.Handle);
  end;
  // Call original handler if assigned
  if Assigned(FOldOnMouseDown) then
    FOldOnMouseDown(Sender, Button, Shift, X, Y);
end;

procedure TFormGrip.FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  NewWidth, NewHeight: integer;
begin
  if csDesigning in ComponentState then
  begin
    // In design-time just call original handler and do nothing
    if Assigned(FOldOnMouseMove) then
      FOldOnMouseMove(Sender, Shift, X, Y);
    Exit;
  end;

  if FEnabled and FActive and FShowGrip and (FForm <> nil) then
  begin
    if FDragging then
    begin
      NewWidth := FStartWidth + (X - FStartPoint.X);
      NewHeight := FStartHeight + (Y - FStartPoint.Y);
      if NewWidth < FMinFormWidth then
        NewWidth := FMinFormWidth;
      if NewHeight < FMinFormHeight then
        NewHeight := FMinFormHeight;
      // Use SetBounds for atomic size change, reduces flicker
      FForm.SetBounds(FForm.Left, FForm.Top, NewWidth, NewHeight);
    end
    else if IsInGripArea(X, Y) then
    begin
      if FForm.Cursor <> crSizeNWSE then
      begin
        FPrevCursor := FForm.Cursor;
        FForm.Cursor := crSizeNWSE;
      end;
    end
    else if FForm.Cursor = crSizeNWSE then
    begin
      FForm.Cursor := FPrevCursor;
    end;
  end;
  // Call original handler if assigned
  if Assigned(FOldOnMouseMove) then
    FOldOnMouseMove(Sender, Shift, X, Y);
end;

procedure TFormGrip.FormMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  if csDesigning in ComponentState then
  begin
    // In design-time just call original handler and do nothing
    if Assigned(FOldOnMouseUp) then
      FOldOnMouseUp(Sender, Button, Shift, X, Y);
    Exit;
  end;

  if FDragging then
  begin
    FDragging := False;
    // Restore previous double buffering state
    FForm.Composited := FPrevComposited;
    ReleaseCapture;
  end;
  // Call original handler if assigned
  if Assigned(FOldOnMouseUp) then
    FOldOnMouseUp(Sender, Button, Shift, X, Y);
end;

procedure TFormGrip.FormResize(Sender: TObject);
begin
  // Just call original handler if assigned
  if Assigned(FOldOnResize) then
    FOldOnResize(Sender);
end;

procedure TFormGrip.FormDestroy(Sender: TObject);
begin
  UnhookForm;
  // Call original handler if assigned
  if Assigned(FOldOnDestroy) then
    FOldOnDestroy(Sender);
end;

end.
