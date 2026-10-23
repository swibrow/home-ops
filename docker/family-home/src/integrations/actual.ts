import { mkdir } from "node:fs/promises";
import * as api from "@actual-app/api";
import { cached } from "../lib/cache";
import { env } from "../lib/config";
import { isoDay } from "../lib/time";

type Category = { name: string; budgeted: number; spent: number; balance: number };

const serverURL = env("ACTUAL_URL");
const sessionToken = env("ACTUAL_SESSION_TOKEN");
const syncId = env("ACTUAL_SYNC_ID");
const password = env("ACTUAL_BUDGET_PASSWORD");
const dataDir = env("ACTUAL_DATA_DIR") ?? "/tmp/actual";

let opened: Promise<void> | undefined;

async function open() {
  await mkdir(dataDir, { recursive: true });
  await api.init({ dataDir, serverURL: serverURL!, sessionToken: sessionToken! });
  await api.downloadBudget(syncId!, password ? { password } : undefined);
}

export const loadBudget = () =>
  serverURL && sessionToken && syncId
    ? cached("actual", 600, async () => {
        opened ??= open().catch((error) => {
          opened = undefined;
          throw error;
        });
        await opened;
        await api.sync();
        const month = await api.getBudgetMonth(isoDay().slice(0, 7));
        const categories = month.categoryGroups
          .filter((g) => !g.is_income && !g.hidden)
          .flatMap((g) => (g.categories ?? []) as unknown as (Category & { hidden?: boolean })[])
          .filter((c) => !c.hidden)
          .map((c) => ({ name: c.name, budgeted: c.budgeted, spent: -c.spent, balance: c.balance }));
        return {
          spent: -month.totalSpent,
          budgeted: month.totalBudgeted,
          income: month.totalIncome,
          top: categories.filter((c) => c.spent > 0).sort((a, b) => b.spent - a.spent).slice(0, 4),
          over: categories.filter((c) => c.balance < 0),
        };
      })
    : undefined;
