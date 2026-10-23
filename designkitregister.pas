//-----------------------------------------------------------------------------------
//  DesignKit Package © 2026 by Alexander Tverskoy
//  Licensed under the MIT License
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//-----------------------------------------------------------------------------------

unit DesignKitRegister;

{$mode objfpc}{$H+}

interface

uses
  Controls, Classes, LResources, PropEdits, GraphPropEdits, FormGrip, FlatButton;

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

procedure Register;
begin
  RegisterComponents('Common Controls', [TFormGrip]);
  RegisterComponents('Common Controls', [TFlatButton]);
  RegisterPropertyEditor(TypeInfo(TCaption), TFlatButton, 'Tooltip', TFlatButtonTooltipPropertyEditor);
end;

initialization
  {$I designkit.lrs}

end.
