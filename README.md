# horse-security-headers

> Response security headers middleware for the [Horse](https://github.com/HashLoad/horse) web framework.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Delphi](https://img.shields.io/badge/Delphi-10.4%2B-red.svg)](https://www.embarcadero.com/products/delphi)
[![FPC](https://img.shields.io/badge/FPC-3.2%2B-blue.svg)](https://www.freepascal.org/)
[![Horse](https://img.shields.io/badge/Horse-3.x-blue.svg)](https://github.com/HashLoad/horse)
[![Boss](https://img.shields.io/badge/Boss-compatible-green.svg)](https://github.com/HashLoad/boss)

---

## What it does

Adds hardening headers to every HTTP response.  The middleware calls `Next` first (letting your route handler run) and then appends the configured headers to the completed response.

| Header | Default value |
|---|---|
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Cache-Control` | `no-store` |
| `Strict-Transport-Security` | *(disabled — opt-in)* |
| `Server` | `unknown` *(replaces the default server banner)* |

---

## Installation

```bash
boss install github.com/freitasjca/horse-security-headers
```

Or add to your project's `boss.json`:

```json
{
  "dependencies": {
    "github.com/freitasjca/horse-security-headers": ">=1.0.0"
  }
}
```

---

## Usage

### Default configuration

```pascal
uses
  Horse,
  Horse.Middleware.SecurityHeaders;

begin
  THorse.Use(THorseSecurityHeaders.New);   // applies to all responses

  THorse.Get('/ping',
    procedure(Req: THorseRequest; Res: THorseResponse)
    begin
      Res.Send('pong');
    end);

  THorse.Listen(9000);
end.
```

### Strict profile (HTTPS endpoints)

```pascal
THorse.Use(THorseSecurityHeaders.New(
  THorseSecurityHeadersConfig.Strict));   // adds 1-year HSTS + includeSubDomains
```

### Custom configuration

```pascal
uses
  Horse,
  Horse.Middleware.SecurityHeaders;

var
  LConfig: THorseSecurityHeadersConfig;
begin
  LConfig                    := THorseSecurityHeadersConfig.Default;
  LConfig.XFrameOptions      := fosameorigin;  // allow embedding by same origin
  LConfig.CacheControlNoStore := False;         // let browsers cache responses
  LConfig.HSTSMaxAge         := 86400;          // HSTS: 1 day
  LConfig.HSTSIncludeSubDomains := True;

  THorse.Use(THorseSecurityHeaders.New(LConfig));

  THorse.Listen(9000);
end.
```

---

## Configuration reference

```pascal
type
  TFrameOption = (
    fodeny,        // X-Frame-Options: DENY
    fosameorigin   // X-Frame-Options: SAMEORIGIN
  );

  TReferrerPolicy = (
    rpStrictOriginWhenCrossOrigin,  // strict-origin-when-cross-origin
    rpNoReferrer,                   // no-referrer
    rpSameOrigin                    // same-origin
  );

  THorseSecurityHeadersConfig = record
    XContentTypeOptions:   Boolean;
    XFrameOptions:         TFrameOption;
    ReferrerPolicy:        TReferrerPolicy;
    CacheControlNoStore:   Boolean;
    HSTSMaxAge:            Integer;
    HSTSIncludeSubDomains: Boolean;
    SuppressServerHeader:  Boolean;
    class function Default: THorseSecurityHeadersConfig; static;
    class function Strict:  THorseSecurityHeadersConfig; static;
  end;
```

| Field | Default | Strict | Description |
|---|:---:|:---:|---|
| `XContentTypeOptions` | `True` | `True` | Emits `X-Content-Type-Options: nosniff`.  Prevents browsers from MIME-sniffing a response away from the declared content type. |
| `XFrameOptions` | `fodeny` | `fodeny` | Controls `X-Frame-Options`.  `fodeny` prevents any framing; `fosameorigin` allows framing by the same origin. |
| `ReferrerPolicy` | `rpStrictOriginWhenCrossOrigin` | same | Controls the `Referrer-Policy` header.  See the table below. |
| `CacheControlNoStore` | `True` | `True` | Emits `Cache-Control: no-store`.  Prevents sensitive responses from being stored in caches. |
| `HSTSMaxAge` | `0` *(off)* | `31536000` | `max-age` in seconds for `Strict-Transport-Security`.  Set to `0` to suppress the header.  **Only enable on HTTPS endpoints.** |
| `HSTSIncludeSubDomains` | `False` | `True` | Appends `; includeSubDomains` to the HSTS header. |
| `SuppressServerHeader` | `True` | `True` | Replaces the `Server` response header with `unknown` to reduce information disclosure. |

### `ReferrerPolicy` values

| Enum | Header value | Effect |
|---|---|---|
| `rpStrictOriginWhenCrossOrigin` | `strict-origin-when-cross-origin` | Sends full URL to same-origin requests; only origin to cross-origin HTTPS; nothing to HTTP. |
| `rpNoReferrer` | `no-referrer` | Never sends a `Referer` header. |
| `rpSameOrigin` | `same-origin` | Sends full URL only to same-origin requests. |

---

## Registration order

This middleware must be registered **after** any middleware that sets response headers you want to preserve, because it runs after `Next` and adds to (not replaces) the existing headers.  It does not need to be first.

```pascal
THorse.Use(THorseRequestGuard.New);      // first — rejects invalid requests
THorse.Use(THorseSecurityHeaders.New);   // anywhere — wraps every response
THorse.Get('/api/data', ...);
```

---

## Provider compatibility

| Provider | Source of security headers |
|---|---|
| **Horse + Indy** | **This middleware is the only source.** Register it to harden all responses. |
| **Horse + CrossSocket** | `TResponseBridge.Flush` in the CrossSocket provider also injects these headers at the transport layer.  Using both is safe — the HTTP specification permits duplicate headers for most of these and browsers apply the most restrictive value.  Use this middleware on CrossSocket for defence in depth or to centralise header policy in application code. |

---

## License

MIT — see [LICENSE](LICENSE).
