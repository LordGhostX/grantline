# Grantline — Product Brief

**Programmable financial authority for AI agents.**

- **Website:** grantline.xyz
- **X:** @usegrantline
- **GitHub:** usegrantline
- **Telegram:** @usegrantline

---

## Overview

AI agents are moving from recommending financial actions to executing them.

They can manage capital, make payments, trade assets, interact with financial products, and delegate tasks to other agents.

But giving an autonomous agent access to a wallet can also give it far more authority than it needs.

**Grantline provides the financial authority layer between autonomous intent and execution.**

Instead of giving an agent unrestricted control of capital, users give it a **Mandate** defining exactly what it is authorised to do and under what conditions.

The agent decides what it wants to do.

**Grantline determines whether it is allowed to do it.**

> **AI proposes. Mandate authorises.**

---

# The Problem

Existing wallets primarily answer:

> Who controls these assets?

Autonomous financial systems need to answer a different set of questions:

> What is this agent allowed to do?

> How much authority has it been given?

> Where did that authority come from?

> What conditions must be satisfied before it acts?

> When should a human step in?

> What happened after the decision was made?

Basic spending limits are not enough.

A user may want an agent to:

- manage up to $50,000
- never deploy more than $10,000 at once
- only interact with approved assets
- maintain minimum liquidity
- require additional checks for certain transactions
- request human approval above a threshold
- delegate narrower authority to another agent
- stop acting when specified conditions change

Grantline turns those requirements into enforceable financial authority.

---

# How Grantline Works

Every autonomous action begins with an agent proposing what it wants to do.

Grantline then evaluates that action through the controls selected by the owner.

### Typical flow

**Agent proposes**

→ **Mandate checks authority**

→ **Configured conditions check the proposed action**

→ **Configured Preflight checks test the proposed action**

→ **Allow / Escalate / Deny**

→ **Owner approval when escalated**

→ **Execute**

→ **Record**

Not every action needs every step.

A simple payment may only require authorisation.

A significant treasury action may require additional checks and human approval.

---

# Product Model

Grantline is built around six core concepts.

## Mandates

Define **what an agent is authorised to do**.

A current Mandate can specify amount bounds, typed actions, owner-approved escalation, inherited Preflight rules, delegation permissions, deadlines, and revocation. Planned extensions can add approved assets or products, richer liquidity requirements, multiple approvals, and Guardian conditions.

Mandates govern authority.

---

## Vaults

Define **what capital that authority applies to**.

Capital assigned to autonomous agents is separated from the owner's unrestricted funds.

The agent only operates against the capital made available to it and only within its Mandate.

> **Vaults hold capital. Mandates define authority.**

---

## Delegation Graph

Shows **where authority came from and how it has been delegated**.

An owner may authorise one agent, which can then delegate a narrower portion of that authority to another.

For example:

**Company**

→ Treasury Agent
Can manage $500,000.

→ Execution Agent
Can execute up to $50,000 but cannot borrow.

→ Payments Agent
Can make approved payments up to $5,000.

The governing principle is:

> **Delegated authority may become narrower, but never broader.**

Authority can be narrowed by capital, actions, assets, duration, approvals, or other conditions.

Every delegation remains traceable to its original source.

---

## Guardians

Guardians are planned modules for verifying **external conditions relevant to an action**.

They could check whether required market information is current, whether an asset is operating normally, or whether an exceptional condition should prevent autonomous execution. Guardians do not decide whether an investment is good; they answer specific questions that the owner has chosen to make relevant to authorisation.

The first planned Guardian is an **RWA Guardian** for tokenised real-world assets. Other modules could cover protocol, oracle, security, compliance, or asset conditions. Guardian conditions are deferred from the current contracts MVP.

---

## Preflight

Tests **what the resulting Vault state could look like before execution**.

The current MVP checks the projected native Vault balance after the plan's aggregate native outflow against inherited minimum reserves in native units and, when configured, whole-dollar native/USD value. A violation can produce `DENY` or `ESCALATE` according to the corresponding Preflight rule. Token-only plans still preserve the native reserve, and the USD reserve values only the actual native balance rather than wrapped-native or arbitrary token holdings.

Preflight does not predict whether an investment will succeed; it checks whether execution would leave the Vault outside the owner's configured boundary. Richer portfolio, liquidity, collateral, and organisation-specific stress scenarios remain future work.

---

## Records

Provide **a traceable history of autonomous financial activity**.

Records can show:

- which agent acted
- who granted its authority
- which Mandate governed the action
- which Vault was involved
- which checks ran
- whether human approval was required
- whether the action was allowed, escalated, or denied
- what happened during execution

Onchain events provide the current MVP's traceable history of authority changes, approvals, custody changes, and execution. Assembled **Decision Receipts**, offchain indexing, and behavioural history remain future work that could support external agent reputation, credit, insurance, compliance, and risk systems.

---

# Strategy vs. Authority

Grantline does not decide an agent's strategy.

An agent may determine:

> I want to allocate more capital to Treasury assets.

Grantline asks:

> Are you authorised to do that?

A Guardian may ask:

> Are the required external conditions satisfied?

Preflight may ask:

> Does the resulting state remain within the owner's limits?

This distinction is fundamental.

**Agents decide what they want to do. Grantline governs what they are allowed to do.**

---

# Example

A company places $50,000 into a Treasury Vault and gives its Treasury Agent a Mandate:

- manage up to $50,000
- maximum transaction of $10,000
- keep a configured minimum reserve in the Vault
- Preflight required
- human approval above $7,500
- limited delegation permitted

The Treasury Agent delegates narrower authority to an Execution Agent:

- maximum transaction: $3,000
- approved Treasury assets only
- no borrowing
- no further delegation

The Execution Agent proposes a $3,000 transaction.

Grantline verifies its authority.

Preflight passes.

The transaction executes and an onchain execution record is emitted.

Later, the same agent attempts an action outside its Mandate.

It may still want to execute.

**It cannot.**

Grantline blocks the action before capital moves.

---

# MVP

The hackathon MVP should prove one core idea:

> **An AI agent can operate autonomously with capital without receiving unrestricted authority over it.**

The MVP includes:

### Vault

Assign a defined amount of capital to autonomous activity.

### Mandate

Create enforceable rules governing what an agent can do.

### Delegation

Allow an owner to authorise one agent and that agent to delegate narrower authority to another.

### Owner-approved escalation

Route configured authority or Preflight overruns to the owner for explicit approval before execution.

### Preflight

Check the projected native Vault balance against the configured reserve boundary.

### Enforcement

Every action results in:

**Allow · Escalate · Deny**

The agent cannot bypass the result.

### Revocation

The owner can revoke authority at any time.

### Records

Successful authority and execution changes emit onchain records; assembled receipts and indexed history remain future work.

---

# MVP Demo

The demo should prove both autonomy and control.

### 1. Create authority

A user funds a Vault and creates a Mandate for the Treasury Agent.

The user reviews and approves the policy before the agent can act.

### 2. Delegate authority

The Treasury Agent gives narrower execution authority to another agent.

The Delegation Graph shows where that authority originated.

### 3. Execute an allowed action

The agent proposes a transaction.

Mandate passes.

Preflight passes.

The transaction executes.

An onchain execution record is emitted.

### 4. Block an unauthorised action

The agent attempts something outside its authority.

Grantline denies execution.

### 5. Handle an escalation

A proposed action exceeds a configured boundary that permits escalation.

The owner approves or denies the stored plan, and execution re-evaluates current authority before moving capital.

### 6. Revoke authority

The owner revokes the agent's Mandate.

Any future attempt fails because the authority no longer exists.

---

# Future State

Grantline can evolve from individual agent controls into infrastructure for autonomous organisations.

## Richer Mandates

Support temporary permissions, emergency authority, multiple approvals, reusable policies, expiry, and conditional changes in authority.

## Organizational Delegation

Support complete hierarchies of specialised agents across treasury, payments, procurement, execution, risk, and other functions.

## Guardian Ecosystem

Allow organisations and developers to build specialised Guardian modules.

## Advanced Preflight

Support richer portfolio, liquidity, collateral, and organisation-specific stress scenarios.

## Mandate Templates

Provide reusable authority frameworks for common agent roles.

## Agent Reputation

Use Records as trusted behavioural history for external reputation, credit, insurance, compliance, and risk systems.

## Agent-to-Agent Delegation

Build on current parent/child delegation with safe agent-to-agent hiring and payment flows while preserving the chain back to the original owner.

---

# Long-Term Vision

Today, financial systems ask:

> **Who owns this wallet?**

Autonomous systems increasingly need to ask:

> **Who is this agent acting for, what authority was it given, and under what conditions may it act?**

Grantline aims to become the infrastructure that answers those questions.

Any environment in which an autonomous agent is trusted with money eventually needs:

**authorisation · delegation · limits · conditions · escalation · revocation · accountability**

Grantline provides that layer.

**Agent spending controls**

→ **Conditional financial authority**

→ **Delegated agent organisations**

→ **Authorisation infrastructure for autonomous economic actors**

---

# Positioning

### Brand

**Grantline**

### Category

**Programmable financial authority for AI agents.**

### Product

**Grantline lets people and organisations delegate capital to AI agents under enforceable, conditional, and revocable Mandates.**

### Hackathon / RWA

**Grantline enables AI agents to interact with tokenised real-world assets without giving them unrestricted control of capital. Every action must satisfy delegated authority and any required external or Preflight conditions before execution.**

### Core Principle

> **AI proposes. Mandate authorises.**

### Brand Principle

> **Give agents autonomy. Keep authority bounded.**

### Why Grantline

Wallets solve custody.

AI models solve reasoning.

Financial protocols solve execution.

**Grantline governs the authority between them.**
