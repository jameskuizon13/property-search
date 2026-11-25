// Pre-commit checks, run by .husky/pre-commit through lint-staged.
//
// A package is checked only when the commit touches it:
//   - lint: only the staged files of that package
//   - tests: the package's whole suite, because a change in one file can break
//     callers anywhere else in it (both suites take seconds)
//
// lint-staged hides unstaged changes while this runs, so the checks see what
// is being committed. The hook passes --diff-filter=ACMRD so that a commit
// that only deletes files still runs the tests.
import { execFile } from 'node:child_process'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { promisify } from 'node:util'
import { defineConfig } from 'lint-staged/config'

const run = promisify(execFile)
const root = import.meta.dirname

// Paths relative to the package, without deleted files (nothing to lint).
const lintable = (dir, files, isLintable) =>
  files
    .filter((file) => existsSync(file) && isLintable(file))
    .map((file) => path.relative(path.join(root, dir), file))

// Run a command inside a package folder. Its output is shown only on failure.
async function exec(dir, command, args, log) {
  try {
    await run(command, args, { cwd: path.join(root, dir), maxBuffer: 64 * 1024 * 1024 })
  } catch (error) {
    log('$ (cd %s && %s %s)', dir, command, args.join(' '))
    log('%s%s', error.stdout ?? '', error.stderr ?? error.message)
    const failure = new Error(`${dir}: ${command} ${args.join(' ')} failed`)
    failure.stack = failure.message // the command output above is the useful part
    throw failure
  }
}

// Keep each linter call well under the OS argument limit.
async function inChunks(files, fn, size = 200) {
  for (let i = 0; i < files.length; i += size) await fn(files.slice(i, i + size))
}

const JS = /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$/

export default defineConfig({
  'api/**': {
    title: 'api: rubocop on staged files, then rspec',
    task: async (files, { log }) => {
      // RuboCop picks the Ruby files itself (extensions, Gemfile, shebangs in bin/).
      const existing = lintable('api', files, () => true)
      await inChunks(existing, (chunk) =>
        exec('api', 'bin/rubocop', ['--force-exclusion', '--only-recognized-file-types', ...chunk], log),
      )
      // Needs Postgres running: `make services`.
      await exec('api', 'bundle', ['exec', 'rspec'], log)
    },
  },
  'web/**': {
    title: 'web: oxlint on staged files, then vitest',
    task: async (files, { log }) => {
      const js = lintable('web', files, (f) => JS.test(f))
      await inChunks(js, (chunk) => exec('web', 'pnpm', ['exec', 'oxlint', ...chunk], log))
      await exec('web', 'pnpm', ['test'], log)
    },
  },
})
