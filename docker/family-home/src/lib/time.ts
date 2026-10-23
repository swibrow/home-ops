import { config } from "./config";

const parts = (date: Date) =>
  Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", { timeZone: config.timezone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", hourCycle: "h23" })
      .formatToParts(date)
      .map((p) => [p.type, p.value]),
  );

export const isoDay = (date = new Date()) => {
  const p = parts(date);
  return `${p.year}-${p.month}-${p.day}`;
};

export const addDays = (date: Date, days: number) => new Date(date.getTime() + days * 86_400_000);

export const hour = (date = new Date()) => Number(parts(date).hour);

export const format = (date: Date, options: Intl.DateTimeFormatOptions) =>
  new Intl.DateTimeFormat("en-GB", { timeZone: config.timezone, ...options }).format(date);

export const money = (cents: number) =>
  new Intl.NumberFormat("de-CH", { style: "currency", currency: config.currency, maximumFractionDigits: 0 }).format(cents / 100);
