import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const EXCLUDED_DIRS = new Set([
  ".git",
  ".hg",
  ".svn",
  "node_modules",
  ".next",
  ".turbo",
  ".pnpm",
  ".yarn",
  "dist",
  "build",
  "coverage",
  ".build",
  ".artifacts",
  ".DS_Store",
]);
const EXCLUDED_SKILL_KEYS = new Set(["gemini", "nano-banana-pro"]);

const SYNC_REPOS = [
  { dir: "openai-skills-main", url: "https://github.com/openai/skills.git" },
  { dir: "browser-use-main", url: "https://github.com/browser-use/browser-use.git" },
  { dir: "BrowserMCP-mcp-main", url: "https://github.com/BrowserMCP/mcp.git" },
  { dir: "gogcli-main", url: "https://github.com/steipete/gogcli.git" },
  { dir: "superset-main", url: "https://github.com/superset-sh/superset.git" },
];

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const repoRoot = path.resolve(scriptDir, "..");
const workspaceRoot = process.env.TUA_SKILLS_SOURCE_ROOT
  ? path.resolve(process.env.TUA_SKILLS_SOURCE_ROOT)
  : path.resolve(repoRoot, "..");
const targetRoot = process.env.TAU_AGENT_MANAGED_SKILLS_DIR
  ? path.resolve(process.env.TAU_AGENT_MANAGED_SKILLS_DIR)
  : path.join(os.homedir(), ".tau-agent", "skills");

async function exists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

function normalizeSkillKey(value) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
}

function parseSkillName(markdown, fallbackName) {
  const frontmatterMatch = markdown.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!frontmatterMatch) {
    return fallbackName;
  }
  const nameMatch = frontmatterMatch[1]?.match(/^\s*name:\s*(.+?)\s*$/m);
  if (!nameMatch) {
    return fallbackName;
  }
  return nameMatch[1].replace(/^['"]|['"]$/g, "").trim() || fallbackName;
}

async function collectSkillDirs(rootDir, targetDir) {
  const results = [];
  const targetReal = await fs.realpath(targetDir).catch(() => null);

  async function walk(currentDir) {
    let currentReal = null;
    try {
      currentReal = await fs.realpath(currentDir);
    } catch {
      currentReal = currentDir;
    }
    if (targetReal && currentReal === targetReal) {
      return;
    }

    const entries = await fs.readdir(currentDir, { withFileTypes: true });
    const hasSkill = entries.some((entry) => entry.isFile() && entry.name === "SKILL.md");
    if (hasSkill) {
      results.push(currentDir);
      return;
    }

    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }
      if (EXCLUDED_DIRS.has(entry.name)) {
        continue;
      }
      await walk(path.join(currentDir, entry.name));
    }
  }

  await walk(rootDir);
  return results;
}

async function copyDir(sourceDir, destDir) {
  await fs.mkdir(destDir, { recursive: true });
  const entries = await fs.readdir(sourceDir, { withFileTypes: true });
  for (const entry of entries) {
    const sourcePath = path.join(sourceDir, entry.name);
    const destPath = path.join(destDir, entry.name);
    if (entry.isDirectory()) {
      await copyDir(sourcePath, destPath);
      continue;
    }
    if (entry.isFile()) {
      await fs.copyFile(sourcePath, destPath);
    }
  }
}

async function syncRepo(repo) {
  const repoDir = path.join(workspaceRoot, repo.dir);
  if (!(await exists(repoDir))) {
    await runCommand(["git", "clone", "--depth", "1", repo.url, repo.dir], workspaceRoot);
    return { ...repo, status: "cloned", path: repoDir };
  }
  if (!(await exists(path.join(repoDir, ".git")))) {
    return { ...repo, status: "skipped-non-git", path: repoDir };
  }
  await runCommand(["git", "-C", repoDir, "pull", "--ff-only"], workspaceRoot);
  return { ...repo, status: "updated", path: repoDir };
}

async function runCommand(command, cwd) {
  const { spawn } = await import("node:child_process");
  await new Promise((resolve, reject) => {
    const child = spawn(command[0], command.slice(1), {
      cwd,
      stdio: "inherit",
      env: process.env,
    });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command.join(" ")} exited with code ${code ?? "unknown"}`));
      }
    });
  });
}

function repoNameForSkill(skillDir) {
  const relative = path.relative(workspaceRoot, skillDir);
  const [repoName] = relative.split(path.sep);
  return repoName || "workspace";
}

async function main() {
  await fs.mkdir(targetRoot, { recursive: true });
  const existingEntries = await fs.readdir(targetRoot, { withFileTypes: true });
  for (const entry of existingEntries) {
    await fs.rm(path.join(targetRoot, entry.name), { recursive: true, force: true });
  }

  const repoSync = [];
  for (const repo of SYNC_REPOS) {
    try {
      repoSync.push(await syncRepo(repo));
    } catch (error) {
      repoSync.push({
        ...repo,
        status: "failed",
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  const sourceRoots = [repoRoot, ...SYNC_REPOS.map((repo) => path.join(workspaceRoot, repo.dir))];
  const skillDirSet = new Set();
  for (const sourceRoot of sourceRoots) {
    if (!(await exists(sourceRoot))) {
      continue;
    }
    const dirs = await collectSkillDirs(sourceRoot, targetRoot);
    for (const dir of dirs) {
      skillDirSet.add(dir);
    }
  }
  const skillDirs = [...skillDirSet].sort((a, b) => a.localeCompare(b));

  const discovered = [];
  for (const skillDir of skillDirs) {
    const skillFile = path.join(skillDir, "SKILL.md");
    const markdown = await fs.readFile(skillFile, "utf8");
    const parsedName = parseSkillName(markdown, path.basename(skillDir));
    const skillKey = normalizeSkillKey(parsedName || path.basename(skillDir));
    if (EXCLUDED_SKILL_KEYS.has(skillKey)) {
      continue;
    }
    discovered.push({
      skillDir,
      skillFile,
      repoName: repoNameForSkill(skillDir),
      skillName: parsedName,
      skillKey,
    });
  }

  const collisionCounts = new Map();
  for (const skill of discovered) {
    collisionCounts.set(skill.skillKey, (collisionCounts.get(skill.skillKey) ?? 0) + 1);
  }

  const usedInstallNames = new Set();
  const installed = [];
  for (const skill of discovered) {
    const baseName =
      collisionCounts.get(skill.skillKey) === 1
        ? skill.skillKey
        : normalizeSkillKey(`${skill.repoName}-${skill.skillKey}`);
    let installName = baseName || normalizeSkillKey(path.basename(skill.skillDir)) || "skill";
    let suffix = 2;
    while (usedInstallNames.has(installName)) {
      installName = `${baseName}-${suffix}`;
      suffix += 1;
    }
    usedInstallNames.add(installName);

    const destDir = path.join(targetRoot, installName);
    await fs.rm(destDir, { recursive: true, force: true });
    await copyDir(skill.skillDir, destDir);
    installed.push({
      installName,
      skillName: skill.skillName,
      repoName: skill.repoName,
      source: skill.skillDir,
      destination: destDir,
    });
  }

  const manifest = {
    generatedAt: new Date().toISOString(),
    workspaceRoot,
    targetRoot,
    repoSync,
    installed,
  };
  await fs.writeFile(
    path.join(targetRoot, ".tua-installed-skills.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
    "utf8",
  );

  console.log(`Installed ${installed.length} skills into ${targetRoot}`);
  for (const repo of repoSync) {
    const suffix = "error" in repo ? ` (${repo.error})` : "";
    console.log(`repo ${repo.status}: ${repo.dir}${suffix}`);
  }
  for (const item of installed) {
    console.log(`- ${item.installName} <- ${path.relative(workspaceRoot, item.source)}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
