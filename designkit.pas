{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit designkit;

{$warn 5023 off : no warning about unused units}
interface

uses
  DesignKitRegister, FormGrip, FlatButton, SpellChecker, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('DesignKitRegister', @DesignKitRegister.Register);
end;

initialization
  RegisterPackage('designkit', @Register);
end.
