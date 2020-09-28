unit NtUtils.Com.Dispatch;

interface

uses
  NtUtils;

// TODO: TNtxStatus misinterprets some HRESULTs

// Variant creation helpers
function VarFromWord(const Value: Word): TVarData;
function VarFromCardinal(const Value: Cardinal): TVarData;

// Bind to a COM object using a name
function DispxBindToObject(const ObjectName: String; out Dispatch: IDispatch):
  TNtxStatus;

// Retrieve a property on an object referenced by IDispatch
function DispxPropertyGet(const Dispatch: IDispatch; const Name: String;
  out Value: TVarData): TNtxStatus;

// Assign a property on an object pointed by IDispatch
function DispxPropertySet(const Dispatch: IDispatch; const Name: String;
  const Value: TVarData): TNtxStatus;

// Call a method on an object pointer by IDispatch
function DispxMethodCall(const Dispatch: IDispatch; const Name: String;
  const Parameters: TArray<TVarData> = nil; VarResult: PVarData = nil):
  TNtxStatus;

implementation

uses
  Winapi.ObjIdl, Winapi.ObjBase, Winapi.WinError, DelphiUtils.Arrays;

{ Variant helpers }

function VarFromWord(const Value: Word): TVarData;
begin
  VariantInit(Result);
  Result.VType := varWord;
  Result.VWord := Value;
end;

function VarFromCardinal(const Value: Cardinal): TVarData;
begin
  VariantInit(Result);
  Result.VType := varUInt32;
  Result.VUInt32 := Value;
end;

{ Binding helpers }

function DispxBindToObject(const ObjectName: String; out Dispatch: IDispatch):
  TNtxStatus;
var
  BindCtx: IBindCtx;
  Moniker: IMoniker;
  chEaten: Cardinal;
begin
  Result.Location := 'CreateBindCtx';
  Result.HResult := CreateBindCtx(0, BindCtx);

  if not Result.IsSuccess then
    Exit;

  Result.Location := 'MkParseDisplayName("' + ObjectName + '")';
  Result.HResult := MkParseDisplayName(BindCtx, StringToOleStr(ObjectName),
    chEaten, Moniker);

  if not Result.IsSuccess then
    Exit;

  Result.Location := 'Moniker.BindToObject("' + ObjectName + '")';
  Result.HResult := Moniker.BindToObject(BindCtx, nil, IDispatch, Dispatch);
end;

{ IDispatch invocation helpers }

function DispxGetNameId(const Dispatch: IDispatch; const Name: String;
  out DispId: TDispID): TNtxStatus;
var
  WideName: WideString;
begin
  WideName := Name;

  Result.Location := 'IDispatch.GetIDsOfNames("' + Name + '")';
  Result.HResult := Dispatch.GetIDsOfNames(GUID_NULL, @WideName, 1, 0, @DispID);
end;

function DispxInvoke(const Dispatch: IDispatch; const DispId: TDispID;
  const Flags: Word; var Params: TDispParams; VarResult: Pointer): TNtxStatus;
var
  ExceptInfo: TExcepInfo;
  ArgErr: Cardinal;
  Code: HRESULT;
begin
  Code := Dispatch.Invoke(DispID, GUID_NULL, 0, Flags, Params, VarResult,
    @ExceptInfo, @ArgErr);

  if Code = DISP_E_EXCEPTION then
  begin
    // Prefere more specific error codes
    Result.Location := ExceptInfo.bstrSource;
    Result.HResult := ExceptInfo.scode;
  end
  else
  begin
    Result.Location := 'IDispatch.Invoke';
    Result.HResult := Code;
  end;
end;

function DispxPropertyGet(const Dispatch: IDispatch; const Name: String;
  out Value: TVarData): TNtxStatus;
var
  DispID: TDispID;
  Params: TDispParams;
begin
  // Determine the DispID of the property
  Result := DispxGetNameId(Dispatch, Name, DispID);

  if not Result.IsSuccess then
    Exit;

  // Prepare the parameters
  FillChar(Params, SizeOf(Params), 0);

  VariantInit(Value);

  Result := DispxInvoke(Dispatch, DispID, DISPATCH_METHOD or
    DISPATCH_PROPERTYGET, Params, @Value);
end;

function DispxPropertySet(const Dispatch: IDispatch; const Name: String;
  const Value: TVarData): TNtxStatus;
var
  DispID, Action: TDispID;
  Params: TDispParams;
begin
  // Determine the DispID of the property
  Result := DispxGetNameId(Dispatch, Name, DispID);

  if not Result.IsSuccess then
    Exit;

  Action := DISPID_PROPERTYPUT;

  // Prepare the parameters
  Params.rgvarg := Pointer(@Value);
  Params.rgdispidNamedArgs := Pointer(@Action);
  Params.cArgs := 1;
  Params.cNamedArgs := 1;

  Result := DispxInvoke(Dispatch, DispID, DISPATCH_PROPERTYPUT, Params, nil);
end;

function DispxMethodCall(const Dispatch: IDispatch; const Name: String;
  const Parameters: TArray<TVarData>; VarResult: PVarData): TNtxStatus;
var
  DispID: TDispID;
  Params: TDispParams;
begin
  // Determine the DispID of the property
  Result := DispxGetNameId(Dispatch, Name, DispID);

  if not Result.IsSuccess then
    Exit;

  // IDispatch expects method parameters to go from right to left
  Params.cArgs := Length(Parameters);
  Params.rgvarg := Pointer(TArray.Reverse<TVarData>(Parameters));
  Params.cNamedArgs := 0;
  Params.rgdispidNamedArgs := nil;

  if Assigned(VarResult) then
    VariantInit(VarResult^);

  Result := DispxInvoke(Dispatch, DispID, DISPATCH_METHOD, Params, VarResult);
end;

end.
