# Integration Test Projects — horse-security-headers

Two console programs that together form the integration test suite.

| Program | Role |
|---|---|
| `HorseSHTestServer.dpr` | HTTP server on `127.0.0.1:9300` — start first |
| `HorseSHTestClient.dpr` | Test runner — exits with `0` (all pass) or `N` (N failures) |

---

## Creating the .dproj files

The `.dpr` sources are committed. The `.dproj` project files must be created in the Delphi IDE. Create two separate console application projects with the settings below.

### HorseSHTestServer.dproj

**Project Options → Delphi Compiler → Conditional defines:**
```
HORSE_CROSSSOCKET
```

**Project Options → Delphi Compiler → Search path** (relative to this file's directory):
```
..\..\modules\horse\src
..\..\modules\Delphi-Cross-Socket\Net
..\..\modules\Delphi-Cross-Socket\Utils
..\..\modules\Delphi-Cross-Socket\OpenSSL
..\..\modules\horse-provider-crosssocket\src
..\..\src
```

**Project Options → Delphi Compiler → Output directory:**
```
$(Platform)\$(Config)
```

**App type:** Console application (`{$APPTYPE CONSOLE}` is already in the .dpr)

---

### HorseSHTestClient.dproj

**Project Options → Delphi Compiler → Conditional defines:** *(none required)*

**Project Options → Delphi Compiler → Search path:**
```
..\..\modules\Delphi-Cross-Socket\Net
..\..\modules\Delphi-Cross-Socket\Utils
..\..\modules\Delphi-Cross-Socket\OpenSSL
```

**Project Options → Delphi Compiler → Output directory:**
```
$(Platform)\$(Config)
```

**App type:** Console application

---

## Running manually

```bat
cd horse-security-headers

REM 1. Install dependencies (once)
boss install

REM 2. Build both projects in the Delphi IDE (Win64 Release)

REM 3. Start the server (leave this window open)
samples\tests\Win64\Release\HorseSHTestServer.exe

REM 4. In a second window: run the client
samples\tests\Win64\Release\HorseSHTestClient.exe
REM Exit code 0 = all tests passed; N = N failures
echo Exit code: %ERRORLEVEL%
```

---

## Server route structure

The server uses **per-route middleware** (not global `THorse.Use`) so that different configs can be tested in isolation without header duplication.  Each route captures its own `THorseCallback` closure at startup:

| Route | Middleware config | Purpose |
|---|---|---|
| `GET /default` | `THorseSecurityHeaders.New` (Default) | Tests all default headers |
| `GET /strict` | `THorseSecurityHeaders.New(Strict)` | Tests HSTS with includeSubDomains |
| `GET /sameorigin` | Custom config, `XFrameOptions = fosameorigin` | Tests SAMEORIGIN frame option |
| `GET /plain` | None | Negative baseline — no security headers |

---

## Test coverage

| # | Route | What is tested | Expected header value |
|---|---|---|---|
| 01 | `/default` | `X-Content-Type-Options` | `nosniff` |
| 02 | `/default` | `X-Frame-Options` | `DENY` |
| 03 | `/default` | `Referrer-Policy` | `strict-origin-when-cross-origin` |
| 04 | `/default` | `Cache-Control` | `no-store` |
| 05 | `/default` | `Strict-Transport-Security` **absent** | `""` (HSTSMaxAge=0) |
| 06 | `/default` | `Server` suppressed | `unknown` |
| 07 | `/default` | Handler called via `Next` | status 200, body `"ok"` |
| 08 | `/strict` | `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` |
| 09 | `/strict` | `X-Content-Type-Options` still present | `nosniff` |
| 10 | `/sameorigin` | `X-Frame-Options` | `SAMEORIGIN` |
| 11 | `/plain` | `X-Content-Type-Options` **absent** | `""` |
| 12 | `/plain` | `X-Frame-Options` **absent** | `""` |

### Notes on design

**`Next` is called first:** `THorseSecurityHeaders` runs `Next` before adding headers. This means the route handler always executes first and sets the response status/body; the middleware appends headers to the completed response. Test 07 verifies this contract (status 200 + body "ok") is preserved.

**Per-route middleware pattern:** The server wraps each `THorseCallback` in an anonymous lambda to pass it as a Horse route-level middleware:

```pascal
LDefaultMW := THorseSecurityHeaders.New;

THorse.Get('/default',
  procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
  begin
    LDefaultMW(Req, Res, Next);   // applies security headers then calls Next
  end,
  procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
  begin
    Res.Send('ok');
  end);
```

This avoids global `THorse.Use` so each route is independently testable without header duplication.

**CrossSocket transport already injects default security headers** in `TResponseBridge.Flush`. When both this middleware and CrossSocket are active, some headers may appear as duplicates. This is harmless (browsers take the first or last occurrence of most security headers), but for clean test results the client checks for presence/value rather than exact single occurrence.
