import { existsSync, readFileSync } from "node:fs";
import { getRuntimeDataPath } from "./paths.js";

export type ModelRoutingEntry = {
  provider: string;
  distribution: string;
  connection_mode: string;
  tier: string;
  model: string;
  status: "default" | "explicit" | "candidate" | "blocked" | "legacy_unsupported";
  selection_reason: string;
  price: Record<string, string>;
};

type Catalog = {
  schema: string;
  catalog_date: string;
  price_snapshot_valid_until: string;
  policy: Record<string, unknown>;
  models: ModelRoutingEntry[];
};

function readCatalog(): Catalog {
  const catalogPath = getRuntimeDataPath("model-routing-catalog.json");
  if (!existsSync(catalogPath)) throw new Error(`Model routing catalog is missing: ${catalogPath}`);
  const value = JSON.parse(readFileSync(catalogPath, "utf8").replace(/^\uFEFF/, "")) as Catalog;
  if (value.schema !== "codex-praetor-model-routing-catalog/v1" || !Array.isArray(value.models)) {
    throw new Error(`Model routing catalog has an unsupported schema: ${catalogPath}`);
  }
  return value;
}

function isSnapshotFresh(catalog: Catalog): boolean {
  return Date.now() <= Date.parse(`${catalog.price_snapshot_valid_until}T23:59:59.999Z`);
}

export function modelSelection(input: { provider: string; tier?: string; model?: string; connection_mode?: string }) {
  const catalog = readCatalog();
  const entry = catalog.models.find((candidate) =>
    candidate.provider === input.provider
    && (input.tier ? candidate.tier === input.tier : true)
    && (input.model ? candidate.model.toLowerCase() === input.model.toLowerCase() : true)
    && (input.connection_mode ? candidate.connection_mode === input.connection_mode : true)
  ) ?? catalog.models.find((candidate) => candidate.provider === input.provider && candidate.model.toLowerCase() === String(input.model ?? "").toLowerCase());
  if (!entry) {
    return { catalog_schema: catalog.schema, catalog_date: catalog.catalog_date, price_state: "unknown", selection_reason: "该 provider/model 未在受跟踪模型目录中登记。", status: "candidate" };
  }
  const snapshotFresh = isSnapshotFresh(catalog);
  const declaredState = String(entry.price.state ?? "unknown");
  const priceState = snapshotFresh ? declaredState : declaredState === "confirmed" ? "snapshot_expired" : declaredState;
  return {
    catalog_schema: catalog.schema,
    catalog_date: catalog.catalog_date,
    price_snapshot_at: entry.price.source_date ?? catalog.catalog_date,
    price_snapshot_valid_until: catalog.price_snapshot_valid_until,
    price_state: priceState,
    price: entry.price,
    selection_reason: entry.selection_reason,
    status: entry.status,
    provider: entry.provider,
    distribution: entry.distribution,
    connection_mode: entry.connection_mode,
    tier: entry.tier,
    model: entry.model
  };
}

export function modelRoutingCatalogTool() {
  const catalog = readCatalog();
  return {
    schema: catalog.schema,
    catalog_date: catalog.catalog_date,
    price_snapshot_valid_until: catalog.price_snapshot_valid_until,
    price_snapshot_fresh: isSnapshotFresh(catalog),
    policy: catalog.policy,
    models: catalog.models,
    display: {
      阶段: "模型路由目录",
      状态: isSnapshotFresh(catalog) ? "价格快照在有效期内" : "价格快照待确认，不会自动改选模型",
      下一步: "仅 default/explicit 且固定模型可进入计划；candidate 需单独验证，Auto 与历史 MiMo 不得路由。"
    }
  };
}
