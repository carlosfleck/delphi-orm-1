unit OlfeiORM;

interface

uses
  OlfeiSQL, System.SysUtils, System.Classes, FireDac.Comp.Client, System.DateUtils,
  System.Rtti, System.UITypes, System.JSON;

type
  TOlfeiFilterFields = array of string;

  TOlfeiPivotItem = record
    FTable, FLocalKey, FRemoteKey, FLocalValue, FRemoteValue: string;
  end;

  TOlfeiForeignItem = record
    FLocalKey, FRemoteKey: string;
  end;

  TOlfeiPivotItems = array of TOlfeiPivotItem;

  TOlfeiForeignItems = array of TOlfeiForeignItem;

  TOlfeiField = class(TCustomAttribute)
  private
    FName: string;
  public
    property Name: string read FName;
    constructor Create(AName: string);
  end;

  TOlfeiForeignField = class(TCustomAttribute)
  private
    FLocalKey, FRemoteKey: string;
  public
    property LocalKey: string read FLocalKey;
    property RemoteKey: string read FRemoteKey;
    constructor Create(ALocalKey, ARemoteKey: string);
  end;

  TOlfeiTable = class(TCustomAttribute)
  private
    FName: string;
  public
    property Name: string read FName;
    constructor Create(AName: string);
  end;

  TOlfeiPivotField = class(TCustomAttribute)
  private
    FTable, FLocalKey, FRemoteKey, FLocalValue, FRemoteValue: string;
  public
    property Table: string read FTable;
    property LocalKey: string read FLocalKey;
    property RemoteKey: string read FRemoteKey;
    property LocalValue: string read FLocalValue;
    property RemoteValue: string read FRemoteValue;
    constructor Create(ATable, ALocalKey, ALocalValue, ARemoteKey, ARemoteValue: string);
  end;

  TOlfeiCollectionField = class(TCustomAttribute)
  private
    FLocalKey, FRemoteKey: string;
  public
    property LocalKey: string read FLocalKey;
    property RemoteKey: string read FRemoteKey;
    constructor Create(ALocalKey, ARemoteKey: string);
  end;

  TOlfeiBlobField = class(TCustomAttribute)
  private
    FName: string;
  public
    property Name: string read FName;
    constructor Create(AName: string);
  end;

  TOlfeiCoreORM = class
  private
    SLValues, SLChangedFields: TStringList;
    JSONValues, BlobValues, OlfeiCollections, OlfeiForeigns: array of TObject;
    FFieldName: string;
    function PackFloat(Value: string): string;
    function UnpackFloat(Value: string): string;
    function OlfeiBoolToStr(Fl: Boolean): Integer;
    function OlfeiStrToBool(Fl: string): Boolean;
    function PrepareValue(ValueType, Value: string): string;
      //function FormatValue(Index: Integer): string;
    function FormatValueByField(Index: Integer): string;
    function GetLocalKey(Name: string): string;
  public
    ID: integer;
    Table: string;
    constructor Create(FDB: TOlfeiDB; FID: integer = 0; WithCache: boolean = true); overload;
    constructor Create(FDB: TOlfeiDB; const FFilterFields: TOlfeiFilterFields; FID: integer = 0; WithCache: Boolean = true); overload;
    destructor Destroy; override;
    function Exists: Boolean;
    procedure Delete;
    procedure Save;
    procedure Find(FID: Integer);
    procedure FindBy(AFieldName, AFieldValue: string);
    procedure Cache(LockBeforeUpdate: Boolean = false);
    procedure Attach(AObject: TOlfeiCoreORM; AID: integer); overload;
    procedure Attach(AObject: TObject; ARemoteKey: string); overload;
    procedure Dettach(AObject: TObject; ARemoteKey: string = '');
    function ToJSON: TJSONObject;
    property FieldName: string read FFieldName write FFieldName;
  protected
    Fields, BlobFields: TOlfeiStrings;
    PivotFields, CollectionFields: TOlfeiPivotItems;
    ForeignFields: TOlfeiForeignItems;
    DBConnection: TOlfeiDB;
    UseTimestamps: boolean;
    FJSONObject: TJSONObject;
    function GetColor(index: Integer): TAlphaColor;
    procedure SetColor(Index: integer; Value: TAlphaColor);
    function GetBoolean(index: Integer): Boolean;
    procedure SetBoolean(Index: integer; Value: Boolean);
    function GetInteger(index: Integer): Integer;
    procedure SetInteger(Index: integer; Value: Integer);
    function GetFloat(index: Integer): Real;
    procedure SetFloat(Index: integer; Value: Real);
    function GetString(Index: integer): string;
    procedure SetString(Index: integer; Value: string);
    function GetJSON(Index: Integer): TJSONObject;
    function GetDateTime(index: Integer): TDateTime;
    procedure SetDateTime(Index: integer; Value: TDateTime);
    function GetDate(index: Integer): TDate;
    procedure SetDate(Index: integer; Value: TDate);
    function GetBlob(index: Integer): TStringStream;
    function GetForeignObject(index: Integer; T: TClass): TObject;
    function GetForeignCollection(index: Integer; T: TClass): TObject;
    function GetPivotCollection(index: Integer; T: TClass): TObject;
    function IndexToField(Index: integer): string;
    function IsExist(FID: integer): boolean;
  end;

  TOlfeiORM = class(TOlfeiCoreORM)
  private
    function GetCreated: TDateTime;
    function GetUpdated: TDateTime;
  public
    property Created: TDateTime read GetCreated;
    property Updated: TDateTime read GetUpdated;
    constructor Create(FDB: TOlfeiDB; FID: integer = 0; WithCache: boolean = true); overload;
    constructor Create(FDB: TOlfeiDB; const FFilterFields: TOlfeiFilterFields; FID: integer = 0; WithCache: boolean = true); overload;
  end;

implementation

uses
  OlfeiCollection;

constructor TOlfeiForeignField.Create(ALocalKey, ARemoteKey: string);
begin
  FLocalKey := ALocalKey;
  FRemoteKey := ARemoteKey;
end;

constructor TOlfeiField.Create(AName: string);
begin
  FName := AName;
end;

constructor TOlfeiBlobField.Create(AName: string);
begin
  FName := AName;
end;

constructor TOlfeiTable.Create(AName: string);
begin
  FName := AName;
end;

constructor TOlfeiCollectionField.Create(ALocalKey, ARemoteKey: string);
begin
  FLocalKey := ALocalKey;
  FRemoteKey := ARemoteKey;
end;

constructor TOlfeiPivotField.Create(ATable, ALocalKey, ALocalValue, ARemoteKey, ARemoteValue: string);
begin
  FTable := ATable;
  FLocalKey := ALocalKey;
  FRemoteKey := ARemoteKey;
  FLocalValue := ALocalValue;
  FRemoteValue := ARemoteValue;
end;

constructor TOlfeiORM.Create(FDB: TOlfeiDB; const FFilterFields: TOlfeiFilterFields; FID: Integer = 0; WithCache: boolean = true);
var
  RttiCtx: TRttiContext;
  RttiType: TRttiType;
  RttiProp: TRttiProperty;
  RttiAttr: TCustomAttribute;

  function CheckField(FField: string): boolean;
  var
    i: Integer;
  begin
    if Length(FFilterFields) = 0 then
      Exit(True);

    Result := false;
    for i := 0 to Length(FFilterFields) - 1 do
      if FField = FFilterFields[i] then
        Result := True;
  end;

begin
  FJSONObject := TJSONObject.Create;

  RttiCtx := TRttiContext.Create;
  RttiType := RttiCtx.GetType(Self.ClassType);

  for RttiAttr in RttiType.GetAttributes do
    if RttiAttr is TOlfeiTable then
      Table := TOlfeiTable(RttiAttr).Name;

  for RttiProp in RttiType.GetProperties do
    for RttiAttr in RttiProp.GetAttributes do
    begin
      if RttiAttr is TOlfeiField then
      begin
        if not CheckField(TOlfeiField(RttiAttr).Name) then
          Continue;

        if Length(Fields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(Fields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if Fields[(RttiProp as TRttiInstanceProperty).Index].Name <> '' then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for column ' + TOlfeiField(RttiAttr).Name);

        Fields[(RttiProp as TRttiInstanceProperty).Index].Name := TOlfeiField(RttiAttr).Name;
        Fields[(RttiProp as TRttiInstanceProperty).Index].ItemType := (RttiProp as TRttiInstanceProperty).PropertyType.ToString;
      end;

      if RttiAttr is TOlfeiCollectionField then
      begin
        if Length(CollectionFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(CollectionFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index for ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for collection ' + TOlfeiCollectionField(RttiAttr).LocalKey);

        CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiCollectionField(RttiAttr).LocalKey;
        CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiCollectionField(RttiAttr).RemoteKey;
      end;

      if RttiAttr is TOlfeiBlobField then
      begin
        if not CheckField(TOlfeiBlobField(RttiAttr).Name) then
          Continue;

        if Length(BlobFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(BlobFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if BlobFields[(RttiProp as TRttiInstanceProperty).Index].Name <> '' then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for column ' + TOlfeiBlobField(RttiAttr).Name);

        BlobFields[(RttiProp as TRttiInstanceProperty).Index].Name := TOlfeiBlobField(RttiAttr).Name;
      end;

      if RttiAttr is TOlfeiPivotField then
      begin
        if Length(PivotFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(PivotFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FTable <> '') or (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for pivot ' + TOlfeiPivotField(RttiAttr).LocalKey);

        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FTable := TOlfeiPivotField(RttiAttr).Table;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiPivotField(RttiAttr).LocalKey;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiPivotField(RttiAttr).RemoteKey;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalValue := TOlfeiPivotField(RttiAttr).LocalValue;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteValue := TOlfeiPivotField(RttiAttr).RemoteValue;
      end;

      if RttiAttr is TOlfeiForeignField then
      begin
        if Length(ForeignFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(ForeignFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for foreign ' + TOlfeiForeignField(RttiAttr).LocalKey);

        ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiForeignField(RttiAttr).LocalKey;
        ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiForeignField(RttiAttr).RemoteKey;
      end;
    end;

  RttiCtx.Free;

  UseTimestamps := True;
  DBConnection := FDB;

  SLValues := TStringList.Create;
  SLChangedFields := TStringList.Create;

  //if Isset(FID) then
  //begin
  ID := FID;

  if WithCache then
    Cache;
  //end;
end;

constructor TOlfeiORM.Create(FDB: TOlfeiDB; FID: Integer = 0; WithCache: boolean = true);
var
  RttiCtx: TRttiContext;
  RttiType: TRttiType;
  RttiProp: TRttiProperty;
  RttiAttr: TCustomAttribute;
begin
  FJSONObject := TJSONObject.Create;

  RttiCtx := TRttiContext.Create;
  RttiType := RttiCtx.GetType(Self.ClassType);

  for RttiAttr in RttiType.GetAttributes do
    if RttiAttr is TOlfeiTable then
      Table := TOlfeiTable(RttiAttr).Name;

  for RttiProp in RttiType.GetProperties do
    for RttiAttr in RttiProp.GetAttributes do
    begin
      if RttiAttr is TOlfeiField then
      begin
        if Length(Fields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(Fields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if Fields[(RttiProp as TRttiInstanceProperty).Index].Name <> '' then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for column ' + TOlfeiField(RttiAttr).Name);

        Fields[(RttiProp as TRttiInstanceProperty).Index].Name := TOlfeiField(RttiAttr).Name;
        Fields[(RttiProp as TRttiInstanceProperty).Index].ItemType := (RttiProp as TRttiInstanceProperty).PropertyType.ToString;
      end;

      if RttiAttr is TOlfeiCollectionField then
      begin
        if Length(CollectionFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(CollectionFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index for ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for collection ' + TOlfeiCollectionField(RttiAttr).LocalKey);

        CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiCollectionField(RttiAttr).LocalKey;
        CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiCollectionField(RttiAttr).RemoteKey;
      end;

      if RttiAttr is TOlfeiBlobField then
      begin
        if Length(BlobFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(BlobFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if BlobFields[(RttiProp as TRttiInstanceProperty).Index].Name <> '' then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for column ' + TOlfeiBlobField(RttiAttr).Name);

        BlobFields[(RttiProp as TRttiInstanceProperty).Index].Name := TOlfeiBlobField(RttiAttr).Name;
      end;

      if RttiAttr is TOlfeiPivotField then
      begin
        if Length(PivotFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(PivotFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FTable <> '') or (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for pivot ' + TOlfeiPivotField(RttiAttr).LocalKey);

        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FTable := TOlfeiPivotField(RttiAttr).Table;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiPivotField(RttiAttr).LocalKey;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiPivotField(RttiAttr).RemoteKey;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalValue := TOlfeiPivotField(RttiAttr).LocalValue;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteValue := TOlfeiPivotField(RttiAttr).RemoteValue;
      end;

      if RttiAttr is TOlfeiForeignField then
      begin
        if Length(ForeignFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(ForeignFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for foreign ' + TOlfeiForeignField(RttiAttr).LocalKey);

        ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiForeignField(RttiAttr).LocalKey;
        ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiForeignField(RttiAttr).RemoteKey;
      end;
    end;

  RttiCtx.Free;

  UseTimestamps := True;
  DBConnection := FDB;

  SLValues := TStringList.Create;
  SLChangedFields := TStringList.Create;

  //if Isset(FID) then
  //begin
  ID := FID;

  if WithCache then
    Cache;
  //end;
end;

constructor TOlfeiCoreORM.Create(FDB: TOlfeiDB; FID: Integer = 0; WithCache: boolean = true);
var
  RttiCtx: TRttiContext;
  RttiType: TRttiType;
  RttiProp: TRttiProperty;
  RttiAttr: TCustomAttribute;
begin
  FJSONObject := TJSONObject.Create;

  RttiCtx := TRttiContext.Create;
  RttiType := RttiCtx.GetType(Self.ClassType);

  for RttiAttr in RttiType.GetAttributes do
    if RttiAttr is TOlfeiTable then
      Table := TOlfeiTable(RttiAttr).Name;

  for RttiProp in RttiType.GetProperties do
    for RttiAttr in RttiProp.GetAttributes do
    begin
      if RttiAttr is TOlfeiField then
      begin
        if Length(Fields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(Fields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if Fields[(RttiProp as TRttiInstanceProperty).Index].Name <> '' then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for column ' + TOlfeiField(RttiAttr).Name);

        Fields[(RttiProp as TRttiInstanceProperty).Index].Name := TOlfeiField(RttiAttr).Name;
        Fields[(RttiProp as TRttiInstanceProperty).Index].ItemType := (RttiProp as TRttiInstanceProperty).PropertyType.ToString;
      end;

      if RttiAttr is TOlfeiCollectionField then
      begin
        if Length(CollectionFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(CollectionFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index for ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for collection ' + TOlfeiCollectionField(RttiAttr).LocalKey);

        CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiCollectionField(RttiAttr).LocalKey;
        CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiCollectionField(RttiAttr).RemoteKey;
      end;

      if RttiAttr is TOlfeiBlobField then
      begin
        if Length(BlobFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(BlobFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if BlobFields[(RttiProp as TRttiInstanceProperty).Index].Name <> '' then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for column ' + TOlfeiBlobField(RttiAttr).Name);

        BlobFields[(RttiProp as TRttiInstanceProperty).Index].Name := TOlfeiBlobField(RttiAttr).Name;
      end;

      if RttiAttr is TOlfeiPivotField then
      begin
        if Length(PivotFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(PivotFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FTable <> '') or (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for pivot ' + TOlfeiPivotField(RttiAttr).LocalKey);

        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FTable := TOlfeiPivotField(RttiAttr).Table;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiPivotField(RttiAttr).LocalKey;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiPivotField(RttiAttr).RemoteKey;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalValue := TOlfeiPivotField(RttiAttr).LocalValue;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteValue := TOlfeiPivotField(RttiAttr).RemoteValue;
      end;

      if RttiAttr is TOlfeiForeignField then
      begin
        if Length(ForeignFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(ForeignFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for foreign ' + TOlfeiForeignField(RttiAttr).LocalKey);

        ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiForeignField(RttiAttr).LocalKey;
        ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiForeignField(RttiAttr).RemoteKey;
      end;
    end;

  RttiCtx.Free;

  UseTimestamps := false;
  DBConnection := FDB;

  SLValues := TStringList.Create;
  SLChangedFields := TStringList.Create;

  //if Isset(FID) then
  //begin
  ID := FID;

  if WithCache then
    Cache;
  //end;
end;

constructor TOlfeiCoreORM.Create(FDB: TOlfeiDB; const FFilterFields: TOlfeiFilterFields; FID: Integer = 0; WithCache: boolean = true);
var
  RttiCtx: TRttiContext;
  RttiType: TRttiType;
  RttiProp: TRttiProperty;
  RttiAttr: TCustomAttribute;

  function CheckField(FField: string): boolean;
  var
    i: Integer;
  begin
    if Length(FFilterFields) = 0 then
      Exit(True);

    Result := false;
    for i := 0 to Length(FFilterFields) - 1 do
      if FField = FFilterFields[i] then
        Result := True;
  end;

begin
  FJSONObject := TJSONObject.Create;

  RttiCtx := TRttiContext.Create;
  RttiType := RttiCtx.GetType(Self.ClassType);

  for RttiAttr in RttiType.GetAttributes do
    if RttiAttr is TOlfeiTable then
      Table := TOlfeiTable(RttiAttr).Name;

  for RttiProp in RttiType.GetProperties do
    for RttiAttr in RttiProp.GetAttributes do
    begin
      if RttiAttr is TOlfeiField then
      begin
        if not CheckField(TOlfeiField(RttiAttr).Name) then
          Continue;

        if Length(Fields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(Fields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if Fields[(RttiProp as TRttiInstanceProperty).Index].Name <> '' then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for column ' + TOlfeiField(RttiAttr).Name);

        Fields[(RttiProp as TRttiInstanceProperty).Index].Name := TOlfeiField(RttiAttr).Name;
        Fields[(RttiProp as TRttiInstanceProperty).Index].ItemType := (RttiProp as TRttiInstanceProperty).PropertyType.ToString;
      end;

      if RttiAttr is TOlfeiCollectionField then
      begin
        if Length(CollectionFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(CollectionFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index for ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for collection ' + TOlfeiCollectionField(RttiAttr).LocalKey);

        CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiCollectionField(RttiAttr).LocalKey;
        CollectionFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiCollectionField(RttiAttr).RemoteKey;
      end;

      if RttiAttr is TOlfeiBlobField then
      begin
        if not CheckField(TOlfeiBlobField(RttiAttr).Name) then
          Continue;

        if Length(BlobFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(BlobFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if BlobFields[(RttiProp as TRttiInstanceProperty).Index].Name <> '' then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for column ' + TOlfeiBlobField(RttiAttr).Name);

        BlobFields[(RttiProp as TRttiInstanceProperty).Index].Name := TOlfeiBlobField(RttiAttr).Name;
      end;

      if RttiAttr is TOlfeiPivotField then
      begin
        if Length(PivotFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(PivotFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FTable <> '') or (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for pivot ' + TOlfeiPivotField(RttiAttr).LocalKey);

        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FTable := TOlfeiPivotField(RttiAttr).Table;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiPivotField(RttiAttr).LocalKey;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiPivotField(RttiAttr).RemoteKey;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FLocalValue := TOlfeiPivotField(RttiAttr).LocalValue;
        PivotFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteValue := TOlfeiPivotField(RttiAttr).RemoteValue;
      end;

      if RttiAttr is TOlfeiForeignField then
      begin
        if Length(ForeignFields) < (RttiProp as TRttiInstanceProperty).Index + 1 then
          SetLength(ForeignFields, (RttiProp as TRttiInstanceProperty).Index + 1);

        if (ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey <> '') or (ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey <> '') then
          raise Exception.Create('Dupplicate index ' + (RttiProp as TRttiInstanceProperty).Index.ToString + ' for foreign ' + TOlfeiForeignField(RttiAttr).LocalKey);

        ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FLocalKey := TOlfeiForeignField(RttiAttr).LocalKey;
        ForeignFields[(RttiProp as TRttiInstanceProperty).Index].FRemoteKey := TOlfeiForeignField(RttiAttr).RemoteKey;
      end;
    end;

  RttiCtx.Free;

  UseTimestamps := false;
  DBConnection := FDB;

  SLValues := TStringList.Create;
  SLChangedFields := TStringList.Create;

  //if Isset(FID) then
  //begin
  ID := FID;

  if WithCache then
    Cache;
  //end;
end;

destructor TOlfeiCoreORM.Destroy;
var
  i: integer;
begin
  if Assigned(FJSONObject) then
    FJSONObject.Free;

  SLValues.Free;
  SLChangedFields.Free;

  for i := Length(BlobValues) - 1 downto 0 do
    if Assigned(BlobValues[i]) then
      BlobValues[i].Free;

  for i := Length(JSONValues) - 1 downto 0 do
    if Assigned(JSONValues[i]) then
      JSONValues[i].Free;

  for i := Length(OlfeiCollections) - 1 downto 0 do
    if Assigned(OlfeiCollections[i]) then
      OlfeiCollections[i].Free;

  for i := Length(OlfeiForeigns) - 1 downto 0 do
    if Assigned(OlfeiForeigns[i]) then
      OlfeiForeigns[i].Free;

  inherited;
end;

function TOlfeiCoreORM.PackFloat(Value: string): string;
begin
  Result := StringReplace(Value, FormatSettings.DecimalSeparator, '.', []);
end;

function TOlfeiCoreORM.UnpackFloat(Value: string): string;
begin
  Result := StringReplace(Value, '.', FormatSettings.DecimalSeparator, []);
end;

procedure TOlfeiCoreORM.Attach(AObject: TOlfeiCoreORM; AID: Integer);
begin
  if AObject.FieldName = '' then
    raise Exception.Create('Trying attach to not foreign field');

  Self.SLValues.Values[AObject.FieldName] := AID.ToString;
end;

procedure TOlfeiCoreORM.Attach(AObject: TObject; ARemoteKey: string);
var
  i: Integer;
begin
  if TOlfeiCollection<TOlfeiORM>(AObject).RemoteTable = '' then
    raise Exception.Create('Trying attach for not pivot field');

  for i := 0 to Length(PivotFields) - 1 do
    if PivotFields[i].FTable = TOlfeiCollection<TOlfeiORM>(AObject).RemoteTable then
    begin
      DBConnection.RunSQL('INSERT INTO ' + DBConnection.Quote + PivotFields[i].FTable + DBConnection.Quote + ' (' + DBConnection.Quote + PivotFields[i].FLocalKey + DBConnection.Quote + ', ' + DBConnection.Quote + PivotFields[i].FRemoteKey + DBConnection.Quote + ') VALUES ("' + GetLocalKey(PivotFields[i].FLocalValue) + '", "' + ARemoteKey + '")');

      break;
    end;
end;

procedure TOlfeiCoreORM.Dettach(AObject: TObject; ARemoteKey: string = '');
var
  i: Integer;
begin
  if TOlfeiCollection<TOlfeiORM>(AObject).RemoteTable = '' then
    raise Exception.Create('Trying dettach for not pivot field');

  for i := 0 to Length(PivotFields) - 1 do
    if PivotFields[i].FTable = TOlfeiCollection<TOlfeiORM>(AObject).RemoteTable then
    begin
      if ARemoteKey = '' then
        DBConnection.RunSQL('DELETE FROM ' + DBConnection.Quote + PivotFields[i].FTable + DBConnection.Quote + ' WHERE ' + DBConnection.Quote + PivotFields[i].FLocalKey + DBConnection.Quote + ' = "' + GetLocalKey(PivotFields[i].FLocalValue) + '"')
      else
        DBConnection.RunSQL('DELETE FROM ' + DBConnection.Quote + PivotFields[i].FTable + DBConnection.Quote + ' WHERE ' + DBConnection.Quote + PivotFields[i].FLocalKey + DBConnection.Quote + ' = "' + GetLocalKey(PivotFields[i].FLocalValue) + '" AND ' + DBConnection.Quote + PivotFields[i].FRemoteKey + DBConnection.Quote + ' = "' + ARemoteKey + '"');

      break;
    end;
end;

function TOlfeiCoreORM.IsExist(FID: Integer): boolean;
begin
  Result := DBConnection.GetOnce('SELECT COUNT(' + DBConnection.Quote + 'id' + DBConnection.Quote + ') as mc FROM ' + DBConnection.Quote + Table + DBConnection.Quote + ' WHERE ' + DBConnection.Quote + 'id' + DBConnection.Quote + ' = ' + FID.ToString() + ' LIMIT 1', 'integer') <> '0';
end;

function TOlfeiORM.GetCreated: TDateTime;
begin
  if not UseTimestamps then
    Result := 0
  else
    Result := StrToDateTime(SLValues.Values['created_at']);
end;

function TOlfeiORM.GetUpdated: TDateTime;
begin
  if not UseTimestamps then
    Result := 0
  else
    Result := StrToDateTime(SLValues.Values['updated_at']);
end;

procedure TOlfeiCoreORM.Find(FID: Integer);
begin
  if IsExist(FID) then
  begin
    Self.ID := FID;
    Self.Cache;
  end;
end;

procedure TOlfeiCoreORM.FindBy(AFieldName, AFieldValue: string);
var
  FID: integer;
begin
  FID := DBConnection.GetOnce('SELECT ' + DBConnection.Quote + 'id' + DBConnection.Quote + ' FROM ' + DBConnection.Quote + Table + DBConnection.Quote + ' WHERE ' + DBConnection.Quote + AFieldName + DBConnection.Quote + ' = ' + AFieldValue + ' LIMIT 1', 'integer').ToInteger;

  if IsExist(FID) then
  begin
    Self.ID := FID;
    Self.Cache;
  end;
end;

function TOlfeiCoreORM.OlfeiBoolToStr(Fl: Boolean): Integer;
begin
  if Fl then
    Result := 1
  else
    Result := 0;
end;

function TOlfeiCoreORM.OlfeiStrToBool(Fl: string): boolean;
begin
  Result := False;

  if (AnsiLowerCase(Fl) = 'true') or (Fl = '-1') or (Fl = '1') then
    Result := True;
end;

function TOlfeiCoreORM.ToJSON: TJSONObject;
var
  i: integer;
begin
  FJSONObject.AddPair('id', TJSONNumber.Create(Self.ID));

  for i := 0 to Length(Fields) - 1 do
    FJSONObject.AddPair(Fields[i].Name, SLValues.Values[Fields[i].Name]);

  if UseTimestamps then
  begin
    if SLValues.Values['created_at'] <> '' then
      FJSONObject.AddPair('created_at', FormatDateTime('yyyy-mm-dd hh:nn:ss', StrToDateTime(SLValues.Values['created_at'])))
    else
      FJSONObject.AddPair('created_at', '0000-00-00 00:00:00');

    if SLValues.Values['updated_at'] <> '' then
      FJSONObject.AddPair('updated_at', FormatDateTime('yyyy-mm-dd hh:nn:ss', StrToDateTime(SLValues.Values['updated_at'])))
    else
      FJSONObject.AddPair('updated_at', '0000-00-00 00:00:00');
  end;

  Result := FJSONObject;
end;

procedure TOlfeiCoreORM.Cache(LockBeforeUpdate: boolean = false);
var
  DS: TFDMemTable;
  i: integer;
  Query: string;
begin
  if ID > 0 then
  begin
    Query := '';

    for i := 0 to Length(Fields) - 1 do
      if Fields[i].Name <> '' then
        Query := Query + DBConnection.Quote + Fields[i].Name + DBConnection.Quote + ',';

    for i := 0 to Length(ForeignFields) - 1 do
      if ForeignFields[i].FLocalKey <> '' then
        Query := Query + DBConnection.Quote + ForeignFields[i].FLocalKey + DBConnection.Quote + ',';

    if Self.UseTimestamps then
      Query := Query + DBConnection.Quote + 'created_at' + DBConnection.Quote + ',' + DBConnection.Quote + 'updated_at' + DBConnection.Quote + ',';

    if Length(Query) > 0 then
    begin
      SetLength(Query, Length(Query) - 1);

      if (LockBeforeUpdate) and (DBConnection.Driver = 'mysql') then
        DS := DBConnection.GetSQL('SELECT ' + Query + ' FROM ' + DBConnection.Quote + Table + DBConnection.Quote + ' WHERE ' + DBConnection.Quote + 'id' + DBConnection.Quote + ' = ' + ID.ToString() + ' FOR UPDATE')
      else
        DS := DBConnection.GetSQL('SELECT ' + Query + ' FROM ' + DBConnection.Quote + Table + DBConnection.Quote + ' WHERE ' + DBConnection.Quote + 'id' + DBConnection.Quote + ' = ' + ID.ToString());

      for i := 0 to Length(Fields) - 1 do
        if Fields[i].Name <> '' then
          SLValues.Values[Fields[i].Name] := PrepareValue(AnsiLowerCase(Fields[i].ItemType), DS.FieldByName(Fields[i].Name).AsString);

      for i := 0 to Length(ForeignFields) - 1 do
        if ForeignFields[i].FLocalKey <> '' then
          SLValues.Values[ForeignFields[i].FLocalKey] := DS.FieldByName(ForeignFields[i].FLocalKey).AsString;

      if Self.UseTimestamps then
      begin
        SLValues.Values['created_at'] := PrepareValue('tdatetime', DS.FieldByName('created_at').AsString);
        SLValues.Values['updated_at'] := PrepareValue('tdatetime', DS.FieldByName('updated_at').AsString);
      end;

      DS.Free;
    end;
  end;
end;

{function TOlfeiCoreORM.FormatValue(Index: Integer): string;
var
  i: integer;
begin
  for i := 0 to Length(Self.Fields) - 1 do
    if Fields[i].Name = Self.SLValues.Names[Index] then
    begin
      if AnsiLowerCase(Fields[i].ItemType) = 'tdatetime' then
        Exit(FormatDateTime('yyyy-mm-dd hh:nn:ss', StrToDateTime(Self.SLValues.ValueFromIndex[Index])))
      else if AnsiLowerCase(Fields[i].ItemType) = 'tdate' then
        Exit(FormatDateTime('yyyy-mm-dd', StrToDate(Self.SLValues.ValueFromIndex[Index])))
      else
        Exit(Self.SLValues.ValueFromIndex[Index]);
    end;
end;}

function TOlfeiCoreORM.FormatValueByField(Index: Integer): string;
begin
  if AnsiLowerCase(Fields[Index].ItemType) = 'tdatetime' then
  begin
    if Self.SLValues.IndexOfName(Fields[Index].Name) <> -1 then
      Exit(FormatDateTime('yyyy-mm-dd hh:nn:ss', StrToDateTime(Self.SLValues.Values[Fields[Index].Name])))
  end
  else if AnsiLowerCase(Fields[Index].ItemType) = 'tdate' then
  begin
    if Self.SLValues.IndexOfName(Fields[Index].Name) <> -1 then
      Exit(FormatDateTime('yyyy-mm-dd', StrToDate(Self.SLValues.Values[Fields[Index].Name])))
  end
  else if AnsiLowerCase(Fields[Index].ItemType) = 'tjsonobject' then
  begin
    if Assigned(JSONValues[Index]) then
      Exit(DBConnection.Quoted((JSONValues[Index] as TJSONObject).ToJSON));
  end;

  Exit(Self.SLValues.Values[Fields[Index].Name]);
end;

procedure TOlfeiCoreORM.Save;
var
  i: integer;
  Query, QueryValues, QueryFields: string;
begin
  Query := '';
  QueryValues := '';
  QueryFields := '';

  if SLValues.Count > 0 then
  begin
    if Self.Exists then
    begin
      for i := 0 to Length(Fields) - 1 do
        if (SLChangedFields.Values[Fields[i].Name] = '1') and (Fields[i].Name <> 'created_at') and (Fields[i].Name <> '') and (Fields[i].Name <> 'updated_at') then
          Query := Query + DBConnection.Quote + Fields[i].Name + DBConnection.Quote + ' = "' + Self.FormatValueByField(i) + '",';

      for i := 0 to Length(ForeignFields) - 1 do
        Query := Query + DBConnection.Quote + ForeignFields[i].FLocalKey + DBConnection.Quote + ' = "' + Self.SLValues.Values[ForeignFields[i].FLocalKey] + '",';

      {for i := 0 to SLValues.Count - 1 do
        if (SLValues.Names[i] <> 'created_at') and (SLValues.Names[i] <> 'updated_at') then
          Query := Query + DBConnection.Quote + SLValues.Names[i] + DBConnection.Quote + ' = "' + Self.FormatValue(i) + '",';}

      for i := 0 to Length(BlobFields) - 1 do
        if (Length(BlobValues) > i) then
          if Assigned(BlobValues[i]) then
            if ((BlobValues[i] as TStringStream).Size > 0) and (BlobFields[i].Name <> '') then
              Query := Query + DBConnection.Quote + BlobFields[i].Name + DBConnection.Quote + ' = ' + DBConnection.FullQuoted((BlobValues[i] as TStringStream).DataString) + ',';

      if Length(Query) > 0 then
      begin
        SetLength(Query, Length(Query) - 1);

        DBConnection.RunSQL('UPDATE ' + DBConnection.Quote + Table + DBConnection.Quote + ' SET ' + Query + ' WHERE ' + DBConnection.Quote + 'id' + DBConnection.Quote + ' = "' + ID.ToString() + '"');
      end;

      if Self.UseTimestamps then
        DBConnection.RunSQL('UPDATE ' + DBConnection.Quote + Table + DBConnection.Quote + ' SET ' + DBConnection.Quote + 'updated_at' + DBConnection.Quote + ' = "' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now()) + '" WHERE ' + DBConnection.Quote + 'id' + DBConnection.Quote + ' = "' + ID.ToString() + '"');
    end
    else
    begin
      for i := 0 to Length(Fields) - 1 do
        if (Fields[i].Name <> 'created_at') and (Fields[i].Name <> '') and (Fields[i].Name <> 'updated_at') then
        begin
          QueryFields := QueryFields + DBConnection.Quote + Fields[i].Name + DBConnection.Quote + ',';
          QueryValues := QueryValues + '"' + Self.FormatValueByField(i) + '",';
        end;

      for i := 0 to Length(ForeignFields) - 1 do
      begin
        QueryFields := QueryFields + DBConnection.Quote + ForeignFields[i].FLocalKey + DBConnection.Quote + ',';
        QueryValues := QueryValues + '"' + Self.SLValues.Values[ForeignFields[i].FLocalKey] + '",';
      end;

      {for i := 0 to SLValues.Count - 1 do
        if (SLValues.Names[i] <> 'created_at') and (SLValues.Names[i] <> 'updated_at') then
        begin
          QueryFields := QueryFields + DBConnection.Quote + SLValues.Names[i] + DBConnection.Quote + ',';
          QueryValues := QueryValues + '"' + Self.FormatValue(i) + '",';
        end;}

      for i := 0 to Length(BlobFields) - 1 do
        if (Length(BlobValues) > i) then
          if Assigned(BlobValues[i]) then
            if ((BlobValues[i] as TStringStream).Size > 0) and (BlobFields[i].Name <> '') then
            begin
              QueryFields := QueryFields + DBConnection.Quote + BlobFields[i].Name + DBConnection.Quote + ',';
              QueryValues := QueryValues + DBConnection.FullQuoted((BlobValues[i] as TStringStream).DataString) + ',';
            end;

      SetLength(QueryFields, Length(QueryFields) - 1);
      SetLength(QueryValues, Length(QueryValues) - 1);

      DBConnection.RunSQL('INSERT INTO ' + DBConnection.Quote + Table + DBConnection.Quote + ' (' + QueryFields + ') VALUES (' + QueryValues + ')');
      ID := DBConnection.GetOnce('SELECT MAX(' + DBConnection.Quote + 'id' + DBConnection.Quote + ') FROM ' + DBConnection.Quote + Table + DBConnection.Quote, 'integer').ToInteger();

      if Self.UseTimestamps then
        DBConnection.RunSQL('UPDATE ' + DBConnection.Quote + Table + DBConnection.Quote + ' SET `updated_at` = "' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now()) + '", `created_at` = "' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now()) + '" WHERE ' + DBConnection.Quote + 'id' + DBConnection.Quote + ' = "' + ID.ToString() + '"');
    end;
  end;
end;

function TOlfeiCoreORM.IndexToField(Index: Integer): string;
begin
  if Length(Fields) = 0 then
    Result := ''
  else
    Result := Fields[Index].Name;
end;

function TOlfeiCoreORM.GetForeignObject(index: Integer; T: TClass): TObject;
var
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  RttiValue: TValue;
  RttiParameters: TArray<TValue>;
  LocalCollection: TOlfeiCollection<TOlfeiORM>;
  RemoteID: integer;

  function SmartToInteger(Value: string): integer;
  begin
    if Value = '' then
      Value := '0';

    Result := Value.ToInteger();
  end;

begin
  if Length(OlfeiForeigns) < index + 1 then
    SetLength(OlfeiForeigns, index + 1);

  if not Assigned(OlfeiForeigns[index]) then
  begin
    LocalCollection := TOlfeiCollection<TOlfeiORM>.Create(DBConnection, T);

    RemoteID := LocalCollection.Where(Self.ForeignFields[index].FRemoteKey, Self.SLValues.Values[ForeignFields[index].FLocalKey]).First(false, false).ID;

    LocalCollection.Free;

    RttiContext := TRttiContext.Create;
    RttiType := RttiContext.GetType(T);

    Setlength(RttiParameters, 3);
    RttiParameters[0] := TValue.From<TOlfeiDB>(DBConnection);
    RttiParameters[1] := RemoteID;
    RttiParameters[2] := True;

    RttiValue := RttiType.GetMethod('Create').Invoke(RttiType.AsInstance.MetaclassType, RttiParameters);

    OlfeiForeigns[index] := RttiValue.AsObject;
    (OlfeiForeigns[index] as TOlfeiCoreORM).FieldName := ForeignFields[index].FLocalKey;

    RttiContext.Free;
  end;

  Result := OlfeiForeigns[index];
end;

function TOlfeiCoreORM.GetForeignCollection(index: Integer; T: TClass): TObject;
var
  LocalCollection: TOlfeiCollection<TOlfeiORM>;
  Key: string;
begin
  if Length(OlfeiCollections) < index + 1 then
    SetLength(OlfeiCollections, index + 1);

  if Assigned(OlfeiCollections[index]) then
    FreeAndNil(OlfeiCollections[index]);

  if not Assigned(OlfeiCollections[index]) then
  begin
    LocalCollection := TOlfeiCollection<TOlfeiORM>.Create(DBConnection, T);

    if AnsiLowerCase(CollectionFields[index].FLocalKey) = AnsiLowerCase('id') then
      Key := Self.ID.ToString()
    else
      Key := Self.SLValues.Values[CollectionFields[index].FLocalKey];

    OlfeiCollections[index] := LocalCollection.Where(CollectionFields[index].FRemoteKey, '=', Key);
  end;

  Result := OlfeiCollections[index];
end;

function TOlfeiCoreORM.GetPivotCollection(index: Integer; T: TClass): TObject;
var
  LocalCollection: TOlfeiCollection<TOlfeiORM>;
begin
  if Length(OlfeiCollections) < index + 1 then
    SetLength(OlfeiCollections, index + 1);

  if Assigned(OlfeiCollections[index]) then
    FreeAndNil(OlfeiCollections[index]);

  if not Assigned(OlfeiCollections[index]) then
  begin
    LocalCollection := TOlfeiCollection<TOlfeiORM>.Create(DBConnection, T, true);

    LocalCollection.RemoteKey := PivotFields[index].FRemoteKey;
    LocalCollection.RemoteTable := PivotFields[index].FTable;
    LocalCollection.LocalKey := PivotFields[index].FLocalKey;
    LocalCollection.RemoteValue := PivotFields[index].FRemoteValue;

    OlfeiCollections[index] := LocalCollection
      .WhereFor(PivotFields[index].FTable, PivotFields[index].FLocalKey, '=', GetLocalKey(PivotFields[index].FLocalValue));
  end;

  Result := OlfeiCollections[index];
end;

function TOlfeiCoreORM.GetDateTime(index: Integer): TDateTime;
begin
  if SLValues.IndexOfName(IndexToField(index)) <> -1 then
    Result := StrToDateTime(SLValues.Values[IndexToField(index)])
  else
    Result := 0;
end;

procedure TOlfeiCoreORM.SetDateTime(index: Integer; Value: TDateTime);
begin
  SLValues.Values[IndexToField(index)] := FormatDateTime(FormatSettings.ShortDateFormat + ' ' + FormatSettings.LongTimeFormat, Value);
  SLChangedFields.Values[IndexToField(index)] := '1';
end;

function TOlfeiCoreORM.GetBlob(index: Integer): TStringStream;
begin
  if (Length(BlobValues) < index + 1) then
  begin
    if Length(BlobValues) < index + 1 then
      SetLength(BlobValues, index + 1);

    BlobValues[index] := TStringStream.Create(Self.DBConnection.GetOnce('SELECT ' + Self.BlobFields[index].Name + ' FROM ' + DBConnection.Quote + Self.Table + DBConnection.Quote + ' WHERE ' + DBConnection.Quote + 'id' + DBConnection.Quote + ' = ' + Self.ID.ToString(), 'string'));
  end;

  Result := (BlobValues[index] as TStringStream);
end;

function TOlfeiCoreORM.GetJSON(Index: Integer): TJSONObject;
begin
  if (Length(JSONValues) < Index + 1) then
  begin
    if Length(JSONValues) < Index + 1 then
      SetLength(JSONValues, Index + 1);

    JSONValues[Index] := TJSONObject.Create;
    (JSONValues[Index] as TJSONObject).Parse(BytesOf(SLValues.Values[IndexToField(Index)]), 0);
  end;

  Result := (JSONValues[Index] as TJSONObject);
end;

function TOlfeiCoreORM.GetDate(index: Integer): TDate;
begin
  if (SLValues.IndexOfName(IndexToField(index)) <> -1) and (SLValues.Values[IndexToField(index)] <> '') then
    Result := StrToDate(SLValues.Values[IndexToField(index)])
  else
    Result := 0;
end;

procedure TOlfeiCoreORM.SetDate(index: Integer; Value: TDate);
begin
  SLValues.Values[IndexToField(index)] := FormatDateTime(FormatSettings.ShortDateFormat, Value);
  SLChangedFields.Values[IndexToField(index)] := '1';
end;

function TOlfeiCoreORM.GetBoolean(index: Integer): Boolean;
begin
  if SLValues.IndexOfName(IndexToField(index)) <> -1 then
    Result := SLValues.Values[IndexToField(index)].ToBoolean()
  else
    Result := False;
end;

procedure TOlfeiCoreORM.SetBoolean(index: Integer; Value: Boolean);
begin
  SLValues.Values[IndexToField(index)] := OlfeiBoolToStr(Value).ToString();
  SLChangedFields.Values[IndexToField(index)] := '1';
end;

function TOlfeiCoreORM.GetInteger(index: Integer): Integer;
begin
  if SLValues.IndexOfName(IndexToField(index)) <> -1 then
    Result := SLValues.Values[IndexToField(index)].ToInteger()
  else
    Result := 0;
end;

procedure TOlfeiCoreORM.SetInteger(index: Integer; Value: Integer);
begin
  SLValues.Values[IndexToField(index)] := Value.ToString();
  SLChangedFields.Values[IndexToField(index)] := '1';
end;

function TOlfeiCoreORM.GetColor(index: Integer): TAlphaColor;
begin
  if SLValues.IndexOfName(IndexToField(index)) <> -1 then
    Result := TAlphaColor(SLValues.Values[IndexToField(index)].ToInteger())
  else
    Result := TAlphaColor(0);
end;

procedure TOlfeiCoreORM.SetColor(index: Integer; Value: TAlphaColor);
begin
  SLValues.Values[IndexToField(index)] := Integer(Value).ToString();
  SLChangedFields.Values[IndexToField(index)] := '1';
end;

function TOlfeiCoreORM.GetFloat(index: Integer): Real;
begin
  if SLValues.IndexOfName(IndexToField(index)) <> -1 then
    Result := UnpackFloat(SLValues.Values[IndexToField(index)]).ToDouble()
  else
    Result := 0;
end;

procedure TOlfeiCoreORM.SetFloat(index: Integer; Value: Real);
begin
  SLValues.Values[IndexToField(index)] := PackFloat(FloatToStr(Value));
  SLChangedFields.Values[IndexToField(index)] := '1';
end;

function TOlfeiCoreORM.GetString(Index: Integer): string;
begin
  if SLValues.IndexOfName(IndexToField(Index)) <> -1 then
    Result := SLValues.Values[IndexToField(Index)]
  else
    Result := '';
end;

procedure TOlfeiCoreORM.SetString(index: Integer; Value: string);
begin
  SLValues.Values[IndexToField(index)] := PrepareValue('string', Value);
  SLChangedFields.Values[IndexToField(index)] := '1';
end;

function TOlfeiCoreORM.PrepareValue(ValueType: string; Value: string): string;
begin
  Result := Value;

  if (ValueType = 'real') or (ValueType = 'decimal') or (ValueType = 'single') then
    Result := PackFloat(Value);

  if ValueType = 'boolean' then
    Result := Self.OlfeiBoolToStr(Self.OlfeiStrToBool(Value)).ToString();

  if ValueType = 'string' then
    Result := DBConnection.Quoted(Value);
end;

function TOlfeiCoreORM.Exists: Boolean;
begin
  Result := ID > 0;
end;

procedure TOlfeiCoreORM.Delete;
begin
  if Self.Exists then
  begin
    DBConnection.RunSQL('DELETE FROM ' + DBConnection.Quote + Table + DBConnection.Quote + ' WHERE ' + DBConnection.Quote + 'id' + DBConnection.Quote + ' = ' + ID.ToString());
    ID := 0;
  end;
end;

function TOlfeiCoreORM.GetLocalKey(Name: string): string;
begin
  if AnsiUpperCase(Name) = 'ID' then
    Result := Self.ID.ToString
  else
    Result := SLValues.Values[Name];
end;

end.

