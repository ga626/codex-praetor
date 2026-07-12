# CodeBuddy provider setup

Codex Praetor can dispatch CodeBuddy only when the user has installed and signed in to Tencent CodeBuddy or WorkBuddy CLI on the same Windows machine.

Codex Praetor does not install CodeBuddy, sign in for the user, read provider account databases, or promise that a model is free. It only calls the configured CLI path with explicit model and tool allowlists.

普通用户只需要记住一句：Codex Praetor 可以检查本机有没有 CodeBuddy 命令，但不能替你选择中国站、国际站、企业域或 iOA，也不能替你完成浏览器登录。

## Install

Install CodeBuddy or WorkBuddy through Tencent's official channel for your edition.

CodeBuddy currently has two public installation routes:

- Package-manager route. It requires Node.js 18.20 or later.
- Native binary route. It is currently marked Beta by CodeBuddy and supports Windows x86_64.

Official installation guide:

https://www.codebuddy.ai/docs/zh/cli/installation

Public npm package reference:

https://www.npmjs.com/package/@tencent-ai/codebuddy-code

Some editions are launched through a Node entrypoint, while the native binary route can expose a standalone command. Codex Praetor therefore keeps both `nodePath` and `cliPath` in the config.

Verify installation in the same shell where Codex Praetor will run:

```powershell
node --version
codebuddy --version
```

If your edition exposes a different command or a JavaScript entrypoint, set that exact path in the local config.

## Sign in

Complete the provider's normal login flow outside Codex Praetor. In enterprise or China-specific editions, follow the provider's current instructions for endpoint, domain, token, or desktop login state.

Do not place provider tokens, cookies, desktop databases, account screenshots, or usage pages into this repository.

首次启动 CodeBuddy 时，官方流程可能要求用户选择中国站、国际站、企业域或 iOA，并通过浏览器完成认证。Codex Praetor 的安装向导只能把你带到这一步，不能代替你选择或登录。

## Configure Codex Praetor

Copy the public template to an ignored local config:

```powershell
Copy-Item .\config\codex-praetor-tiers.example.json .\config\codex-praetor.local.json
```

Then edit only your local config:

```json
{
  "providers": {
    "codebuddy": {
      "nodePath": "node",
      "cliPath": "C:\\Path\\To\\codebuddy"
    }
  }
}
```

Use a real command name if it is on `PATH`, or an absolute path if the CLI is installed inside a desktop product.

## Verify

Run doctor:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify\doctor-codex-praetor.ps1 -RequireHead -PublicRelease
```

Expected doctor states:

- `provider:codebuddy:node` ready: Node can run the CodeBuddy entrypoint.
- `provider:codebuddy:cli` ready: the CLI path exists or resolves from `PATH`.
- `provider:codebuddy:version` ready or info: version probing succeeded, or doctor could not prove compatibility.
- `provider:codebuddy:auth` info: doctor intentionally does not inspect login state.

Before real dispatch, run a dry-run or readonly canary. CodeBuddy tool permission behavior can vary by edition, so treat the first readonly canary as the real capability proof.

## Cost and model boundary

Codex Praetor blocks provider `auto` by default. Current default-routable CodeBuddy models are configured in `codex-praetor-tiers.json`, including `hy3`, `deepseek-v4-flash`, and `deepseek-v4-pro`.

Whether a model is free, cheap, or paid depends on the user's provider account and current product policy. Confirm this in CodeBuddy before large runs.

## If CodeBuddy is missing

Nothing is broken. CodeBuddy real dispatch is disabled, but Codex Praetor can still use local planning, route-intent, status, MCP visibility tools, and any other configured provider.
