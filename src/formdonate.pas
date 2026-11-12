//-----------------------------------------------------------------------------------
//  DesignKit Package © 2026 by Alexander Tverskoy
//  Licensed under the GNU General Public License, Version 3 (GPL-3.0)
//  You may obtain a copy of the License at https://www.gnu.org/licenses/gpl-3.0.html
//-----------------------------------------------------------------------------------

unit FormDonate;

{$mode ObjFPC}{$H+}

interface

uses
  Forms,
  Classes,
  StdCtrls,
  Graphics,
  ExtCtrls,
  LCLIntf;

type

  { TFormDonate }

  TFormDonate = class(TForm)
    BtnOk: TButton;
    ImageBank: TImage;
    ImageCrypto: TImage;
    LabelDonate: TLabel;
    LabelSupport: TLabel;
    LabelContribution: TLabel;
    labelBank: TLabel;
    labelCrypto: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure labelBankClick(Sender: TObject);
  public
    // Dialog content - assigned by the controlling component before ApplySettings
    HeaderText: string;
    SupportLine: string;
    BankCaption: string;
    BankUrl: string;
    CryptoCaption: string;
    CryptoUrl: string;
    Contribution: string;
    OkCaption: string;
    BankPicture: TPicture;
    CryptoPicture: TPicture;
    constructor Create(AOwner: TComponent); override;
    procedure ApplySettings;
  end;

implementation

uses DarkUtils;

  {$R *.lfm}

  { TFormDonate }

constructor TFormDonate.Create(AOwner: TComponent);
begin
  BankPicture := TPicture.Create;
  CryptoPicture := TPicture.Create;
  inherited Create(AOwner);
end;

procedure TFormDonate.FormCreate(Sender: TObject);
begin
  // Links: color within the theme
  labelBank.Font.Color := TDarkUtils.ThemeColor(clBlue, clSkyBlue);
  labelCrypto.Font.Color := TDarkUtils.ThemeColor(clBlue, clSkyBlue);
end;

procedure TFormDonate.FormDestroy(Sender: TObject);
begin
  CryptoPicture.Free;
  BankPicture.Free;
end;

procedure TFormDonate.labelBankClick(Sender: TObject);
var
  Url: string;
begin
  Url := (Sender as TLabel).Hint;
  if Url <> '' then
    OpenUrl(Url);
end;

procedure TFormDonate.ApplySettings;
begin
  LabelDonate.Caption := HeaderText;
  LabelSupport.Caption := SupportLine;
  LabelContribution.Caption := Contribution;

  // Bank link
  labelBank.Caption := BankCaption;
  labelBank.Hint := BankUrl;
  labelBank.Visible := BankCaption <> '';

  // Crypto link
  labelCrypto.Caption := CryptoCaption;
  labelCrypto.Hint := CryptoUrl;
  labelCrypto.Visible := CryptoCaption <> '';

  // OK button
  BtnOk.Caption := OkCaption;

  // Bank icon
  if (BankPicture.Graphic <> nil) and not BankPicture.Graphic.Empty then
  begin
    ImageBank.Picture.Assign(BankPicture);
    ImageBank.Visible := True;
  end
  else
    ImageBank.Visible := False;

  // Crypto icon
  if (CryptoPicture.Graphic <> nil) and not CryptoPicture.Graphic.Empty then
  begin
    ImageCrypto.Picture.Assign(CryptoPicture);
    ImageCrypto.Visible := True;
  end
  else
    ImageCrypto.Visible := False;
end;

end.
