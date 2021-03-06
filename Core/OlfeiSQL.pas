unit OlfeiSQL;

interface

uses Classes, Sysutils,
  SyncObjs, FireDAC.Stan.Intf,
  FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf,
  FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys,
  FireDAC.Comp.Client, FireDAC.Phys.SQLite, FireDAC.DApt, Data.DB,
  System.IniFiles, System.Threading, System.IOUtils, JSON

  {$IFDEF MSWINDOWS}
    ,FireDAC.Phys.MySQL
  {$ENDIF};

type
  TOlfeiStringItem = record
    Name, ItemType: string;
  end;

  TOlfeiStrings = array of TOlfeiStringItem;
  TOlfeiClasses = array of TClass;

  TOlfeiResultArray<T> = array of T;

  TOlfeiDB = class
  private
    CriticalSection: TCriticalSection;
    flLoaded, flAutoMigrate: Boolean;
    DriverConnect: TObject;
    IsDebug: Boolean;
    DebugFileName: string;

    {$IFDEF MSWINDOWS}
      FDPhysMySQLDriverLink: TFDPhysMySQLDriverLink;
    {$ENDIF}

    function IsRaw(val: string): boolean;
    function ClearRaw(val: string): string;
    procedure DebugSQL(Query: string);
  public
    Parameters: TStringList;
    SQLConnection: TFDConnection;
    Quote: string;
    Driver: string;
    IsPool: boolean;

    constructor Create(AutoMigrate: boolean = True); overload;
    constructor Create(ConnectionName: string; AutoMigrate: Boolean = True); overload;
    destructor Destroy; override;
    function GetSQL(SQL: string): TFDMemTable;
    function GetOnce(SQL, ValueType: string): string;
    procedure RunSQL(SQL: string);
    procedure BeginTransaction;
    procedure EndTransaction;
    procedure RollbackTransaction;
    procedure Connect;
    procedure Migrate;
    function RandomOrder: string;

    function Quoted(val: string): string;
    function FullQuoted(val: string): string;
    function Raw(val: string): string;
    procedure SetDebugFile(FileName: string);
  end;

implementation

uses
  {$I 'schema.inc'} OlfeiDriverSQLite, OlfeiDriverMySQL, OlfeiSchema, OlfeiSQLDriver;

function TOlfeiDB.RandomOrder: string;
begin
  Result := (DriverConnect as TOlfeiSQLDriver).RandomOrder;
end;

destructor TOlfeiDB.Destroy;
begin
  DriverConnect.Free;

  SQLConnection.Connected := false;
  SQLConnection.Close;
  SQLConnection.Free;

  CriticalSection.Free;

  Parameters.Free;

  {$IFDEF MSWINDOWS}
    FDPhysMySQLDriverLink.Free;
  {$ENDIF}

  inherited;
end;

function TOlfeiDB.Quoted(val: string): string;
begin
  Result := StringReplace(trim(val), #39, #39#39, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(trim(Result), #34, #34#34, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(trim(Result), '!', '', [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(trim(Result), '\', '\\', [rfReplaceAll, rfIgnoreCase]);

  if Result = ' ' then
    Result := '';
end;

procedure TOlfeiDB.DebugSQL(Query: string);
begin
  if IsDebug then
  begin
    TMonitor.Enter(Self);

    TFile.AppendAllText(DebugFileName, Query + #13, TEncoding.UTF8);

    TMonitor.Exit(Self);
  end;
end;

function TOlfeiDB.FullQuoted(val: string): string;
begin
  if Self.IsRaw(val) then
    Result := Self.ClearRaw(val)
  else
    Result := '"' + Self.Quoted(val) + '"';
end;

function TOlfeiDB.Raw(val: string): string;
begin
  Result := 'RAWDATA={' + val + '}';
end;

function TOlfeiDB.ClearRaw(val: string): string;
begin
  Result := Copy(val, 10, Length(val) - 10);
end;

function TOlfeiDB.IsRaw(val: string): boolean;
begin
  Result := Pos('RAWDATA', val) > 0;
end;

constructor TOlfeiDB.Create(ConnectionName: string; AutoMigrate: Boolean = true);
begin
  IsPool := True;

  flLoaded := true;
  flAutoMigrate := AutoMigrate;

  SQLConnection := TFDConnection.Create(nil);

  SQLConnection.ConnectionDefName := ConnectionName;

  SQLConnection.FetchOptions.Mode := fmAll;
  SQLConnection.FetchOptions.RowsetSize := 300;
  SQLConnection.FetchOptions.AutoClose := True;
  SQLConnection.TxOptions.AutoCommit := True;

  SQLConnection.ResourceOptions.SilentMode := True;

  CriticalSection := TCriticalSection.Create;

  Parameters := TStringList.Create;
end;

constructor TOlfeiDB.Create(AutoMigrate: boolean = True);
begin
  IsPool := false;

  flLoaded := true;
  flAutoMigrate := AutoMigrate;
  IsDebug := false;

  SQLConnection := TFDConnection.Create(nil);

  SQLConnection.FetchOptions.Mode := fmAll;
  SQLConnection.FetchOptions.RowsetSize := 300;
  SQLConnection.FetchOptions.AutoClose := True;
  SQLConnection.TxOptions.AutoCommit := True;
  SQLConnection.ResourceOptions.SilentMode := True;

  CriticalSection := TCriticalSection.Create;

  {$IFDEF MSWINDOWS}
    FDPhysMySQLDriverLink := TFDPhysMySQLDriverLink.Create(nil);
  {$ENDIF}

  Parameters := TStringList.Create;
end;

procedure TOlfeiDB.Connect;
begin
  if IsPool then
  begin
    if Pos(AnsiUpperCase('MySQL'), AnsiUpperCase(SQLConnection.ConnectionDefName)) > 0 then
      Driver := 'mysql';

    if Pos(AnsiUpperCase('SQLite'), AnsiUpperCase(SQLConnection.ConnectionDefName)) > 0 then
      Driver := 'sqlite';
  end
  else
    Driver := Parameters.Values['driver'];

  if Driver = '' then
    raise Exception.Create('ORM support only SQLite and MySQL (MariaDB)');

  if Driver = 'sqlite' then
  begin
    DriverConnect := TOlfeiDriverSQLite.Create(Self);
    (DriverConnect as TOlfeiDriverSQLite).Init(Parameters);

    SQLConnection.Connected := true;

    if flAutoMigrate then
      Self.Migrate;
  end;

  if Driver = 'mysql' then
  begin
    {$IFDEF MSWINDOWS}
      DriverConnect := TOlfeiDriverMySQL.Create(Self);
      (DriverConnect as TOlfeiDriverMySQL).Init(Parameters);

      SQLConnection.Connected := true;

      if flAutoMigrate then
        Self.Migrate;
    {$ELSE}
      raise Exception.Create('Mobile platforms support only SQLite');
    {$ENDIF}
  end;
end;

procedure TOlfeiDB.SetDebugFile(FileName: string);
begin
  IsDebug := True;
  DebugFileName := FileName;
end;

procedure TOlfeiDB.Migrate;
var
  OlfeiSchema: TOlfeiSchema;
begin
  OlfeiSchema := TOlfeiSchema.Create((DriverConnect as TOlfeiSQLDriver));
  OlfeiSchema.Run;
  OlfeiSchema.Free;
end;

function TOlfeiDB.GetSQL(SQL: string): TFDMemTable;
var
  Query: TFDQuery;
begin
  Self.DebugSQL(SQL);

  if SQLConnection.Connected then
  begin
    CriticalSection.Enter;

    Query := TFDQuery.Create(SQLConnection);
    Query.Connection := SQLConnection;

    Query.SQL.Clear;
    Query.SQL.Add(SQL);
    Query.Open;

    Query.FetchAll;

    Result := TFDMemTable.Create(nil);
    Result.Data := Query.Data;
    Result.First;

    Query.Free;
    
    CriticalSection.Leave;
  end
  else
    Result := TFDMemTable.Create(nil);
end;

procedure TOlfeiDB.RunSQL(SQL: string);
begin
  Self.DebugSQL(SQL);

  if SQLConnection.Connected then
  begin
    CriticalSection.Enter;

    SQLConnection.ExecSQL(SQL);
    
    CriticalSection.Leave;
  end;
end;

function TOlfeiDB.GetOnce(SQL, ValueType: string): string;
var
  DS: TFDMemTable;
begin
  Self.DebugSQL(SQL);

  if SQLConnection.Connected then
  begin
    DS := GetSQL(SQL);

    CriticalSection.Enter;

    if not DS.Eof then
      Result := DS.Fields[0].AsString
    else
      if ValueType = 'string' then
        Result := ''
      else
        Result := '0';

    DS.Free;

    if (ValueType = 'integer') and (Result = '') then
      Result := '0';

    if (ValueType = 'integer') and (Result[Length(Result)] = '0') and (Result[Length(Result) - 1] = '.')  then
      Result := StringReplace(Result, '.0', '', []);

    if (ValueType = 'integer') and (Result[Length(Result)] = '0') and (Result[Length(Result) - 1] = ',')  then
      Result := StringReplace(Result, ',0', '', []);

    if ValueType = 'integer' then
      Result := StringReplace(Result, '.', ',', [rfReplaceAll]);

    if Result = 'False' then
      Result := '0';

    if Result = 'True' then
      Result := '1';

    CriticalSection.Leave;
  end;
end;

procedure TOlfeiDB.BeginTransaction;
begin
  SQLConnection.TxOptions.AutoCommit := False;
  SQLConnection.TxOptions.AutoStart := False;
  SQLConnection.TxOptions.AutoStop := False;

  SQLConnection.StartTransaction;
end;

procedure TOlfeiDB.EndTransaction;
begin
  SQLConnection.Commit;

  SQLConnection.TxOptions.AutoCommit := True;
  SQLConnection.TxOptions.AutoStart := True;
  SQLConnection.TxOptions.AutoStop := True;
end;

procedure TOlfeiDB.RollbackTransaction;
begin
  SQLConnection.Rollback;

  SQLConnection.TxOptions.AutoCommit := True;
  SQLConnection.TxOptions.AutoStart := True;
  SQLConnection.TxOptions.AutoStop := True;
end;

end.




