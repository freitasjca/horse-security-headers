program HorseSHTestClient;

{$APPTYPE CONSOLE}

{
  Horse.Middleware.SecurityHeaders  —  Integration Test Client
  ============================================================
  Destination: horse-security-headers/samples/tests/HorseSHTestClient.dpr

  Requires HorseSHTestServer running on 127.0.0.1:9300 before executing.

  Test matrix:

    Default config (GET /default):
    01  X-Content-Type-Options: nosniff                         (XContentTypeOptions=True)
    02  X-Frame-Options: DENY                                   (XFrameOptions=fodeny)
    03  Referrer-Policy: strict-origin-when-cross-origin        (ReferrerPolicy default)
    04  Cache-Control: no-store                                 (CacheControlNoStore=True)
    05  Strict-Transport-Security absent                        (HSTSMaxAge=0 — disabled)
    06  Server: unknown                                         (SuppressServerHeader=True)
    07  Handler called: status 200, body "ok"                   (Next works correctly)

    Strict config (GET /strict):
    08  Strict-Transport-Security: max-age=31536000; includeSubDomains
    09  X-Content-Type-Options still present in strict config

    Custom config (GET /sameorigin):
    10  X-Frame-Options: SAMEORIGIN                            (XFrameOptions=fosameorigin)

    Negative baseline (GET /plain — no middleware):
    11  X-Content-Type-Options absent on plain route
    12  X-Frame-Options absent on plain route

  Exit code = number of failed assertions (0 = all passed).
}

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Net.CrossHttpClient,
  Net.CrossHttpParams;

const
  BASE_URL   = 'http://127.0.0.1:9300';
  TIMEOUT_MS = 8000;

var
  GPassCount: Integer = 0;
  GFailCount: Integer = 0;

// ── Helpers ───────────────────────────────────────────────────────────────────

function StreamToStr(AStream: TStream): string;
var
  LBytes: TBytes;
begin
  Result := '';
  if not Assigned(AStream) or (AStream.Size = 0) then Exit;
  AStream.Position := 0;
  SetLength(LBytes, AStream.Size);
  AStream.ReadBuffer(LBytes[0], AStream.Size);
  Result := TEncoding.UTF8.GetString(LBytes);
end;

procedure Check(const AName: string; const APassed: Boolean;
  const ADetail: string = '');
begin
  if APassed then
  begin
    Writeln(Format('  PASS  %s', [AName]));
    Inc(GPassCount);
  end
  else
  begin
    if ADetail <> '' then
      Writeln(Format('  FAIL  %s  [%s]', [AName, ADetail]))
    else
      Writeln(Format('  FAIL  %s', [AName]));
    Inc(GFailCount);
  end;
end;

// ── Synchronous request helper ────────────────────────────────────────────────

type
  TReqResult = record
    StatusCode: Integer;
    Body:       string;
    Response:   ICrossHttpClientResponse;
    TimedOut:   Boolean;
  end;

function DoSync(
  const AClient: TCrossHttpClient;
  const AMethod: string;
  const AUrl:    string;
  out   AResult: TReqResult
): Boolean;
var
  LEvent:  TEvent;
  LResult: TReqResult;
begin
  LResult   := Default(TReqResult);
  LEvent    := TEvent.Create(nil, True, False, '');
  try
    AClient.DoRequest(AMethod, AUrl, nil, TBytes(nil), nil, nil,
      procedure(const AResp: ICrossHttpClientResponse)
      begin
        if AResp <> nil then
        begin
          LResult.StatusCode := AResp.StatusCode;
          LResult.Body       := StreamToStr(AResp.Content);
          LResult.Response   := AResp;
        end;
        LEvent.SetEvent;
      end);
    LResult.TimedOut := (LEvent.WaitFor(TIMEOUT_MS) <> wrSignaled);
  finally
    LEvent.Free;
  end;
  AResult := LResult;
  Result  := not AResult.TimedOut;
end;

{ Return the value of a named response header, or '' if absent. }
function RH(const AResult: TReqResult; const AName: string): string;
begin
  if Assigned(AResult.Response) then
    Result := AResult.Response.Header[AName]
  else
    Result := '';
end;

// ── Test suite ────────────────────────────────────────────────────────────────

procedure RunTests(const AClient: TCrossHttpClient);
var
  R: TReqResult;

  procedure Section(const ATitle: string);
  begin
    Writeln('');
    Writeln('── ' + ATitle);
  end;

begin

  // ── Default config headers ────────────────────────────────────────────────────
  Section('Default config  GET /default');
  DoSync(AClient, 'GET', BASE_URL + '/default', R);

  Check('01  X-Content-Type-Options = nosniff',
    RH(R, 'X-Content-Type-Options') = 'nosniff',
    RH(R, 'X-Content-Type-Options'));

  Check('02  X-Frame-Options = DENY',
    RH(R, 'X-Frame-Options') = 'DENY',
    RH(R, 'X-Frame-Options'));

  Check('03  Referrer-Policy = strict-origin-when-cross-origin',
    RH(R, 'Referrer-Policy') = 'strict-origin-when-cross-origin',
    RH(R, 'Referrer-Policy'));

  Check('04  Cache-Control = no-store',
    RH(R, 'Cache-Control') = 'no-store',
    RH(R, 'Cache-Control'));

  Check('05  Strict-Transport-Security absent  (HSTSMaxAge = 0)',
    RH(R, 'Strict-Transport-Security') = '',
    RH(R, 'Strict-Transport-Security'));

  Check('06  Server = unknown  (SuppressServerHeader = True)',
    RH(R, 'Server') = 'unknown',
    RH(R, 'Server'));

  Check('07  handler called: status 200',
    R.StatusCode = 200,
    IntToStr(R.StatusCode));

  Check('07  handler called: body = "ok"',
    R.Body = 'ok',
    R.Body);

  // ── Strict config — HSTS ──────────────────────────────────────────────────────
  Section('Strict config  GET /strict');
  DoSync(AClient, 'GET', BASE_URL + '/strict', R);

  Check('08  Strict-Transport-Security: max-age=31536000; includeSubDomains',
    RH(R, 'Strict-Transport-Security') = 'max-age=31536000; includeSubDomains',
    RH(R, 'Strict-Transport-Security'));

  Check('09  X-Content-Type-Options present in strict config',
    RH(R, 'X-Content-Type-Options') = 'nosniff',
    RH(R, 'X-Content-Type-Options'));

  // ── Custom config — SAMEORIGIN frame option ───────────────────────────────────
  Section('Custom config  GET /sameorigin');
  DoSync(AClient, 'GET', BASE_URL + '/sameorigin', R);

  Check('10  X-Frame-Options = SAMEORIGIN',
    RH(R, 'X-Frame-Options') = 'SAMEORIGIN',
    RH(R, 'X-Frame-Options'));

  // ── Negative baseline — no middleware on /plain ───────────────────────────────
  Section('No middleware  GET /plain');
  DoSync(AClient, 'GET', BASE_URL + '/plain', R);

  Check('11  X-Content-Type-Options absent on plain route',
    RH(R, 'X-Content-Type-Options') = '',
    RH(R, 'X-Content-Type-Options'));

  Check('12  X-Frame-Options absent on plain route',
    RH(R, 'X-Frame-Options') = '',
    RH(R, 'X-Frame-Options'));

end;

// ── Entry point ───────────────────────────────────────────────────────────────

var
  AClient: TCrossHttpClient;
begin
  Writeln('Horse SecurityHeaders — Integration Tests');
  Writeln('Server: ' + BASE_URL);
  Writeln(StringOfChar('─', 50));

  AClient := TCrossHttpClient.Create(2);
  try
    RunTests(AClient);
  finally
    AClient.Free;
  end;

  Writeln('');
  Writeln(StringOfChar('─', 50));
  Writeln(Format('Results: %d passed  %d failed  %d total',
    [GPassCount, GFailCount, GPassCount + GFailCount]));

  ExitCode := GFailCount;
end.
