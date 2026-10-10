const assert = require('node:assert/strict');
const test = require('node:test');
const scheduledWorkflowAlert = require('./scheduled_workflow_alert.cjs');

const title = '[CI] Flutter CI: scheduled runs are failing';
const run = (id, conclusion, extra = {}) => ({
  id, conclusion, status: 'completed', run_attempt: 1, name: 'Flutter CI',
  workflow_id: 7, html_url: `https://github.com/owner/project/actions/runs/${id}`, ...extra,
});

async function execute(completion, recentRuns, issues = [{ title, number: 42 }], apiFailure = false) {
  const updates = [], creations = [], queries = [];
  const listForRepo = () => { throw new Error('Issue lookup must use pagination'); };
  const github = {
    paginate: async (method, parameters) => {
      assert.equal(method, listForRepo);
      assert.equal(parameters.state, 'open');
      return issues;
    },
    rest: {
      actions: {
        listWorkflowRuns: async parameters => {
          queries.push(parameters);
          if (apiFailure) throw new Error('Actions API unavailable');
          assert.equal(parameters.event, 'schedule');
          assert.equal(parameters.status, undefined);
          return { data: { workflow_runs: recentRuns } };
        },
      },
      issues: {
        listForRepo,
        update: async parameters => updates.push(parameters),
        create: async parameters => creations.push(parameters),
      },
    },
  };
  const context = { repo: { owner: 'owner', repo: 'project' }, payload: { workflow_run: completion } };
  await scheduledWorkflowAlert({ github, context, core: { info() {}, warning() {} } });
  return { updates, creations, queries };
}

test('an old successful rerun cannot close an alert for newer failures', async () => {
  const result = await execute(run(10, 'success', { run_attempt: 2 }), [run(12, 'failure'), run(11, 'failure')]);
  assert.equal(result.updates.length, 0);
  assert.equal(result.creations.length, 0);
});

test('only the latest successful scheduled run closes the active alert', async () => {
  const current = run(12, 'success');
  const result = await execute(current, [current, run(11, 'failure')]);
  assert.deepEqual(result.updates.map(issue => [issue.issue_number, issue.state]), [[42, 'closed']]);
});

test('a newer running schedule prevents an older success from closing the alert', async () => {
  const result = await execute(run(11, 'success'), [run(12, null, { status: 'in_progress' }), run(11, 'success')]);
  assert.equal(result.updates.length, 0);
});

test('an outdated attempt cannot close an alert after a failed retry', async () => {
  const result = await execute(run(12, 'success'), [run(12, 'failure', { run_attempt: 2 }), run(11, 'failure')]);
  assert.equal(result.updates.length, 0);
});

test('two consecutive failures or timeouts open one alert', async () => {
  for (const conclusion of ['failure', 'timed_out']) {
    const current = run(12, conclusion);
    const result = await execute(current, [current, run(11, 'failure')], []);
    assert.equal(result.creations.length, 1);
    assert.equal(result.creations[0].title, title);
    assert.match(result.creations[0].body, /actions\/runs\/12/);
  }
});

test('one failure after a success does not open an alert', async () => {
  const current = run(12, 'failure');
  const result = await execute(current, [current, run(11, 'success')], []);
  assert.equal(result.creations.length, 0);
});

test('cancellation does not close an existing alert', async () => {
  const result = await execute(run(12, 'cancelled'), []);
  assert.equal(result.updates.length, 0);
  assert.equal(result.queries.length, 0);
});

test('an existing alert found beyond the first page is reused', async () => {
  const current = run(12, 'failure');
  const issues = Array.from({ length: 100 }, (_, index) => ({ title: `Other issue ${index}`, number: index + 1 }));
  issues.push({ title, number: 142 });
  const result = await execute(current, [current, run(11, 'failure')], issues);
  assert.equal(result.creations.length, 0);
});

test('pull requests with the same title are not mistaken for alerts', async () => {
  const current = run(12, 'success');
  const result = await execute(current, [current, run(11, 'failure')], [
    { title, number: 99, pull_request: {} }, { title, number: 42 },
  ]);
  assert.equal(result.updates[0].issue_number, 42);
});

test('old failures cannot open an alert after a newer success', async () => {
  const result = await execute(run(10, 'failure'), [run(12, 'success'), run(11, 'success')], []);
  assert.equal(result.creations.length, 0);
});

test('API errors fail visibly without changing issues', async () => {
  await assert.rejects(execute(run(12, 'success'), [], [], true), /Actions API unavailable/);
});
