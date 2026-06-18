import { createRequire } from "node:module";

import { Command } from "commander";

import { registerWalletCommands } from "./commands/wallet.js";
import { formatErrorMessage } from "./errors.js";

export const commandName = "mega";

const require = createRequire(import.meta.url);
const { version } = require("../package.json") as { version: string };

export function createCli(): Command {
  const program = new Command();

  program
    .name(commandName)
    .description("MegaETH MOSS account CLI")
    .version(version)
    .showHelpAfterError()
    .exitOverride();

  registerWalletCommands(program);

  return program;
}

export async function runCli(argv = process.argv): Promise<void> {
  const program = createCli();

  try {
    await program.parseAsync(argv);
  } catch (error) {
    if (error instanceof Error && error.name === "CommanderError") {
      process.exitCode = Number("exitCode" in error ? error.exitCode : 1);
      return;
    }

    process.stderr.write(`${formatErrorMessage(error)}\n`);
    process.exitCode = 1;
  }
}
