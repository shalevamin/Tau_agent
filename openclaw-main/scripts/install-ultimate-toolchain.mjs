import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const homeDir = os.homedir();
const managedRoot = path.join(homeDir, ".openclaw");
const binDir = path.join(managedRoot, "bin");
const toolsRoot = path.join(managedRoot, "tools");
const npmPrefix = path.join(toolsRoot, "npm-global");
const browserUseVenv = path.join(toolsRoot, "browser-use");
const browserUseBin = path.join(browserUseVenv, "bin", "browser-use");
const browserUsePip = path.join(browserUseVenv, "bin", "pip");
const openAiCuaDir = path.join(toolsRoot, "openai-cua-sample-app");
const openAiCuaRepoUrl = "https://github.com/openai/openai-cua-sample-app.git";

const NPM_TOOLS = [{ id: "codex", pkg: "@openai/codex", bin: "codex" }];

const BREW_TOOLS = [{ id: "gog", formula: "steipete/tap/gogcli", bin: "gog" }];

async function ensureDir(targetPath) {
  await fs.mkdir(targetPath, { recursive: true });
}

async function pathExists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function runCommand(command, options = {}) {
  const { cwd, env, timeoutMs = 0 } = options;
  return await new Promise((resolve) => {
    const child = spawn(command[0], command.slice(1), {
      cwd,
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    let timedOut = false;
    let timeout = null;

    if (timeoutMs > 0) {
      timeout = setTimeout(() => {
        timedOut = true;
        child.kill("SIGTERM");
      }, timeoutMs);
    }

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (error) => {
      if (timeout) {
        clearTimeout(timeout);
      }
      if (settled) {
        return;
      }
      settled = true;
      resolve({
        ok: false,
        stdout,
        stderr: `${stderr}\n${error.message}`.trim(),
        code: null,
        timedOut,
      });
    });
    child.on("close", (code) => {
      if (timeout) {
        clearTimeout(timeout);
      }
      if (settled) {
        return;
      }
      settled = true;
      resolve({
        ok: code === 0 && !timedOut,
        stdout,
        stderr,
        code,
        timedOut,
      });
    });
  });
}

function summarize(text, limit = 2) {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  return lines.slice(0, limit).join(" | ");
}

async function ensureSymlink(sourcePath, targetPath) {
  await fs.rm(targetPath, { force: true, recursive: true });
  await fs.symlink(sourcePath, targetPath);
}

async function writeExecutable(targetPath, contents) {
  await fs.writeFile(targetPath, contents, "utf8");
  await fs.chmod(targetPath, 0o755);
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\"'\"'`)}'`;
}

async function installNpmTool(tool) {
  const result = await runCommand(
    [
      "npm",
      "install",
      "--global",
      "--prefix",
      npmPrefix,
      "--no-audit",
      "--no-fund",
      tool.pkg,
    ],
    {
      env: {
        npm_config_update_notifier: "false",
      },
      timeoutMs: 20 * 60 * 1000,
    },
  );
  const sourceBin = path.join(npmPrefix, "bin", tool.bin);
  const targetBin = path.join(binDir, tool.bin);
  if (result.ok && (await pathExists(sourceBin))) {
    await ensureSymlink(sourceBin, targetBin);
  }
  return {
    ...tool,
    status: result.ok ? "installed" : "failed",
    detail:
      summarize(result.ok ? result.stdout : result.stderr) ||
      (result.ok ? "ok" : "failed"),
  };
}

async function installBrowserUse(pythonPath) {
  const steps = [];

  const venvResult = await runCommand(
    [pythonPath, "-m", "venv", browserUseVenv],
    {
      timeoutMs: 10 * 60 * 1000,
    },
  );
  steps.push({
    step: "venv",
    ok: venvResult.ok,
    detail:
      summarize(venvResult.ok ? venvResult.stdout : venvResult.stderr) ||
      "venv ready",
  });
  if (!venvResult.ok) {
    return { id: "browser-use", status: "failed", steps };
  }

  const pipUpgrade = await runCommand(
    [browserUsePip, "install", "--upgrade", "pip", "setuptools", "wheel"],
    {
      env: { PIP_DISABLE_PIP_VERSION_CHECK: "1" },
      timeoutMs: 20 * 60 * 1000,
    },
  );
  steps.push({
    step: "pip-upgrade",
    ok: pipUpgrade.ok,
    detail:
      summarize(pipUpgrade.ok ? pipUpgrade.stdout : pipUpgrade.stderr) ||
      "pip upgraded",
  });
  if (!pipUpgrade.ok) {
    return { id: "browser-use", status: "failed", steps };
  }

  const installResult = await runCommand(
    [browserUsePip, "install", "browser-use"],
    {
      env: { PIP_DISABLE_PIP_VERSION_CHECK: "1" },
      timeoutMs: 30 * 60 * 1000,
    },
  );
  steps.push({
    step: "pip-install",
    ok: installResult.ok,
    detail:
      summarize(
        installResult.ok ? installResult.stdout : installResult.stderr,
      ) || "installed",
  });
  if (!installResult.ok) {
    return { id: "browser-use", status: "failed", steps };
  }

  if (await pathExists(browserUseBin)) {
    await ensureSymlink(browserUseBin, path.join(binDir, "browser-use"));
  }

  const chromiumResult = await runCommand([browserUseBin, "install"], {
    timeoutMs: 30 * 60 * 1000,
  });
  steps.push({
    step: "browser-install",
    ok: chromiumResult.ok,
    detail:
      summarize(
        chromiumResult.ok ? chromiumResult.stdout : chromiumResult.stderr,
      ) || "browser runtime ready",
  });

  const doctorResult = await runCommand([browserUseBin, "doctor"], {
    timeoutMs: 10 * 60 * 1000,
  });
  steps.push({
    step: "doctor",
    ok: doctorResult.ok,
    detail:
      summarize(doctorResult.ok ? doctorResult.stdout : doctorResult.stderr) ||
      "doctor complete",
  });

  return {
    id: "browser-use",
    status: steps.every((step) => step.ok) ? "installed" : "partial",
    steps,
  };
}

async function detectCommand(candidates, args = ["--version"]) {
  for (const candidate of candidates) {
    const result = await runCommand([candidate, ...args], {
      timeoutMs: 15_000,
    });
    if (result.ok) {
      return candidate;
    }
  }
  return null;
}

async function detectGit() {
  return await detectCommand(["git", "/usr/bin/git", "/opt/homebrew/bin/git"]);
}

async function resolvePnpmCommand() {
  const pnpm = await detectCommand([
    "pnpm",
    "/opt/homebrew/bin/pnpm",
    "/usr/local/bin/pnpm",
  ]);
  if (pnpm) {
    return [pnpm];
  }

  const corepack = await detectCommand([
    "corepack",
    "/opt/homebrew/bin/corepack",
    "/usr/local/bin/corepack",
  ]);
  if (!corepack) {
    return null;
  }

  const enableResult = await runCommand([corepack, "enable"], {
    timeoutMs: 60_000,
  });
  if (!enableResult.ok) {
    return null;
  }

  const probe = await runCommand([corepack, "pnpm", "--version"], {
    timeoutMs: 60_000,
  });
  if (!probe.ok) {
    return null;
  }

  return [corepack, "pnpm"];
}

async function ensureOpenAiCuaEnv() {
  const defaults = [
    "OPENAI_API_KEY=",
    "HOST=127.0.0.1",
    "PORT=4001",
    "CUA_DEFAULT_MODEL=gpt-5.4",
    "CUA_RESPONSES_MODE=auto",
    "RUNNER_BASE_URL=http://127.0.0.1:4001",
    "NEXT_PUBLIC_CUA_DEFAULT_MODEL=gpt-5.4",
    "NEXT_PUBLIC_CUA_DEFAULT_MAX_RESPONSE_TURNS=24",
  ].join("\n");

  const envPath = path.join(openAiCuaDir, ".env");
  if (!(await pathExists(envPath))) {
    await fs.writeFile(envPath, `${defaults}\n`, "utf8");
  }
}

async function writeOpenAiCuaWrappers(pnpmCommand) {
  const scripts = [
    { name: "tua-cua-dev", script: "dev" },
    { name: "tua-cua-runner", script: "dev:runner" },
    { name: "tua-cua-web", script: "dev:web" },
  ];

  for (const item of scripts) {
    const targetPath = path.join(binDir, item.name);
    const command = [
      ...pnpmCommand.map((part) => shellQuote(part)),
      shellQuote(item.script),
    ].join(" ");
    await writeExecutable(
      targetPath,
      [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        `cd ${shellQuote(openAiCuaDir)}`,
        `exec ${command} \"$@\"`,
        "",
      ].join("\n"),
    );
  }
}

async function installOpenAiCuaStack() {
  const steps = [];

  const gitPath = await detectGit();
  if (!gitPath) {
    return {
      id: "openai-cua",
      status: "failed",
      steps: [{ step: "git", ok: false, detail: "git not found" }],
    };
  }

  const pnpmCommand = await resolvePnpmCommand();
  if (!pnpmCommand) {
    return {
      id: "openai-cua",
      status: "failed",
      steps: [{ step: "pnpm", ok: false, detail: "pnpm/corepack not found" }],
    };
  }

  if (!(await pathExists(openAiCuaDir))) {
    const cloneResult = await runCommand(
      [gitPath, "clone", "--depth", "1", openAiCuaRepoUrl, openAiCuaDir],
      { timeoutMs: 20 * 60 * 1000 },
    );
    steps.push({
      step: "clone",
      ok: cloneResult.ok,
      detail:
        summarize(cloneResult.ok ? cloneResult.stdout : cloneResult.stderr) ||
        "cloned",
    });
    if (!cloneResult.ok) {
      return { id: "openai-cua", status: "failed", steps };
    }
  } else {
    const pullResult = await runCommand(
      [gitPath, "-C", openAiCuaDir, "pull", "--ff-only"],
      {
        timeoutMs: 10 * 60 * 1000,
      },
    );
    steps.push({
      step: "update",
      ok: pullResult.ok,
      detail:
        summarize(pullResult.ok ? pullResult.stdout : pullResult.stderr) ||
        "updated",
    });
    if (!pullResult.ok) {
      return { id: "openai-cua", status: "failed", steps };
    }
  }

  await ensureOpenAiCuaEnv();
  steps.push({
    step: "env",
    ok: true,
    detail: "default .env ready",
  });

  const installResult = await runCommand([...pnpmCommand, "install"], {
    cwd: openAiCuaDir,
    timeoutMs: 60 * 60 * 1000,
  });
  steps.push({
    step: "install",
    ok: installResult.ok,
    detail:
      summarize(
        installResult.ok ? installResult.stdout : installResult.stderr,
      ) || "dependencies installed",
  });
  if (!installResult.ok) {
    return { id: "openai-cua", status: "failed", steps };
  }

  const playwrightResult = await runCommand(
    [...pnpmCommand, "playwright:install"],
    {
      cwd: openAiCuaDir,
      timeoutMs: 45 * 60 * 1000,
    },
  );
  steps.push({
    step: "playwright",
    ok: playwrightResult.ok,
    detail:
      summarize(
        playwrightResult.ok ? playwrightResult.stdout : playwrightResult.stderr,
      ) || "chromium installed",
  });

  await writeOpenAiCuaWrappers(pnpmCommand);
  steps.push({
    step: "wrappers",
    ok: true,
    detail: "tua-cua-dev / tua-cua-runner / tua-cua-web ready",
  });

  return {
    id: "openai-cua",
    status: steps.every((step) => step.ok) ? "installed" : "partial",
    steps,
  };
}

async function detectBrew() {
  return await detectCommand([
    "brew",
    "/opt/homebrew/bin/brew",
    "/usr/local/bin/brew",
  ]);
}

async function installBrewTool(brewPath, tool) {
  const result = await runCommand([brewPath, "install", tool.formula], {
    env: { HOMEBREW_NO_AUTO_UPDATE: "1" },
    timeoutMs: 30 * 60 * 1000,
  });
  let sourceBin = null;
  if (result.ok) {
    const prefixResult = await runCommand(
      [brewPath, "--prefix", tool.formula],
      {
        timeoutMs: 30_000,
      },
    );
    if (prefixResult.ok) {
      const prefix = prefixResult.stdout.trim();
      const candidate = path.join(prefix, "bin", tool.bin);
      if (await pathExists(candidate)) {
        sourceBin = candidate;
      }
    }
  }
  if (!sourceBin) {
    const fallback = path.join(path.dirname(brewPath), tool.bin);
    if (await pathExists(fallback)) {
      sourceBin = fallback;
    }
  }
  if (result.ok && sourceBin) {
    await ensureSymlink(sourceBin, path.join(binDir, tool.bin));
  }
  return {
    id: tool.id,
    status: result.ok && sourceBin ? "installed" : "failed",
    detail:
      summarize(result.ok ? result.stdout : result.stderr) ||
      (result.ok ? "installed" : "failed"),
  };
}

async function detectPython() {
  return await detectCommand([
    "python3",
    "/usr/bin/python3",
    "/opt/homebrew/bin/python3",
  ]);
}

async function main() {
  await ensureDir(binDir);
  await ensureDir(toolsRoot);
  await ensureDir(npmPrefix);

  const installed = [];
  for (const tool of NPM_TOOLS) {
    installed.push(await installNpmTool(tool));
  }

  const brewPath = await detectBrew();
  if (brewPath) {
    for (const tool of BREW_TOOLS) {
      installed.push(await installBrewTool(brewPath, tool));
    }
  } else {
    for (const tool of BREW_TOOLS) {
      installed.push({
        id: tool.id,
        status: "failed",
        detail: "brew not found",
      });
    }
  }

  const pythonPath = await detectPython();
  if (pythonPath) {
    installed.push(await installBrowserUse(pythonPath));
  } else {
    installed.push({
      id: "browser-use",
      status: "failed",
      steps: [
        { step: "detect-python", ok: false, detail: "python3 not found" },
      ],
    });
  }

  installed.push(await installOpenAiCuaStack());

  const manifest = {
    generatedAt: new Date().toISOString(),
    managedRoot,
    npmPrefix,
    installed,
  };
  await fs.writeFile(
    path.join(managedRoot, ".tua-installed-toolchain.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
    "utf8",
  );

  const successCount = installed.filter(
    (item) => item.status === "installed",
  ).length;
  console.log(
    `Installed ${successCount}/${installed.length} toolchain targets into ${managedRoot}`,
  );
  for (const item of installed) {
    if (Array.isArray(item.steps)) {
      const detail = item.steps
        .map((step) => `${step.step}:${step.ok ? "ok" : "fail"}`)
        .join(", ");
      console.log(`tool ${item.status}: ${item.id} (${detail})`);
      continue;
    }
    console.log(`tool ${item.status}: ${item.id} (${item.detail})`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
