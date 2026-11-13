import json
from datetime import datetime
from pathlib import Path


def stamp(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00'))


reports = []
for path in sorted(Path(__file__).parent.glob('*-attempt*.json')):
    run = json.loads(path.read_text(encoding='utf-8-sig'))
    jobs = [j for j in run['jobs'] if j['conclusion'] != 'skipped']
    durations = {j['name']: (stamp(j['completedAt']) - stamp(j['startedAt'])).total_seconds() for j in jobs}
    report = {
        'file': path.name, 'url': run['url'], 'source': run['headSha'],
        'success': all(j['conclusion'] == 'success' for j in jobs),
        'elapsedExcludingWorkflowQueueSeconds': (max(stamp(j['completedAt']) for j in jobs) - min(stamp(j['startedAt']) for j in jobs)).total_seconds(),
        'summedRunnerSeconds': sum(durations.values()), 'jobsSeconds': durations,
        'stepsSeconds': {j['name']: {s['name']: (stamp(s['completedAt'])-stamp(s['startedAt'])).total_seconds()
                                    for s in j['steps'] if s['conclusion'] == 'success'} for j in jobs},
    }
    reports.append(report)
output = Path(__file__).with_name('comparison.json')
output.write_text(json.dumps({'scope': 'GitHub-hosted windows-2022 dry runs, same application revision; excludes release signing/publication and appcast. Hosted load/cache may vary.', 'samples': reports}, indent=2)+'\n', encoding='utf-8')
for r in reports:
    print(r['file'], r['success'], 'elapsed=',r['elapsedExcludingWorkflowQueueSeconds'], 'runner=',r['summedRunnerSeconds'])
