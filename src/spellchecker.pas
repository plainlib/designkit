//-----------------------------------------------------------------------------------
//  SpellChecker Component © 2026 by Alexander Tverskoy
//  Licensed under the MIT License
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//-----------------------------------------------------------------------------------
//  Non-visual component for spell checking a TRichMemo using Windows Spell Checker.
//  Handles background checking, debounced real-time updates, cancellation,
//  automatic context menu with suggestions, and re-check after replacement.
//  Optimized to avoid redundant repaints during replacement.
//-----------------------------------------------------------------------------------

unit SpellChecker;

{$mode objfpc}{$H+}

interface

uses
  Controls, Classes, SysUtils, ExtCtrls, Menus, RichMemo, RichSpellChecker, SpellUtils,
  {$IFDEF WINDOWS}
  WinSpellChecker,
  {$ENDIF}
  OneShotThread, OneShotTimer;

type
  // Event fired after spell check results have been applied to the RichMemo
  TSpellCheckCompleteEvent = procedure(Sender: TObject; ErrorCount: integer) of object;
  // Event fired when context menu is about to be shown (before our automatic handling)
  TSpellContextPopupEvent = procedure(Sender: TObject; MousePos: TPoint; var Handled: boolean) of object;

  TSpellChecker = class(TComponent)
  private
    FRichMemo: TRichMemo;
    FLanguage: string;
    FEnabled: boolean;
    FOptions: TSpellCheckOptions;
    FAddEmptySuggestions: boolean;
    FRealTime: boolean;
    FCheckDelay: integer;
    FAutoApply: boolean;
    FAutoContextMenu: boolean;
    FOnSpellCheckComplete: TSpellCheckCompleteEvent;
    FOnContextPopup: TSpellContextPopupEvent; // optional user hook

    FSpellChecker: TRichSpellChecker;
    FCheckThread: TThread;
    FChecking: boolean;
    FPendingCheck: boolean;
    FCancelRequested: integer; // 0 = no cancel, 1 = cancel requested
    FCheckText: string;        // Snapshot of text for background check
    FLastErrors: RichSpellChecker.TSpellErrorArray;
    FDebounceTimer: TTimer;
    FPrevContextPopup: TContextPopupEvent; // saved original RichMemo.OnContextPopup
    FPrevOnChange: TNotifyEvent;           // saved original RichMemo.OnChange
    FContextMenuOpen: boolean;             // True while context menu is visible
    FReplaceJustDone: boolean;             // True after replacement to avoid duplicate check

    procedure SetRichMemo(AValue: TRichMemo);
    procedure SetLanguage(const AValue: string);
    procedure SetEnabled(AValue: boolean);
    procedure SetRealTime(AValue: boolean);
    procedure SetCheckDelay(AValue: integer);
    procedure SetOptions(AValue: TSpellCheckOptions);
    procedure SetAutoContextMenu(AValue: boolean);
    procedure UpdateContextMenuHandler;
    procedure OnRichMemoChange(Sender: TObject);
    procedure OnRichMemoContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure DoDebouncedCheck(Sender: TObject);
    procedure DoBackgroundCheck;
    procedure OnBackgroundDone;
    procedure StartCheck;
    procedure ApplyErrors(const AErrors: RichSpellChecker.TSpellErrorArray);
    procedure ClearUnderlines;
    procedure DoSpellCheckNeeded(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Start an immediate spell check (in background)
    procedure CheckNow;
    // Request cancellation of the currently running check (result will be ignored)
    procedure CancelCheck;
    // Clear all existing error underlines
    procedure ClearErrors;
    // Returns True if a check is currently running
    function IsChecking: boolean;
    // Manually show context menu with suggestions at given client coordinates
    function ShowContextMenu(X, Y: integer): boolean;
  published
    // The RichMemo to be checked
    property RichMemo: TRichMemo read FRichMemo write SetRichMemo;
    // BCP-47 language tag, e.g. 'en-US' or 'ru-RU'
    property Language: string read FLanguage write SetLanguage;
    // Enable or disable spell checking
    property Enabled: boolean read FEnabled write SetEnabled default True;
    // Which checks to perform (spelling, comprehensive spelling)
    property Options: TSpellCheckOptions read FOptions write SetOptions default [scoSpelling];
    // Include errors that have no suggestions
    property AddEmptySuggestions: boolean read FAddEmptySuggestions write FAddEmptySuggestions default True;
    // Automatically check after text changes (with debounce)
    property RealTime: boolean read FRealTime write SetRealTime default False;
    // Debounce delay in milliseconds for real-time checks
    property CheckDelay: integer read FCheckDelay write SetCheckDelay default 500;
    // Automatically apply underlines after check completes
    property AutoApply: boolean read FAutoApply write FAutoApply default True;
    // Automatically attach to RichMemo.OnContextPopup to show suggestion menu.
    // When enabled, the component handles context menu and falls back to RichMemo.PopupMenu.
    property AutoContextMenu: boolean read FAutoContextMenu write SetAutoContextMenu default True;
    // Called after a check has finished and (if AutoApply) errors are applied
    property OnSpellCheckComplete: TSpellCheckCompleteEvent read FOnSpellCheckComplete write FOnSpellCheckComplete;
    // Called when context menu is about to be shown (before our automatic handler).
    // Set Handled to True to prevent our handling.
    property OnContextPopup: TSpellContextPopupEvent read FOnContextPopup write FOnContextPopup;
  end;

implementation

{ TSpellChecker }

constructor TSpellChecker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := True;
  FOptions := [scoSpelling];
  FAddEmptySuggestions := True;
  FRealTime := False;
  FCheckDelay := 500;
  FAutoApply := True;
  FAutoContextMenu := True;
  FChecking := False;
  FPendingCheck := False;
  FCancelRequested := 0;
  FCheckThread := nil;
  FSpellChecker := nil;
  FLastErrors := nil;
  FDebounceTimer := nil;
  FPrevContextPopup := nil;
  FPrevOnChange := nil;
  FContextMenuOpen := False;
  FReplaceJustDone := False;
end;

destructor TSpellChecker.Destroy;
begin
  // Cancel any running check and ignore its result
  if FChecking then
  begin
    InterlockedExchange(FCancelRequested, 1);
    FCheckThread := nil;
  end;

  // Restore previous handlers if we replaced them
  if Assigned(FRichMemo) then
  begin
    if Assigned(FPrevContextPopup) then
      FRichMemo.OnContextPopup := FPrevContextPopup;
    if Assigned(FPrevOnChange) then
      FRichMemo.OnChange := FPrevOnChange;
  end;

  // Stop and free debounce timer
  if Assigned(FDebounceTimer) then
  begin
    FDebounceTimer.Enabled := False;
    FreeAndNil(FDebounceTimer);
  end;

  // Free internal spell checker
  if Assigned(FSpellChecker) then
    FreeAndNil(FSpellChecker);

  // Clear error array
  SetLength(FLastErrors, 0);

  inherited Destroy;
end;

procedure TSpellChecker.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  if (Operation = opRemove) and (AComponent = FRichMemo) then
  begin
    if Assigned(FPrevContextPopup) then
      FRichMemo.OnContextPopup := FPrevContextPopup;
    if Assigned(FPrevOnChange) then
      FRichMemo.OnChange := FPrevOnChange;
    FPrevContextPopup := nil;
    FPrevOnChange := nil;

    if Assigned(FSpellChecker) then
    begin
      FreeAndNil(FSpellChecker);
    end;
    FRichMemo := nil;
    if Assigned(FDebounceTimer) then
      FDebounceTimer.Enabled := False;
  end;
end;

procedure TSpellChecker.SetRichMemo(AValue: TRichMemo);
begin
  if FRichMemo = AValue then Exit;

  if Assigned(FRichMemo) then
  begin
    if Assigned(FPrevContextPopup) then
      FRichMemo.OnContextPopup := FPrevContextPopup;
    if Assigned(FPrevOnChange) then
      FRichMemo.OnChange := FPrevOnChange;
    FPrevContextPopup := nil;
    FPrevOnChange := nil;

    if Assigned(FSpellChecker) then
      FreeAndNil(FSpellChecker);
  end;

  FRichMemo := AValue;

  if Assigned(FRichMemo) then
  begin
    FPrevOnChange := FRichMemo.OnChange;
    FRichMemo.OnChange := @OnRichMemoChange;
    FPrevContextPopup := FRichMemo.OnContextPopup;
    FRichMemo.OnContextPopup := @OnRichMemoContextPopup;

    FSpellChecker := TRichSpellChecker.Create(FRichMemo);
    FSpellChecker.OnSpellCheckNeeded := @DoSpellCheckNeeded;

    ClearUnderlines;
  end;
end;

procedure TSpellChecker.SetLanguage(const AValue: string);
begin
  if FLanguage <> AValue then
  begin
    FLanguage := AValue;
    if FEnabled and Assigned(FRichMemo) then
      CheckNow;
  end;
end;

procedure TSpellChecker.SetEnabled(AValue: boolean);
begin
  if FEnabled <> AValue then
  begin
    FEnabled := AValue;
    if FEnabled then
    begin
      if Assigned(FRichMemo) then
        CheckNow;
    end
    else
    begin
      ClearUnderlines;
      CancelCheck;
    end;
  end;
end;

procedure TSpellChecker.SetRealTime(AValue: boolean);
begin
  if FRealTime <> AValue then
  begin
    FRealTime := AValue;
    if FRealTime then
    begin
      if not Assigned(FDebounceTimer) then
      begin
        FDebounceTimer := TTimer.Create(nil);
        FDebounceTimer.Enabled := False;
        FDebounceTimer.OnTimer := @DoDebouncedCheck;
      end;
      if Assigned(FRichMemo) and FEnabled then
        CheckNow;
    end
    else
    begin
      if Assigned(FDebounceTimer) then
      begin
        FDebounceTimer.Enabled := False;
        FreeAndNil(FDebounceTimer);
      end;
    end;
  end;
end;

procedure TSpellChecker.SetCheckDelay(AValue: integer);
begin
  if AValue < 0 then AValue := 0;
  if FCheckDelay <> AValue then
  begin
    FCheckDelay := AValue;
    if Assigned(FDebounceTimer) then
      FDebounceTimer.Interval := FCheckDelay;
  end;
end;

procedure TSpellChecker.SetOptions(AValue: TSpellCheckOptions);
begin
  if FOptions <> AValue then
  begin
    FOptions := AValue;
    if FEnabled and Assigned(FRichMemo) then
      CheckNow;
  end;
end;

procedure TSpellChecker.SetAutoContextMenu(AValue: boolean);
begin
  if FAutoContextMenu <> AValue then
  begin
    FAutoContextMenu := AValue;
    UpdateContextMenuHandler;
  end;
end;

procedure TSpellChecker.UpdateContextMenuHandler;
begin
  if not Assigned(FRichMemo) then Exit;

  if FAutoContextMenu then
  begin
    FPrevContextPopup := FRichMemo.OnContextPopup;
    FRichMemo.OnContextPopup := @OnRichMemoContextPopup;
  end
  else
  begin
    if Assigned(FPrevContextPopup) then
      FRichMemo.OnContextPopup := FPrevContextPopup;
    FPrevContextPopup := nil;
  end;
end;

procedure TSpellChecker.OnRichMemoChange(Sender: TObject);
begin
  if not FRealTime or not FEnabled then Exit;
  if not Assigned(FDebounceTimer) then Exit;

  // If a replacement was just done, we want immediate check, not debounced
  if FReplaceJustDone then
  begin
    FReplaceJustDone := False;
    // Stop any pending debounce timer to prevent duplicate checks
    if Assigned(FDebounceTimer) then
      FDebounceTimer.Enabled := False;
    CheckNow;
    Exit;
  end;

  FDebounceTimer.Enabled := False;
  FDebounceTimer.Interval := FCheckDelay;
  FDebounceTimer.Enabled := True;
end;

procedure TSpellChecker.OnRichMemoContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var
  ScreenPoint: TPoint;
begin
  if Assigned(FOnContextPopup) then
    FOnContextPopup(Sender, MousePos, Handled);

  if Handled then Exit;

  if Assigned(FSpellChecker) then
  begin
    FContextMenuOpen := True;
    try
      CancelCheck; // stop background check to keep error list stable
      if FSpellChecker.ShowContextMenu(MousePos.X, MousePos.Y) then
      begin
        Handled := True;
      end;
    finally
      FContextMenuOpen := False;
      // Do not check here; replacement already triggered check if needed
    end;
    if Handled then Exit;
  end;

  if Assigned(FRichMemo) and Assigned(FRichMemo.PopupMenu) then
  begin
    ScreenPoint := FRichMemo.ClientToScreen(MousePos);
    FRichMemo.PopupMenu.PopUp(ScreenPoint.X, ScreenPoint.Y);
    Handled := True;
    Exit;
  end;

  if Assigned(FPrevContextPopup) then
    FPrevContextPopup(Sender, MousePos, Handled);
end;

procedure TSpellChecker.DoSpellCheckNeeded(Sender: TObject);
begin
  // Called after replacement from context menu
  if FContextMenuOpen then
    Exit; // will be handled after menu closes (but we already prevent duplicate)

  // Mark that a replacement happened; the next OnChange will do immediate check
  FReplaceJustDone := True;

  // Stop debounce timer to avoid extra check
  if Assigned(FDebounceTimer) then
    FDebounceTimer.Enabled := False;

  // Trigger immediate check now (instead of waiting for OnChange)
  if FEnabled and Assigned(FRichMemo) then
    CheckNow;
end;

procedure TSpellChecker.DoDebouncedCheck(Sender: TObject);
begin
  if Assigned(FDebounceTimer) then
    FDebounceTimer.Enabled := False;
  if FEnabled and Assigned(FRichMemo) then
    CheckNow;
end;

procedure TSpellChecker.StartCheck;
begin
  if FContextMenuOpen then
    Exit;

  if FChecking then
  begin
    FPendingCheck := True;
    Exit;
  end;

  InterlockedExchange(FCancelRequested, 0);
  FChecking := True;
  FCheckText := FRichMemo.Text;
  RunAsync(@DoBackgroundCheck, @OnBackgroundDone);
end;

procedure TSpellChecker.CheckNow;
begin
  if not FEnabled or not Assigned(FRichMemo) or not Assigned(FSpellChecker) then
    Exit;
  StartCheck;
end;

procedure TSpellChecker.CancelCheck;
begin
  if FChecking then
  begin
    InterlockedExchange(FCancelRequested, 1);
  end;
  FPendingCheck := False;
end;

procedure TSpellChecker.ClearErrors;
begin
  if Assigned(FSpellChecker) then
    FSpellChecker.Clear;
  SetLength(FLastErrors, 0);
end;

function TSpellChecker.IsChecking: boolean;
begin
  Result := FChecking;
end;

function TSpellChecker.ShowContextMenu(X, Y: integer): boolean;
begin
  Result := False;
  if Assigned(FSpellChecker) then
    Result := FSpellChecker.ShowContextMenu(X, Y);
end;

procedure TSpellChecker.DoBackgroundCheck;
begin
  FLastErrors := TSpell.CheckText(FCheckText, FLanguage, FOptions, FAddEmptySuggestions);
end;

procedure TSpellChecker.OnBackgroundDone;
var
  ErrorCount: integer;
begin
  if InterlockedCompareExchange(FCancelRequested, 0, 0) = 1 then
  begin
    FChecking := False;
    if FPendingCheck then
    begin
      FPendingCheck := False;
      StartCheck;
    end;
    Exit;
  end;

  if not FEnabled or (FRichMemo = nil) or (FSpellChecker = nil) then
  begin
    FChecking := False;
    if FPendingCheck then
    begin
      FPendingCheck := False;
      StartCheck;
    end;
    Exit;
  end;

  if FAutoApply then
  begin
    TSpell.ApplyErrors(FSpellChecker, FLastErrors);
  end;

  ErrorCount := Length(FLastErrors);
  FChecking := False;

  if Assigned(FOnSpellCheckComplete) then
    FOnSpellCheckComplete(Self, ErrorCount);

  if FPendingCheck then
  begin
    FPendingCheck := False;
    StartCheck;
  end;
end;

procedure TSpellChecker.ApplyErrors(const AErrors: RichSpellChecker.TSpellErrorArray);
begin
  if Assigned(FSpellChecker) then
    TSpell.ApplyErrors(FSpellChecker, AErrors);
end;

procedure TSpellChecker.ClearUnderlines;
begin
  if Assigned(FSpellChecker) then
    FSpellChecker.Clear;
end;

end.
