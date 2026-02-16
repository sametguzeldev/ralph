---
name: prd-questions
description: "Generate clarifying questions for a feature before writing a PRD. Use when starting to plan a feature and you need to gather requirements. Triggers on: prd questions, clarifying questions for, what questions for, plan questions."
user-invocable: true
---

# PRD Clarifying Questions

Generate clarifying questions for a feature description. The user answers them in the file, then uses the `/prd` skill to generate the PRD.

---

## The Job

### First run (new feature):
1. Receive a feature description from the user
2. Analyze it for ambiguities and missing context
3. Generate clarifying questions with lettered options
4. Save to `tasks/prd-questions-[feature-name].md`

### Follow-up run (existing questions file with answers):
1. Read the existing questions file the user points you to
2. Review all previous questions AND their answers
3. Identify new ambiguities or gaps raised by the answers
4. **Append** a `## Follow-up Questions` section with new questions (numbered continuing from where the previous questions left off)
5. If no follow-up questions are needed, tell the user the file is ready for `/prd`

**Important:** Do NOT generate the PRD. Only generate questions. On follow-up runs, do NOT modify or remove existing questions/answers — only append new ones.

---

## Question Guidelines

Ask as many questions as needed to fully understand the feature. Focus on:

- **Problem/Goal:** What problem does this solve? Why is it needed?
- **Target Users:** Who will use this? What are their needs?
- **Core Functionality:** What are the key actions and behaviors?
- **Scope/Boundaries:** What should it NOT do?
- **Technical Context:** What existing systems does it integrate with?
- **UI/UX:** What should the interface look like? What interactions?
- **Data:** What data is involved? Where does it come from?
- **Edge Cases:** What happens in unusual scenarios?
- **Success Criteria:** How do we know it's done and working?

Don't artificially limit the number of questions. A simple feature may need 3 questions; a complex one may need 10+. Ask whatever is necessary for a complete understanding.

---

## Output Format

Write a markdown file with this structure:

```markdown
# Clarifying Questions: [Feature Name]

> Original request: [the user's feature description]

## Questions

1. [Question text]
   A. [Option]
   B. [Option]
   C. [Option]
   D. Other: [please specify]

   **Answer:**

2. [Question text]
   A. [Option]
   B. [Option]
   C. [Option]

   **Answer:**

[... more questions as needed ...]

## Additional Context

[Space for the user to add any extra context, notes, or requirements not covered by the questions above.]
```

### On follow-up runs, append:

```markdown
## Follow-up Questions

7. [Follow-up question based on previous answers]
   A. [Option]
   B. [Option]
   C. [Option]

   **Answer:**

[... more follow-up questions as needed ...]
```

Continue numbering from where the previous questions left off. If running follow-ups multiple times, use `## Follow-up Questions (Round 2)`, `## Follow-up Questions (Round 3)`, etc.

### Rules:
- Each question should have 2-4 lettered options plus an "Other" option where appropriate
- Always include an `**Answer:**` field after each question for the user to fill in
- Include an `## Additional Context` section at the end for free-form input (first run only)
- Indent options under their question
- On follow-up runs, never modify existing content — only append

---

## Output

- **Format:** Markdown (`.md`)
- **Location:** `tasks/`
- **Filename:** `prd-questions-[feature-name].md` (kebab-case)

---

## Example

For input: "Add user notifications to the app"

```markdown
# Clarifying Questions: User Notifications

> Original request: Add user notifications to the app

## Questions

1. What types of notifications should be supported?
   A. In-app notifications only (bell icon, dropdown)
   B. Email notifications only
   C. Both in-app and email
   D. In-app, email, and push notifications

   **Answer:**

2. What events should trigger notifications?
   A. Only actions by other users (e.g., comments, mentions)
   B. System events (e.g., task due dates, status changes)
   C. Both user actions and system events
   D. Other: [please specify]

   **Answer:**

3. Should users be able to configure their notification preferences?
   A. No, all notifications are on by default
   B. Yes, simple on/off per notification type
   C. Yes, granular control per event type and delivery channel
   D. Other: [please specify]

   **Answer:**

4. How should notifications be stored?
   A. Database table with read/unread status
   B. Ephemeral (only shown once, not persisted)
   C. Database with archiving/deletion support

   **Answer:**

5. Should notifications support real-time delivery?
   A. No, load on page refresh only
   B. Yes, real-time via WebSockets or SSE
   C. Polling at regular intervals

   **Answer:**

6. What is the scope for this iteration?
   A. Minimal viable version (basic in-app only)
   B. Full-featured implementation
   C. Just the backend/API infrastructure
   D. Just the UI components

   **Answer:**

## Additional Context

[Add any extra details, constraints, or requirements here.]
```

---

## Checklist

### First run:
- [ ] All ambiguous aspects of the feature have a question
- [ ] Each question has lettered options
- [ ] Each question has an `**Answer:**` field
- [ ] `## Additional Context` section is included at the end
- [ ] Saved to `tasks/prd-questions-[feature-name].md`

### Follow-up run:
- [ ] Read and understood all existing questions and answers
- [ ] New questions address gaps revealed by the answers
- [ ] Numbering continues from previous questions
- [ ] Existing content is untouched — only appended
- [ ] If no follow-ups needed, informed user the file is ready for `/prd`
