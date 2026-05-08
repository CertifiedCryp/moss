#!/usr/bin/env node

import { Command } from "commander";

import { registerWalletSubcommands } from "./commands/wallet.js";
import { formatErrorMessage } from "./errors.js";

export function createWalletCli(): Command {
  const program = new Command();

  program
    .name("wallet")
    .description("MegaETH wallet CLI")
    .version("0.1.0")
    .showHelpAfterError()
    .exitOverride();

  registerWalletSubcommands(program);

  return program;
}

export async function runWalletCli(argv = process.argv): Promise<void> {
  const program = createWalletCli();

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

await runWalletCli();
