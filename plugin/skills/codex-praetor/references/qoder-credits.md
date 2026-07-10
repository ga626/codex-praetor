# Qoder Credits Notes

Use these notes for routing. Re-check official docs if pricing or products look stale.

- Qoder CN off-peak window is Beijing time 22:00-08:00, including weekends and holidays.
- Qwen3.7-Max: base 0.5x, daytime regular discount 0.25x, off-peak 0.1x.
- Qwen3.7-Plus: daytime 0.1x, off-peak 0.04x.
- The off-peak discount applies automatically for eligible subscriptions and covered Qoder CN products, including Desktop, JetBrains plugin, CLI, QoderWork, Mobile, and Cloud Agents.
- Discounted usage still consumes monthly quota/credits; the discount is not extra free credits.
- Plan Credits are valid only in the current subscription cycle and reset to zero at cycle end.
- Add-on or promotional Credits have their own expiration.
- Qoder consumes credits with the earliest expiration first; for the same expiration, Plan Credits are used before Add-on Credits.
- QoderWork CN daily check-in gives 100 Credits per day. Each daily package is valid for 30 days and resets at 00:00 UTC+8. Missed days cannot be recovered.
- A user's current balance type cannot be proven from public repo files. Confirm in the Qoder Usage page or after CLI login with `/usage`.
- Local validation showed that Qoder CLI model IDs are display names such as `Qwen3.7-Max`, `Qwen3.7-Plus`, `Qwen3.6-Flash`, `DeepSeek-V4-Pro`, `DeepSeek-V4-Flash`, `GLM-5.2`, `Kimi-K2.7-Code`, `MiniMax-M2.7`, plus `Auto`.
- Account-specific `/usage` output, screenshots, local renderer logs, and cache files are private evidence. Keep them out of the public repository.
- Official referral terms say each successful referral grants 200 Credits and each referrer can receive at most 200 successful-referral rewards, for a cumulative cap of 40,000 Credits.
- Current usable balance must be checked per user and is subject to expiration.
- Qoder CLI probes indicated that worker runs should use a git worktree. Non-git folders may fail before a model response.
- CodeBuddy validation on 2026-07-07/2026-07-08: the selected HY3 route used model id `hy3` and returned successful smoke output. Tencent Cloud TokenHub CodeBuddy Code official setup also uses `hy3` in `models.json` and `availableModels`. Do not replace it with `auto`; `auto` is blocked because it gives provider-side model choice back to CodeBuddy. Do not default to `hy3-preview-agent`; bundled product configs list it as a preview/credit-multiplied route. Account-specific billing observations are private evidence and are not included in the public release. For non-interactive readonly file checks on Windows, the reliable combination was `-y --tools Read,Glob`; `--permission-mode plan` either exceeded turns or returned an incorrect file existence result, and `--permission-mode bypassPermissions` returned an incorrect result in the same probe.

Primary sources found during research:

- https://help.aliyun.com/zh/lingma/product-overview/qwen-3-7-series-model-staggering-discount
- https://help.aliyun.com/zh/lingma/product-overview/credits
- https://help.aliyun.com/zh/lingma/product-overview/billing-description
- https://help.aliyun.com/en/lingma/product-overview/credits
- https://help.aliyun.com/en/lingma/product-overview/daily-check-in-100-credits-reward-program-terms
- QoderWork local cache files are private runtime data and should not be read or published unless the user explicitly asks for diagnostics.

