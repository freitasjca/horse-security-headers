unit Horse.Middleware.SecurityHeaders;

{$IF DEFINED(FPC)}{$MODE DELPHI}{$H+}{$ENDIF}

// ============================================================================
//  Horse.Middleware.SecurityHeaders
//  Response hardening: X-Content-Type-Options, X-Frame-Options, Referrer-Policy,
//  Cache-Control, HSTS (opt-in), Server header suppression.
//
//  Provider-agnostic — works with any Horse provider (Indy, CrossSocket, etc.)
//  On CrossSocket, TResponseBridge.Flush also injects these headers at the
//  transport layer; using both is safe (headers appear once per HTTP spec for
//  most of these, or the harmless duplicate is filtered by the client).
//  On Indy this middleware is the only source of these headers.
//
//  Usage:
//    THorse.Use(THorseSecurityHeaders.New);              // default config
//    THorse.Use(THorseSecurityHeaders.New(               // custom config
//      THorseSecurityHeadersConfig.Strict));
// ============================================================================

interface

uses
  Horse;
  //Horse.Request,
  //Horse.Response,
  //Horse.Callback;

type
  /// Controls the X-Frame-Options response header.
  TFrameOption = (
    /// DENY — page cannot be embedded in any frame.
    fodeny,
    /// SAMEORIGIN — page can only be embedded by the same origin.
    fosameorigin
  );

  /// Controls the Referrer-Policy response header.
  TReferrerPolicy = (
    /// strict-origin-when-cross-origin (recommended default).
    rpStrictOriginWhenCrossOrigin,
    /// no-referrer — never send the Referer header.
    rpNoReferrer,
    /// same-origin — send the full URL only to same-origin requests.
    rpSameOrigin
  );

  THorseSecurityHeadersConfig = record
    /// Emit X-Content-Type-Options: nosniff.  Default: True.
    XContentTypeOptions:   Boolean;
    /// X-Frame-Options value.  Default: fodeny.
    XFrameOptions:         TFrameOption;
    /// Referrer-Policy value.  Default: rpStrictOriginWhenCrossOrigin.
    ReferrerPolicy:        TReferrerPolicy;
    /// Emit Cache-Control: no-store.  Default: True.
    CacheControlNoStore:   Boolean;
    /// HSTS max-age in seconds.  0 = disabled (do not emit HSTS).  Default: 0.
    HSTSMaxAge:            Integer;
    /// Append '; includeSubDomains' to the HSTS header.  Default: False.
    HSTSIncludeSubDomains: Boolean;
    /// Replace Server header value with 'unknown'.  Default: True.
    SuppressServerHeader:  Boolean;

    /// Safe defaults suitable for most applications.
    /// HSTS is disabled — enable explicitly once HTTPS is confirmed.
    class function Default: THorseSecurityHeadersConfig; static;

    /// Strict profile: same as Default plus HSTS with a 1-year max-age and
    /// includeSubDomains.  Use only on fully HTTPS endpoints.
    class function Strict: THorseSecurityHeadersConfig; static;
  end;

  THorseSecurityHeadersMiddleware = class
  private
    FConfig: THorseSecurityHeadersConfig;
  public
    constructor Create(const AConfig: THorseSecurityHeadersConfig);
    procedure Handle(AReq: THorseRequest; ARes: THorseResponse; ANext: TNextProc);
  end;

  THorseSecurityHeaders = class
  public
    class function New: THorseCallback; overload;
    class function New(const AConfig: THorseSecurityHeadersConfig): THorseCallback; overload;
  end;

implementation

uses
{$IF DEFINED(FPC)}
  SysUtils;
{$ELSE}
  System.SysUtils;
{$ENDIF}
  //Horse.Proc;

{ Helpers }

function FrameOptionStr(AOption: TFrameOption): string;
begin
  case AOption of
    fodeny:       Result := 'DENY';
    fosameorigin: Result := 'SAMEORIGIN';
  else
    Result := 'DENY';
  end;
end;

function ReferrerPolicyStr(APolicy: TReferrerPolicy): string;
begin
  case APolicy of
    rpStrictOriginWhenCrossOrigin: Result := 'strict-origin-when-cross-origin';
    rpNoReferrer:                  Result := 'no-referrer';
    rpSameOrigin:                  Result := 'same-origin';
  else
    Result := 'strict-origin-when-cross-origin';
  end;
end;

{ THorseSecurityHeadersConfig }

class function THorseSecurityHeadersConfig.Default: THorseSecurityHeadersConfig;
begin
  Result.XContentTypeOptions   := True;
  Result.XFrameOptions         := fodeny;
  Result.ReferrerPolicy        := rpStrictOriginWhenCrossOrigin;
  Result.CacheControlNoStore   := True;
  Result.HSTSMaxAge            := 0;      // disabled
  Result.HSTSIncludeSubDomains := False;
  Result.SuppressServerHeader  := True;
end;

class function THorseSecurityHeadersConfig.Strict: THorseSecurityHeadersConfig;
begin
  Result                       := Default;
  Result.HSTSMaxAge            := 31536000; // 1 year
  Result.HSTSIncludeSubDomains := True;
end;

{ THorseSecurityHeaders }

class function THorseSecurityHeaders.New: THorseCallback;
var
  LMiddleware: THorseSecurityHeadersMiddleware;
begin
  LMiddleware := THorseSecurityHeadersMiddleware.Create(THorseSecurityHeadersConfig.Default);
  Result := LMiddleware.Handle;
end;

class function THorseSecurityHeaders.New(const AConfig: THorseSecurityHeadersConfig): THorseCallback;
var
  LMiddleware: THorseSecurityHeadersMiddleware;
begin
  LMiddleware := THorseSecurityHeadersMiddleware.Create(AConfig);
  Result := LMiddleware.Handle;
end;

(*
class function THorseSecurityHeaders.New(const AConfig: THorseSecurityHeadersConfig): THorseCallback;
var
  // Capture a copy of the config record.  AConfig is a const param (passed by
  // reference on large records); capturing it directly would capture a
  // pointer to a stack frame that is gone after New() returns.
  LConfig: THorseSecurityHeadersConfig;
begin
  LConfig := AConfig;

  Result :=
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TNextProc)
    var
      LHsts: string;
    begin
      // Run the downstream middleware and route handler first.
      // Headers are added to the completed response below.
      Next;

      if LConfig.XContentTypeOptions then
        Res.AddHeader('X-Content-Type-Options', 'nosniff');

      Res.AddHeader('X-Frame-Options', FrameOptionStr(LConfig.XFrameOptions));

      Res.AddHeader('Referrer-Policy', ReferrerPolicyStr(LConfig.ReferrerPolicy));

      if LConfig.CacheControlNoStore then
        Res.AddHeader('Cache-Control', 'no-store');

      if LConfig.HSTSMaxAge > 0 then
      begin
        LHsts := 'max-age=' + IntToStr(LConfig.HSTSMaxAge);
        if LConfig.HSTSIncludeSubDomains then
          LHsts := LHsts + '; includeSubDomains';
        Res.AddHeader('Strict-Transport-Security', LHsts);
      end;

      if LConfig.SuppressServerHeader then
        Res.AddHeader('Server', 'unknown');
    end;
end;
*)

{ THorseSecurityHeadersMiddleware }

constructor THorseSecurityHeadersMiddleware.Create(const AConfig: THorseSecurityHeadersConfig);
begin
  FConfig := AConfig;
end;

procedure THorseSecurityHeadersMiddleware.Handle(AReq: THorseRequest; ARes: THorseResponse; ANext: TNextProc);
var
  LHsts: string;
begin

  if FConfig.XContentTypeOptions then
    ARes.AddHeader('X-Content-Type-Options', 'nosniff');

  ARes.AddHeader('X-Frame-Options', FrameOptionStr(FConfig.XFrameOptions));

  ARes.AddHeader('Referrer-Policy', ReferrerPolicyStr(FConfig.ReferrerPolicy));

  if FConfig.CacheControlNoStore then
    ARes.AddHeader('Cache-Control', 'no-store');

  if FConfig.HSTSMaxAge > 0 then
  begin
    LHsts := 'max-age=' + IntToStr(FConfig.HSTSMaxAge);
    if FConfig.HSTSIncludeSubDomains then
      LHsts := LHsts + '; includeSubDomains';
    ARes.AddHeader('Strict-Transport-Security', LHsts);
  end;

  if FConfig.SuppressServerHeader then
    ARes.AddHeader('Server', 'unknown');

  ANext();
end;

end.

