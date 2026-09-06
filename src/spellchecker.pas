//-----------------------------------------------------------------------------------
//  SpellChecker Component © 2026 by Alexander Tverskoy
//  Licensed under the MIT License
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//-----------------------------------------------------------------------------------
//  Non-visual component for spell checking a TRichMemo using Windows Spell Checker
//  or HunSpell. Handles background checking, debounced real-time updates, cancellation,
//  automatic context menu with suggestions, and re-check after replacement.
//  Optimized to avoid redundant repaints during replacement.
//-----------------------------------------------------------------------------------

unit SpellChecker;

{$mode objfpc}{$H+}

interface

uses
  Controls,
  Classes,
  SysUtils,
  ExtCtrls,
  Menus,
  LazFileUtils,
  RichMemo,
  RichSpellChecker,
  SpellUtils,
  HunSpellChecker,
  {$IFDEF WINDOWS}
  WinSpellChecker,
  {$ENDIF}
  OneShotThread,
  OneShotTimer,
  Downloader;

type
  // Event fired after spell check results have been applied to the RichMemo
  TSpellCheckCompleteEvent = procedure(Sender: TObject; ErrorCount: integer) of object;
  // Event fired when context menu is about to be shown (before our automatic handling)
  TSpellContextPopupEvent = procedure(Sender: TObject; MousePos: TPoint; var Handled: boolean) of object;

  // Spell engine selection
  TSpellEngine = (seWindows, seHunspell);

  TSpellChecker = class(TComponent)
  private
    FRichMemo: TRichMemo;
    FLanguage: string;
    FEnabled: boolean;
    FDestroying: boolean;
    FOptions: TSpellCheckOptions;
    FAddEmptySuggestions: boolean;
    FRealTime: boolean;
    FCheckDelay: integer;
    FAutoApply: boolean;
    FAutoContextMenu: boolean;
    FOnSpellCheckComplete: TSpellCheckCompleteEvent;
    FOnContextPopup: TSpellContextPopupEvent; // optional user hook
    FEngine: TSpellEngine;
    FHunSpellChecker: THunSpellChecker;
    FHunDictionaryLoaded: boolean; // True when a Hunspell dictionary has been loaded
    FDicPath: string;              // Directory where Hunspell dictionaries are stored
    FDicUrl: string;               // URL template for downloading dictionaries

    FDownloading: boolean;         // True while dictionary download is in progress
    FDownloadLang: string;         // Language for which download was started
    FDownloadCandidate: string;    // The candidate for whom the download was performed

    // Integration with external PopupMenu
    FPopupMenu: TPopupMenu;
    FSubMenu: boolean;
    FSubMenuCaption: string;
    FSubMenuIndex: integer;

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
    procedure SetPopupMenu(AValue: TPopupMenu);
    procedure SetUseSubMenu(AValue: boolean);
    procedure SetSuggestionsCaption(const AValue: string);
    procedure SetSubMenuIndex(AValue: integer);
    procedure SetEngine(AValue: TSpellEngine);
    procedure SetDicPath(const AValue: string);
    procedure SetDicUrl(const AValue: string);
    procedure UpdateContextMenuHandler;
    procedure OnRichMemoChange(Sender: TObject);
    procedure OnRichMemoContextPopup(Sender: TObject; MousePos: TPoint; var Handled: boolean);
    procedure DoDebouncedCheck(Sender: TObject);
    procedure DoBackgroundCheck;
    procedure OnBackgroundDone;
    procedure StartCheck;
    procedure ApplyErrors(const AErrors: RichSpellChecker.TSpellErrorArray);
    procedure ClearUnderlines;
    procedure DoSpellCheckNeeded(Sender: TObject);
    procedure LoadHunDictionaryForLanguage;
    function TryLoadHunDictionary(const AffFile, DicFile: string): boolean;
    procedure StartDictionaryDownload(const LangCode: string);
    function BuildDictURL(const Template, CandidateCode, Ext: string): string;
    function GetLibreOfficePathByCode(const Code: string): string;
    procedure OnDictionaryDownloadComplete(Sender: TObject; AStreams: array of TMemoryStream; AErrors: array of string);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override; // Called after all properties are loaded from .lfm
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
    // Load Hunspell dictionary from files
    procedure LoadHunDictionaryFromFiles(const AFFFileName, DICFileName: string);
    // Load Hunspell dictionary from streams
    procedure LoadHunDictionaryFromStream(AFFStream, DICStream: TStream);
    // Unload Hunspell dictionary (clears checker and underlines if engine is Hunspell)
    procedure UnloadHunDictionary;
  published
    // The RichMemo to be checked
    property RichMemo: TRichMemo read FRichMemo write SetRichMemo;
    // BCP-47 language tag, e.g. 'en-US' or 'ru-RU' (used only by Windows engine)
    property Language: string read FLanguage write SetLanguage;
    // Enable or disable spell checking
    property Enabled: boolean read FEnabled write SetEnabled default True;
    // Which checks to perform (spelling, comprehensive spelling). Windows engine supports both,
    // Hunspell engine only supports scoSpelling (other options are ignored).
    property Options: TSpellCheckOptions read FOptions write SetOptions default [scoSpelling];
    // Include errors that have no suggestions
    property AddEmptySuggestions: boolean read FAddEmptySuggestions write FAddEmptySuggestions default True;
    // Automatically check after text changes (with debounce)
    property RealTime: boolean read FRealTime write SetRealTime default False;
    // Debounce delay in milliseconds for real-time checks
    property CheckDelay: integer read FCheckDelay write SetCheckDelay default 1000;
    // Automatically apply underlines after check completes
    property AutoApply: boolean read FAutoApply write FAutoApply default True;
    // Automatically attach to RichMemo.OnContextPopup to show suggestion menu.
    // When enabled, the component handles context menu and falls back to RichMemo.PopupMenu.
    property AutoContextMenu: boolean read FAutoContextMenu write SetAutoContextMenu default True;

    // External PopupMenu to integrate suggestions into (if nil, use default behavior)
    property PopupMenu: TPopupMenu read FPopupMenu write SetPopupMenu;
    // If True, suggestions are placed in a submenu with caption SuggestionsCaption
    property SubMenu: boolean read FSubMenu write SetUseSubMenu default False;
    // Caption of the submenu when UseSubMenu is True
    property SubMenuCaption: string read FSubMenuCaption write SetSuggestionsCaption;
    // Index where suggestions (or submenu) will be inserted in the PopupMenu
    property SubMenuIndex: integer read FSubMenuIndex write SetSubMenuIndex default 0;

    // Select spell checking engine: Windows (default) or Hunspell
    property Engine: TSpellEngine read FEngine write SetEngine default seWindows;

    // Directory path for Hunspell dictionaries (.aff and .dic). Can be absolute or relative to the application folder.
    property DicPath: string read FDicPath write SetDicPath;
    // URL template for downloading Hunspell dictionaries. Supports placeholders:
    //   {dict}      - replaced by language code (e.g. en_US) and then .aff/.dic appended
    //   {libredict} - replaced by path inside LibreOffice dictionaries repository
    // If empty, no automatic download is performed.
    property DicUrl: string read FDicUrl write SetDicUrl;

    // Called after a check has finished and (if AutoApply) errors are applied
    property OnSpellCheckComplete: TSpellCheckCompleteEvent read FOnSpellCheckComplete write FOnSpellCheckComplete;
    // Called when context menu is about to be shown (before our automatic handler).
    // Set Handled to True to prevent our handling.
    property OnContextPopup: TSpellContextPopupEvent read FOnContextPopup write FOnContextPopup;
  end;

implementation

function IsPathAbsolute(const Path: string): boolean;
begin
  {$IFDEF WINDOWS}
  // Absolute if starts with drive letter and separator (e.g. C:\) or UNC (\\)
  Result := ((Length(Path) >= 3) and (Path[2] = ':') and ((Path[3] = '\') or (Path[3] = '/')))
            or ((Length(Path) >= 2) and (Path[1] = '\') and (Path[2] = '\'));
  {$ELSE}
  Result := (Length(Path) > 0) and (Path[1] = '/');
  {$ENDIF}
end;

{ TSpellChecker }

constructor TSpellChecker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := True;
  FDestroying := False;
  FOptions := [scoSpelling];
  FAddEmptySuggestions := True;
  FRealTime := False;
  FCheckDelay := 1000;
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
  FEngine := seWindows;
  FHunSpellChecker := nil;
  FHunDictionaryLoaded := False;
  FDicPath := '';
  FDicUrl := 'https://raw.githubusercontent.com/LibreOffice/dictionaries/master/{libredict}';
  FDownloading := False;
  FDownloadLang := '';
  FLanguage := ''; // Initialize language to empty

  // Default integration settings
  FPopupMenu := nil;
  FSubMenu := False;
  FSubMenuCaption := 'Suggestions';
  FSubMenuIndex := 0;
end;

destructor TSpellChecker.Destroy;
begin
  // Signal that the component is being destroyed
  FDestroying := True;

  // Cancel any running check and wait for it to finish
  if FChecking then
  begin
    InterlockedExchange(FCancelRequested, 1);
    while FChecking do
    begin
      Sleep(10);
      CheckSynchronize; // Process any pending Synchronize calls (OnBackgroundDone)
    end;
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

  // Free Hunspell checker (safe now because background thread has finished)
  if Assigned(FHunSpellChecker) then
    FreeAndNil(FHunSpellChecker);

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
  end
  else if (Operation = opRemove) and (AComponent = FPopupMenu) then
  begin
    FPopupMenu := nil;
    if Assigned(FSpellChecker) then
      FSpellChecker.PopupMenu := nil; // detach from internal checker
  end;
end;

procedure TSpellChecker.Loaded;
begin
  inherited Loaded;
  if csDesigning in ComponentState then Exit; // Skip in IDE designer
  if FEngine = seHunspell then
    LoadHunDictionaryForLanguage;
  if FEnabled and Assigned(FRichMemo) then
    CheckNow;
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

    // Apply current integration settings to the new internal checker
    FSpellChecker.PopupMenu := FPopupMenu;
    FSpellChecker.SubMenu := FSubMenu;
    FSpellChecker.SubMenuCaption := FSubMenuCaption;
    FSpellChecker.SubMenuIndex := FSubMenuIndex;

    ClearUnderlines;

    // If real-time is enabled and all settings ready, start check immediately
    if FEnabled and FRealTime and not (csDesigning in ComponentState) and not (csLoading in ComponentState) then
      CheckNow;
  end;
end;

procedure TSpellChecker.SetLanguage(const AValue: string);
begin
  if FLanguage = AValue then Exit;
  FLanguage := AValue;
  // Only load dictionary when DicPath is set and engine is Hunspell
  if (FEngine = seHunspell) and (FDicPath <> '') and (FLanguage <> '') and not (csDesigning in ComponentState) and
    not (csLoading in ComponentState) then
    LoadHunDictionaryForLanguage;
  if FEnabled and Assigned(FRichMemo) and not (csLoading in ComponentState) then
    CheckNow;
end;

procedure TSpellChecker.SetEnabled(AValue: boolean);
begin
  if FEnabled <> AValue then
  begin
    FEnabled := AValue;
    if FEnabled then
    begin
      if Assigned(FRichMemo) and not (csLoading in ComponentState) then
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
      if Assigned(FRichMemo) and FEnabled and not (csLoading in ComponentState) then
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
    if FEnabled and Assigned(FRichMemo) and not (csLoading in ComponentState) then
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

procedure TSpellChecker.SetPopupMenu(AValue: TPopupMenu);
begin
  if FPopupMenu <> AValue then
  begin
    FPopupMenu := AValue;
    if Assigned(FSpellChecker) then
      FSpellChecker.PopupMenu := AValue;
  end;
end;

procedure TSpellChecker.SetUseSubMenu(AValue: boolean);
begin
  if FSubMenu <> AValue then
  begin
    FSubMenu := AValue;
    if Assigned(FSpellChecker) then
      FSpellChecker.SubMenu := AValue;
  end;
end;

procedure TSpellChecker.SetSuggestionsCaption(const AValue: string);
begin
  if FSubMenuCaption <> AValue then
  begin
    FSubMenuCaption := AValue;
    if Assigned(FSpellChecker) then
      FSpellChecker.SubMenuCaption := AValue;
  end;
end;

procedure TSpellChecker.SetSubMenuIndex(AValue: integer);
begin
  if FSubMenuIndex <> AValue then
  begin
    FSubMenuIndex := AValue;
    if Assigned(FSpellChecker) then
      FSpellChecker.SubMenuIndex := AValue;
  end;
end;

procedure TSpellChecker.SetEngine(AValue: TSpellEngine);
begin
  if FEngine <> AValue then
  begin
    FEngine := AValue;
    if FEngine = seHunspell then
    begin
      if not Assigned(FHunSpellChecker) then
        FHunSpellChecker := THunSpellChecker.Create;
      // Attempt to load dictionary if possible (unless loading from .lfm)
      if (FDicPath <> '') and (FLanguage <> '') and not (csDesigning in ComponentState) and not (csLoading in ComponentState) then
        LoadHunDictionaryForLanguage;
    end;
    if FEnabled and Assigned(FRichMemo) and not (csLoading in ComponentState) then
      CheckNow;
  end;
end;

procedure TSpellChecker.SetDicPath(const AValue: string);
begin
  if FDicPath <> AValue then
  begin
    FDicPath := AValue;
    if (FEngine = seHunspell) and (FDicPath <> '') and (FLanguage <> '') and not (csDesigning in ComponentState) and
      not (csLoading in ComponentState) then
      LoadHunDictionaryForLanguage;
  end;
end;

procedure TSpellChecker.SetDicUrl(const AValue: string);
begin
  if FDicUrl <> AValue then
  begin
    FDicUrl := AValue;
    // If URL is set and we are in Hunspell mode, we might want to trigger download
    // but only if dictionary not already loaded and language/path set.
    if (FEngine = seHunspell) and (FDicUrl <> '') and (FDicPath <> '') and (FLanguage <> '') and not
      (csDesigning in ComponentState) and not (csLoading in ComponentState) then
      LoadHunDictionaryForLanguage;
  end;
end;

procedure TSpellChecker.LoadHunDictionaryFromFiles(const AFFFileName, DICFileName: string);
begin
  if not Assigned(FHunSpellChecker) then
    FHunSpellChecker := THunSpellChecker.Create;
  FHunDictionaryLoaded := FHunSpellChecker.LoadFromFiles(AFFFileName, DICFileName);
  if FHunDictionaryLoaded and (FEngine = seHunspell) and FEnabled and Assigned(FRichMemo) then
    CheckNow;
end;

procedure TSpellChecker.LoadHunDictionaryFromStream(AFFStream, DICStream: TStream);
begin
  if not Assigned(FHunSpellChecker) then
    FHunSpellChecker := THunSpellChecker.Create;
  FHunDictionaryLoaded := FHunSpellChecker.LoadFromStream(AFFStream, DICStream);
  if FHunDictionaryLoaded and (FEngine = seHunspell) and FEnabled and Assigned(FRichMemo) then
    CheckNow;
end;

procedure TSpellChecker.UnloadHunDictionary;
begin
  if Assigned(FHunSpellChecker) then
  begin
    FreeAndNil(FHunSpellChecker);
    FHunDictionaryLoaded := False;
    if (FEngine = seHunspell) and Assigned(FSpellChecker) then
      ClearUnderlines;
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

procedure TSpellChecker.OnRichMemoContextPopup(Sender: TObject; MousePos: TPoint; var Handled: boolean);
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
  // Do not run checks in design-time or during loading
  if csDesigning in ComponentState then Exit;
  if csLoading in ComponentState then Exit;

  if not FEnabled or not Assigned(FRichMemo) or not Assigned(FSpellChecker) then
    Exit;

  // For Hunspell engine, dictionary must be loaded
  if (FEngine = seHunspell) and ((FHunSpellChecker = nil) or (not FHunDictionaryLoaded)) then
  begin
    ClearErrors;
    Exit;
  end;

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
  if FEngine = seHunspell then
  begin
    if Assigned(FHunSpellChecker) then
      FLastErrors := TSpell.HunCheckText(FCheckText, FHunSpellChecker, FOptions, FAddEmptySuggestions)
    else
      SetLength(FLastErrors, 0);
  end
  else
    FLastErrors := TSpell.CheckText(FCheckText, FLanguage, FOptions, FAddEmptySuggestions);
end;

procedure TSpellChecker.OnBackgroundDone;
var
  ErrorCount: integer;
begin
  // If the component is being destroyed, do not touch UI or resources
  if FDestroying then
  begin
    FChecking := False;
    Exit;
  end;

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

procedure TSpellChecker.LoadHunDictionaryForLanguage;
var
  candidates: TStringArray;
  i: integer;
  affFile, dicFile: string;
  basePath: string;
  found: boolean;
begin
  if csDesigning in ComponentState then Exit;
  if csLoading in ComponentState then Exit;

  // Prevent concurrent downloads
  if FDownloading then Exit;

  // Unload previous dictionary
  if Assigned(FHunSpellChecker) then
  begin
    FreeAndNil(FHunSpellChecker);
    FHunDictionaryLoaded := False;
  end;

  if (FDicPath = '') or (FLanguage = '') then
    Exit;

  // Resolve relative path to application directory
  basePath := FDicPath;
  if not IsPathAbsolute(basePath) then
    basePath := ExtractFilePath(ParamStr(0)) + basePath;
  basePath := IncludeTrailingPathDelimiter(basePath);

  candidates := HunspellDictionaryCandidates(FLanguage);

  found := False;
  for i := 0 to High(candidates) do
  begin
    affFile := basePath + candidates[i] + '.aff';
    dicFile := basePath + candidates[i] + '.dic';
    if TryLoadHunDictionary(affFile, dicFile) then
    begin
      found := True;
      Break;
    end;
  end;

  if not found and (FDicUrl <> '') then
  begin
    // Start asynchronous download
    StartDictionaryDownload(FLanguage);
  end;
end;

procedure TSpellChecker.StartDictionaryDownload(const LangCode: string);
var
  candidates: TStringArray;
  i: integer;
  urlAff, urlDic: string;
begin
  if FDownloading then Exit;
  if FDicUrl = '' then Exit;

  candidates := HunspellDictionaryCandidates(LangCode);

  for i := 0 to High(candidates) do
  begin
    urlAff := BuildDictURL(FDicUrl, candidates[i], 'aff');
    urlDic := BuildDictURL(FDicUrl, candidates[i], 'dic');
    if (urlAff <> '') and (urlDic <> '') then
    begin
      FDownloading := True;
      FDownloadLang := LangCode;
      FDownloadCandidate := candidates[i];
      DownloadFiles([urlAff, urlDic], @OnDictionaryDownloadComplete);
      Break;
    end;
  end;
end;

function TSpellChecker.BuildDictURL(const Template, CandidateCode, Ext: string): string;
var
  url: string;
  librePath: string;
begin
  url := Template;

  if Pos('{dict}', url) > 0 then
  begin
    // Replace {dict} with candidate code + extension
    url := StringReplace(url, '{dict}', CandidateCode + '.' + Ext, [rfReplaceAll]);
  end
  else if Pos('{libredict}', url) > 0 then
  begin
    librePath := GetLibreOfficePathByCode(CandidateCode);
    if librePath = '' then
      Exit('');
    url := StringReplace(url, '{libredict}', librePath + '.' + Ext, [rfReplaceAll]);
  end
  else
  begin
    // No placeholder found, assume template is base URL, append code and ext?
    // For safety, return empty to avoid malformed URLs
    Exit('');
  end;

  Result := url;
end;

function TSpellChecker.GetLibreOfficePathByCode(const Code: string): string;
begin
  // Returns path (without extension) inside LibreOffice dictionaries repository for given candidate code.
  // Code is expected to be a candidate from HunspellDictionaryCandidates (may contain '-' or '_').
  case Code of
    'af_ZA': Result := 'af_ZA/af_ZA';
    'an_ES': Result := 'an_ES/an_ES';
    'ar': Result := 'ar/ar';
    'as_IN': Result := 'as_IN/as_IN';
    'be_BY': Result := 'be_BY/be-official';
    'be-official': Result := 'be_BY/be-official';
    'bg_BG': Result := 'bg_BG/bg_BG';
    'bn_BD': Result := 'bn_BD/bn_BD';
    'bo': Result := 'bo/bo';
    'br_FR': Result := 'br_FR/br_FR';
    'bs_BA': Result := 'bs_BA/bs_BA';
    'ca': Result := 'ca/dictionaries/ca';
    'ca-valencia': Result := 'ca/dictionaries/ca-valencia';
    'ckb': Result := 'ckb/dictionaries/ckb';
    'cs_CZ': Result := 'cs_CZ/cs_CZ';
    'da_DK': Result := 'da_DK/da_DK';
    'de': Result := 'de/de_DE_frami';
    'de_DE': Result := 'de/de_DE_frami';
    'de_AT': Result := 'de/de_AT_frami';
    'de_CH': Result := 'de/de_CH_frami';
    'de_DE_frami': Result := 'de/de_DE_frami';
    'de_AT_frami': Result := 'de/de_AT_frami';
    'de_CH_frami': Result := 'de/de_CH_frami';
    'el_GR': Result := 'el_GR/el_GR';
    'en': Result := 'en/en_US';
    'en_US': Result := 'en/en_US';
    'en_AU': Result := 'en/en_AU';
    'en_CA': Result := 'en/en_CA';
    'en_GB': Result := 'en/en_GB';
    'en_ZA': Result := 'en/en_ZA';
    'eo': Result := 'eo/eo';
    'es': Result := 'es/es_ES';
    'es_ES': Result := 'es/es_ES';
    'es_AR': Result := 'es/es_AR';
    'es_BO': Result := 'es/es_BO';
    'es_CL': Result := 'es/es_CL';
    'es_CO': Result := 'es/es_CO';
    'es_CR': Result := 'es/es_CR';
    'es_CU': Result := 'es/es_CU';
    'es_DO': Result := 'es/es_DO';
    'es_EC': Result := 'es/es_EC';
    'es_GQ': Result := 'es/es_GQ';
    'es_GT': Result := 'es/es_GT';
    'es_HN': Result := 'es/es_HN';
    'es_MX': Result := 'es/es_MX';
    'es_NI': Result := 'es/es_NI';
    'es_PA': Result := 'es/es_PA';
    'es_PE': Result := 'es/es_PE';
    'es_PH': Result := 'es/es_PH';
    'es_PR': Result := 'es/es_PR';
    'es_PY': Result := 'es/es_PY';
    'es_SV': Result := 'es/es_SV';
    'es_US': Result := 'es/es_US';
    'es_UY': Result := 'es/es_UY';
    'es_VE': Result := 'es/es_VE';
    'et_EE': Result := 'et_EE/et_EE';
    'fa_IR': Result := 'fa_IR/fa-IR';
    'fa-IR': Result := 'fa_IR/fa-IR';
    'fr_FR': Result := 'fr_FR/dictionaries/fr';
    'fr': Result := 'fr_FR/dictionaries/fr';
    'gd_GB': Result := 'gd_GB/gd_GB';
    'gl': Result := 'gl/gl_ES';
    'gl_ES': Result := 'gl/gl_ES';
    'gu_IN': Result := 'gu_IN/gu_IN';
    'gug': Result := 'gug/gug';
    'he_IL': Result := 'he_IL/he_IL';
    'hi_IN': Result := 'hi_IN/hi_IN';
    'hr_HR': Result := 'hr_HR/hr_HR';
    'hu_HU': Result := 'hu_HU/hu_HU';
    'id': Result := 'id/id_ID';
    'id_ID': Result := 'id/id_ID';
    'is': Result := 'is/is';
    'it_IT': Result := 'it_IT/it_IT';
    'kmr_Latn': Result := 'kmr_Latn/kmr_Latn';
    'kn_IN': Result := 'kn_IN/kn_IN';
    'ko_KR': Result := 'ko_KR/ko_KR';
    'lo_LA': Result := 'lo_LA/lo_LA';
    'lt_LT': Result := 'lt_LT/lt';
    'lt': Result := 'lt_LT/lt';
    'lv_LV': Result := 'lv_LV/lv_LV';
    'mn_MN': Result := 'mn_MN/mn_MN';
    'mr_IN': Result := 'mr_IN/mr_IN';
    'ne_NP': Result := 'ne_NP/ne_NP';
    'nl_NL': Result := 'nl_NL/nl_NL';
    'no': Result := 'no/nb_NO';
    'nb_NO': Result := 'no/nb_NO';
    'nn_NO': Result := 'no/nn_NO';
    'oc_FR': Result := 'oc_FR/oc_FR';
    'or_IN': Result := 'or_IN/or_IN';
    'pa_IN': Result := 'pa_IN/pa_IN';
    'pl_PL': Result := 'pl_PL/pl_PL';
    'pt_BR': Result := 'pt_BR/pt_BR';
    'pt_PT': Result := 'pt_PT/pt_PT';
    'pt': Result := 'pt_BR/pt_BR'; // default to Brazilian if only 'pt'
    'ro': Result := 'ro/ro_RO';
    'ro_RO': Result := 'ro/ro_RO';
    'ru_RU': Result := 'ru_RU/ru_RU';
    'sa_IN': Result := 'sa_IN/sa_IN';
    'si_LK': Result := 'si_LK/si_LK';
    'sk_SK': Result := 'sk_SK/sk_SK';
    'sl_SI': Result := 'sl_SI/sl_SI';
    'sq_AL': Result := 'sq_AL/sq_AL';
    'sr': Result := 'sr/sr';
    'sr_Latn': Result := 'sr/sr-Latn';
    'sr-Latn': Result := 'sr/sr-Latn';
    'sv_SE': Result := 'sv_SE/dictionaries/sv_SE';
    'sv_FI': Result := 'sv_SE/dictionaries/sv_FI';
    'sw_TZ': Result := 'sw_TZ/sw_TZ';
    'ta_IN': Result := 'ta_IN/ta_IN';
    'te_IN': Result := 'te_IN/te_IN';
    'th_TH': Result := 'th_TH/th_TH';
    'tr_TR': Result := 'tr_TR/tr_TR';
    'uk_UA': Result := 'uk_UA/uk_UA';
    'vi': Result := 'vi/vi_VN';
    'vi_VN': Result := 'vi/vi_VN';
    else
      Result := '';
  end;
end;

procedure TSpellChecker.OnDictionaryDownloadComplete(Sender: TObject; AStreams: array of TMemoryStream; AErrors: array of string);
var
  affFileName, dicFileName: string;
  basePath: string;
begin
  FDownloading := False;

  // Ignore if component is being destroyed or language changed during download
  if FDestroying or (FDownloadLang <> FLanguage) then Exit;

  // Check if we got both streams without errors
  if (Length(AStreams) < 2) or (Length(AErrors) < 2) then Exit;
  if (AErrors[0] <> '') or (AErrors[1] <> '') then Exit;
  if (AStreams[0] = nil) or (AStreams[1] = nil) then Exit;
  if (AStreams[0].Size = 0) or (AStreams[1].Size = 0) then Exit;

  // Load dictionary from streams
  LoadHunDictionaryFromStream(AStreams[0], AStreams[1]);

  // Attempt to cache to DicPath
  if FHunDictionaryLoaded and (FDicPath <> '') then
  begin
    basePath := FDicPath;
    if not IsPathAbsolute(basePath) then
      basePath := ExtractFilePath(ParamStr(0)) + basePath;
    basePath := IncludeTrailingPathDelimiter(basePath);

    // Ensure directory exists
    if ForceDirectories(basePath) then
    begin
      affFileName := basePath + FDownloadCandidate + '.aff';
      dicFileName := basePath + FDownloadCandidate + '.dic';
      try
        AStreams[0].SaveToFile(affFileName);
        AStreams[1].SaveToFile(dicFileName);
      except
        // Ignore save errors
      end;
    end;
  end;

  // If dictionary loaded, CheckNow will be called inside LoadHunDictionaryFromStream,
  // but we also call it here to be safe (it will be skipped if already checking)
  if FHunDictionaryLoaded and FEnabled and Assigned(FRichMemo) then
    CheckNow;
end;

function TSpellChecker.TryLoadHunDictionary(const AffFile, DicFile: string): boolean;
begin
  Result := False;
  if not FileExists(AffFile) or not FileExists(DicFile) then
    Exit;
  if not Assigned(FHunSpellChecker) then
    FHunSpellChecker := THunSpellChecker.Create;
  FHunDictionaryLoaded := FHunSpellChecker.LoadFromFiles(AffFile, DicFile);
  Result := FHunDictionaryLoaded;
end;

end.
