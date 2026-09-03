unit FlatButton;

{$mode ObjFPC}{$H+}

interface

uses
  Forms, Classes, SysUtils, Controls, Buttons, Graphics, Themes, LCLType, Types,
  ExtCtrls, OneShotTooltip;

type
  TFlatButton = class(TSpeedButton)
  private
    FFlat: boolean;                         // Always True, used to hide Flat property
    FOffsetY: integer;
    FDrawPressed: boolean;                  // Controls whether pressed state is drawn
    FIsPressed: boolean;                    // Track mouse press state
    FTooltip: TCaption;                     // Tooltip text (translatable)
    FTooltipDelay: integer;                 // Delay before showing tooltip (ms)
    FTooltipWidth: integer;                 // Tooltip width (0 = auto)
    FTooltipHeight: integer;                // Tooltip height (0 = auto)
    FTooltipColor: TColor;                  // Tooltip background color
    FTooltipDuration: integer;              // Tooltip auto-hide duration (ms, 0 = no auto-hide)
    FTooltipTimer: TTimer;                  // Timer for delayed tooltip
    FTooltipActive: boolean;                // Is tooltip currently visible or scheduled
    FTooltipInstance: TOneShotTooltip;      // Active tooltip instance
    procedure SetOffsetY(AValue: integer);
    procedure SetDrawPressed(AValue: boolean);
    procedure SetTooltip(const AValue: TCaption);
    procedure SetTooltipDelay(AValue: integer);
    procedure SetTooltipWidth(AValue: integer);
    procedure SetTooltipHeight(AValue: integer);
    procedure SetTooltipColor(AValue: TColor);
    procedure SetTooltipDuration(AValue: integer);
    procedure TooltipTimerHandler(Sender: TObject);
    procedure ShowTooltip;
    procedure TooltipHidden(Sender: TObject);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    // Hide the inherited Flat property by making it read-only and always True
    property Flat: boolean read FFlat default True;
    // Enable/disable drawing of the pressed state (if False, the button never appears pressed)
    property DrawPressed: boolean read FDrawPressed write SetDrawPressed default True;
    // Vertical offset for the caption relative to the icon center (0 = default centered)
    property OffsetY: integer read FOffsetY write SetOffsetY default 0;
    // Tooltip settings
    property Tooltip: TCaption read FTooltip write SetTooltip;
    property TooltipDelay: integer read FTooltipDelay write SetTooltipDelay default 0;
    property TooltipWidth: integer read FTooltipWidth write SetTooltipWidth default 0;
    property TooltipHeight: integer read FTooltipHeight write SetTooltipHeight default 0;
    property TooltipColor: TColor read FTooltipColor write SetTooltipColor default clDefault;
    property TooltipDuration: integer read FTooltipDuration write SetTooltipDuration default 0;
  end;

implementation

constructor TFlatButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFlat := True;
  FOffsetY := 0;
  FDrawPressed := True;
  FIsPressed := False;
  FTooltip := '';
  FTooltipDelay := 0;
  FTooltipWidth := 0;
  FTooltipHeight := 0;
  FTooltipColor := clDefault;
  FTooltipDuration := 0;
  FTooltipTimer := TTimer.Create(Self);
  FTooltipTimer.Enabled := False;
  FTooltipTimer.OnTimer := @TooltipTimerHandler;
  FTooltipActive := False;
  FTooltipInstance := nil;
  inherited Flat := True;
end;

destructor TFlatButton.Destroy;
var
  OldTip: TOneShotTooltip;
begin
  FTooltipTimer.Free;
  OldTip := FTooltipInstance;
  FTooltipInstance := nil;
  if Assigned(OldTip) then
  begin
    OldTip.OnHide := nil;   // disconnect handler to avoid callbacks on destroyed button
    OldTip.Hide;            // hide and auto-free if needed
  end;
  inherited Destroy;
end;

procedure TFlatButton.SetOffsetY(AValue: integer);
begin
  if FOffsetY = AValue then Exit;
  FOffsetY := AValue;
  Invalidate;
end;

procedure TFlatButton.SetDrawPressed(AValue: boolean);
begin
  if FDrawPressed = AValue then Exit;
  FDrawPressed := AValue;
  Invalidate;
end;

procedure TFlatButton.SetTooltip(const AValue: TCaption);
begin
  if FTooltip = AValue then Exit;
  FTooltip := AValue;
end;

procedure TFlatButton.SetTooltipDelay(AValue: integer);
begin
  if FTooltipDelay = AValue then Exit;
  FTooltipDelay := AValue;
end;

procedure TFlatButton.SetTooltipWidth(AValue: integer);
begin
  if FTooltipWidth = AValue then Exit;
  FTooltipWidth := AValue;
end;

procedure TFlatButton.SetTooltipHeight(AValue: integer);
begin
  if FTooltipHeight = AValue then Exit;
  FTooltipHeight := AValue;
end;

procedure TFlatButton.SetTooltipColor(AValue: TColor);
begin
  if FTooltipColor = AValue then Exit;
  FTooltipColor := AValue;
end;

procedure TFlatButton.SetTooltipDuration(AValue: integer);
begin
  if FTooltipDuration = AValue then Exit;
  FTooltipDuration := AValue;
end;

procedure TFlatButton.TooltipTimerHandler(Sender: TObject);
begin
  FTooltipTimer.Enabled := False;
  ShowTooltip;
end;

procedure TFlatButton.ShowTooltip;
var
  MousePos: TPoint;
  tipX, tipY: integer;
  NewTip: TOneShotTooltip;
begin
  if FTooltip = '' then Exit;

  // Hide previous tooltip if any
  if Assigned(FTooltipInstance) then
    FTooltipInstance.Hide;

  MousePos := Mouse.CursorPos;
  tipX := MousePos.X + 15;
  tipY := MousePos.Y + 15;

  NewTip := TOneShotTooltip.Create(Application);
  NewTip.AutoFree := True;
  NewTip.OnHide := @TooltipHidden;
  FTooltipInstance := NewTip;
  FTooltipActive := True;
  Invalidate; // update button appearance (pressed)

  // Pass Self as owner control so the hint knows not to hide when clicked
  NewTip.ShowHintText(FTooltip, tipX, tipY, FTooltipWidth, FTooltipHeight, FTooltipDuration, FTooltipColor, Self);
end;

procedure TFlatButton.TooltipHidden(Sender: TObject);
begin
  FTooltipActive := False;
  FTooltipInstance := nil;
  Invalidate;
end;

procedure TFlatButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);

  if (Button = mbLeft) and FDrawPressed then
  begin
    FIsPressed := True;
    Invalidate;
  end;
end;

procedure TFlatButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);

  if Button <> mbLeft then Exit;

  if FDrawPressed then
  begin
    FIsPressed := False;
    Invalidate;
  end;

  // If tooltip is active (visible or scheduled), just hide it and do not show again
  if FTooltipActive then
  begin
    if Assigned(FTooltipInstance) then
      FTooltipInstance.Hide;  // triggers TooltipHidden and resets flags
    Exit;
  end;

  // No tooltip active, so show it (with delay if configured)
  if FTooltip = '' then Exit;

  FTooltipTimer.Enabled := False;

  if FTooltipDelay > 0 then
  begin
    FTooltipTimer.Interval := FTooltipDelay;
    FTooltipTimer.Enabled := True;
  end
  else
    ShowTooltip;
end;

procedure TFlatButton.Paint;
var
  r: TRect;
  xIcon, yIcon, xText: integer;
  ts: TTextStyle;
  Details: TThemedElementDetails;
  imgW, imgH: integer;
  textWidth, totalWidth, xStart: integer;
  gap: integer;
begin
  gap := 4;
  // Toolbar theme elements give the native flat look
  if FDrawPressed and (Down or FIsPressed or FTooltipActive) then
    Details := ThemeServices.GetElementDetails(ttbButtonPressed)
  else if MouseInClient then
    Details := ThemeServices.GetElementDetails(ttbButtonHot)
  else
    Details := ThemeServices.GetElementDetails(ttbButtonNormal);

  ThemeServices.DrawElement(Canvas.Handle, Details, ClientRect);

  // Determine icon dimensions from ImageList or Glyph
  if (ImageIndex >= 0) and (Images <> nil) then
  begin
    imgW := Images.Width;
    imgH := Images.Height;
  end
  else if (Glyph <> nil) and (not Glyph.Empty) then
  begin
    imgW := Glyph.Width;
    imgH := Glyph.Height;
  end
  else
  begin
    imgW := 0;
    imgH := 0;
  end;

  // Calculate total content width
  Canvas.Font.Assign(Font);
  textWidth := Canvas.TextWidth(Caption);
  if imgW > 0 then
    totalWidth := imgW + gap + textWidth
  else
    totalWidth := textWidth;

  // Horizontal alignment of the whole icon+text block
  case Alignment of
    taRightJustify: xStart := ClientWidth - totalWidth - gap;
    taCenter:
    begin
      xStart := (ClientWidth - totalWidth) div 2;
      if xStart < gap then xStart := gap;
    end;
    else
      xStart := gap;
  end;

  // Draw the icon vertically centered
  if imgW > 0 then
  begin
    xIcon := xStart;
    yIcon := (ClientHeight - imgH) div 2;
    if (ImageIndex >= 0) and (Images <> nil) then
      Images.Draw(Canvas, xIcon, yIcon, ImageIndex, Enabled)
    else if (Glyph <> nil) and (not Glyph.Empty) then
      Canvas.Draw(xIcon, yIcon, Glyph);
    xText := xIcon + imgW + gap;
  end
  else
    xText := xStart;

  // Caption rectangle shifted vertically by OffsetY
  case Alignment of
    taRightJustify: r := Rect(xText, FOffsetY, ClientWidth - gap, ClientHeight + FOffsetY);
    taCenter: r := Rect(xText, FOffsetY, ClientWidth - xStart, ClientHeight + FOffsetY);
    else
      r := Rect(xText, FOffsetY, ClientWidth - gap, ClientHeight + FOffsetY);
  end;

  // Draw caption centered vertically inside the shifted rectangle
  ts := Canvas.TextStyle;
  ts.Alignment := taLeftJustify;
  ts.Layout := tlCenter;
  Canvas.TextRect(r, r.Left, r.Top, Caption, ts);
end;

end.
