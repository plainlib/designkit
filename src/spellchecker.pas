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
  LazUTF8,
  RichMemo,
  RichSpellChecker,
  SpellUtils,
  HunSpellChecker,
  {$IFDEF WINDOWS}
  Windows,
  WinSpellChecker,
  {$ENDIF}
  OneShotThread,
  OneShotTimer,
  Downloader,
  stringhelper;

type
  // Event fired after spell check results have been applied to the RichMemo
  TSpellCheckCompleteEvent = procedure(Sender: TObject; ErrorCount: integer) of object;
  // Event fired when context menu is about to be shown (before our automatic handling)
  TSpellContextPopupEvent = procedure(Sender: TObject; MousePos: TPoint; var Handled: boolean) of object;
  // Event fired right after a suggestion from the context menu replaces a word
  TSpellReplaceEvent = procedure(Sender: TObject) of object;

  // Spell engine selection
  TSpellEngine = (seWindows, seHunspell);

  // Dictionary change deferred until the running background check finishes
  TDictionaryPendingAction = (dpaNone, dpaReload, dpaUnload);

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
    FMemoChangeOnReplace: boolean;
    FOnSpellCheckComplete: TSpellCheckCompleteEvent;
    FOnContextPopup: TSpellContextPopupEvent; // optional user hook
    FOnReplace: TSpellReplaceEvent;           // fired after a replacement from the menu
    FEngine: TSpellEngine;
    FHunSpellChecker: THunSpellChecker;
    FHunDictionaryLoaded: boolean; // True when a Hunspell dictionary has been loaded
    FDictionaryConfigured: boolean; // True once the user code has assigned DicPath or DicUrl
    FDictionaryPendingAction: TDictionaryPendingAction; // Deferred change while a check is running

    FChunkedCheck: boolean;           // Enable incremental chunk based checking
    FChunkSize: integer;              // Size of one chunk in characters
    FAppliedErrorCount: integer;      // Number of errors already drawn in chunked mode
    FLastPartialApplyTick: QWord; // Last time partial errors were drawn in chunked mode

    FCheckVisibleOnly: boolean;    // When True, only the visible portion is checked
    FScrollTimer: TTimer;          // Polls the visible range and re-checks on scroll
    FLastVisStart: integer;        // Last observed visible character start (1-based)
    FLastVisEnd: integer;          // Last observed visible character end (1-based)
    FCheckByteStart: integer;      // Byte offset in FCheckText of the range being checked
    FCheckByteEnd: integer;        // Byte offset in FCheckText of the range being checked
    FLastVisChangeTick: QWord;     // When the visible range last changed
    FScrollSettleDelay: integer;   // Stability time before a visible-only check runs

    // Async dictionary loading state
    FLoadThread: TThread;              // Thread handle used to wait on a pending async load
    FLoadingDictionary: boolean;       // True while a dictionary is being loaded in background
    FLocalChecker: THunSpellChecker;   // Checker being built by the background thread
    FLoadSuccess: boolean;             // Result of the last background load
    FLoadGeneration: integer;          // Incremented on each reload request, detects parameter changes
    FLoadingGeneration: integer;       // Generation recorded when the current load started
    FLoadAffFile: string;              // Affix file path for the current async load
    FLoadDicFile: string;              // Dictionary file path for the current async load
    FLoadAffStream: TMemoryStream;     // Affix data for stream based async load
    FLoadDicStream: TMemoryStream;     // Dictionary data for stream based async load

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
    FTwoPhaseSuggestions: boolean; // When True, suggestions are generated in a separate background pass
    FSuggestionErrors: array of TStringArray; // Suggestion lists collected by the second pass
    FSuggestionThread: TThread;    // Background thread for the suggestion pass
    FSuggesting: boolean;          // True while the suggestion pass is running
    FPendingCheck: boolean;
    FInternalChange: boolean;   // True while we modify RichMemo ourselves
    FCancelRequested: integer; // 0 = no cancel, 1 = cancel requested
    FCheckText: string;        // Snapshot of text for background check
    FTextChangedSinceCheck: boolean; // True when the memo text changed after the last snapshot
    FLastErrors: RichSpellChecker.TSpellErrorArray;
    FDebounceTimer: TTimer;
    FPrevContextPopup: TContextPopupEvent; // saved original RichMemo.OnContextPopup
    FPrevOnChange: TNotifyEvent;           // saved original RichMemo.OnChange
    FContextMenuOpen: boolean;             // True while context menu is visible
    FReplaceJustDone: boolean;             // True after replacement to avoid duplicate check
    FWinSupportedLanguages: TStringList; // cached TStrings view for the SupportedLanguages property

    procedure SetRichMemo(AValue: TRichMemo);
    procedure SetLanguage(const AValue: string);
    procedure SetEnabled(AValue: boolean);
    procedure SetRealTime(AValue: boolean);
    procedure SetCheckDelay(AValue: integer);
    procedure SetOptions(AValue: TSpellCheckOptions);
    procedure SetAutoContextMenu(AValue: boolean);
    procedure SetMemoChangeOnReplace(AValue: boolean);
    procedure SetPopupMenu(AValue: TPopupMenu);
    procedure SetUseSubMenu(AValue: boolean);
    procedure SetSuggestionsCaption(const AValue: string);
    procedure SetSubMenuIndex(AValue: integer);
    procedure SetEngine(AValue: TSpellEngine);
    procedure SetDicPath(const AValue: string);
    procedure SetDicUrl(const AValue: string);
    procedure SetChunkedCheck(AValue: boolean);
    procedure SetChunkSize(AValue: integer);
    procedure SetCheckVisibleOnly(AValue: boolean);
    procedure SetTwoPhaseSuggestions(AValue: boolean);
    function GetWinSupportedLanguages: TStrings;
    procedure StartScrollTimer;
    procedure StopScrollTimer;
    procedure OnScrollTimerTick(Sender: TObject);
    procedure UpdateContextMenuHandler;
    procedure OnRichMemoChange(Sender: TObject);
    procedure OnRichMemoContextPopup(Sender: TObject; MousePos: TPoint; var Handled: boolean);
    procedure DoDebouncedCheck(Sender: TObject);
    procedure DoBackgroundCheck;
    procedure ApplyPartialErrors;     // Runs on the main thread via Synchronize
    // Returns the 1-based character range currently visible in the memo.
    // Falls back to the whole text when the platform cannot report it.
    function GetVisibleTextRange(out AStart, AEnd: integer): boolean;
    procedure OnBackgroundDone;
    procedure StartSuggestionPass;
    procedure DoBackgroundSuggestions;
    procedure OnSuggestionsReady;
    procedure StartCheck;
    procedure ApplyErrors(const AErrors: RichSpellChecker.TSpellErrorArray);
    procedure ClearUnderlines;
    procedure DoSpellCheckNeeded(Sender: TObject);
    procedure LoadHunDictionaryForLanguage;
    procedure StartAsyncDictionaryLoadFromFiles(const AFFFile, DICFile: string);
    procedure StartAsyncDictionaryLoadFromStream(AFFStream, DICStream: TStream);
    procedure DoLoadHunDictionary;
    procedure OnHunDictionaryLoaded;
    procedure StartDictionaryDownload(const LangCode: string);
    function BuildDictURL(const Template, CandidateCode, Ext: string): string;
    function NormalizeFlatCode(const Code: string): string;
    function GetFlatDictByCode(const Code: string): string;
    function GetLibreOfficePathByCode(const Code: string): string;
    function GetWooormPathByCode(const Code: string): string;
    function ResolveRelativeDicPath(const APath: string): string;
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

    // Draw the current spell errors (last check result) as underlines on any
    // RichMemo that displays the same text. Useful when the same text is
    // mirrored in another control (for example a grid cell) and should be
    // highlighted too. The target memo is not switched to and no background
    // check is started; interaction (context menu, suggestions) still happens
    // only in the memo currently assigned to RichMemo.
    procedure ApplyErrorsTo(ATargetMemo: TRichMemo);

    // Returns True if a check is currently running
    function IsChecking: boolean;

    // Returns the list of BCP-47 tags supported by the current engine, empty for Hunspell
    // Pass AForceRefresh to re-read the list from Windows instead of using the cache
    function GetSupportedLanguages(AForceRefresh: boolean = False): TStringArray;

    // Returns True when the given BCP-47 tag is usable with the current engine
    function IsLanguageSupported(const ALanguageTag: string): boolean;

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

    // BCP-47 language tag, e.g. 'en-US' or 'ru-RU', two-letter codes are allowed
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

    // When True, RichMemo.OnChange fires when a word is replaced from the
    // suggestions menu. When False (default), OnChange is suppressed during
    // the replacement to avoid reentrant spell checking.
    property MemoChangeOnReplace: boolean read FMemoChangeOnReplace write SetMemoChangeOnReplace default False;

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

    // Directory path for Hunspell dictionaries (.aff and .dic). Can be absolute
    // or relative to the application folder. Supports one placeholder:
    //   {temp} - replaced by the system temporary directory. Use it when the
    //   dictionary should be cached outside the project, for example
    //   '{temp}\dic' or '{temp}\myapp\dic'. Windows cleans the temp folder
    //   automatically after some time, so the dictionary may be re-downloaded.
    property DicPath: string read FDicPath write SetDicPath;

    // URL template for downloading Hunspell dictionaries. Supports placeholders:
    //   {dict}      - replaced by language code (e.g. en_US) and then .aff/.dic appended
    //   {plaindict} - replaced by the flat dictionary base name
    //   https://raw.githubusercontent.com/plainlib/dictionaries/main/{plaindict}
    //   {libredict} - replaced by path inside LibreOffice dictionaries repository
    //   https://raw.githubusercontent.com/LibreOffice/dictionaries/master/{libredict}
    //   {wooormdict} - replaced by path inside Wooormdict dictionaries repository
    //   https://raw.githubusercontent.com/wooorm/dictionaries/refs/heads/main/dictionaries/{wooormdict}
    // If empty, no automatic download is performed.
    property DicUrl: string read FDicUrl write SetDicUrl;

    // When True, large texts are checked in chunks and errors are drawn
    // incrementally, so the user sees the top of the document highlighted
    // while the rest is still being checked in the background.
    property ChunkedCheck: boolean read FChunkedCheck write SetChunkedCheck default False;

    // Size of a single chunk in characters (used when ChunkedCheck is True)
    property ChunkSize: integer read FChunkSize write SetChunkSize default 16384;

    // When True, only the text currently visible in the RichMemo is checked.
    // A polling timer re-runs the check whenever the visible range changes
    // (scroll or text change), keeping the visible area up to date without
    // touching the rest of the document. ChunkedCheck is ignored in this
    // mode because the visible portion is already small.
    property CheckVisibleOnly: boolean read FCheckVisibleOnly write SetCheckVisibleOnly default False;

    // Called after a check has finished and (if AutoApply) errors are applied
    property OnSpellCheckComplete: TSpellCheckCompleteEvent read FOnSpellCheckComplete write FOnSpellCheckComplete;

    // Called when context menu is about to be shown (before our automatic handler).
    // Set Handled to True to prevent our handling.
    property OnContextPopup: TSpellContextPopupEvent read FOnContextPopup write FOnContextPopup;

    // Called right after a word was replaced from the suggestions menu.
    // RichMemo.OnChange does not fire in this case, so use this event if you
    // need to react to a replacement.
    property OnReplace: TSpellReplaceEvent read FOnReplace write FOnReplace;

    // Read only list of BCP-47 tags supported by the current engine, visible in the Object Inspector
    property WinSupportedLanguages: TStrings read GetWinSupportedLanguages;

    // When True, the check is split into two passes. The first pass only
    // detects errors and draws underlines so the user sees feedback as
    // soon as possible. The second pass runs in the background and
    // generates suggestions for every detected error. Suggestions appear
    // in the context menu as soon as they are ready. Currently supported
    // only by the Hunspell engine.
    property TwoPhaseSuggestions: boolean read FTwoPhaseSuggestions write SetTwoPhaseSuggestions default False;
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

function SpellOffsetBase(const S: string; AByteLen: integer): integer;
  {$IFDEF WINDOWS}
var
  I: integer;
  C: cardinal;
  {$ENDIF}
begin
  if AByteLen <= 0 then
    Exit(0);

  {$IFDEF WINDOWS}
  Result := 0;
  I := 1;
  while I <= AByteLen do
  begin
    C := Ord(S[I]);
    if (C and $F8) = $F0 then
    begin
      Inc(Result, 2);
      Inc(I, 4);
    end
    else if (C and $F0) = $E0 then
    begin
      Inc(Result);
      Inc(I, 3);
    end
    else if (C and $E0) = $C0 then
    begin
      Inc(Result);
      Inc(I, 2);
    end
    else
    begin
      Inc(Result);
      Inc(I);
    end;
  end;
  {$ELSE}
  Result := UTF8Length(PChar(S), AByteLen);
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
  FMemoChangeOnReplace := False;
  FChecking := False;
  FPendingCheck := False;
  FInternalChange := False;
  FCancelRequested := 0;
  FTextChangedSinceCheck := False;
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
  FDictionaryConfigured := False;
  FDictionaryPendingAction := dpaNone;
  FLoadThread := nil;
  FLoadingDictionary := False;
  FLocalChecker := nil;
  FLoadSuccess := False;
  FLoadGeneration := 0;
  FLoadingGeneration := 0;
  FLoadAffFile := '';
  FLoadDicFile := '';
  FLoadAffStream := nil;
  FLoadDicStream := nil;
  FDicPath := '';
  FDicUrl := 'https://raw.githubusercontent.com/plainlib/dictionaries/main/{plaindict}';
  FDownloading := False;
  FDownloadLang := '';
  FLanguage := ''; // Initialize language to empty
  FOnReplace := nil;
  FChunkedCheck := False;
  FChunkSize := 16384;
  FTwoPhaseSuggestions := False;
  FSuggesting := False;
  FSuggestionThread := nil;
  SetLength(FSuggestionErrors, 0);
  FAppliedErrorCount := 0;
  FLastPartialApplyTick := 0;
  FCheckVisibleOnly := False;
  FScrollTimer := nil;
  FLastVisStart := -1;
  FLastVisEnd := -1;
  FCheckByteStart := 1;
  FCheckByteEnd := 0;
  FLastVisChangeTick := 0;
  FScrollSettleDelay := 400;
  FWinSupportedLanguages := nil;

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

  // Cancel and wait for any pending async dictionary load. The loading thread
  // runs LoadFromFiles/LoadFromStream which cannot be interrupted, so we must
  // wait for it to finish before freeing the component.
  if FLoadThread <> nil then
  begin
    FLoadThread.Terminate;
    while FLoadThread <> nil do
    begin
      Sleep(10);
      CheckSynchronize;
    end;
  end;

  // Free any checker that was left behind after the load thread was terminated
  if Assigned(FLocalChecker) then
    FreeAndNil(FLocalChecker);
  FreeAndNil(FLoadAffStream);
  FreeAndNil(FLoadDicStream);

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

  // Wait for the suggestion pass if it is still running. Both passes use
  // the same Hunspell checker instance, so the suggestion pass must be
  // finished before the dictionary is released.
  if FSuggesting then
  begin
    InterlockedExchange(FCancelRequested, 1);
    while FSuggesting do
    begin
      Sleep(10);
      CheckSynchronize;
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

  StopScrollTimer;
  if Assigned(FScrollTimer) then
    FreeAndNil(FScrollTimer);

  // Free internal spell checker
  if Assigned(FSpellChecker) then
    FreeAndNil(FSpellChecker);

  // Free Hunspell checker (safe now because background thread has finished)
  if Assigned(FHunSpellChecker) then
    FreeAndNil(FHunSpellChecker);

  // Clear error array
  SetLength(FLastErrors, 0);

  if Assigned(FWinSupportedLanguages) then
    FreeAndNil(FWinSupportedLanguages);

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
    StopScrollTimer;
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

  // Hook RichMemo events now that all LFM properties, including the user's
  // OnChange and OnContextPopup handlers, have been applied. In the designer
  // we never touch these events, so the user sees his own handlers in the IDE.
  if Assigned(FRichMemo) and Assigned(FSpellChecker) and not (csDesigning in ComponentState) then
  begin
    FPrevOnChange := FRichMemo.OnChange;
    FRichMemo.OnChange := @OnRichMemoChange;
    FPrevContextPopup := FRichMemo.OnContextPopup;
    FRichMemo.OnContextPopup := @OnRichMemoContextPopup;
  end;

  // Auto-load when the LFM already specified a Hunspell engine and a language.
  // Loaded is called before Form.OnCreate, so anything the user plans to set
  // in Form.OnCreate cannot be honored here. If Language is empty at this
  // point we assume the user will configure the component in Form.OnCreate,
  // and the corresponding setters will trigger the load. Marking the source
  // as configured here also lets later Language changes trigger a reload.
  // The source is marked as configured even when the component starts
  // disabled, so a later Enabled := True can still trigger the dictionary
  // load and match the behaviour of a component that was enabled in the
  // designer.
  if (FEngine = seHunspell) and (FLanguage <> '') then
  begin
    FDictionaryConfigured := True;
    if FEnabled then
      LoadHunDictionaryForLanguage;
  end;

  if FEnabled and FCheckVisibleOnly and Assigned(FRichMemo) and not (csDesigning in ComponentState) then
    StartScrollTimer;

  if FEnabled and Assigned(FRichMemo) then
    CheckNow;
end;

procedure TSpellChecker.SetRichMemo(AValue: TRichMemo);
var
  ReuseErrors: boolean;
begin
  if FRichMemo = AValue then
  begin
    // The same memo object may be reused with new content (for example the
    // grid reuses a single cell editor for different rows). If the text no
    // longer matches the last check snapshot, run a fresh check so the
    // underlines follow the new content.
    if Assigned(AValue) and (not AValue.Text.EqualNormalized(FCheckText)) and FEnabled and not
      (csDesigning in ComponentState) and not (csLoading in ComponentState) then
      CheckNow;
    Exit;
  end;

  ReuseErrors := Assigned(AValue) and Assigned(FRichMemo) and (FCheckText <> '') and (AValue.Text.EqualNormalized(FCheckText));

  FLastVisStart := -1;
  FLastVisEnd := -1;

  if Assigned(FRichMemo) then
  begin
    // Always restore the original handlers, even when the saved value is nil.
    // A nil value simply means the RichMemo had no handler before we hooked it.
    // Skipping the restore would leave our own handler installed and cause
    // infinite recursion when this Memo is selected again later.
    FRichMemo.OnContextPopup := FPrevContextPopup;
    FRichMemo.OnChange := FPrevOnChange;
    FPrevContextPopup := nil;
    FPrevOnChange := nil;

    if Assigned(FSpellChecker) then
      FreeAndNil(FSpellChecker);
  end;

  FRichMemo := AValue;

  if Assigned(FRichMemo) then
  begin
    if not (csDesigning in ComponentState) and not (csLoading in ComponentState) then
    begin
      // Only remember a real user handler. If our own hook is still installed
      // (for example because some other path forgot to restore it), storing it
      // in FPrevOnChange would produce infinite recursion the next time we fire
      // OnChange. Same rule applies to OnContextPopup.
      if not Assigned(FRichMemo.OnChange) or (TMethod(FRichMemo.OnChange).Code <> TMethod(@OnRichMemoChange).Code) then
        FPrevOnChange := FRichMemo.OnChange;

      if not Assigned(FRichMemo.OnContextPopup) or (TMethod(FRichMemo.OnContextPopup).Code <>
        TMethod(@OnRichMemoContextPopup).Code) then
        FPrevContextPopup := FRichMemo.OnContextPopup;

      FRichMemo.OnChange := @OnRichMemoChange;
      FRichMemo.OnContextPopup := @OnRichMemoContextPopup;
    end;

    FSpellChecker := TRichSpellChecker.Create(FRichMemo);
    FSpellChecker.OnSpellCheckNeeded := @DoSpellCheckNeeded;

    FSpellChecker.PopupMenu := FPopupMenu;
    FSpellChecker.SubMenu := FSubMenu;
    FSpellChecker.SubMenuCaption := FSubMenuCaption;
    FSpellChecker.SubMenuIndex := FSubMenuIndex;
    FSpellChecker.MemoChangeOnReplace := FMemoChangeOnReplace;

    if ReuseErrors then
    begin
      FInternalChange := True;
      try
        TSpell.ApplyErrors(FSpellChecker, FLastErrors);

        if Assigned(FOnSpellCheckComplete) then
          FOnSpellCheckComplete(Self, Length(FLastErrors));
      finally
        FInternalChange := False;
      end;
    end
    else
      ClearUnderlines;

    if not ReuseErrors and FEnabled and not (csLoading in ComponentState) then
    begin
      // Coalesce rapid memo reassignments into a single check in runtime,
      // where the debounce timer exists and hooks are installed. In the
      // designer check immediately so the preview shows underlines.
      if Assigned(FDebounceTimer) and not (csDesigning in ComponentState) then
      begin
        FDebounceTimer.Enabled := False;
        FDebounceTimer.Interval := 150;
        FDebounceTimer.Enabled := True;
      end
      else
        CheckNow;
    end;
  end;
end;

procedure TSpellChecker.SetLanguage(const AValue: string);
begin
  if FLanguage = AValue then Exit;
  FLanguage := AValue;
  // In the designer the user expects an immediate reaction, so arm the
  // dictionary source as soon as the language is set there.
  if csDesigning in ComponentState then
    FDictionaryConfigured := True;
  // When the language is cleared, unload any Hunspell dictionary that was
  // loaded for the previous language. Otherwise the old dictionary stays in
  // memory and keeps checking text in its language even though Language is
  // empty, which is confusing.
  if (FEngine = seHunspell) and (FLanguage = '') and (not (csLoading in ComponentState)) then
  begin
    UnloadHunDictionary;
    ClearErrors;
    Exit;
  end;
  // Only load when the user has already decided where the dictionary comes
  // from (DicPath or DicUrl was assigned by user code, not by LFM). This
  // prevents an unwanted URL download when Language is assigned before
  // DicPath in Form.Create.
  if FEnabled and (FEngine = seHunspell) and FDictionaryConfigured and (FLanguage <> '') and not (csLoading in ComponentState) then
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
      // Lazily load the Hunspell dictionary when the component is enabled
      if (FEngine = seHunspell) and (not Assigned(FHunSpellChecker)) and FDictionaryConfigured and
        (FLanguage <> '') and not (csDesigning in ComponentState) and not (csLoading in ComponentState) then
        LoadHunDictionaryForLanguage;

      if FCheckVisibleOnly and Assigned(FRichMemo) and not (csDesigning in ComponentState) then
        StartScrollTimer;

      if Assigned(FRichMemo) and not (csLoading in ComponentState) then
        CheckNow;
    end
    else
    begin
      StopScrollTimer;
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

procedure TSpellChecker.SetMemoChangeOnReplace(AValue: boolean);
begin
  if FMemoChangeOnReplace <> AValue then
  begin
    FMemoChangeOnReplace := AValue;
    if Assigned(FSpellChecker) then
      FSpellChecker.MemoChangeOnReplace := AValue;
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
    if (FEngine = seHunspell) and FEnabled then
    begin
      if not Assigned(FHunSpellChecker) and not FLoadingDictionary then
      begin
        // Only load when the user has already decided where the dictionary
        // comes from (DicPath or DicUrl was assigned by user code).
        if (FLanguage <> '') and FDictionaryConfigured and not (csLoading in ComponentState) then
          LoadHunDictionaryForLanguage;
      end;
    end;
    if FEnabled and Assigned(FRichMemo) and not (csLoading in ComponentState) then
      CheckNow;
  end;
end;

procedure TSpellChecker.SetDicPath(const AValue: string);
begin
  if FDicPath <> AValue then
    FDicPath := AValue;

  // Any assignment from user code (not from LFM loading) marks the dictionary
  // source as explicitly configured and arms automatic loading. This includes
  // the explicit DicPath := '' used to enable URL-only mode.
  if not (csLoading in ComponentState) then
    FDictionaryConfigured := True;

  if FEnabled and FDictionaryConfigured and (FEngine = seHunspell) and (FLanguage <> '') and not (csLoading in ComponentState) then
    LoadHunDictionaryForLanguage;
end;

procedure TSpellChecker.SetDicUrl(const AValue: string);
begin
  if FDicUrl <> AValue then
    FDicUrl := AValue;

  // Same rule as for DicPath: only user code (not LFM loading) arms the load.
  if not (csLoading in ComponentState) then
    FDictionaryConfigured := True;

  if FEnabled and FDictionaryConfigured and (FEngine = seHunspell) and (FLanguage <> '') and not (csLoading in ComponentState) then
    LoadHunDictionaryForLanguage;
end;

procedure TSpellChecker.SetChunkedCheck(AValue: boolean);
begin
  if FChunkedCheck <> AValue then
  begin
    FChunkedCheck := AValue;
    if FEnabled and Assigned(FRichMemo) and not (csLoading in ComponentState) then
      CheckNow;
  end;
end;

procedure TSpellChecker.SetChunkSize(AValue: integer);
begin
  // Keep a sane minimum to avoid pathological fragmentation in normal use.
  // During design time the limit is relaxed so the property can be set to
  // very small values for testing chunked drawing behaviour.
  if not (csDesigning in ComponentState) and (AValue < 256) then
    AValue := 256;
  if AValue < 1 then AValue := 1;
  if FChunkSize <> AValue then
  begin
    FChunkSize := AValue;
    if FEnabled and FChunkedCheck and Assigned(FRichMemo) and not (csLoading in ComponentState) then
      CheckNow;
  end;
end;

procedure TSpellChecker.SetCheckVisibleOnly(AValue: boolean);
begin
  if FCheckVisibleOnly <> AValue then
  begin
    FCheckVisibleOnly := AValue;
    if FCheckVisibleOnly and FEnabled and Assigned(FRichMemo) and not (csDesigning in ComponentState) then
      StartScrollTimer
    else
      StopScrollTimer;
    if FEnabled and Assigned(FRichMemo) and not (csLoading in ComponentState) then
      CheckNow;
  end;
end;

procedure TSpellChecker.SetTwoPhaseSuggestions(AValue: boolean);
begin
  if FTwoPhaseSuggestions <> AValue then
  begin
    FTwoPhaseSuggestions := AValue;
    if FEnabled and Assigned(FRichMemo) and not (csLoading in ComponentState) then
      CheckNow;
  end;
end;

function TSpellChecker.GetWinSupportedLanguages: TStrings;
  {$IFDEF WINDOWS}
var
  Langs: TSupportedLanguages = nil;
  i: integer = 0;
  {$ENDIF}
begin
  if FWinSupportedLanguages = nil then
    FWinSupportedLanguages := TStringList.Create;
  FWinSupportedLanguages.Clear;

  {$IFDEF WINDOWS}
  // always report the Windows list, independent of the current engine
  Langs := WinSpellChecker.GetSupportedSpellCheckerLanguages;
  for i := 0 to High(Langs) do
    FWinSupportedLanguages.Add(UTF8Encode(Langs[i]));
  {$ENDIF}

  Result := FWinSupportedLanguages;
end;

procedure TSpellChecker.StartScrollTimer;
begin
  if FScrollTimer = nil then
  begin
    FScrollTimer := TTimer.Create(nil);
    FScrollTimer.Interval := 200;
    FScrollTimer.OnTimer := @OnScrollTimerTick;
  end;
  // Force the first poll to detect a change and trigger a check
  FLastVisStart := -1;
  FLastVisEnd := -1;
  FScrollTimer.Enabled := True;
end;

procedure TSpellChecker.StopScrollTimer;
begin
  if Assigned(FScrollTimer) then
    FScrollTimer.Enabled := False;
end;

procedure TSpellChecker.OnScrollTimerTick(Sender: TObject);
var
  VisStart, VisEnd: integer;
  Now: QWord;
begin
  if not FEnabled or not FCheckVisibleOnly then
    Exit;
  if not Assigned(FRichMemo) then
    Exit;
  if not GetVisibleTextRange(VisStart, VisEnd) then
    Exit;

  // The visible range changed, the user is (probably) scrolling. Record the
  // moment and cancel any running check: applying stale results right now
  // would repaint the memo in the middle of a scroll and cause visible
  // jitter and the loss of the current scroll position. The same behaviour
  // is now used on all platforms, because starting a check during an active
  // scroll slows down large documents.
  if (VisStart <> FLastVisStart) or (VisEnd <> FLastVisEnd) then
  begin
    FLastVisStart := VisStart;
    FLastVisEnd := VisEnd;
    FLastVisChangeTick := GetTickCount64;
    CancelCheck;
    Exit;
  end;

  // The range has not changed since the last tick. Wait until it has been
  // stable long enough, so the actual check only starts after the user has
  // stopped scrolling.
  Now := GetTickCount64;
  if (FLastVisChangeTick = 0) or (Now - FLastVisChangeTick < QWord(FScrollSettleDelay)) then
    Exit;

  // Mark as already handled: the next tick will not fire again until the
  // visible range changes, so a stable scroll position is checked only once.
  FLastVisChangeTick := 0;
  CheckNow;
end;

procedure TSpellChecker.LoadHunDictionaryFromFiles(const AFFFileName, DICFileName: string);
begin
  StartAsyncDictionaryLoadFromFiles(AFFFileName, DICFileName);
end;

procedure TSpellChecker.LoadHunDictionaryFromStream(AFFStream, DICStream: TStream);
begin
  StartAsyncDictionaryLoadFromStream(AFFStream, DICStream);
end;

procedure TSpellChecker.UnloadHunDictionary;
begin
  // If an async load is running, defer the unload until it completes
  if FLoadingDictionary then
  begin
    FDictionaryPendingAction := dpaUnload;
    Exit;
  end;

  // If a background check is running, defer the unload instead of blocking
  // the main thread. OnBackgroundDone will re-enter this method when the
  // worker thread has finished and it is safe to free the dictionary.
  if FChecking then
  begin
    FPendingCheck := False;
    FDictionaryPendingAction := dpaUnload;
    InterlockedExchange(FCancelRequested, 1);
    Exit;
  end;

  // Wait for the suggestion pass before freeing the dictionary
  if FSuggesting then
  begin
    InterlockedExchange(FCancelRequested, 1);
    while FSuggesting do
    begin
      Sleep(5);
      CheckSynchronize;
    end;
  end;

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
    // Do not store our own hook as the previous handler
    if not Assigned(FRichMemo.OnContextPopup) or (TMethod(FRichMemo.OnContextPopup).Code <>
      TMethod(@OnRichMemoContextPopup).Code) then
      FPrevContextPopup := FRichMemo.OnContextPopup;
    FRichMemo.OnContextPopup := @OnRichMemoContextPopup;
  end
  else
  begin
    // Restore unconditionally: nil is a valid original value
    FRichMemo.OnContextPopup := FPrevContextPopup;
    FPrevContextPopup := nil;
  end;
end;

procedure TSpellChecker.OnRichMemoChange(Sender: TObject);
begin
  // If the change was caused by our own internal operation
  // (e.g. applying spell-check underlines), do not notify the user.
  if FInternalChange then Exit;

  // Any user visible change invalidates the snapshot used by the running
  // check. Track it with a flag so ApplyPartialErrors and OnBackgroundDone
  // can skip their work without comparing the full text on every chunk,
  // which is very expensive on large documents.
  FTextChangedSinceCheck := True;

  // Call original RichMemo.OnChange handler if assigned
  if Assigned(FPrevOnChange) then
    FPrevOnChange(Sender);

  if not FRealTime or not FEnabled then Exit;
  if not Assigned(FDebounceTimer) then Exit;

  // A RichMemo can fire OnChange for non-text modifications such as
  // applying spell underline formatting. Re-check only when the text
  // actually differs from the last snapshot.
  if (FCheckText <> '') and FRichMemo.Text.EqualNormalized(FCheckText) then
    Exit;

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
  ChunkedActive: boolean = False;
begin
  if Assigned(FOnContextPopup) then
    FOnContextPopup(Sender, MousePos, Handled);

  if Handled then Exit;

  // Call original RichMemo.OnContextPopup handler if assigned
  if Assigned(FPrevContextPopup) then
    FPrevContextPopup(Sender, MousePos, Handled);

  if Handled then Exit;

  if Assigned(FSpellChecker) then
  begin
    FContextMenuOpen := True;
    try
      // In chunked mode the error list is extended incrementally and the
      // offsets are absolute, so cancelling the background pass here would
      // leave the rest of the document unhighlighted until a fresh check
      // is triggered. Non chunked checks draw nothing until they finish,
      // so they can still be aborted without any visible effect.
      ChunkedActive := FChunkedCheck and (FChunkSize > 0) and (Length(FCheckText) > FChunkSize);
      if not ChunkedActive then
        CancelCheck;
      if FSpellChecker.ShowContextMenu(MousePos.X, MousePos.Y) then
      begin
        Handled := True;
      end;
    finally
      FContextMenuOpen := False;
      // If a suggestion was chosen, RichMemo.OnChange did not fire because
      // RichSpellChecker clears it during replacement. Start the re-check now.
      if FReplaceJustDone then
      begin
        FReplaceJustDone := False;
        if FEnabled and Assigned(FRichMemo) then
          CheckNow;
      end;
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
end;

procedure TSpellChecker.DoSpellCheckNeeded(Sender: TObject);
begin
  // Called by RichSpellChecker after a replacement from the context menu.
  // RichSpellChecker temporarily clears RichMemo.OnChange during the replacement,
  // so OnChange does not fire here. We must trigger the re-check ourselves.
  FReplaceJustDone := True;

  // Notify the user that a replacement has just happened
  if Assigned(FOnReplace) then
    FOnReplace(Self);

  // Stop debounce timer to avoid an extra check
  if Assigned(FDebounceTimer) then
    FDebounceTimer.Enabled := False;

  // If the context menu is still open, OnRichMemoContextPopup will start the
  // check as soon as the menu closes. Otherwise start it immediately.
  if not FContextMenuOpen and FEnabled and Assigned(FRichMemo) then
  begin
    FReplaceJustDone := False;
    CheckNow;
  end;
end;

procedure TSpellChecker.DoDebouncedCheck(Sender: TObject);
begin
  if Assigned(FDebounceTimer) then
    FDebounceTimer.Enabled := False;

  if not FEnabled or not Assigned(FRichMemo) then
    Exit;

  // The debounce timer can be re-armed by a benign OnChange that fires
  // after underline formatting is applied. Skip the check when the memo
  // text still matches the last snapshot, otherwise an endless check loop
  // would run once per CheckDelay while the user does nothing.
  if (FCheckText <> '') and FRichMemo.Text.EqualNormalized(FCheckText) then
    Exit;

  CheckNow;
end;

procedure TSpellChecker.StartCheck;
var
  VisStart, VisEnd: integer;
  TotalChars: integer;
begin
  if FContextMenuOpen then
    Exit;

  // Never start a Hunspell check while the dictionary is unloaded or being reloaded
  if (FEngine = seHunspell) and ((FHunSpellChecker = nil) or (not FHunDictionaryLoaded)) then
    Exit;

  // The check pass and the suggestion pass share the same Hunspell
  // checker instance, so the suggestion pass must not run concurrently
  if FSuggesting then
  begin
    InterlockedExchange(FCancelRequested, 1);
    while FSuggesting do
    begin
      Sleep(5);
      CheckSynchronize;
    end;
  end;

  if FChecking then
  begin
    // Ask the running check to abort as soon as possible so a fresh one can
    // start without waiting for the full dictionary scan to complete.
    InterlockedExchange(FCancelRequested, 1);
    FPendingCheck := True;
    Exit;
  end;

  if not FChecking then
    InterlockedExchange(FCancelRequested, 0);

  FChecking := True;

  // Chunked mode accumulates errors and draws them incrementally on top of
  // the existing underlines. Previous underlines are intentionally left in
  // place: wiping them here would make the whole document blink while the
  // background pass walks through it. The final atomic replace happens in
  // OnBackgroundDone through TSpell.ApplyErrors.
  // Chunked mode is not used in visible-only mode because the visible
  // portion is already small enough to be checked in a single pass.
  if FChunkedCheck and (FChunkSize > 0) and (Length(FRichMemo.Text) > FChunkSize) then
  begin
    FAppliedErrorCount := 0;
    SetLength(FLastErrors, 0);
    FLastPartialApplyTick := 0;
  end;

  FCheckText := FRichMemo.Text;
  FTextChangedSinceCheck := False;

  // Compute the byte range that should be checked. In visible-only mode this
  // is the region reported by the widget, converted from character offsets
  // to byte offsets into the UTF-8 snapshot. Otherwise the whole text is
  // checked and the range is trivially 1..Length(FCheckText).
  if FCheckVisibleOnly then
  begin
    if GetVisibleTextRange(VisStart, VisEnd) and (VisStart > 0) then
    begin
      TotalChars := UTF8Length(FCheckText);
      if VisStart > TotalChars then
        VisStart := TotalChars;
      if VisEnd > TotalChars then
        VisEnd := TotalChars;
      if VisEnd < VisStart then
        VisEnd := VisStart;
      FCheckByteStart := UTF8CodepointToByteIndex(PChar(FCheckText), Length(FCheckText), VisStart);
      FCheckByteEnd := UTF8CodepointToByteIndex(PChar(FCheckText), Length(FCheckText), VisEnd);
      if FCheckByteStart < 1 then
        FCheckByteStart := 1;
      if (FCheckByteEnd < FCheckByteStart) or (FCheckByteEnd > Length(FCheckText)) then
        FCheckByteEnd := Length(FCheckText);

      // Extend the range to whole words so a check that starts or ends in
      // the middle of a word does not misreport the clipped fragments. Bytes
      // that belong to a multi-byte UTF-8 character are never equal to an
      // ASCII whitespace, so the backward scan stops exactly at a character
      // boundary right after the previous whitespace, and the forward scan
      // stops right before the next one.
      while (FCheckByteStart > 1) and not (FCheckText[FCheckByteStart - 1] in [' ', #9, #10, #13]) do
        Dec(FCheckByteStart);
      while (FCheckByteEnd < Length(FCheckText)) and not (FCheckText[FCheckByteEnd + 1] in [' ', #9, #10, #13]) do
        Inc(FCheckByteEnd);
    end
    else
    begin
      FCheckByteStart := 1;
      FCheckByteEnd := Length(FCheckText);
    end;
  end
  else
  begin
    FCheckByteStart := 1;
    FCheckByteEnd := Length(FCheckText);
  end;

  // Give the Hunspell engine a pointer to the cancellation flag so that long
  // running dictionary scans stop quickly when text or language changes.
  if (FEngine = seHunspell) and Assigned(FHunSpellChecker) then
    FHunSpellChecker.CancelFlag := @FCancelRequested;
  RunAsync(@DoBackgroundCheck, @OnBackgroundDone);
end;

procedure TSpellChecker.CheckNow;
begin
  // Skip while the component is being loaded from the .lfm file
  if csLoading in ComponentState then Exit;

  if not FEnabled or not Assigned(FRichMemo) or not Assigned(FSpellChecker) then
    Exit;

  // For Hunspell engine, dictionary must be loaded
  if (FEngine = seHunspell) and ((FHunSpellChecker = nil) or (not FHunDictionaryLoaded)) then
  begin
    ClearErrors;
    // Request the dictionary load when the source has already been configured
    // by the user. This covers runtime engine changes and memo reassignments
    // that happen before the dictionary was ever requested. OnHunDictionaryLoaded
    // will call CheckNow once the load finishes, so the pending check still runs.
    if (not FLoadingDictionary) and (not FDownloading) and (FLanguage <> '') and FDictionaryConfigured then
      LoadHunDictionaryForLanguage;
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

procedure TSpellChecker.ApplyErrorsTo(ATargetMemo: TRichMemo);
begin
  if not Assigned(ATargetMemo) then
    Exit;

  // Text must match the snapshot taken at the last check, otherwise the stored
  // offsets would point to the wrong characters. In that case just clear
  // whatever was drawn earlier and wait for a real check.
  if (FCheckText = '') or (not ATargetMemo.Text.EqualNormalized(FCheckText)) then
  begin
    RichSpellChecker.ClearSpellErrors(ATargetMemo);
    Exit;
  end;

  RichSpellChecker.DrawSpellErrors(ATargetMemo, FLastErrors);
end;

function TSpellChecker.IsChecking: boolean;
begin
  Result := FChecking;
end;

function TSpellChecker.GetSupportedLanguages(AForceRefresh: boolean = False): TStringArray;
  {$IFDEF WINDOWS}
var
  Langs: TSupportedLanguages = nil;
  i: integer = 0;
  {$ENDIF}
begin
  Result := nil;
  {$IFDEF WINDOWS}
  // the system list is only meaningful for the Windows engine
  if FEngine <> seWindows then
    Exit;

  if AForceRefresh then
    WinSpellChecker.ResetSupportedLanguagesCache;

  Langs := WinSpellChecker.GetSupportedSpellCheckerLanguages;
  SetLength(Result, Length(Langs));
  for i := 0 to High(Langs) do
    Result[i] := UTF8Encode(Langs[i]);
  {$ENDIF}
end;

function TSpellChecker.IsLanguageSupported(const ALanguageTag: string): boolean;
  {$IFDEF WINDOWS}
var
  ATag: widestring = '';
  {$ENDIF}
begin
  Result := False;
  if ALanguageTag = '' then
    Exit;

  {$IFDEF WINDOWS}
  if FEngine = seWindows then
  begin
    // the unit is already pulled in by the WINDOWS define, no extra uses needed
    ATag := WinSpellChecker.NormalizeLanguageTag(ALanguageTag);
    Result := WinSpellChecker.IsLanguageSupported(ATag);
    Exit;
  end;
  {$ENDIF}

  // Hunspell has no fixed list, a language counts as supported once its dictionary is loaded
  Result := FHunDictionaryLoaded;
end;

function TSpellChecker.ShowContextMenu(X, Y: integer): boolean;
begin
  Result := False;
  if Assigned(FSpellChecker) then
    Result := FSpellChecker.ShowContextMenu(X, Y);
end;

procedure TSpellChecker.DoBackgroundCheck;
var
  TotalLen: integer = 0;
  RangeStart: integer = 1;
  RangeEnd: integer = 0;
  ChunkStart: integer = 1;
  ChunkEnd: integer = 0;
  ChunkText: string = '';
  ChunkErrors: RichSpellChecker.TSpellErrorArray = nil;
  i: integer = 0;
  Base: integer = 0;
  UseChunked: boolean = False;
  MaxExtend: integer = 0;
  VisStart: integer = 0;
  VisEnd: integer = 0;
  OffsetBase: integer = 0;
  DeferSuggestions: boolean = False;
  Ranges: array of record
    StartPos: integer;
    EndPos: integer;
    end
  = nil;
  r: integer = 0;
begin
  SetLength(FLastErrors, 0);

  // When two-phase mode is active, disable suggestion generation for this
  // pass. Suggestions are produced later by a separate background pass, so
  // the underlines appear on screen as soon as this pass completes
  DeferSuggestions := FTwoPhaseSuggestions and (FEngine = seHunspell) and Assigned(FHunSpellChecker);
  if DeferSuggestions then
    FHunSpellChecker.IncludeSuggestions := False;
  try

    // Determine the byte range to check. In visible-only mode this is the
    // region computed in StartCheck, otherwise the whole snapshot. The range
    // is always expressed in bytes into the UTF-8 FCheckText snapshot.
    if FCheckVisibleOnly then
    begin
      RangeStart := FCheckByteStart;
      RangeEnd := FCheckByteEnd;
    end
    else
    begin
      RangeStart := 1;
      RangeEnd := Length(FCheckText);
    end;

    if RangeEnd < RangeStart then
      Exit;

    // Chunked mode is driven by the size of the range that is actually being
    // checked, so it works the same way for the whole document and for the
    // visible area only.
    UseChunked := FChunkedCheck and (FChunkSize > 0) and ((RangeEnd - RangeStart + 1) > FChunkSize);

    if not UseChunked then
    begin
      // Single pass on the chosen range
      ChunkText := Copy(FCheckText, RangeStart, RangeEnd - RangeStart + 1);
      // OffsetBase is the character offset of the range start in the full
      // text. It is added to every error offset so the caller can draw
      // underlines against the whole document.
      OffsetBase := SpellOffsetBase(FCheckText, RangeStart - 1);

      if FEngine = seHunspell then
      begin
        if Assigned(FHunSpellChecker) then
          ChunkErrors := TSpell.HunCheckText(ChunkText, FHunSpellChecker, FOptions, FAddEmptySuggestions)
        else
          SetLength(ChunkErrors, 0);
      end
      else
        ChunkErrors := TSpell.CheckText(ChunkText, FLanguage, FOptions, FAddEmptySuggestions);

      SetLength(FLastErrors, Length(ChunkErrors));
      for i := 0 to High(ChunkErrors) do
      begin
        FLastErrors[i] := ChunkErrors[i];
        FLastErrors[i].Offset := ChunkErrors[i].Offset + OffsetBase;
      end;
      Exit;
    end;

    TotalLen := Length(FCheckText);

    // Build the list of ranges in the order they should be checked. In
    // visible-only mode the checked range is already the visible area, so
    // there is only one range. In full mode the area currently visible in
    // the memo goes first so the user sees fresh results where he is looking,
    // and the remaining parts are processed from the top of the document
    // downwards to keep the perceived order predictable.
    SetLength(Ranges, 0);
    if FCheckVisibleOnly then
    begin
      SetLength(Ranges, 1);
      Ranges[0].StartPos := RangeStart;
      Ranges[0].EndPos := RangeEnd;
    end
    else if GetVisibleTextRange(VisStart, VisEnd) and (VisStart > 1) and (VisStart <= TotalLen) then
    begin
      if VisEnd > TotalLen then
        VisEnd := TotalLen;
      // Convert the character offsets reported by the widget into byte
      // offsets into the UTF-8 snapshot, because Ranges are consumed as
      // byte positions by the chunk loop below. Without this conversion
      // the "visible area first" priority is wrong on multibyte text.
      VisStart := UTF8CodepointToByteIndex(PChar(FCheckText), TotalLen, VisStart);
      VisEnd := UTF8CodepointToByteIndex(PChar(FCheckText), TotalLen, VisEnd);
      SetLength(Ranges, 3);
      Ranges[0].StartPos := VisStart;
      Ranges[0].EndPos := VisEnd;
      Ranges[1].StartPos := 1;
      Ranges[1].EndPos := VisStart - 1;
      Ranges[2].StartPos := VisEnd + 1;
      Ranges[2].EndPos := TotalLen;
    end
    else
    begin
      SetLength(Ranges, 1);
      Ranges[0].StartPos := 1;
      Ranges[0].EndPos := TotalLen;
    end;

    for r := 0 to High(Ranges) do
    begin
      if Ranges[r].StartPos > Ranges[r].EndPos then
        Continue;
      ChunkStart := Ranges[r].StartPos;
      // Compute the character offset of ChunkStart in the full text. The
      // spell checker returns offsets in characters (UTF-16 code units on
      // Windows), while ChunkStart is a byte position in the UTF-8 snapshot.
      // Adding the byte offset directly would shift every underline by the
      // number of multi-byte characters that precede the chunk.
      OffsetBase := SpellOffsetBase(FCheckText, ChunkStart - 1);
      while ChunkStart <= Ranges[r].EndPos do
      begin
        if InterlockedCompareExchange(FCancelRequested, 0, 0) = 1 then
          Exit;

        ChunkEnd := ChunkStart + FChunkSize - 1;
        if ChunkEnd > Ranges[r].EndPos then
          ChunkEnd := Ranges[r].EndPos;
        // Extend to the next whitespace so a word is not split in half. The
        // extension is capped to avoid scanning megabytes when no whitespace
        // exists for a long time (for example a base64 blob in the text).
        MaxExtend := ChunkStart + FChunkSize * 4;
        while (ChunkEnd < Ranges[r].EndPos) and (ChunkEnd < MaxExtend) and not (FCheckText[ChunkEnd] in [' ', #9, #10, #13]) do
          Inc(ChunkEnd);
        ChunkText := Copy(FCheckText, ChunkStart, ChunkEnd - ChunkStart + 1);

        if FEngine = seHunspell then
        begin
          if Assigned(FHunSpellChecker) then
            ChunkErrors := TSpell.HunCheckText(ChunkText, FHunSpellChecker, FOptions, FAddEmptySuggestions)
          else
            SetLength(ChunkErrors, 0);
        end
        else
          ChunkErrors := TSpell.CheckText(ChunkText, FLanguage, FOptions, FAddEmptySuggestions);

        // Shift offsets from chunk local to full text coordinates. The base
        // is a character offset, matching the unit used by the checker.
        for i := 0 to High(ChunkErrors) do
          ChunkErrors[i].Offset := ChunkErrors[i].Offset + OffsetBase;

        // Update the character offset for the next iteration by counting the
        // characters in the bytes that were just consumed.
        Inc(OffsetBase, SpellOffsetBase(ChunkText, Length(ChunkText)));

        // Append to the accumulated error list. Assignment is used instead of
        // Move because TSpellError contains managed fields (string, dyn array).
        Base := Length(FLastErrors);
        SetLength(FLastErrors, Base + Length(ChunkErrors));
        for i := 0 to High(ChunkErrors) do
          FLastErrors[Base + i] := ChunkErrors[i];

        // Hand off the newly found errors to the main thread for drawing.
        // Only the visible range (Ranges[0]) should trigger an incremental
        // draw. Off screen chunks would still force the main thread to
        // repaint the visible area after every chunk with no visible benefit
        // and are the main source of hangs on large documents with dense
        // errors. Their errors are still collected in FLastErrors and drawn
        // once by the final atomic ApplyErrors call in OnBackgroundDone.
        if FAutoApply and not FDestroying and (r = 0) then
          TThread.Synchronize(nil, @ApplyPartialErrors);

        ChunkStart := ChunkEnd + 1;
      end;
    end;
  finally
    if DeferSuggestions and Assigned(FHunSpellChecker) then
      FHunSpellChecker.IncludeSuggestions := True;
  end;
end;

procedure TSpellChecker.ApplyPartialErrors;
const
  // Minimum delay between two incremental draws while a chunked check is
  // running. Drawing on every chunk makes RichEdit rebuild its formatting
  // runs and repaint the affected lines far too often, which on large
  // documents with many underlines turns the whole check into what looks
  // like a freeze near the end, where the error density is highest.
  PARTIAL_APPLY_INTERVAL_MS = 300;
  // If more than this many errors are waiting to be drawn, skip the
  // incremental pass entirely. A single very large batch can block the
  // main thread for seconds, and the final full apply in OnBackgroundDone
  // will draw everything anyway, so no underline is ever lost. Lower this
  // value if freezes persist, raise it if the incremental feedback feels
  // too coarse on well behaved documents.
  PARTIAL_APPLY_MAX_BATCH = 1000;
var
  i: integer = 0;
  NewCount: integer = 0;
  Now: QWord = 0;
begin
  if FDestroying or (FRichMemo = nil) or (FSpellChecker = nil) then
    Exit;

  // Skip drawing if the memo text changed after the snapshot was taken.
  // The flag is maintained by OnRichMemoChange, so no full text copy or
  // comparison is needed here. This keeps the per chunk overhead constant
  // even on very large documents.
  if FTextChangedSinceCheck then
    Exit;

  NewCount := Length(FLastErrors) - FAppliedErrorCount;
  if NewCount <= 0 then
    Exit;

  // Defer very large batches to avoid a multi second freeze. The final
  // apply in OnBackgroundDone still draws them, so nothing is lost.
  if NewCount > PARTIAL_APPLY_MAX_BATCH then
    Exit;

  // Throttle small batches by time so the widget is not repainted on every
  // chunk. The first call always passes because the tick is still zero.
  Now := GetTickCount64;
  if (FLastPartialApplyTick <> 0) and (Now - FLastPartialApplyTick < QWord(PARTIAL_APPLY_INTERVAL_MS)) then
    Exit;
  FLastPartialApplyTick := Now;

  // Batching through BeginUpdate/EndUpdate keeps the checker's internal
  // error list in sync with what is drawn on screen. This is important for
  // the context menu: GetErrorAtTextPos searches that list, so errors that
  // are only painted directly would be invisible to the menu. EndUpdate
  // is incremental now, so only the newly added errors are drawn and the
  // total cost stays linear across all chunks.
  FInternalChange := True;
  try
    FSpellChecker.BeginUpdate;
    try
      for i := FAppliedErrorCount to High(FLastErrors) do
        FSpellChecker.AddError(
          FLastErrors[i].Offset,
          FLastErrors[i].Length,
          FLastErrors[i].Message,
          FLastErrors[i].Replacements,
          FLastErrors[i].Color);
    finally
      FSpellChecker.EndUpdate;
    end;
    FAppliedErrorCount := Length(FLastErrors);
  finally
    FInternalChange := False;
  end;
end;

function TSpellChecker.GetVisibleTextRange(out AStart, AEnd: integer): boolean;
  {$IFDEF WINDOWS}
var
  PtTopLeft, PtBottomRight: TPoint;
  P1, P2: Longint;
  {$ELSE}
var
  P1, P2: integer;
  {$ENDIF}
begin
  Result := False;
  AStart := 1;
  AEnd := 0;
  if not Assigned(FRichMemo) then
    Exit;

  {$IFDEF WINDOWS}
  // Map the top left and bottom right corners of the client area to
  // character positions. EM_CHARFROMPOS returns 0 based indices.
  PtTopLeft.X := 0;
  PtTopLeft.Y := 0;
  PtBottomRight.X := FRichMemo.ClientWidth - 1;
  PtBottomRight.Y := FRichMemo.ClientHeight - 1;
  {$HINTS OFF}
  P1 := SendMessage(FRichMemo.Handle, EM_CHARFROMPOS, 0, LPARAM(PtrInt(@PtTopLeft)));
  P2 := SendMessage(FRichMemo.Handle, EM_CHARFROMPOS, 0, LPARAM(PtrInt(@PtBottomRight)));
  {$HINTS ON}
  if (P1 < 0) or (P2 < 0) then
    Exit;
  AStart := P1 + 1;
  AEnd := P2 + 1;
  {$ELSE}
  // On other platforms fall back to the cross platform RichMemo helper
  P1 := FRichMemo.CharAtPos(0, 0);
  P2 := FRichMemo.CharAtPos(FRichMemo.ClientWidth - 1, FRichMemo.ClientHeight - 1);
  if (P1 < 0) or (P2 < 0) then
    Exit;
  AStart := P1 + 1;
  AEnd := P2 + 1;
  {$ENDIF}

  if AEnd < AStart then
    AEnd := AStart;
  Result := True;
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

  FChecking := False;

  // Apply a dictionary change that was deferred while the worker thread was
  // still running. Now that FChecking is False, it is safe to free the old
  // dictionary object, so no blocking wait is required.
  if FDictionaryPendingAction = dpaUnload then
  begin
    FDictionaryPendingAction := dpaNone;
    FPendingCheck := False;
    UnloadHunDictionary;
    Exit;
  end
  else if FDictionaryPendingAction = dpaReload then
  begin
    FDictionaryPendingAction := dpaNone;
    FPendingCheck := False;
    LoadHunDictionaryForLanguage;
    Exit;
  end;

  if InterlockedCompareExchange(FCancelRequested, 0, 0) = 1 then
  begin
    if FPendingCheck then
    begin
      FPendingCheck := False;
      StartCheck;
    end;
    Exit;
  end;

  if not FEnabled or (FRichMemo = nil) or (FSpellChecker = nil) then
  begin
    if FPendingCheck then
    begin
      FPendingCheck := False;
      StartCheck;
    end;
    Exit;
  end;

  if FAutoApply then
  begin
    // Skip applying if text has changed since check started. The flag is
    // set by OnRichMemoChange, so a full text comparison is not needed.
    if not FTextChangedSinceCheck then
    begin
      // The final atomic replace is what removes stale underlines left
      // over from the previous run. In chunked mode the incremental pass
      // only added new underlines on top, so this call is required to
      // discard everything that is no longer an error.
      FRichMemo.Lines.BeginUpdate;
      FInternalChange := True;
      try
        TSpell.ApplyErrors(FSpellChecker, FLastErrors);
      finally
        FRichMemo.Lines.EndUpdate;
        FInternalChange := False;
      end;
    end;
  end;

  // Start the second pass that generates suggestions for the errors just
  // drawn. Running it now means the user will see the suggestions as soon
  // as the context menu opens over one of these errors
  if FTwoPhaseSuggestions and (FEngine = seHunspell) and (Length(FLastErrors) > 0) and not FTextChangedSinceCheck then
    StartSuggestionPass;

  ErrorCount := Length(FLastErrors);

  if Assigned(FOnSpellCheckComplete) then
    FOnSpellCheckComplete(Self, ErrorCount);

  if FPendingCheck then
  begin
    FPendingCheck := False;
    StartCheck;
  end;
end;

procedure TSpellChecker.StartSuggestionPass;
var
  i: integer;
begin
  if FSuggesting then
    Exit;
  if FDestroying then
    Exit;
  if not Assigned(FHunSpellChecker) then
    Exit;
  if Length(FLastErrors) = 0 then
    Exit;

  SetLength(FSuggestionErrors, Length(FLastErrors));
  for i := 0 to High(FSuggestionErrors) do
    SetLength(FSuggestionErrors[i], 0);

  FSuggesting := True;
  RunAsync(FSuggestionThread, @DoBackgroundSuggestions, @OnSuggestionsReady);
end;

procedure TSpellChecker.DoBackgroundSuggestions;
var
  i, j: integer;
  word: string;
  Sug: TStringArray;
begin
  for i := 0 to High(FLastErrors) do
  begin
    if FDestroying then
      Exit;
    if InterlockedCompareExchange(FCancelRequested, 0, 0) = 1 then
      Exit;
    if not Assigned(FHunSpellChecker) then
      Exit;

    // Extract the misspelled word from the snapshot text. The offsets in
    // FLastErrors are character based, so UTF8Copy is the right tool here
    word := UTF8Copy(FCheckText, FLastErrors[i].Offset + 1, FLastErrors[i].Length);
    if word = '' then
      Continue;

    Sug := FHunSpellChecker.Suggest(word);

    SetLength(FSuggestionErrors[i], Length(Sug));
    for j := 0 to High(Sug) do
      FSuggestionErrors[i][j] := Sug[j];
  end;
end;

procedure TSpellChecker.OnSuggestionsReady;
var
  i: integer;
begin
  FSuggesting := False;
  FSuggestionThread := nil;

  if FDestroying then
    Exit;
  if FTextChangedSinceCheck then
    Exit;
  if InterlockedCompareExchange(FCancelRequested, 0, 0) = 1 then
    Exit;

  // Attach the new suggestions to both the internal error list and the
  // RichSpellChecker records, so the context menu shows them the next
  // time the user opens it over one of these errors
  for i := 0 to High(FLastErrors) do
  begin
    if i > High(FSuggestionErrors) then
      Break;
    if Length(FSuggestionErrors[i]) = 0 then
      Continue;

    FLastErrors[i].Replacements := FSuggestionErrors[i];

    if Assigned(FSpellChecker) then
      FSpellChecker.UpdateErrorSuggestions(
        FLastErrors[i].Offset,
        FLastErrors[i].Length,
        FSuggestionErrors[i]);
  end;

  SetLength(FSuggestionErrors, 0);
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
  if csLoading in ComponentState then Exit;

  // Record that a reload has been requested. If a load is already in progress
  // its completion callback will notice the generation mismatch and reload.
  Inc(FLoadGeneration);

  // If an async load is already running, let it finish first
  if FLoadingDictionary then Exit;

  // If a background check is running, defer the reload instead of blocking
  // the main thread. OnBackgroundDone will re-enter this method when the
  // worker thread has finished and it is safe to free the old dictionary.
  if FChecking then
  begin
    FPendingCheck := False;
    FDictionaryPendingAction := dpaReload;
    InterlockedExchange(FCancelRequested, 1);
    Exit;
  end;

  // A running suggestion pass uses the current dictionary instance, so
  // wait for it to finish before replacing the dictionary
  if FSuggesting then
  begin
    InterlockedExchange(FCancelRequested, 1);
    while FSuggesting do
    begin
      Sleep(5);
      CheckSynchronize;
    end;
  end;

  // Prevent concurrent downloads
  if FDownloading then Exit;

  // Unload previous dictionary. Safe now because no check is running and
  // no async load is in progress.
  if Assigned(FHunSpellChecker) then
  begin
    FreeAndNil(FHunSpellChecker);
    FHunDictionaryLoaded := False;
  end;

  if FLanguage = '' then
    Exit;

  found := False;
  if FDicPath <> '' then
  begin
    // Resolve relative path to application directory
    basePath := IncludeTrailingPathDelimiter(ResolveRelativeDicPath(FDicPath));

    candidates := HunspellDictionaryCandidates(FLanguage);

    for i := 0 to High(candidates) do
    begin
      affFile := basePath + candidates[i] + '.aff';
      dicFile := basePath + candidates[i] + '.dic';
      if FileExists(affFile) and FileExists(dicFile) then
      begin
        StartAsyncDictionaryLoadFromFiles(affFile, dicFile);
        found := True;
        Break;
      end;
    end;
  end;

  if not found and (FDicUrl <> '') then
  begin
    // Start asynchronous download
    StartDictionaryDownload(FLanguage);
  end;
end;

procedure TSpellChecker.StartAsyncDictionaryLoadFromFiles(const AFFFile, DICFile: string);
begin
  if FLoadingDictionary then Exit; // Guard, should not happen

  // Discard leftovers from a previous load
  FreeAndNil(FLoadAffStream);
  FreeAndNil(FLoadDicStream);
  if Assigned(FLocalChecker) then
    FreeAndNil(FLocalChecker);

  FLoadAffFile := AFFFile;
  FLoadDicFile := DICFile;
  FLoadSuccess := False;
  FLoadingGeneration := FLoadGeneration;
  FLoadingDictionary := True;

  RunAsync(FLoadThread, @DoLoadHunDictionary, @OnHunDictionaryLoaded);
end;

procedure TSpellChecker.StartAsyncDictionaryLoadFromStream(AFFStream, DICStream: TStream);
begin
  if FLoadingDictionary then Exit; // Guard, should not happen

  // Discard leftovers from a previous load
  FreeAndNil(FLoadAffStream);
  FreeAndNil(FLoadDicStream);
  if Assigned(FLocalChecker) then
    FreeAndNil(FLocalChecker);

  // The source streams may be freed by the caller after we return, so we
  // copy their contents into memory streams that we own.
  FLoadAffStream := TMemoryStream.Create;
  FLoadDicStream := TMemoryStream.Create;
  AFFStream.Position := 0;
  DICStream.Position := 0;
  FLoadAffStream.CopyFrom(AFFStream, AFFStream.Size);
  FLoadDicStream.CopyFrom(DICStream, DICStream.Size);
  FLoadAffStream.Position := 0;
  FLoadDicStream.Position := 0;

  FLoadAffFile := '';
  FLoadDicFile := '';
  FLoadSuccess := False;
  FLoadingGeneration := FLoadGeneration;
  FLoadingDictionary := True;

  RunAsync(FLoadThread, @DoLoadHunDictionary, @OnHunDictionaryLoaded);
end;

procedure TSpellChecker.DoLoadHunDictionary;
begin
  // This method runs in a background thread, do not touch UI here
  FLocalChecker := THunSpellChecker.Create;
  try
    if Assigned(FLoadAffStream) then
      FLoadSuccess := FLocalChecker.LoadFromStream(FLoadAffStream, FLoadDicStream)
    else
      FLoadSuccess := FLocalChecker.LoadFromFiles(FLoadAffFile, FLoadDicFile);
  except
    FLoadSuccess := False;
  end;
  if not FLoadSuccess then
    FreeAndNil(FLocalChecker);
end;

procedure TSpellChecker.OnHunDictionaryLoaded;
begin
  // This method runs in the main thread after DoLoadHunDictionary completes
  FLoadingDictionary := False;

  // Free temporary streams used for stream based loading
  FreeAndNil(FLoadAffStream);
  FreeAndNil(FLoadDicStream);

  if FDestroying then
  begin
    if Assigned(FLocalChecker) then
      FreeAndNil(FLocalChecker);
    Exit;
  end;

  // Handle a deferred unload requested while the load was running
  if FDictionaryPendingAction = dpaUnload then
  begin
    FDictionaryPendingAction := dpaNone;
    if Assigned(FLocalChecker) then
      FreeAndNil(FLocalChecker);
    UnloadHunDictionary;
    Exit;
  end;

  // Discard a failed load
  if not FLoadSuccess or not Assigned(FLocalChecker) then
  begin
    if Assigned(FLocalChecker) then
      FreeAndNil(FLocalChecker);
    Exit;
  end;

  // If the load parameters changed while loading, discard the result and reload
  if FLoadingGeneration <> FLoadGeneration then
  begin
    FreeAndNil(FLocalChecker);
    LoadHunDictionaryForLanguage;
    Exit;
  end;

  // Install the newly loaded dictionary
  if Assigned(FHunSpellChecker) then
    FreeAndNil(FHunSpellChecker);
  FHunSpellChecker := FLocalChecker;
  FLocalChecker := nil;
  FHunDictionaryLoaded := True;

  if FEnabled and Assigned(FRichMemo) then
    CheckNow;
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
  flatPath: string;
  librePath: string;
  wooormPath: string;
begin
  url := Template;

  if Pos('{dict}', url) > 0 then
  begin
    // Replace {dict} with candidate code + extension
    url := StringReplace(url, '{dict}', CandidateCode + '.' + Ext, [rfReplaceAll]);
  end
  else if Pos('{plaindict}', url) > 0 then
  begin
    flatPath := GetFlatDictByCode(CandidateCode);
    if flatPath = '' then
      Exit('');
    url := StringReplace(url, '{plaindict}', flatPath + '.' + Ext, [rfReplaceAll]);
  end
  else if Pos('{libredict}', url) > 0 then
  begin
    librePath := GetLibreOfficePathByCode(CandidateCode);
    if librePath = '' then
      Exit('');
    url := StringReplace(url, '{libredict}', librePath + '.' + Ext, [rfReplaceAll]);
  end
  else if Pos('{wooormdict}', url) > 0 then
  begin
    wooormPath := GetWooormPathByCode(CandidateCode);
    if wooormPath = '' then
      Exit('');
    url := StringReplace(url, '{wooormdict}', wooormPath + '.' + Ext, [rfReplaceAll]);
  end
  else
  begin
    // No placeholder found, assume template is base URL, append code and ext?
    // For safety, return empty to avoid malformed URLs
    Exit('');
  end;

  Result := url;
end;

function TSpellChecker.NormalizeFlatCode(const Code: string): string;
var
  S, First, Second: string;
  P, Sep: integer;
begin
  // Trim and drop locale suffix: ru_RU.UTF-8 -> ru_RU
  S := Trim(Code);
  if S = '' then
  begin
    Result := '';
    Exit;
  end;

  P := Pos('.', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);

  // Find separator, either '_' or '-'
  Sep := Pos('_', S);
  if Sep = 0 then
    Sep := Pos('-', S);

  if Sep = 0 then
  begin
    // Language only, two or three letters
    Result := LowerCase(S);
    Exit;
  end;

  First := LowerCase(Copy(S, 1, Sep - 1));
  Second := Copy(S, Sep + 1, MaxInt);

  // If the region part is exactly two letters, uppercase it (ru_RU, en-us)
  if Length(Second) = 2 then
    Second := UpperCase(Second);

  Result := First + '_' + Second;
end;

function TSpellChecker.GetFlatDictByCode(const Code: string): string;
var
  C: string;
begin
  // Returns base file name (without extension) in the flat dic folder
  // for the given language code. Caller appends '.aff' or '.dic'.
  // Input may use '-' or '_' and may carry a locale suffix like '.UTF-8'.
  C := NormalizeFlatCode(Code);

  case C of
    // A
    'af', 'af_ZA': Result := 'af_ZA';
    'an', 'an_ES': Result := 'an_ES';
    'ar': Result := 'ar';
    'as', 'as_IN': Result := 'as_IN';

    // B
    'be', 'be_BY': Result := 'be_BY';
    'be_official': Result := 'be-official';
    'bg', 'bg_BG': Result := 'bg_BG';
    'bn', 'bn_BD': Result := 'bn_BD';
    'bo': Result := 'bo';
    'br', 'br_FR': Result := 'br_FR';
    'bs', 'bs_BA': Result := 'bs_BA';

    // C
    'ca': Result := 'ca';
    'ca_valencia': Result := 'ca-valencia';
    'ckb': Result := 'ckb';
    'cs', 'cs_CZ': Result := 'cs_CZ';
    'cy': Result := 'cy';

    // D
    'da', 'da_DK': Result := 'da_DK';
    'de', 'de_DE', 'de_DE_frami': Result := 'de_DE_frami';
    'de_AT', 'de_AT_frami': Result := 'de_AT_frami';
    'de_CH', 'de_CH_frami': Result := 'de_CH_frami';

    // E
    'el', 'el_GR': Result := 'el_GR';
    'el_polyton': Result := 'el-polyton';
    'en', 'en_US': Result := 'en_US';
    'en_AU': Result := 'en_AU';
    'en_CA': Result := 'en_CA';
    'en_GB': Result := 'en_GB';
    'en_ZA': Result := 'en_ZA';
    'eo': Result := 'eo';
    'es', 'es_ES': Result := 'es_ES';
    'es_ANY': Result := 'es_ANY';
    'es_AR': Result := 'es_AR';
    'es_BO': Result := 'es_BO';
    'es_CL': Result := 'es_CL';
    'es_CO': Result := 'es_CO';
    'es_CR': Result := 'es_CR';
    'es_CU': Result := 'es_CU';
    'es_DO': Result := 'es_DO';
    'es_EC': Result := 'es_EC';
    'es_GQ': Result := 'es_GQ';
    'es_GT': Result := 'es_GT';
    'es_HN': Result := 'es_HN';
    'es_MX': Result := 'es_MX';
    'es_NI': Result := 'es_NI';
    'es_PA': Result := 'es_PA';
    'es_PE': Result := 'es_PE';
    'es_PH': Result := 'es_PH';
    'es_PR': Result := 'es_PR';
    'es_PY': Result := 'es_PY';
    'es_SV': Result := 'es_SV';
    'es_US': Result := 'es_US';
    'es_UY': Result := 'es_UY';
    'es_VE': Result := 'es_VE';
    'et', 'et_EE': Result := 'et_EE';
    'eu': Result := 'eu';

    // F
    'fa', 'fa_IR': Result := 'fa-IR';
    'fi', 'fi_FI': Result := 'fi_FI';
    'fo': Result := 'fo';
    'fr': Result := 'fr';
    'fur': Result := 'fur';
    'fy': Result := 'fy';

    // G
    'ga': Result := 'ga';
    'gd', 'gd_GB': Result := 'gd_GB';
    'gl', 'gl_ES': Result := 'gl_ES';
    'gug': Result := 'gug';
    'gu', 'gu_IN': Result := 'gu_IN';

    // H
    'he', 'he_IL': Result := 'he_IL';
    'hi', 'hi_IN': Result := 'hi_IN';
    'hr', 'hr_HR': Result := 'hr_HR';
    'hu', 'hu_HU': Result := 'hu_HU';
    'hy': Result := 'hy';
    'hyw': Result := 'hyw';

    // I
    'ia': Result := 'ia';
    'id', 'id_ID': Result := 'id_ID';
    'ie': Result := 'ie';
    'is': Result := 'is';
    'it', 'it_IT': Result := 'it_IT';

    // K
    'ka': Result := 'ka';
    'kmr', 'kmr_Latn': Result := 'kmr_Latn';
    'kn', 'kn_IN': Result := 'kn_IN';
    'ko', 'ko_KR': Result := 'ko_KR';

    // L
    'la': Result := 'la';
    'lb': Result := 'lb';
    'lo', 'lo_LA': Result := 'lo_LA';
    'lt': Result := 'lt';
    'ltg': Result := 'ltg';
    'lv', 'lv_LV': Result := 'lv_LV';

    // M
    'mk': Result := 'mk';
    'mn', 'mn_MN': Result := 'mn_MN';
    'mr', 'mr_IN': Result := 'mr_IN';

    // N
    'nb', 'nb_NO', 'no': Result := 'nb_NO';
    'nds': Result := 'nds';
    'ne', 'ne_NP': Result := 'ne_NP';
    'nl', 'nl_NL': Result := 'nl_NL';
    'nn', 'nn_NO': Result := 'nn_NO';

    // O
    'oc', 'oc_FR': Result := 'oc_FR';
    'or', 'or_IN': Result := 'or_IN';

    // P
    'pa', 'pa_IN': Result := 'pa_IN';
    'pl', 'pl_PL': Result := 'pl_PL';
    'pt', 'pt_PT': Result := 'pt_PT';
    'pt_BR': Result := 'pt_BR';

    // R
    'ro', 'ro_RO': Result := 'ro_RO';
    'ru', 'ru_RU': Result := 'ru_RU';
    'rw': Result := 'rw';

    // S
    'sa', 'sa_IN': Result := 'sa_IN';
    'si', 'si_LK': Result := 'si_LK';
    'sk', 'sk_SK': Result := 'sk_SK';
    'sl', 'sl_SI': Result := 'sl_SI';
    'sq', 'sq_AL': Result := 'sq_AL';
    'sr': Result := 'sr';
    'sr_Latn': Result := 'sr-Latn';
    'sv', 'sv_SE': Result := 'sv_SE';
    'sv_FI': Result := 'sv_FI';
    'sw', 'sw_TZ': Result := 'sw_TZ';

    // T
    'ta', 'ta_IN': Result := 'ta_IN';
    'te', 'te_IN': Result := 'te_IN';
    'th', 'th_TH': Result := 'th_TH';
    'tk': Result := 'tk';
    'tlh': Result := 'tlh';
    'tlh_Latn': Result := 'tlh-Latn';
    'tr', 'tr_TR': Result := 'tr_TR';

    // U, V
    'uk', 'uk_UA': Result := 'uk_UA';
    'vi', 'vi_VN': Result := 'vi_VN';
    else
      Result := '';
  end;
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
    'pt': Result := 'pt_PT/pt_PT';
    'pt_PT': Result := 'pt_PT/pt_PT';
    'pt_BR': Result := 'pt_BR/pt_BR';
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
    'zu_ZA': Result := 'zu_ZA/zu_ZA';
    else
      Result := '';
  end;
end;

function TSpellChecker.GetWooormPathByCode(const Code: string): string;
begin
  // Returns path (without extension) inside wooorm dictionaries repository for given candidate code.
  // Code is expected to be a candidate from HunspellDictionaryCandidates (may contain '-' or '_').
  case Code of
    'bg': Result := 'bg/index';
    'bg_BG': Result := 'bg/index';
    'br': Result := 'br/index';
    'br_FR': Result := 'br/index';
    'ca': Result := 'ca/index';
    'ca_ES': Result := 'ca/index';
    'ca-valencia': Result := 'ca-valencia/index';
    'cs': Result := 'cs/index';
    'cs_CZ': Result := 'cs/index';
    'cy': Result := 'cy/index';
    'da': Result := 'da/index';
    'da_DK': Result := 'da/index';
    'de': Result := 'de/index';
    'de_DE': Result := 'de/index';
    'de_DE_frami': Result := 'de/index';
    'de_AT': Result := 'de-AT/index';
    'de_AT_frami': Result := 'de-AT/index';
    'de_CH': Result := 'de-CH/index';
    'de_CH_frami': Result := 'de-CH/index';
    'el': Result := 'el/index';
    'el_GR': Result := 'el/index';
    'el-polyton': Result := 'el-polyton/index';
    'en': Result := 'en/index';
    'en_US': Result := 'en/index';
    'en_AU': Result := 'en-AU/index';
    'en_CA': Result := 'en-CA/index';
    'en_GB': Result := 'en-GB/index';
    'en_ZA': Result := 'en-ZA/index';
    'eo': Result := 'eo/index';
    'es': Result := 'es/index';
    'es_ES': Result := 'es/index';
    'es_AR': Result := 'es-AR/index';
    'es_BO': Result := 'es-BO/index';
    'es_CL': Result := 'es-CL/index';
    'es_CO': Result := 'es-CO/index';
    'es_CR': Result := 'es-CR/index';
    'es_CU': Result := 'es-CU/index';
    'es_DO': Result := 'es-DO/index';
    'es_EC': Result := 'es-EC/index';
    'es_GT': Result := 'es-GT/index';
    'es_HN': Result := 'es-HN/index';
    'es_MX': Result := 'es-MX/index';
    'es_NI': Result := 'es-NI/index';
    'es_PA': Result := 'es-PA/index';
    'es_PE': Result := 'es-PE/index';
    'es_PH': Result := 'es-PH/index';
    'es_PR': Result := 'es-PR/index';
    'es_PY': Result := 'es-PY/index';
    'es_SV': Result := 'es-SV/index';
    'es_US': Result := 'es-US/index';
    'es_UY': Result := 'es-UY/index';
    'es_VE': Result := 'es-VE/index';
    'et': Result := 'et/index';
    'et_EE': Result := 'et/index';
    'eu': Result := 'eu/index';
    'fa': Result := 'fa/index';
    'fa_IR': Result := 'fa/index';
    'fa-IR': Result := 'fa/index';
    'fo': Result := 'fo/index';
    'fr': Result := 'fr/index';
    'fr_FR': Result := 'fr/index';
    'fur': Result := 'fur/index';
    'fy': Result := 'fy/index';
    'ga': Result := 'ga/index';
    'gd': Result := 'gd/index';
    'gd_GB': Result := 'gd/index';
    'gl': Result := 'gl/index';
    'gl_ES': Result := 'gl/index';
    'he': Result := 'he/index';
    'he_IL': Result := 'he/index';
    'hr': Result := 'hr/index';
    'hr_HR': Result := 'hr/index';
    'hu': Result := 'hu/index';
    'hu_HU': Result := 'hu/index';
    'hy': Result := 'hy/index';
    'hy_AM': Result := 'hy/index';
    'hyw': Result := 'hyw/index';
    'ia': Result := 'ia/index';
    'ie': Result := 'ie/index';
    'is': Result := 'is/index';
    'it': Result := 'it/index';
    'it_IT': Result := 'it/index';
    'ka': Result := 'ka/index';
    'ka_GE': Result := 'ka/index';
    'ko': Result := 'ko/index';
    'ko_KR': Result := 'ko/index';
    'la': Result := 'la/index';
    'lb': Result := 'lb/index';
    'lt': Result := 'lt/index';
    'lt_LT': Result := 'lt/index';
    'ltg': Result := 'ltg/index';
    'lv': Result := 'lv/index';
    'lv_LV': Result := 'lv/index';
    'mk': Result := 'mk/index';
    'mn': Result := 'mn/index';
    'mn_MN': Result := 'mn/index';
    'nb': Result := 'nb/index';
    'nb_NO': Result := 'nb/index';
    'nds': Result := 'nds/index';
    'ne': Result := 'ne/index';
    'ne_NP': Result := 'ne/index';
    'nl': Result := 'nl/index';
    'nl_NL': Result := 'nl/index';
    'nn': Result := 'nn/index';
    'nn_NO': Result := 'nn/index';
    'no': Result := 'nb/index';
    'oc': Result := 'oc/index';
    'oc_FR': Result := 'oc/index';
    'pl': Result := 'pl/index';
    'pl_PL': Result := 'pl/index';
    'pt': Result := 'pt-PT/index';
    'pt_PT': Result := 'pt-PT/index';
    'pt_BR': Result := 'pt/index';
    'ro': Result := 'ro/index';
    'ro_RO': Result := 'ro/index';
    'ru': Result := 'ru/index';
    'ru_RU': Result := 'ru/index';
    'rw': Result := 'rw/index';
    'sk': Result := 'sk/index';
    'sk_SK': Result := 'sk/index';
    'sl': Result := 'sl/index';
    'sl_SI': Result := 'sl/index';
    'sr': Result := 'sr/index';
    'sr_Latn': Result := 'sr-Latn/index';
    'sr-Latn': Result := 'sr-Latn/index';
    'sv': Result := 'sv/index';
    'sv_SE': Result := 'sv/index';
    'sv_FI': Result := 'sv-FI/index';
    'tk': Result := 'tk/index';
    'tlh': Result := 'tlh/index';
    'tlh-Latn': Result := 'tlh-Latn/index';
    'tr': Result := 'tr/index';
    'tr_TR': Result := 'tr/index';
    'uk': Result := 'uk/index';
    'uk_UA': Result := 'uk/index';
    'vi': Result := 'vi/index';
    'vi_VN': Result := 'vi/index';
    else
      Result := '';
  end;
end;

function TSpellChecker.ResolveRelativeDicPath(const APath: string): string;
var
  P: string;
begin
  // Return an absolute path for DicPath. The {temp} placeholder is expanded
  // to the system temporary directory and takes precedence over the design
  // versus runtime distinction below. Directory separators inside the
  // resulting path are normalized for the current platform, so the same
  // property value works on Windows, Linux and macOS. Without the
  // placeholder relative paths are resolved against the folder of the
  // executable at runtime, while at design time the system temp directory
  // is used to keep dictionaries out of the Lazarus installation and the
  // user project folder.
  if Pos('{temp}', LowerCase(APath)) > 0 then
  begin
    P := StringReplace(APath, '{temp}', ExcludeTrailingPathDelimiter(GetTempDir), [rfReplaceAll, rfIgnoreCase]);
    Result := SetDirSeparators(P);
    Exit;
  end;

  if IsPathAbsolute(APath) then
    Result := APath
  else if csDesigning in ComponentState then
    Result := IncludeTrailingPathDelimiter(GetTempDir) + APath
  else
    Result := ExtractFilePath(ParamStr(0)) + APath;
end;

procedure TSpellChecker.OnDictionaryDownloadComplete(Sender: TObject; AStreams: array of TMemoryStream; AErrors: array of string);
var
  affFileName, dicFileName: string;
  basePath: string;
begin
  FDownloading := False;

  // Ignore if component is being destroyed
  if FDestroying then Exit;

  // If language changed during download, restart the load for the current language
  if FDownloadLang <> FLanguage then
  begin
    LoadHunDictionaryForLanguage;
    Exit;
  end;

  // Check if we got both streams without errors
  if (Length(AStreams) < 2) or (Length(AErrors) < 2) then Exit;
  if (AErrors[0] <> '') or (AErrors[1] <> '') then Exit;
  if (AStreams[0] = nil) or (AStreams[1] = nil) then Exit;
  if (AStreams[0].Size = 0) or (AStreams[1].Size = 0) then Exit;

  if FDicPath <> '' then
  begin
    // Resolve relative path to application directory
    basePath := IncludeTrailingPathDelimiter(ResolveRelativeDicPath(FDicPath));

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

  // Start asynchronous load from the downloaded streams
  StartAsyncDictionaryLoadFromStream(AStreams[0], AStreams[1]);
end;

end.
