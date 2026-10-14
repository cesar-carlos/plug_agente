module.exports = async function scheduledWorkflowAlert({ github, context, core }) {
  const run = context.payload.workflow_run;
  const failures = new Set(['failure', 'timed_out']);
  if (run.conclusion !== 'success' && !failures.has(run.conclusion)) {
    core.info(`Scheduled run ended with ${run.conclusion}; preserving any active alert.`);
    return;
  }

  const { data } = await github.rest.actions.listWorkflowRuns({
    owner: context.repo.owner,
    repo: context.repo.repo,
    workflow_id: run.workflow_id,
    event: 'schedule',
    per_page: 2,
  });
  const recentRuns = data.workflow_runs.slice(0, 2);
  const latest = recentRuns[0];
  if (!latest || latest.id !== run.id || latest.run_attempt !== run.run_attempt ||
      latest.status !== 'completed' || latest.conclusion !== run.conclusion) {
    core.info('A newer scheduled run or attempt exists; ignoring this outdated completion.');
    return;
  }

  if (latest.conclusion !== 'success' && (recentRuns.length !== 2 || !recentRuns.every(candidate =>
    candidate.status === 'completed' && failures.has(candidate.conclusion)))) {
    core.info('Fewer than two consecutive scheduled failures; alert not opened.');
    return;
  }

  const title = `[CI] ${run.name}: scheduled runs are failing`;
  let existingIssue;
  for await (const { data: issues } of github.paginate.iterator(github.rest.issues.listForRepo, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    state: 'open',
    per_page: 100,
  })) {
    existingIssue = issues.find(issue => !issue.pull_request && issue.title === title);
    if (existingIssue) break;
  }
  if (latest.conclusion === 'success') {
    if (existingIssue) {
      await github.rest.issues.update({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: existingIssue.number,
        state: 'closed',
      });
    }
    core.info('The latest scheduled run succeeded; no active alert remains.');
    return;
  }

  if (existingIssue) {
    const previousBody = existingIssue.body || '';
    const latestRunLine = `Latest failed run: ${latest.html_url}`;
    const body = /^Latest failed run:.*$/m.test(previousBody)
      ? previousBody.replace(/^Latest failed run:.*$/m, latestRunLine)
      : `${previousBody}\n\n${latestRunLine}`.trim();
    if (body !== previousBody) {
      await github.rest.issues.update({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: existingIssue.number,
        body,
      });
    }
    core.warning(`An alert is already open: #${existingIssue.number}`);
    return;
  }
  await github.rest.issues.create({
    owner: context.repo.owner,
    repo: context.repo.repo,
    title,
    body: [
      'Two consecutive scheduled executions failed.',
      '',
      `Latest failed run: ${latest.html_url}`,
      'Inspect the workflow logs and close this issue after a successful scheduled execution.',
    ].join('\n'),
  });
};
