//-----------------------------------------------------------------------------------
//  DesignKit Package © 2026 by Alexander Tverskoy
//  Licensed under the MIT License
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//-----------------------------------------------------------------------------------

unit DesignKitRegister;

{$mode objfpc}{$H+}

interface

uses
  Classes, LResources;

procedure Register;

implementation

uses FormGrip;

procedure Register;
begin
  RegisterComponents('Common Controls', [TFormGrip]);
end;

initialization
  {$I designkit.lrs}

end.

