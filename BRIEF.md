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

Instead of giving an agent unrestricted control of capital, users give it a **Mandate** defining exactly what it is authorized to do and under what conditions.

The agent decides what it wants to do.

**Grantline determines whether it is allowed to do it.**

> **AI proposes. Mandate authorizes.**

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

→ **Required Guardians verify external conditions**

→ **Required Preflight checks test the proposed action**

→ **Allow / Escalate / Deny**

→ **Execute**

→ **Record**

Not every action needs every step.

A simple payment may only require authorization.

A significant treasury action may require additional checks and human approval.

---

# Product Model

Grantline is built around six core concepts.

## Mandates

Define **what an agent is authorized to do**.

A Mandate can specify:

- capital limits
- transaction limits
- permitted actions
- approved assets or products
- liquidity requirements
- human approval thresholds
- required Guardians
- required Preflight conditions
- delegation permissions
- expiry or stop conditions

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

An owner may authorize one agent, which can then delegate a narrower portion of that authority to another.

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

Verify **external conditions relevant to an action**.

Mandates can require particular Guardians before execution.

The first Grantline Guardian is the **RWA Guardian**, designed for tokenized real-world assets.

It may verify conditions such as:

- whether required market information is current
- whether an asset is operating normally
- whether an exceptional condition should prevent autonomous execution

Guardians do not decide whether an investment is good.

They answer specific questions that the owner has chosen to make relevant to authorization.

Over time, other Guardians could cover protocol, oracle, security, compliance, or asset conditions.

---

## Preflight

Tests **what the resulting financial state could look like before execution**.

A proposed action can be evaluated against predefined scenarios such as:

- asset value falling
- liquidity deteriorating
- collateral weakening
- concentration increasing

Preflight does not predict whether an investment will succeed.

It evaluates whether the proposed action stays inside the owner's configured boundaries.

For example:

> Minimum liquidity after stress: 20%.

> Maximum stressed loss: 12%.

> All required checks must pass.

Where useful, several checks may be summarized into a Safety Score, but the underlying conditions remain more important than the score itself.

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

A specific authorization event can create a **Decision Receipt**.

Over time, Records may become valuable inputs for external agent reputation, credit, insurance, compliance, and risk systems.

---

# Strategy vs. Authority

Grantline does not decide an agent's strategy.

An agent may determine:

> I want to allocate more capital to Treasury assets.

Grantline asks:

> Are you authorized to do that?

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
- keep at least 25% liquid
- approved assets only
- RWA Guardian required for RWA transactions
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

The RWA Guardian passes.

Preflight passes.

The transaction executes and a Decision Receipt is created.

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

AI can help translate natural-language instructions into a proposed Mandate.

### Delegation

Allow an owner to authorize one agent and that agent to delegate narrower authority to another.

### RWA Guardian

Run additional external-condition checks for supported RWA transactions.

### Preflight

Test proposed actions against a small set of predefined stress conditions.

### Enforcement

Every action results in:

**Allow · Escalate · Deny**

The agent cannot bypass the result.

### Revocation

The owner can revoke authority at any time.

### Records

Every attempted action leaves behind a clear authorization and execution history.

---

# MVP Demo

The demo should prove both autonomy and control.

### 1. Create authority

A user funds a Vault and describes the Treasury Agent's Mandate in natural language.

Grantline converts it into a visible policy that the user approves.

### 2. Delegate authority

The Treasury Agent gives narrower execution authority to another agent.

The Delegation Graph shows where that authority originated.

### 3. Execute an allowed action

The agent proposes a transaction.

Mandate passes.

Guardian passes.

Preflight passes.

The transaction executes.

A Decision Receipt appears.

### 4. Block an unauthorized action

The agent attempts something outside its authority.

Grantline denies execution.

### 5. React to changing conditions

An external condition causes a required Guardian to fail.

The agent still wants to transact.

Grantline blocks it.

### 6. Revoke authority

The owner revokes the agent's Mandate.

Any future attempt fails because the authority no longer exists.

---

# Future State

Grantline can evolve from individual agent controls into infrastructure for autonomous organizations.

## Richer Mandates

Support temporary permissions, emergency authority, multiple approvals, reusable policies, expiry, and conditional changes in authority.

## Organizational Delegation

Support complete hierarchies of specialized agents across treasury, payments, procurement, execution, risk, and other functions.

## Guardian Ecosystem

Allow organizations and developers to build specialized Guardian modules.

## Advanced Preflight

Support richer portfolio, liquidity, collateral, and organization-specific stress scenarios.

## Mandate Templates

Provide reusable authority frameworks for common agent roles.

## Agent Reputation

Use Records as trusted behavioral history for external reputation, credit, insurance, compliance, and risk systems.

## Agent-to-Agent Delegation

Allow autonomous agents to safely hire, pay, and delegate limited authority to other agents while preserving the chain back to the original owner.

---

# Long-Term Vision

Today, financial systems ask:

> **Who owns this wallet?**

Autonomous systems increasingly need to ask:

> **Who is this agent acting for, what authority was it given, and under what conditions may it act?**

Grantline aims to become the infrastructure that answers those questions.

Any environment in which an autonomous agent is trusted with money eventually needs:

**authorization · delegation · limits · conditions · escalation · revocation · accountability**

Grantline provides that layer.

**Agent spending controls**

→ **Conditional financial authority**

→ **Delegated agent organizations**

→ **Authorization infrastructure for autonomous economic actors**

---

# Positioning

### Brand

**Grantline**

### Category

**Programmable financial authority for AI agents.**

### Product

**Grantline lets people and organizations delegate capital to AI agents under enforceable, conditional, and revocable Mandates.**

### Hackathon / RWA

**Grantline enables AI agents to interact with tokenized real-world assets without giving them unrestricted control of capital. Every action must satisfy delegated authority and any required external or Preflight conditions before execution.**

### Core Principle

> **AI proposes. Mandate authorizes.**

### Brand Principle

> **Give agents autonomy. Keep authority bounded.**

### Why Grantline

Wallets solve custody.

AI models solve reasoning.

Financial protocols solve execution.

**Grantline governs the authority between them.**
