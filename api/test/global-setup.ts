import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

export default function setup(): void {
  const script = fileURLToPath(
    new URL("../../db/test-setup.sh", import.meta.url),
  );
  execFileSync("bash", [script], { stdio: "inherit", env: process.env });
}
