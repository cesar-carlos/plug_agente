$ErrorActionPreference = 'Stop'
$root = 'd:\Developer\plug_database\plug_agente'
$srcPath = Join-Path $root 'lib\presentation\pages\agent_actions\agent_actions_page_editor.dart'
$editorDir = Join-Path $root 'lib\presentation\pages\agent_actions\widgets\editor'
New-Item -ItemType Directory -Force -Path $editorDir | Out-Null

$lines = [System.Collections.Generic.List[string]]::new()
Get-Content $srcPath -Encoding UTF8 | ForEach-Object { [void]$lines.Add($_) }

function Find-Line([string]$pattern) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) { return $i + 1 }
    }
    throw "Pattern not found: $pattern"
}

function Get-Lines([int]$start, [int]$end) {
    if ($end -lt $start) { return @() }
    $lines[($start - 1)..($end - 1)]
}

function Wrap-Mixin([string]$name, [string[]]$bodyLines) {
    @(
        "part of '../../agent_actions_page_editor.dart';",
        '',
        "mixin $name on _AgentActionEditorStateBase {"
    ) + $bodyLines + @('}')
}

$importEndLine = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^import ') { $importEndLine = $i + 1 }
}

$stateLine = Find-Line '^class _AgentActionEditorState extends'
$initLine = Find-Line '^\s+void initState\(\)'
$fieldsStartLine = $stateLine + 1
$fieldsEndLine = $initLine - 1
while ($fieldsEndLine -gt $fieldsStartLine -and $lines[$fieldsEndLine - 1] -match '^\s*$') {
    $fieldsEndLine--
}

$preflightLine = Find-Line '^\s+Widget _buildPreflightGateInfoBar'
$execPoliciesLine = Find-Line '^\s+Widget _buildExecutionPoliciesSection'
$draftFieldsLine = Find-Line '^\s+List<Widget> _buildDraftFields'
$devHintsLine = Find-Line '^\s+List<Widget> _buildDeveloperBinaryPathHints'
$saveExecLine = Find-Line '^\s+Future<bool> _saveExecutableDraft'
$scheduleDevLine = Find-Line '^\s+void _scheduleDeveloperConnectionReload'

$closeStateLine = $lines.Count
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -eq '}') {
        $closeStateLine = $i + 1
        break
    }
}

$fieldBody = Get-Lines $fieldsStartLine $fieldsEndLine
$main = (Get-Lines 1 $importEndLine) + @(
    ''
    "part 'widgets/editor/agent_action_editor_core.dart';"
    "part 'widgets/editor/agent_action_editor_ui.dart';"
    "part 'widgets/editor/agent_action_editor_policies.dart';"
    "part 'widgets/editor/agent_action_editor_draft_fields.dart';"
    "part 'widgets/editor/agent_action_editor_developer.dart';"
    "part 'widgets/editor/agent_action_editor_save.dart';"
    ''
) + (Get-Lines ($importEndLine + 1) ($stateLine - 1)) + @(
    ''
    'abstract class _AgentActionEditorStateBase extends State<AgentActionEditor> {'
) + $fieldBody + @(
    '}'
    ''
    'class _AgentActionEditorState extends _AgentActionEditorStateBase'
    '    with'
    '        _AgentActionEditorCore,'
    '        _AgentActionEditorUi,'
    '        _AgentActionEditorPolicies,'
    '        _AgentActionEditorDraftFields,'
    '        _AgentActionEditorDeveloper,'
    '        _AgentActionEditorSave {}'
    ''
)

$main | Set-Content $srcPath -Encoding UTF8

$coreBody = Get-Lines $initLine ($preflightLine - 1)
if ($coreBody[0] -match '^\s+void initState') {
    $coreBody[0] = '  @override' + [Environment]::NewLine + $coreBody[0]
}
Wrap-Mixin '_AgentActionEditorCore' $coreBody | Set-Content (Join-Path $editorDir 'agent_action_editor_core.dart') -Encoding UTF8
Wrap-Mixin '_AgentActionEditorUi' (Get-Lines $preflightLine ($execPoliciesLine - 1)) | Set-Content (Join-Path $editorDir 'agent_action_editor_ui.dart') -Encoding UTF8
Wrap-Mixin '_AgentActionEditorPolicies' (Get-Lines $execPoliciesLine ($draftFieldsLine - 1)) | Set-Content (Join-Path $editorDir 'agent_action_editor_policies.dart') -Encoding UTF8
Wrap-Mixin '_AgentActionEditorDraftFields' (Get-Lines $draftFieldsLine ($devHintsLine - 1)) | Set-Content (Join-Path $editorDir 'agent_action_editor_draft_fields.dart') -Encoding UTF8
Wrap-Mixin '_AgentActionEditorDeveloper' (
    (Get-Lines $devHintsLine ($saveExecLine - 1)) + (Get-Lines $scheduleDevLine ($closeStateLine - 1))
) | Set-Content (Join-Path $editorDir 'agent_action_editor_developer.dart') -Encoding UTF8
Wrap-Mixin '_AgentActionEditorSave' (Get-Lines $saveExecLine ($scheduleDevLine - 1)) | Set-Content (Join-Path $editorDir 'agent_action_editor_save.dart') -Encoding UTF8

Write-Host "Main lines: $($main.Count)"
