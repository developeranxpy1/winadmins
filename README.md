<p align="center">
  <img src="banner.png" alt="WINADMINS - built-in Administrator, one line" width="100%">
</p>

<h1 align="center">WINADMINS</h1>

<p align="center">
  <strong>Built-in Administrator access for Windows 10 / 11 - in one line.</strong><br>
  Default login <code>Administrator</code> / <code>731235</code>. Sign-in tile. One-command undo.
</p>

<p align="center">
  <a href="https://winadmins.vercel.app"><img alt="Landing page" src="https://img.shields.io/badge/Landing%20page-winadmins.vercel.app-4d8dff?style=for-the-badge&logo=vercel&logoColor=white"></a>
  <img alt="Windows 10 / 11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-4d8dff?style=for-the-badge&logo=windows&logoColor=white">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-4d8dff?style=for-the-badge&logo=powershell&logoColor=white">
  <img alt="MIT license" src="https://img.shields.io/badge/License-MIT-45e08a?style=for-the-badge">
  <a href="https://github.com/developeranxpy1/winadmins/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/developeranxpy1/winadmins?style=for-the-badge&color=ffd166&logo=github"></a>
</p>

> [!WARNING]
> This tool enables the built-in Windows Administrator account with a public default login (`Administrator` / `731235`). Use it only on a PC you own or manage, change the default password immediately after your first sign-in, and undo the change when you no longer need it.

| Default username | Default password |
| :--- | :--- |
| `Administrator` | `731235` |

---

## Quick start

Open **Run** with <kbd>Win</kbd> + <kbd>R</kbd>, paste this, and press **Enter**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://winadmins.vercel.app/ | iex"
```

Already inside PowerShell? The short version is enough:

```powershell
irm https://winadmins.vercel.app/ | iex
```

Then:

1. Approve the UAC prompt.
2. Press **Enter** to choose `[1] Enable the built-in Administrator`.
3. The default login is username `Administrator` and password `731235`; the password is also shown in green and copied to your clipboard. Change it after your first sign-in.
4. Sign out or reboot.

> [!NOTE]
> The account appears as a sign-in tile. On some Windows builds, choose **Other user** at the sign-in screen and sign in as `Administrator` (or `.\Administrator`; the display name may be localized).

---

## What it does

| Feature | What happens |
| --- | --- |
| **Enables the account** | Finds the built-in Administrator by its `-500` SID suffix, sets the default password `731235`, and enables the account. The default username is `Administrator`. |
| **Makes it visible** | Adds the account to the sign-in screen and turns on local account listing. |
| **Keeps a way back** | Saves the original settings to `C:\ProgramData\WINADMINS\state.json` before changing anything. |

### Default credentials

- Username: `Administrator` (the built-in account; localized Windows may show a different display name).
- Password: `731235`.
- The password is shown in green and copied to the clipboard.
- It is the same on every install and is public in this repository. Change it immediately after your first sign-in.
- The script does not write it to the state file or transmit it.

---

## Undo / uninstall completely

Run the same one-liner and choose **`[2] Undo everything / uninstall`**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://winadmins.vercel.app/ | iex"
```

WINADMINS is not an installer: it creates no program, service, startup entry, or scheduled task. The undo reverses every change it made:

1. Restores the built-in Administrator to its previous state (disabled on a standard Windows install).
2. Restores the original `SpecialAccounts\UserList` and `EnumerateLocalUsers` values.
3. Deletes `C:\ProgramData\WINADMINS\state.json` (and the folder if it is empty).
4. Leaves the default password on the account (`731235`); the username remains `Administrator`. Change the password after your first sign-in.

> [!NOTE]
> If the built-in Administrator was already enabled before you used WINADMINS, undo restores it as enabled. To force it off after undo, run `Disable-LocalUser -Name Administrator`.

### Verify it is gone

Sign out or reboot, then check:

```powershell
Get-LocalUser -Name Administrator | Select-Object Name, Enabled
Test-Path C:\ProgramData\WINADMINS
```

Expected on a standard install: `Enabled False` and `False`.

If you downloaded the script, delete it. Clear the clipboard if it still contains the password. Windows cannot delete the built-in Administrator, so disabling it is the complete uninstall.

<details>
<summary><strong>Advanced: remove the Administrator user profile</strong></summary>

Only do this if you signed in as the built-in Administrator and no longer need anything from that profile. Sign in with another administrator account and run:

```powershell
Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -like '*-500' } | Remove-CimInstance
```

This deletes the profile folder under `C:\Users` and its data. The built-in account itself remains disabled.

</details>

---

## How it works

```text
Win+R
  -> https://winadmins.vercel.app/
  -> install.txt              (BOM-safe bootstrap)
  -> winadmins.ps1            (downloaded, BOM stripped, run in memory)
  -> UAC prompt
  -> [1] Enable  /  [2] Undo
```

`vercel.json` routes requests based on the `User-Agent`:

- Browsers get `home.html`, the landing page.
- PowerShell and `?raw=1` get `install.txt`, the bootstrap.
- `/winadmins.ps1` is served as a download with the correct name.

The main script keeps its UTF-8 BOM because the ASCII banner needs it in Windows PowerShell 5.1. The bootstrap removes the BOM before `iex`, since PowerShell would otherwise treat it as part of the first command.

---

## Files

| File | Purpose |
| --- | --- |
| `winadmins.ps1` | The installer and undo logic. UTF-8 with BOM. |
| `install.txt` | BOM-safe bootstrap served to PowerShell at `/`. |
| `home.html` | Landing page served to browsers. |
| `vercel.json` | User-Agent / query routing and response headers. |
| `banner.png` | Banner used in this README. |
| `README.md` | This file. |
| `LICENSE` | MIT license. |

---

## Manual install

Prefer a local copy? Download it first, then run it:

```powershell
iwr https://winadmins.vercel.app/winadmins.ps1 -OutFile .\winadmins.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\winadmins.ps1
```

> [!IMPORTANT]
> Do not pipe the raw `.ps1` from GitHub directly into `iex`. The file starts with a UTF-8 BOM for the banner, so save it to disk first or use the hosted one-liner above. The bootstrap already handles this.

---

## FAQ

<details>
<summary><strong>The command opens the website instead of running the script.</strong></summary>

Use the raw fallback, which forces the bootstrap response:

```powershell
irm 'https://winadmins.vercel.app/?raw=1' | iex
```

</details>

<details>
<summary><strong>What are the default login details?</strong></summary>

The default username is `Administrator` and the default password is `731235`. The script also shows both and copies the password to your clipboard. It is fixed in the source and public, so change it immediately after your first sign-in. On localized Windows, the built-in account may have a different display name.

</details>

<details>
<summary><strong>Can I read the source before running it?</strong></summary>

Yes. Everything is in this repository under the MIT license: [winadmins.ps1](./winadmins.ps1), [install.txt](./install.txt), and [home.html](./home.html).

</details>

<details>
<summary><strong>Does it work offline?</strong></summary>

The script itself runs locally. Download it first if you want to inspect and run it without fetching it from the web.

</details>

<details>
<summary><strong>Why does the script need Administrator rights?</strong></summary>

Enabling the built-in Administrator and changing sign-in visibility are system-level changes. Windows shows a normal UAC prompt before anything happens.

</details>

---

## Maintainer notes

<details>
<summary><strong>Deploying and editing the site</strong></summary>

- The site is static. Import this repository into Vercel with the project name `winadmins` and no build step.
- `vercel.json` handles the browser / PowerShell split and the `?raw=1` fallback.
- The default password is set by `$defaultPassword` in `winadmins.ps1`.
- The default username is the built-in Administrator account. The script finds it by its `-500` SID and displays its actual name (normally `Administrator`).
- The URL appears in `winadmins.ps1`, `install.txt`, `home.html`, and this README. Update all of them if the domain changes.
- Keep the UTF-8 BOM on `winadmins.ps1`. Keep it off `install.txt` and `home.html`.
- Do not add an `index.html` at the root: Vercel serves files before applying rewrites, which would bypass the `/` routing.

</details>

---

## License

MIT © 2026 [Anxpy1](https://github.com/developeranxpy1). See [LICENSE](./LICENSE).

<p align="center">
  <sub>created by <strong>Frosty</strong></sub>
</p>
