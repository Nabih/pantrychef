export function formatCompact(value: number): string {
  return new Intl.NumberFormat("en", {
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(value);
}

export function formatFull(value: number): string {
  return new Intl.NumberFormat("en").format(value);
}

export function formatTime(minutes: number): string {
  if (!minutes || minutes <= 0) return "Time not listed";
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest === 0 ? `${hours} hr` : `${hours} hr ${rest} min`;
}

export function formatPercent(value: number): string {
  return `${Math.round(value * 100)}%`;
}
