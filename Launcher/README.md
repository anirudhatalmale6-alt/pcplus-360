# PC Plus 360 Launcher

WPF + WebView2 native wrapper for the PC Plus 360 HTML dashboard.

## Prerequisites

- Windows 10/11
- .NET 8 SDK (https://dotnet.microsoft.com/download/dotnet/8.0)
- Microsoft Edge WebView2 Runtime (usually pre-installed on Windows 10/11)

## Build

Double-click `build.bat` or run:

```
dotnet publish PCPlus360Launcher\PCPlus360Launcher.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o dist
```

## File Layout

The published exe expects this relative structure:

```
SomeFolder/
├── PCPlus360-Dashboard.html     <- the HTML dashboard
├── Scripts/                     <- PowerShell scripts
│   ├── PCPlus-QuickRiskScore.ps1
│   └── ...
└── Launcher/
    └── dist/
        └── PCPlus360Launcher.exe
```

The launcher looks for `../PCPlus360-Dashboard.html` relative to its own location.

## JavaScript Bridge

The HTML dashboard communicates with the C# backend via WebView2 messaging:

### Send to C# (from JavaScript)

```javascript
window.chrome.webview.postMessage(JSON.stringify({
    action: "runScript",
    script: "PCPlus-QuickRiskScore.ps1",
    requestId: "optional-tracking-id",
    parameters: { "Verbose": "true" }
}));
```

### Supported Actions

| Action | Payload | Description |
|--------|---------|-------------|
| `runScript` | `{script, parameters?, requestId?}` | Execute a PowerShell script |
| `getSystemInfo` | `{}` | Get system information |
| `createRestorePoint` | `{description?}` | Create a system restore point |
| `getRestorePoints` | `{}` | List restore points |
| `executeRepair` | `{name, script?, dryRun?, parameters?}` | Run a repair action |
| `rollback` | `{}` | Rollback last repair |
| `minimize` | `{}` | Minimize window |
| `maximize` | `{}` | Toggle maximize |
| `close` | `{}` | Close application |

### Receive from C# (in JavaScript)

```javascript
window.addEventListener('message', function(e) {
    var msg = e.data;  // {type: "scriptResult", data: {...}}
    switch (msg.type) {
        case 'scriptResult':
            console.log(msg.data.success, msg.data.data);
            break;
        case 'systemInfo':
            console.log(msg.data);
            break;
        case 'error':
            console.error(msg.data.message);
            break;
    }
});
```

## Icon

Replace `Assets/icon.ico.txt` with an actual `icon.ico` file and uncomment
the `ApplicationIcon` line in the `.csproj`.
