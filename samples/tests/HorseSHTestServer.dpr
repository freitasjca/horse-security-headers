program HorseSHTestServer;

{$APPTYPE CONSOLE}

{
  Horse.Middleware.SecurityHeaders  —  Integration Test Server
  ============================================================
  Destination: horse-security-headers/samples/tests/HorseSHTestServer.dpr

  Transport: CrossSocket ({$DEFINE HORSE_CROSSSOCKET  required in project options).

  Port: 9300

  Each route is registered with a single combined callback that (a) invokes the
  appropriate security-headers middleware closure with an inline handler proc as
  its Next argument, then (b) the inline handler sends the response.

  This is the correct Horse pattern for per-route middleware isolation:
  THorse.Get accepts exactly one THorseCallback, so per-route middleware is
  applied by passing the actual handler as the Next proc of the middleware call.

  Routes:
    GET /default    — uses THorseSecurityHeaders.New (Default config)
    GET /strict     — uses THorseSecurityHeaders.New (Strict config, HSTS enabled)
    GET /sameorigin — uses a custom config with XFrameOptions = fosameorigin
    GET /plain      — no security headers middleware (baseline for negative checks)
}

uses
  System.SysUtils,
  System.Classes,
  Horse,
{$IFDEF HORSE_CROSSSOCKET}
  Horse.Provider.CrossSocket,
{$ENDIF}
  Horse.Middleware.SecurityHeaders in '..\..\src\Horse.Middleware.SecurityHeaders.pas';


const
  TEST_PORT = 9300;

procedure RegisterRoutes;
var
  LDefaultMW:    THorseCallback;
  LStrictMW:     THorseCallback;
  LSameOriginMW: THorseCallback;
  LCfg:          THorseSecurityHeadersConfig;
begin

  // Pre-build middleware closures — one config record copy each.
  // NOTE: do NOT use THorse.Use() here.  Global middleware runs for every
  // route including /plain (which must have no headers), and it stamps headers
  // AFTER the route handler returns — overwriting any per-route middleware that
  // already set a different value (e.g. /sameorigin's X-Frame-Options).
  // All middleware is applied per-route via the Next-proc pattern instead.
  LDefaultMW    := THorseSecurityHeaders.New(THorseSecurityHeadersConfig.Default);
  //LDefaultMW    := THorseSecurityHeaders.New;
  LStrictMW     := THorseSecurityHeaders.New(THorseSecurityHeadersConfig.Strict);

  LCfg                 := THorseSecurityHeadersConfig.Default;
  LCfg.XFrameOptions   := fosameorigin;
  LSameOriginMW        := THorseSecurityHeaders.New(LCfg);

  // ── /default — exercises every Default-config header ──────────────────────
  THorse.Get('/default',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    begin
      LDefaultMW(Req, Res,
        procedure
        begin
          Res.ContentType('text/plain').Send('ok');
        end);
    end
  );

  // ── /strict — Strict config: HSTS with includeSubDomains ──────────────────
  THorse.Get('/strict',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    begin
      LStrictMW(Req, Res,
        procedure
        begin
          Res.ContentType('text/plain').Send('ok');
        end);
    end
  );

  // ── /sameorigin — custom XFrameOptions ────────────────────────────────────
  THorse.Get('/sameorigin',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    begin
      LSameOriginMW(Req, Res,
        procedure
        begin
          Res.ContentType('text/plain').Send('ok');
        end);
    end
  );

  // ── /plain — no security middleware (negative baseline) ───────────────────
  // Uses the full three-parameter THorseCallback signature to be compatible
  // with all Horse versions (some lack the THorseCallbackRequestResponse
  // two-param overload of Get).
  THorse.Get('/plain',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    begin
      Res.ContentType('text/plain').Send('ok');
    end
  );

end;

begin
  try
    RegisterRoutes;
{$IFDEF HORSE_CROSSSOCKET}
    THorse.Listen(TEST_PORT);
    Writeln(Format('[HorseSHTest] Server listening on http://127.0.0.1:%d  [CrossSocket]',
      [TEST_PORT]));
{$ELSE}
    THorse.Listen(TEST_PORT);
    Writeln(Format('[HorseSHTest] Server listening on http://127.0.0.1:%d  [Indy/Console]',
      [TEST_PORT]));
{$ENDIF}
    Writeln('[HorseSHTest] Run HorseSHTestClient to execute the test suite.');
    Writeln('[HorseSHTest] Press ENTER to stop...');
    Readln;
  except
    on E: Exception do
    begin
      Writeln('[HorseSHTest] Fatal: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
