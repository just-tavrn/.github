// SPDX-License-Identifier: Apache-2.0
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../../', import.meta.url));
const read = path => readFileSync(`${root}${path}`, 'utf8');

test('every public repository requires the CLA job in its main ruleset', () => {
  const output = process.env.RULESETS_DRY_RUN
    ? readFileSync(process.env.RULESETS_DRY_RUN, 'utf8')
    : execFileSync('bash', ['scripts/github-rulesets.sh', '--dry-run'], { cwd: root, encoding: 'utf8' });
  const sections = [...output.matchAll(/^== ([^:]+): main\n([\s\S]*?)(?=^== |$(?![\s\S]))/gm)];
  const expected = ['.github', 'tavrn', 'tavrn-protocol', 'tavrn-crypto', 'tavrn-js', 'tavrn-node', 'tavrn-web', 'tavrn-website', 'tavrn-bot-platform'];
  assert.deepEqual(sections.map(match => match[1]), expected);
  for (const [, repo, json] of sections) {
    const checks = JSON.parse(json).rules.find(rule => rule.type === 'required_status_checks').parameters.required_status_checks;
    assert.ok(checks.some(check => check.context === 'cla / Contributor license agreement' && check.integration_id === 15368), `${repo}: CLA job must gate merges`);
    assert.ok(!checks.some(check => check.context === 'CLA Assistant'), `${repo}: do not require a nonexistent status`);
  }
});

test('CLA bot asks for exactly the published version-specific signature', () => {
  const cla = read('CLA.md');
  assert.equal(cla, read('agreements/cla-v2.md'));
  const sentence = cla.match(/^> (.+)$/m)[1];
  const workflow = read('.github/workflows/cla.yml');
  assert.ok(workflow.includes(`custom-pr-sign-comment: ${sentence}`));
  assert.ok(workflow.includes(`github.event.comment.body == '${sentence}'`));
  assert.ok(workflow.includes('path-to-signatures: signatures/version2/cla.json'));
  assert.ok(workflow.includes('path-to-document: https://github.com/just-tavrn/.github/blob/main/agreements/cla-v2.md'));
  assert.ok(!workflow.includes('actions/checkout'), 'privileged workflow must not execute PR contents');
});
