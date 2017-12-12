unit MainForm;

interface

uses
  FMX.HanmiIT.RFIDReader,
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Controls.Presentation, FMX.ListBox, FMX.Layouts, FMX.ListView.Types,
  FMX.ListView.Appearances, FMX.ListView.Adapters.Base, FireDAC.Stan.Intf,
  FireDAC.Stan.Option, FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS,
  FireDAC.Phys.Intf, FireDAC.DApt.Intf, Data.DB, FireDAC.Comp.DataSet,
  FireDAC.Comp.Client, FMX.ListView;

type
  TForm2 = class(TForm)
    ToolBar1: TToolBar;
    btnMenu: TButton;
    lytMenu: TLayout;
    lytList: TLayout;
    swcFiltered: TSwitch;
    btnRFIDInventory: TButton;
    Label1: TLabel;
    cbxPowerGain: TComboBox;
    btnRFIDClear: TButton;
    Label2: TLabel;
    ListView1: TListView;
    FDMemTable1: TFDMemTable;
    FDMemTable1TagString: TStringField;
    FDMemTable1Count: TIntegerField;
    tmrFillList: TTimer;
    Layout1: TLayout;
    btnBarcode: TButton;
    procedure btnMenuClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnRFIDInventoryClick(Sender: TObject);
    procedure swcFilteredSwitch(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure cbxPowerGainChange(Sender: TObject);
    procedure tmrFillListTimer(Sender: TObject);
    procedure btnRFIDClearClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnBarcodeClick(Sender: TObject);
  private
    { Private declarations }
    FReader: TRFIDReader;
    FConnectedAddress: string;
    FHasNewData: Boolean; // ���ο� RFID Tag ���翩��
    FInitPower: Boolean;

    procedure InitPowerGainCombo(AValue: Integer);

    // ���� ����
    procedure ConnectToLastDevice;
    procedure ConnectToNewDevice;

    // ��ġ����/����
    procedure ConnectToDevice(AAddress: string);
    procedure DisconnectFromDevice;

    procedure StartInventory;
    procedure StopInventory;

    procedure StartBarcode(RunAction: Boolean);
    procedure StopBarcode(RunAction: Boolean);

    // ȯ������
    function LoadAddressFromConfig: string;
    procedure SaveAddressToConfig(AValue: string);

    // ���� �̺�Ʈ
    procedure ConnectedDeviceEvent(Sender: TObject);
    procedure DisconnectedDeviceEvent(Sender: TObject);

    procedure ReadedTagEvent(ATag: string); // RFID �±� ����
    procedure AddOrUpdateTag(ATag: string);

    procedure ReadedBarcodeEvent(ABarcodeType, ACodeId, ABarcode: string); // ���ڵ� ����
    procedure BarcodeStateEvent(AState: TBarcodeState); // ���ڵ� ���� ����(Start, End)

    procedure EnabledControls(AEnabled: Boolean);
  public
    { Public declarations }
  end;

var
  Form2: TForm2;

implementation

{$R *.fmx}

uses
  System.IOUtils, System.IniFiles,
  Androidapi.Helpers, Androidapi.JNI.Widget, // Toast
  Androidapi.JNI.Bluetooth,
  FMX.UI.OverflowMenu,
  FMX.UI.SelectBluetoothDeviceDialog, FMX.UI.WaitDialog;

procedure ToastMessage(AText: string);
var
  Toast: JToast;
begin
  Toast := TJToast.JavaClass.makeText(TAndroidHelper.Context, StrToJCharSequence(AText), TJToast.JavaClass.LENGTH_LONG);
  Toast.show;
end;

procedure TForm2.FormCreate(Sender: TObject);
begin
  FHasNewData := False;
  tmrFillList.Enabled := False;
  tmrFillList.Interval := 250;

  FDMemTable1.Active := True;
  FDmemTable1.IndexFieldNames := 'TagString';

  ListView1.AllowSelection := False;
  ListView1.ItemAppearance.ItemAppearance := 'ListItemRightDetail';
  ListView1.ItemAppearanceObjects.ItemObjects.Accessory.Visible := False;

  EnabledControls(False);

  FReader := TRFIDReader.Create;
  FReader.OnConnected := ConnectedDeviceEvent;
  FReader.OnDisconnected := DisconnectedDeviceEvent;
  FReader.OnReadedTag := ReadedTagEvent;
  FReader.OnReadedBarcode := ReadedBarcodeEvent;
  FReader.OnBarcodeState := BarcodeStateEvent;
end;

procedure TForm2.FormDestroy(Sender: TObject);
begin
  FReader.Free;
end;

procedure TForm2.FormShow(Sender: TObject);
var
  Adapter: JBluetoothAdapter;
begin
  Adapter := TJBluetoothAdapter.JavaClass.getDefaultAdapter;
  if not Adapter.isEnabled then
  begin
    TWaitDialog.Show('��������� Ȱ��ȭ �մϴ�.', 2000);
    Adapter.enable;
  end;
end;

procedure TForm2.btnRFIDClearClick(Sender: TObject);
begin
  //
  if FReader.Filtered then
    FReader.ClearStoredTag;

  { TODO : �����ͼ� �ʱ�ȭ }
  FDMemTable1.EmptyDataSet;
  ListView1.Items.Clear;
end;

procedure TForm2.btnRFIDInventoryClick(Sender: TObject);
begin
  if TButton(Sender).Text = 'Inventory' then
    StartInventory
  else
    StopInventory;
end;

procedure TForm2.AddOrUpdateTag(ATag: string);
var
  Count: Integer;
begin
  Log.d('AddOrUpdateTag: ' + ATag);
  if not FDMemTable1.FindKey([ATag]) then
  begin
    FDMemTable1.Append;
    FDMemTable1.FieldByName('TagString').AsString := ATag;
    FDMemTable1.FieldByName('Count').AsInteger := 1;
    FDMemTable1.Post;
    Log.d('Append');
  end
  else
  begin
    Count := FDMemTable1.FieldByName('Count').AsInteger;
    Inc(Count);

    FDMemTable1.Edit;
    FDMemTable1.FieldByName('Count').AsInteger := Count;
    FDMemTable1.Post;
    Log.d('Update');
  end;

  FHasNewData := True;
end;

procedure TForm2.BarcodeStateEvent(AState: TBarcodeState);
begin
  case AState of
    ScanStart: StartBarcode(False);
    ScanEnd: StopBarcode(False);
  end;
end;

procedure TForm2.btnBarcodeClick(Sender: TObject);
begin
  if btnBarcode.Text = 'Barcode Scan' then
    StartBarcode(True)
  else
    StopBarcode(True);
end;

procedure TForm2.btnMenuClick(Sender: TObject);
begin
  TOverflowMenu.Settings.Top := ToolBar1.Height + 1;
  TOverflowMenu.Settings.Width := Width * 0.9;
  TOverflowMenu.Settings.RightPadding := 10;

  if FReader.Connected then
  begin
    TOverflowMenu.ShowMenu([
        'Disconnect from device'],
      procedure(AIndex: Integer; AText: string)
      begin
        case AIndex of
          0: DisconnectFromDevice;
        end;
      end);
  end
  else
  begin
    TOverflowMenu.ShowMenu([
        'Connect to last bluetooth device',
        'Connect to new bluetooth device'],
      procedure(AIndex: Integer; AText: string)
      begin
        case AIndex of
          0: ConnectToLastDevice;
          1: ConnectToNewDevice;
        end;
      end);
  end;
end;

procedure TForm2.ConnectToLastDevice;
var
  Addr: string;
begin
  Addr := LoadAddressFromConfig;
  if Addr = '' then
  begin
    ToastMessage('���� ���� ������ ã�� �� �����ϴ�. ���ο� ������ �õ��ϼ���.');
    Exit;
  end;
  ConnectToDevice(Addr);
end;

procedure TForm2.ConnectToNewDevice;
begin
  TSelectBluetoothDeviceDialog.OpenBluetoothDeviceListFilter(
    'RFPrisma',
    procedure(ADeviceName, AAddress: string)
    begin
      ConnectToDevice(AAddress);
    end
  );
end;

procedure TForm2.ConnectToDevice(AAddress: string);
begin
  TWaitDialog.Show('������ ��ø� ��ٷ��ּ���.');
  FReader.ConnectDevice(AAddress);
end;

procedure TForm2.DisconnectFromDevice;
begin
  FReader.DisconnectDevice;
end;

procedure TForm2.ConnectedDeviceEvent(Sender: TObject);
var
  Power: Integer;
begin
  SaveAddressToConfig(FReader.DeivceAddress);
  TWaitDialog.Hide;

  EnabledControls(True);

  Power := FReader.PowerGain;
  InitPowerGainCombo(Power);
  FReader.Filtered := swcFiltered.IsChecked;
end;

procedure TForm2.DisconnectedDeviceEvent(Sender: TObject);
begin
  TWaitDialog.Hide;
  EnabledControls(False);
end;

procedure TForm2.EnabledControls(AEnabled: Boolean);
begin
  swcFiltered.Enabled := AEnabled;
  btnRFIDInventory.Enabled := AEnabled;
  btnRFIDClear.Enabled := AEnabled;
  cbxPowerGain.Enabled := AEnabled;

  btnBarcode.Enabled := AEnabled;
end;

procedure TForm2.InitPowerGainCombo(AValue: Integer);
var
  I: Integer;
  S: string;
begin
  FInitPower := True;
  try
    cbxPowerGain.Items.Clear;

    for I := 30 downto 5 do
      cbxPowerGain.Items.Add(Format('%d.0 dBm', [I]));

    S := Format('%d.0 dBm', [AValue div 10]);
    for I := 0 to cbxPowerGain.Items.Count - 1 do
    begin
      if cbxPowerGain.Items[I] = S then
      begin
        cbxPowerGain.ItemIndex := I;
        Exit;
      end;
    end;
  finally
    FInitPower := False;
  end;
end;

procedure TForm2.cbxPowerGainChange(Sender: TObject);
var
  Power: Integer;
  Txt, PowerStr: string;
  N: Integer;
begin
  if FInitPower then
    Exit;
  Power := 100; // default
  Txt := cbxPowerGain.Selected.Text;

  if Pos('.', Txt) > 0 then
  begin
    PowerStr := Copy(Txt, 1, Pos('.', Txt)-1);

    if TryStrToInt(PowerStr, N) then
      Power := N * 10;
  end;
  FReader.PowerGain := Power;
  ShowMessage(Txt);
end;

function TForm2.LoadAddressFromConfig: string;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(TPath.Combine(TPath.GetDocumentsPath, 'AddrConf.ini'));
  try
    Result := Ini.ReadString('Device', 'Address', '');
  finally
    Ini.Free;
  end;
end;

procedure TForm2.ReadedBarcodeEvent(ABarcodeType, ACodeId, ABarcode: string);
begin
  ToastMessage(Format('[%s][%s] %s',
    [ABarcodeType, ACodeId, ABarcode]));
  StopBarcode(False);
end;

procedure TForm2.ReadedTagEvent(ATag: string);
begin
  AddOrUpdateTag(ATag);
end;

procedure TForm2.SaveAddressToConfig(AValue: string);
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(TPath.Combine(TPath.GetDocumentsPath, 'AddrConf.ini'));
  try
    Ini.WriteString('Device', 'Address', AValue);
  finally
    Ini.Free;
  end;
end;

procedure TForm2.StartBarcode(RunAction: Boolean);
begin
  if RunAction then
    FReader.StartBarcode;
  btnBarcode.Text := 'Stop';
  btnRFIDInventory.Enabled := False;
end;

procedure TForm2.StopBarcode(RunAction: Boolean);
begin
  if RunAction then
    FReader.StopBarcode;
  btnBarcode.Text := 'Barcode Scan';
  btnRFIDInventory.Enabled := True;
end;

procedure TForm2.StartInventory;
begin
  FReader.StartInventory;
  btnRFIDInventory.Text := 'Stop';
  btnRFIDClear.Enabled := False;
  tmrFillList.Enabled := True;

  btnBarcode.Enabled := False;
end;

procedure TForm2.StopInventory;
begin
  FReader.StopInventory;
  btnRFIDInventory.Text := 'Inventory';
  btnRFIDClear.Enabled := True;
  tmrFillList.Enabled := False;

  btnBarcode.Enabled := True;
end;

procedure TForm2.swcFilteredSwitch(Sender: TObject);
begin
  FReader.Filtered := swcFiltered.IsChecked;
end;

procedure TForm2.tmrFillListTimer(Sender: TObject);
var
  Item: TListViewItem;
begin
  if FHasNewData then
  begin
    ListView1.BeginUpdate;
    ListView1.Items.Clear;

    FDMemTable1.First;
    while not FDMemTable1.Eof do
    begin
      Item := ListView1.Items.Add;
      Item.Text := FDMemTable1.FieldByName('TagString').AsString;
      Item.Detail := FDmemTable1.FieldByName('Count').AsString;

      FDMemTable1.Next;
    end;
    ListView1.EndUpdate;
  end;

  FHasNewData := False;
end;

end.
