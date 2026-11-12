//-----------------------------------------------------------------------------------
//  DesignKit Package © 2026 by Alexander Tverskoy
//  Licensed under the GNU General Public License, Version 3 (GPL-3.0)
//  You may obtain a copy of the License at https://www.gnu.org/licenses/gpl-3.0.html
//-----------------------------------------------------------------------------------

unit FormAbout;

{$mode ObjFPC}{$H+}

interface

uses
  Forms,
  Classes,
  StdCtrls,
  ExtCtrls,
  Graphics,
  LCLIntf;

type

  { TFormAbout }

  TFormAbout = class(TForm)
    buttonOk: TButton;
    imageLogo: TImage;
    LabelUrlGithub: TLabel;
    labelBy: TLabel;
    labelName: TLabel;
    labelLic: TLabel;
    LabelUrlEmail: TLabel;
    MemoAbout: TMemo;
    labelBy1: TLabel;
    labelVersion: TLabel;
    panelHeader: TPanel;
    panelBody: TPanel;
    panelFooter: TPanel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure LabelUrlEmailClick(Sender: TObject);
  public
    // Dialog content - assigned by the controlling component before ApplySettings
    AppName: string;
    Copyright: string;
    VersionText: string;
    AppVersion: string;
    LicenseLine1: string;
    LicenseLine2: string;
    ContactLine: string;
    EmailCaption: string;
    EmailUrl: string;
    GithubCaption: string;
    GithubUrl: string;
    AboutText: string;
    OkCaption: string;
    LogoPicture: TPicture;
    HeaderColorLight: TColor;
    HeaderColorDark: TColor;
    constructor Create(AOwner: TComponent); override;
    procedure ApplySettings;
  end;

implementation

uses DarkUtils;

  {$R *.lfm}

  { TFormAbout }

constructor TFormAbout.Create(AOwner: TComponent);
begin
  LogoPicture := TPicture.Create;
  // Default header colors, override via ApplySettings or from the host component
  HeaderColorLight := $00F8F4F0;
  HeaderColorDark := $002D2D2D;
  inherited Create(AOwner);
end;

procedure TFormAbout.FormCreate(Sender: TObject);
begin
  // Links: color within the theme
  LabelUrlEmail.Font.Color := TDarkUtils.ThemeColor(clBlue, clSkyBlue);
  LabelUrlGithub.Font.Color := LabelUrlEmail.Font.Color;

  // Panels: Light/Dark Theme Adaptation
  panelHeader.Color := TDarkUtils.ThemeColor(HeaderColorLight, HeaderColorDark);
  panelBody.Color := TDarkUtils.ThemeColor(clWhite, $001E1E1E);
  labelVersion.Font.Color := TDarkUtils.ThemeColor(clGray, clSilver);
  panelFooter.Color := panelBody.Color;
  MemoAbout.Color := panelBody.Color;
end;

procedure TFormAbout.FormDestroy(Sender: TObject);
begin
  LogoPicture.Free;
end;

procedure TFormAbout.LabelUrlEmailClick(Sender: TObject);
var
  Url: string;
begin
  Url := (Sender as TLabel).Hint;
  if Url <> '' then
    OpenUrl(Url);
end;

procedure TFormAbout.ApplySettings;
var
  FullName: string = '';
  Arch: string = '';
begin
  // Compose name and copyright
  if (AppName <> '') and (Copyright <> '') then
    FullName := AppName + ' ' + Copyright
  else if AppName <> '' then
    FullName := AppName
  else
    FullName := Copyright;
  labelName.Caption := FullName;

  // Compose version line: translated "Version" + app version + arch
  {$IFDEF CPU64}
    Arch := 'x64';
  {$ELSE}
  Arch := 'x86';
  {$ENDIF}
  if AppVersion <> '' then
    labelVersion.Caption := VersionText + ' ' + AppVersion + ' · ' + Arch
  else
    labelVersion.Caption := VersionText + ' · ' + Arch;

  labelBy.Caption := LicenseLine1;
  labelBy1.Caption := LicenseLine2;
  labelLic.Caption := ContactLine;

  // Email link
  LabelUrlEmail.Caption := EmailCaption;
  LabelUrlEmail.Hint := EmailUrl;
  LabelUrlEmail.Visible := EmailCaption <> '';

  // Github link
  LabelUrlGithub.Caption := GithubCaption;
  LabelUrlGithub.Hint := GithubUrl;
  LabelUrlGithub.Visible := GithubCaption <> '';

  // About text (memo)
  MemoAbout.Lines.Text := AboutText;

  // Header panel color - the host component may override the default
  panelHeader.Color := TDarkUtils.ThemeColor(HeaderColorLight, HeaderColorDark);

  // OK button
  buttonOk.Caption := OkCaption;

  // Logo
  if (LogoPicture.Graphic <> nil) and not LogoPicture.Graphic.Empty then
  begin
    imageLogo.Picture.Assign(LogoPicture);
    imageLogo.Visible := True;
  end
  else
    imageLogo.Visible := False;
end;

end.
