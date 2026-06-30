export const meta = {
  name: 'update-presentation',
  description: 'Regenerate presentation.html from the current migration plan as a 5-minute English deck',
  whenToUse: 'When the migration plan / docs have changed and presentation.html needs to reflect them. Produces a 5-minute, English slide deck and returns the full HTML for the main loop to write.',
  phases: [
    { title: 'Plan', detail: 'read the migration plan + docs, build a 5-minute slide outline' },
    { title: 'Render', detail: 'turn the outline into a complete HTML deck, reusing existing CSS/JS' },
    { title: 'Verify', detail: 'adversarially check English-only, no placeholders, timing, grounding, valid HTML' },
    { title: 'Repair', detail: 'fix any issues the verifier found (only if needed)' },
  ],
}

// Sources of truth, relative to repo root (the workflow's working dir).
const SOURCES = [
  'docs/03-migration-plan.md  — the current per-workload migration plan (PRIMARY source)',
  'docs/01-memo.md            — the lift-and-shift-then-optimize stance / stakeholder tension',
  'docs/02-discovery.md       — the undocumented couplings (the gremlins)',
  'README.md                  — team name (\"The 4am Club\"), scenario framing, participants',
  'decisions/0002-target-cloud-aws.md, decisions/0003-secrets-hook-vs-prompt.md — key ADRs',
  'presentation.html          — the CURRENT deck: reuse its CSS, nav buttons, keyboard handler, counter',
  'CLAUDE.md                  — conventions and the local↔cloud mapping table',
]

const TALK = [
  'Audience: hackathon judges + the three project readers (auditor/CTO/ops).',
  'Hard constraints: the talk must be deliverable in ~5 minutes and must be in ENGLISH.',
  '5 minutes ≈ 5 to 7 slides total, ~45–60s of speaking each. Do NOT exceed 7 slides.',
  'Every claim must be grounded in the migration plan / docs — no invented numbers or features.',
  'Keep the existing visual identity: dark theme, the title \"The Lift, the Shift, and the 4am Call\".',
].join('\n')

const OUTLINE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['talkTitle', 'teamName', 'totalSeconds', 'slides'],
  properties: {
    talkTitle: { type: 'string' },
    teamName: { type: 'string' },
    totalSeconds: { type: 'number', description: 'sum of slide times; must be <= 330 (5.5 min) and >= 240' },
    slides: {
      type: 'array',
      minItems: 5,
      maxItems: 7,
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['index', 'title', 'bullets', 'speakerNote', 'approxSeconds'],
        properties: {
          index: { type: 'number' },
          title: { type: 'string' },
          bullets: { type: 'array', items: { type: 'string' }, minItems: 0, maxItems: 5,
            description: 'short slide bullets; title slide may have 0' },
          speakerNote: { type: 'string', description: 'one or two sentences the presenter says' },
          approxSeconds: { type: 'number' },
        },
      },
    },
  },
}

const HTML_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['html'],
  properties: { html: { type: 'string', description: 'the COMPLETE presentation.html document, from <!DOCTYPE html> to </html>' } },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['passed', 'issues', 'checks'],
  properties: {
    passed: { type: 'boolean' },
    issues: { type: 'array', items: { type: 'string' } },
    checks: {
      type: 'object',
      additionalProperties: false,
      required: ['englishOnly', 'noPlaceholders', 'slideCountOk', 'timingOk', 'groundedInPlan', 'validHtmlAndNav'],
      properties: {
        englishOnly: { type: 'boolean' },
        noPlaceholders: { type: 'boolean', description: 'no TODO, no <name>, no leftover skeleton text' },
        slideCountOk: { type: 'boolean', description: '5–7 slides' },
        timingOk: { type: 'boolean', description: 'fits ~5 minutes' },
        groundedInPlan: { type: 'boolean', description: 'claims trace to docs/03-migration-plan.md' },
        validHtmlAndNav: { type: 'boolean', description: 'complete HTML doc; .slide/.active CSS, nav buttons, keydown handler, counter \"n / N\" all intact and N matches slide count' },
      },
    },
  },
}

phase('Plan')
const outline = await agent(
  `You are preparing a 5-minute conference-style talk for "Scenario 2 — Cloud Migration".

Read these files from the repo (use Read/Bash; they exist at the paths shown):
${SOURCES.map(s => '  - ' + s).join('\n')}

Talk constraints:
${TALK}

Produce a slide outline that tells the migration story as it stands NOW in docs/03-migration-plan.md.
A strong arc for this scenario:
  1) Title (team + Contoso → AWS).
  2) The problem & the tension (three workloads; CFO/CTO/compliance/SRE not aligned).
  3) The decision: one 6-R pattern does NOT fit all three — re-platform frontend (S3+CloudFront),
     re-host the API (ECS Fargate behind ALB), re-architect batch (EventBridge → run-to-exit task),
     re-platform the DB (RDS + read replica). Cloud-native where it pays; defer the risky refactors.
  4) What we built: the compose stack mapped to AWS primitives (MinIO→S3, Postgres→RDS, Redis→ElastiCache,
     containers→ECS/ALB); Terraform IaC + the deterministic secrets-blocking hook; a validation suite.
  5) The gremlins: the undocumented couplings C1–C5 and how each was designed-out and asserted.
  6) How we used Claude Code: per-workload CLAUDE.md, deterministic PreToolUse hook vs. prompt preference, ADRs.
Merge/trim to fit ~5 minutes and at most 7 slides. teamName must be the real team name from README.
Set approxSeconds per slide so totalSeconds is between 240 and 330.

Return the structured outline only.`,
  { label: 'plan:outline', phase: 'Plan', schema: OUTLINE_SCHEMA }
)

phase('Render')
const rendered = await agent(
  `Render this slide outline into a COMPLETE, standalone presentation.html document.

OUTLINE (JSON):
${JSON.stringify(outline, null, 2)}

Hard requirements:
- Read the current presentation.html and REUSE its look and mechanics verbatim: the <style> block
  (dark theme, .slide / .slide.active, .tag, .nav, h1/h2 styles), the nav buttons (Prev/Next),
  the keydown ArrowLeft/ArrowRight handler, and the counter element.
- One <section class="slide"> per outline slide; the FIRST slide carries class="slide active".
- The counter must read "1 / N" where N equals the number of slides; the JS already derives N from
  slides.length, so just make sure the initial text and slide count agree.
- Put each slide's bullets in a <ul><li>…</li></ul>; the title slide uses <h1> + <p> like the original.
- OPTIONAL but nice: include each slide's speakerNote as an HTML comment <!-- NOTE: ... --> right after
  its <h2>, so the presenter has cues without showing them. Keep them in English.
- English only. No TODO, no <name>, no leftover skeleton text. Set <title> to the talk title + team name.
- Output must be a single valid HTML document from <!DOCTYPE html> to </html>.

Return { html } only.`,
  { label: 'render:html', phase: 'Render', schema: HTML_SCHEMA }
)

phase('Verify')
const verdict = await agent(
  `Adversarially verify this generated presentation deck against the requirements. Be strict;
default a check to false if you are not certain it passes.

Cross-check claims against docs/03-migration-plan.md (read it).

THE HTML:
${rendered.html}

Check and report:
- englishOnly: every visible word is English.
- noPlaceholders: no "TODO", no "<name>", no skeleton/placeholder phrasing remains.
- slideCountOk: 5–7 <section class="slide"> elements.
- timingOk: content is realistically deliverable in ~5 minutes (not wall-of-text slides).
- groundedInPlan: technical claims (patterns, AWS services, couplings C1–C5) trace to the migration plan.
- validHtmlAndNav: complete HTML doc; .slide/.slide.active CSS present, nav Prev/Next buttons present,
  keydown handler present, counter element present and the initial "n / N" is consistent with slide count.
List concrete, fixable issues. Return the verdict only.`,
  { label: 'verify:deck', phase: 'Verify', schema: VERDICT_SCHEMA }
)

let finalHtml = rendered.html
if (!verdict.passed) {
  phase('Repair')
  log(`Verifier found ${verdict.issues.length} issue(s); running a repair pass.`)
  const repaired = await agent(
    `Fix EVERY issue below in this presentation.html and return the corrected COMPLETE document.
Do not introduce new content beyond what the migration plan supports. Keep it English, 5–7 slides,
and keep the dark-theme CSS, nav buttons, keydown handler and counter intact.

ISSUES:
${verdict.issues.map((x, n) => `${n + 1}. ${x}`).join('\n')}

CURRENT HTML:
${rendered.html}

Return { html } only.`,
    { label: 'repair:html', phase: 'Repair', schema: HTML_SCHEMA }
  )
  finalHtml = repaired.html
}

return { teamName: outline.teamName, slideCount: outline.slides.length, totalSeconds: outline.totalSeconds, verdict, html: finalHtml }
