//-----------------------------------------------------------------------------------
//  DesignKit Package © 2026 by Alexander Tverskoy
//  Licensed under the GNU General Public License, Version 3 (GPL-3.0)
//  You may obtain a copy of the License at https://www.gnu.org/licenses/gpl-3.0.html
//-----------------------------------------------------------------------------------

unit AppDialogs;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Graphics, Forms, Controls, SysUtils, LResources, FormAbout, FormDonate;

type

  { TAboutDialogOptions - published settings for the About dialog }

  TAboutDialogOptions = class(TComponent)
  private
    FCaption: TCaption;
    FAppName: TCaption;
    FCopyright: TCaption;
    FVersion: TCaption;
    FAppVersion: TCaption;
    FLicenseLine1: TCaption;
    FLicenseLine2: TCaption;
    FContactLine: TCaption;
    FEmailCaption: TCaption;
    FEmailUrl: TCaption;
    FGithubCaption: TCaption;
    FGithubUrl: TCaption;
    FAboutText: TCaption;
    FOkCaption: TCaption;
    FWidth: integer;
    FHeight: integer;
    FHeaderColorLight: TColor;
    FHeaderColorDark: TColor;
    FMainIcon: TPicture;
    procedure SetMainIcon(AValue: TPicture);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property Caption: TCaption read FCaption write FCaption;
    property AppName: TCaption read FAppName write FAppName;
    property Copyright: TCaption read FCopyright write FCopyright;
    property Version: TCaption read FVersion write FVersion;
    property AppVersion: TCaption read FAppVersion write FAppVersion;
    property LicenseLine1: TCaption read FLicenseLine1 write FLicenseLine1;
    property LicenseLine2: TCaption read FLicenseLine2 write FLicenseLine2;
    property ContactLine: TCaption read FContactLine write FContactLine;
    property EmailCaption: TCaption read FEmailCaption write FEmailCaption;
    property EmailUrl: TCaption read FEmailUrl write FEmailUrl;
    property GithubCaption: TCaption read FGithubCaption write FGithubCaption;
    property GithubUrl: TCaption read FGithubUrl write FGithubUrl;
    property AboutText: TCaption read FAboutText write FAboutText;
    property OkCaption: TCaption read FOkCaption write FOkCaption;
    property Width: integer read FWidth write FWidth default 580;
    property Height: integer read FHeight write FHeight default 470;
    // Header panel colors; shown depending on the current light/dark theme
    property HeaderColorLight: TColor read FHeaderColorLight write FHeaderColorLight default $00F8F4F0;
    property HeaderColorDark: TColor read FHeaderColorDark write FHeaderColorDark default $002D2D2D;
    property MainIcon: TPicture read FMainIcon write SetMainIcon;
  end;

  { TDonateDialogOptions - published settings for the Donate dialog }

  TDonateDialogOptions = class(TComponent)
  private
    FCaption: TCaption;
    FHeader: TCaption;
    FSupportLine: TCaption;
    FBankCaption: TCaption;
    FBankUrl: TCaption;
    FCryptoCaption: TCaption;
    FCryptoUrl: TCaption;
    FContribution: TCaption;
    FOkCaption: TCaption;
    FWidth: integer;
    FHeight: integer;
    FBankIcon: TPicture;
    FCryptoIcon: TPicture;
    procedure SetBankIcon(AValue: TPicture);
    procedure SetCryptoIcon(AValue: TPicture);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property Caption: TCaption read FCaption write FCaption;
    property Header: TCaption read FHeader write FHeader;
    property SupportLine: TCaption read FSupportLine write FSupportLine;
    property BankCaption: TCaption read FBankCaption write FBankCaption;
    property BankUrl: TCaption read FBankUrl write FBankUrl;
    property CryptoCaption: TCaption read FCryptoCaption write FCryptoCaption;
    property CryptoUrl: TCaption read FCryptoUrl write FCryptoUrl;
    property Contribution: TCaption read FContribution write FContribution;
    property OkCaption: TCaption read FOkCaption write FOkCaption;
    property Width: integer read FWidth write FWidth default 447;
    property Height: integer read FHeight write FHeight default 298;
    property BankIcon: TPicture read FBankIcon write SetBankIcon;
    property CryptoIcon: TPicture read FCryptoIcon write SetCryptoIcon;
  end;

  { TAppDialogs - non-visual component that shows the About and Donate dialogs }

  TAppDialogs = class(TComponent)
  private
    FAboutDialog: TAboutDialogOptions;
    FDonateDialog: TDonateDialogOptions;
    FActiveAboutForm: TFormAbout;
    FActiveDonateForm: TFormDonate;
    procedure SetAboutDialog(AValue: TAboutDialogOptions);
    procedure SetDonateDialog(AValue: TDonateDialogOptions);
    procedure ApplyAboutTexts(Dlg: TFormAbout);
    procedure ApplyDonateTexts(Dlg: TFormDonate);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    procedure ShowAbout;
    procedure ShowDonate;
    procedure UseApplicationIcon;
    // Re-applies translated properties to currently open dialogs
    procedure UpdateCaptions;
  published
    property AboutDialog: TAboutDialogOptions read FAboutDialog write SetAboutDialog;
    property DonateDialog: TDonateDialogOptions read FDonateDialog write SetDonateDialog;
  end;

implementation

uses CheckUpdates;

function AssignLargestAppIcon(APicture: TPicture): boolean;
var
  Icon: TIcon;
  I: integer;
  BestIndex: integer = -1;
  BestArea: int64 = 0;
  Area: int64;
  PixelFormat: TPixelFormat;
  IconWidth: word;
  IconHeight: word;
begin
  Result := False;
  Icon := TIcon.Create;
  try
    // MainInstance points to the exe even when called from a runtime package
    Icon.LoadFromResourceName(MainInstance, 'MAINICON');

    // Pick the largest available icon explicitly, independent of request size
    for I := 0 to Icon.Count - 1 do
    begin
      // The out parameters receive the metadata of the icon at index I
      Icon.GetDescription(I, PixelFormat, IconHeight, IconWidth);
      Area := int64(IconWidth) * int64(IconHeight);
      if Area > BestArea then
      begin
        BestArea := Area;
        BestIndex := I;
      end;
    end;
    if BestIndex >= 0 then
    begin
      Icon.Current := BestIndex;
      APicture.Assign(Icon);
      Result := True;
    end;
  except
    // Resource missing or not a valid icon; caller will use the fallback
  end;
  Icon.Free;
end;

{ TAboutDialogOptions }

constructor TAboutDialogOptions.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetSubComponent(True);
  Name := 'AboutDialog';
  FCaption := 'About';
  FAppName := 'Application';
  FCopyright := '© 2026';
  FVersion := 'Version';
  FAppVersion := '';
  FLicenseLine1 := 'by Author is licensed under';
  FLicenseLine2 := 'the GNU General Public License, Version 3';
  FContactLine := 'For questions or feedback, contact me at';
  FEmailCaption := 'your@mail.com';
  FEmailUrl := 'mailto:your@mail.com';
  FGithubCaption := 'github: name/application';
  FGithubUrl := 'https://github.com';
  FOkCaption := 'OK';
  FWidth := 580;
  FHeight := 470;
  FHeaderColorLight := $00F8F4F0;
  FHeaderColorDark := $002D2D2D;
  FAboutText := 'Description';
  FMainIcon := TPicture.Create;
end;

destructor TAboutDialogOptions.Destroy;
begin
  FMainIcon.Free;
  inherited Destroy;
end;

procedure TAboutDialogOptions.SetMainIcon(AValue: TPicture);
begin
  if AValue = nil then
    FMainIcon.Clear
  else
    FMainIcon.Assign(AValue);
end;

procedure TAboutDialogOptions.Assign(Source: TPersistent);
var
  Src: TAboutDialogOptions;
begin
  if Source is TAboutDialogOptions then
  begin
    Src := TAboutDialogOptions(Source);
    FCaption := Src.FCaption;
    FAppName := Src.FAppName;
    FCopyright := Src.FCopyright;
    FVersion := Src.FVersion;
    FAppVersion := Src.FAppVersion;
    FLicenseLine1 := Src.FLicenseLine1;
    FLicenseLine2 := Src.FLicenseLine2;
    FContactLine := Src.FContactLine;
    FEmailCaption := Src.FEmailCaption;
    FEmailUrl := Src.FEmailUrl;
    FGithubCaption := Src.FGithubCaption;
    FGithubUrl := Src.FGithubUrl;
    FAboutText := Src.FAboutText;
    FOkCaption := Src.FOkCaption;
    FWidth := Src.FWidth;
    FHeight := Src.FHeight;
    FHeaderColorLight := Src.FHeaderColorLight;
    FHeaderColorDark := Src.FHeaderColorDark;
    FMainIcon.Assign(Src.FMainIcon);
  end
  else
    inherited Assign(Source);
end;

{ TDonateDialogOptions }

constructor TDonateDialogOptions.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetSubComponent(True);
  Name := 'DonateDialog';
  FCaption := 'Buy me a coffee';
  FHeader := 'Hey there! Fuel this passion project with a little caffeine boost! Every donation helps keep the code rolling and the coffee brewing. Thanks for supporting the work and the developer behind it!';
  FSupportLine := 'You can support development through one of the following options:';
  FBankCaption := 'Donate with Bank Card or PayPal';
  FBankUrl := 'https://app.lava.top/en/astverskoy?tabId=about&currency=EUR';
  FCryptoCaption := 'Donate with Cryptocurrency';
  FCryptoUrl := 'https://nowpayments.io/donation/astverskoy';
  FContribution := 'Every contribution helps keep the project active and moving forward. Thank you for your support!';
  FOkCaption := 'OK';
  FWidth := 447;
  FHeight := 298;
  FBankIcon := TPicture.Create;
  FCryptoIcon := TPicture.Create;
end;

destructor TDonateDialogOptions.Destroy;
begin
  FCryptoIcon.Free;
  FBankIcon.Free;
  inherited Destroy;
end;

procedure TDonateDialogOptions.SetBankIcon(AValue: TPicture);
begin
  if AValue = nil then
    FBankIcon.Clear
  else
    FBankIcon.Assign(AValue);
end;

procedure TDonateDialogOptions.SetCryptoIcon(AValue: TPicture);
begin
  if AValue = nil then
    FCryptoIcon.Clear
  else
    FCryptoIcon.Assign(AValue);
end;

procedure TDonateDialogOptions.Assign(Source: TPersistent);
var
  Src: TDonateDialogOptions;
begin
  if Source is TDonateDialogOptions then
  begin
    Src := TDonateDialogOptions(Source);
    FCaption := Src.FCaption;
    FHeader := Src.FHeader;
    FSupportLine := Src.FSupportLine;
    FBankCaption := Src.FBankCaption;
    FBankUrl := Src.FBankUrl;
    FCryptoCaption := Src.FCryptoCaption;
    FCryptoUrl := Src.FCryptoUrl;
    FContribution := Src.FContribution;
    FOkCaption := Src.FOkCaption;
    FWidth := Src.FWidth;
    FHeight := Src.FHeight;
    FBankIcon.Assign(Src.FBankIcon);
    FCryptoIcon.Assign(Src.FCryptoIcon);
  end
  else
    inherited Assign(Source);
end;

{ TAppDialogs }

constructor TAppDialogs.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAboutDialog := TAboutDialogOptions.Create(Self);
  FDonateDialog := TDonateDialogOptions.Create(Self);
end;

destructor TAppDialogs.Destroy;
begin
  FDonateDialog.Free;
  FAboutDialog.Free;
  inherited Destroy;
end;

procedure TAppDialogs.Assign(Source: TPersistent);
var
  Src: TAppDialogs;
begin
  if Source is TAppDialogs then
  begin
    Src := TAppDialogs(Source);
    FAboutDialog.Assign(Src.FAboutDialog);
    FDonateDialog.Assign(Src.FDonateDialog);
  end
  else
    inherited Assign(Source);
end;

procedure TAppDialogs.SetAboutDialog(AValue: TAboutDialogOptions);
begin
  if AValue <> nil then
    FAboutDialog.Assign(AValue);
end;

procedure TAppDialogs.SetDonateDialog(AValue: TDonateDialogOptions);
begin
  if AValue <> nil then
    FDonateDialog.Assign(AValue);
end;

procedure TAppDialogs.UseApplicationIcon;
begin
  if Application.Icon <> nil then
    FAboutDialog.MainIcon.Assign(Application.Icon);
end;

procedure TAppDialogs.UpdateCaptions;
begin
  // Push currently translated properties into already visible dialogs
  if FActiveAboutForm <> nil then
  begin
    ApplyAboutTexts(FActiveAboutForm);
    FActiveAboutForm.ApplySettings;
  end;
  if FActiveDonateForm <> nil then
  begin
    ApplyDonateTexts(FActiveDonateForm);
    FActiveDonateForm.ApplySettings;
  end;
end;

procedure TAppDialogs.ApplyAboutTexts(Dlg: TFormAbout);
begin
  Dlg.Caption := FAboutDialog.Caption;
  Dlg.AppName := FAboutDialog.AppName;
  Dlg.Copyright := FAboutDialog.Copyright;
  Dlg.VersionText := FAboutDialog.Version;
  // Fall back to the running application version when not set explicitly
  if FAboutDialog.AppVersion <> '' then
    Dlg.AppVersion := FAboutDialog.AppVersion
  else
    Dlg.AppVersion := GetAppVersion;
  Dlg.LicenseLine1 := FAboutDialog.LicenseLine1;
  Dlg.LicenseLine2 := FAboutDialog.LicenseLine2;
  Dlg.ContactLine := FAboutDialog.ContactLine;
  Dlg.EmailCaption := FAboutDialog.EmailCaption;
  Dlg.EmailUrl := FAboutDialog.EmailUrl;
  Dlg.GithubCaption := FAboutDialog.GithubCaption;
  Dlg.GithubUrl := FAboutDialog.GithubUrl;
  Dlg.AboutText := FAboutDialog.AboutText;
  Dlg.OkCaption := FAboutDialog.OkCaption;
  Dlg.HeaderColorLight := FAboutDialog.HeaderColorLight;
  Dlg.HeaderColorDark := FAboutDialog.HeaderColorDark;
end;

procedure TAppDialogs.ShowAbout;
var
  Dlg: TFormAbout;
begin
  Dlg := TFormAbout.Create(nil);
  FActiveAboutForm := Dlg;
  try
    ApplyAboutTexts(Dlg);

    // MainIcon wins, otherwise load the largest icon from the exe resources
    if (FAboutDialog.MainIcon.Graphic <> nil) and not FAboutDialog.MainIcon.Graphic.Empty then
      Dlg.LogoPicture.Assign(FAboutDialog.MainIcon)
    else
    begin
      // Try to load the biggest icon from MAINICON; fall back to the LCL icon
      if not AssignLargestAppIcon(Dlg.LogoPicture) then
        if (Application.Icon <> nil) and not Application.Icon.Empty then
          Dlg.LogoPicture.Assign(Application.Icon);
    end;

    if FAboutDialog.Width > 0 then
    begin
      Dlg.Constraints.MinWidth := FAboutDialog.Width;
      Dlg.Width := FAboutDialog.Width;
    end;
    if FAboutDialog.Height > 0 then
    begin
      Dlg.Constraints.MinHeight := FAboutDialog.Height;
      Dlg.Height := FAboutDialog.Height;
    end;

    Dlg.ApplySettings;
    Dlg.ShowModal;

    // Remember the dialog size chosen by the user
    FAboutDialog.Width := Dlg.Width;
    FAboutDialog.Height := Dlg.Height;
  finally
    FActiveAboutForm := nil;
    Dlg.Free;
  end;
end;

procedure TAppDialogs.ApplyDonateTexts(Dlg: TFormDonate);
begin
  Dlg.Caption := FDonateDialog.Caption;
  Dlg.HeaderText := FDonateDialog.Header;
  Dlg.SupportLine := FDonateDialog.SupportLine;
  Dlg.BankCaption := FDonateDialog.BankCaption;
  Dlg.BankUrl := FDonateDialog.BankUrl;
  Dlg.CryptoCaption := FDonateDialog.CryptoCaption;
  Dlg.CryptoUrl := FDonateDialog.CryptoUrl;
  Dlg.Contribution := FDonateDialog.Contribution;
  Dlg.OkCaption := FDonateDialog.OkCaption;
end;

procedure TAppDialogs.ShowDonate;
var
  Dlg: TFormDonate;
begin
  Dlg := TFormDonate.Create(nil);
  FActiveDonateForm := Dlg;
  try
    ApplyDonateTexts(Dlg);

    if (FDonateDialog.BankIcon.Graphic <> nil) and not FDonateDialog.BankIcon.Graphic.Empty then
      Dlg.BankPicture.Assign(FDonateDialog.BankIcon);
    if (FDonateDialog.CryptoIcon.Graphic <> nil) and not FDonateDialog.CryptoIcon.Graphic.Empty then
      Dlg.CryptoPicture.Assign(FDonateDialog.CryptoIcon);

    if FDonateDialog.Width > 0 then
    begin
      Dlg.Constraints.MinWidth := FDonateDialog.Width;
      Dlg.Width := FDonateDialog.Width;
    end;
    if FDonateDialog.Height > 0 then
    begin
      Dlg.Constraints.MinHeight := FDonateDialog.Height;
      Dlg.Height := FDonateDialog.Height;
    end;

    Dlg.ApplySettings;
    Dlg.ShowModal;

    // Remember the dialog size chosen by the user
    FDonateDialog.Width := Dlg.Width;
    FDonateDialog.Height := Dlg.Height;
  finally
    FActiveDonateForm := nil;
    Dlg.Free;
  end;
end;

end.
