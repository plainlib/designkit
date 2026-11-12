//-----------------------------------------------------------------------------------
//  DesignKit Package © 2026 by Alexander Tverskoy
//  Licensed under the MIT License
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//-----------------------------------------------------------------------------------

unit DesignKitRegister;

{$mode objfpc}{$H+}

interface

uses
  Forms, StdCtrls, ExtCtrls, Controls, Classes, LResources, PropEdits, GraphPropEdits, FormGrip, FlatButton, CalendarLite, AppDialogs;

procedure Register;

implementation

type
  TFlatButtonTooltipPropertyEditor = class(TStringMultilinePropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
  end;

function TFlatButtonTooltipPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := inherited GetAttributes + [paDialog];
end;

type
  TAboutTextPropertyEditor = class(TStringMultilinePropertyEditor)
  public
    procedure Edit; override;
  end;

procedure TAboutTextPropertyEditor.Edit;
var
  OldValue: string;
  AForm: TCustomForm;
begin
  OldValue := GetStrValue;
  // Standard multiline dialog with a TMemo
  inherited Edit;
  // TStringMultilinePropertyEditor uses SetStrValue, which does not notify
  // the designer for nested TPersistent properties; do it explicitly
  if (GetStrValue <> OldValue) and (PropertyHook <> nil) then
  begin
    AForm := GetDesignerForm(PropertyHook.LookupRoot);
    if (AForm <> nil) and (AForm.Designer <> nil) then
      AForm.Designer.Modified;
  end;
end;

procedure Register;
begin
  RegisterComponents('Common Controls', [TFormGrip]);
  RegisterComponents('Common Controls', [TFlatButton]);
  RegisterComponents('Common Controls', [TCalendarLite]);
  RegisterComponents('Common Controls', [TAppDialogs]);

  RegisterPropertyEditor(TypeInfo(TCaption), TFlatButton, 'Tooltip', TFlatButtonTooltipPropertyEditor);

  // Multiline editor for the About text - same editor as the FlatButton tooltip
  RegisterPropertyEditor(TypeInfo(TCaption), TAboutDialogOptions, 'AboutText', TAboutTextPropertyEditor);
end;

initialization
  {$I designkit.lrs}

end.
