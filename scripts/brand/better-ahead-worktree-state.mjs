import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { lstat, readFile } from "node:fs/promises";
import path from "node:path";
import { promisify, TextDecoder } from "node:util";
import { fileURLToPath } from "node:url";

const runFile = promisify(execFile);
const utf8Decoder = new TextDecoder("utf-8", { fatal: true });

export async function betterAheadWorktreeState(repositoryPath, options = {}) {
  const repository = path.resolve(repositoryPath);
  const excludeExact = options.excludeExact ?? [];
  if (!Array.isArray(excludeExact) || excludeExact.length > 1) {
    throw new Error("--exclude-exact may name at most one exact relative path");
  }
  for (const exclusion of excludeExact) {
    validateRelativePath(exclusion, "--exclude-exact");
  }
  const requireOnlyPrefix = options.requireOnlyPrefix;
  if (requireOnlyPrefix !== undefined) {
    validateRelativePath(requireOnlyPrefix, "--require-only-prefix");
  }

  const { stdout } = await runFile(
    "git",
    ["status", "--porcelain=v1", "-z", "-uall"],
    {
      cwd: repository,
      encoding: "buffer",
      maxBuffer: 64 * 1024 * 1024,
    },
  );
  const records = parsePorcelainV1Z(stdout);

  for (const exclusion of excludeExact) {
    const exact = records.some(({ path: relativePath }) => relativePath === exclusion);
    const ancestor = records.some(({ path: relativePath }) =>
      relativePath.startsWith(`${exclusion}/`));
    if (ancestor) {
      throw new Error(`--exclude-exact rejects directory-wide exclusion: ${exclusion}`);
    }
    if (!exact) {
      throw new Error(`--exclude-exact does not name a reported path: ${exclusion}`);
    }
  }

  const includedRecords = records.filter(({ path: relativePath }) =>
    !excludeExact.includes(relativePath));
  const paths = [];
  for (const record of includedRecords) {
    paths.push({
      ...record,
      ...await physicalState(repository, record.path),
    });
  }
  paths.sort((left, right) => compareUtf8(left.path, right.path));

  if (requireOnlyPrefix !== undefined) {
    if (paths.length === 0) {
      throw new Error("--require-only-prefix requires at least one changed path");
    }
    for (const entry of paths) {
      if (!entry.path.startsWith(`${requireOnlyPrefix}/`)) {
        throw new Error(`changed path is outside required prefix: ${entry.path}`);
      }
      if (entry.state !== "present" || entry.fileType !== "regular_file") {
        throw new Error(`changed path below required prefix must be a present regular file: ${entry.path}`);
      }
    }
  }

  return { schemaVersion: 1, paths };
}

export function parsePorcelainV1Z(buffer) {
  if (!Buffer.isBuffer(buffer)) {
    throw new TypeError("porcelain input must be a Buffer");
  }
  const fields = splitNulFields(buffer);
  const records = [];
  for (let index = 0; index < fields.length; index += 1) {
    const field = fields[index];
    if (field.length < 4 || field[2] !== 0x20) {
      throw new Error("invalid NUL-delimited porcelain v1 record");
    }
    const status = field.subarray(0, 2).toString("ascii");
    const relativePath = decodePath(field.subarray(3));
    validateGitRelativePath(relativePath);
    const record = { path: relativePath, status };
    if (status.includes("R") || status.includes("C")) {
      index += 1;
      if (index >= fields.length) {
        throw new Error("rename/copy porcelain record is missing its original path");
      }
      const originalPath = decodePath(fields[index]);
      validateGitRelativePath(originalPath);
      record.originalPath = originalPath;
    }
    records.push(record);
  }
  return records;
}

function splitNulFields(buffer) {
  const fields = [];
  let start = 0;
  for (let index = 0; index < buffer.length; index += 1) {
    if (buffer[index] !== 0) continue;
    fields.push(buffer.subarray(start, index));
    start = index + 1;
  }
  if (start !== buffer.length) {
    throw new Error("porcelain v1 -z output is not NUL-terminated");
  }
  if (fields.at(-1)?.length === 0) fields.pop();
  return fields;
}

async function physicalState(repository, relativePath) {
  const absolutePath = path.resolve(repository, relativePath);
  if (!absolutePath.startsWith(`${repository}${path.sep}`)) {
    throw new Error(`reported path escapes repository: ${relativePath}`);
  }
  try {
    const metadata = await lstat(absolutePath);
    if (metadata.isFile()) {
      const bytes = await readFile(absolutePath);
      return {
        state: "present",
        fileType: "regular_file",
        byteSize: metadata.size,
        sha256: createHash("sha256").update(bytes).digest("hex"),
      };
    }
    if (metadata.isSymbolicLink()) {
      return {
        state: "present",
        fileType: "symbolic_link",
        byteSize: metadata.size,
        sha256: null,
      };
    }
    return {
      state: "present",
      fileType: metadata.isDirectory() ? "directory" : "other",
      byteSize: metadata.size,
      sha256: null,
    };
  } catch (error) {
    if (error?.code === "ENOENT" || error?.code === "ENOTDIR") {
      return {
        state: "missing",
        fileType: "missing",
        byteSize: null,
        sha256: null,
      };
    }
    throw error;
  }
}

function validateRelativePath(value, flag) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${flag} requires a non-empty relative path`);
  }
  if (path.posix.isAbsolute(value) || path.win32.isAbsolute(value)) {
    throw new Error(`${flag} rejects absolute paths`);
  }
  if (/[\0*?[\]{}]/u.test(value)) {
    throw new Error(`${flag} rejects wildcards`);
  }
  if (value.includes("\\")) {
    throw new Error(`${flag} requires POSIX path separators`);
  }
  const normalized = path.posix.normalize(value);
  if (value === "." || normalized !== value || value.startsWith("../")) {
    throw new Error(`${flag} rejects root and traversal paths`);
  }
}

function validateGitRelativePath(value) {
  if (value.length === 0
    || value.includes("\0")
    || path.posix.isAbsolute(value)
    || path.win32.isAbsolute(value)
    || path.posix.normalize(value) !== value
    || value === "."
    || value.startsWith("../")) {
    throw new Error("git reported an unsafe relative path");
  }
}

function decodePath(buffer) {
  try {
    return utf8Decoder.decode(buffer);
  } catch (error) {
    throw new Error(`git path is not valid UTF-8: ${error instanceof Error ? error.message : error}`);
  }
}

function compareUtf8(left, right) {
  return Buffer.compare(Buffer.from(left, "utf8"), Buffer.from(right, "utf8"));
}

function parseArguments(arguments_) {
  const result = { excludeExact: [] };
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    const value = arguments_[index + 1];
    if (!["--repository", "--exclude-exact", "--require-only-prefix"].includes(argument)
      || value === undefined) {
      throw new Error("usage: better-ahead-worktree-state.mjs --repository PATH [--exclude-exact PATH] [--require-only-prefix DIRECTORY]");
    }
    index += 1;
    if (argument === "--repository") {
      if (result.repository !== undefined) throw new Error("--repository may be supplied only once");
      result.repository = value;
    } else if (argument === "--exclude-exact") {
      result.excludeExact.push(value);
    } else {
      if (result.requireOnlyPrefix !== undefined) {
        throw new Error("--require-only-prefix may be supplied only once");
      }
      result.requireOnlyPrefix = value;
    }
  }
  if (result.repository === undefined) {
    throw new Error("--repository is required");
  }
  return result;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const state = await betterAheadWorktreeState(options.repository, options);
  process.stdout.write(`${JSON.stringify(state, null, 2)}\n`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : error}\n`);
    process.exitCode = 1;
  });
}
