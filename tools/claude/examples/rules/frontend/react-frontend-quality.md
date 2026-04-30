# React Frontend Quality (TanStack + Radix/Shadcn + Tailwind stack)

> **Stack scope:** authoring rules for React webapps using TanStack Query / DB, Radix UI / Shadcn primitives, and Tailwind. Many rules (especially Code Quality, React Patterns, Accessibility) translate to other React stacks; the Styling section is Tailwind-specific and the `cn()` utility is a Shadcn convention. Adapt or skip per your stack.

Each rule is checkable in PR review.

## Code Quality & Uniformity

- **Don't duplicate disabled logic in onClick handlers** — When a UI element has a `disabled` prop that prevents interaction (e.g., Radix UI / Shadcn `Button`, `DropdownMenuItem`), do not add a redundant guard in `onClick` (e.g., `onClick={!isDisabled ? handler : undefined}`). The `disabled` prop already prevents the event. Duplicating the condition creates a maintenance trap where conditions can drift. This applies to all Radix-based primitives that suppress interaction when disabled.
- **Filter server-side when the API supports it** — Before adding client-side filtering in a loader or data-fetching layer, check whether the API already accepts the filter parameter. If it does, pass the filter to the API instead of fetching all data and filtering in JavaScript. If the API doesn't support the needed filter shape (e.g., accepts a single value but the UI needs multi-select), note it as tech debt rather than silently working around it — and fix the API when possible.
- **Flag uniformity gaps when touching a file** — When editing a file, scan for inconsistent patterns: the same concept handled differently across sibling components (e.g., one button guards onClick, another doesn't), mixed approaches to the same problem (client-side vs server-side filtering), or dead code left behind after a refactor. Fix what's in scope; flag the rest to the user.
- **Prefer the established pattern over a "safer" one** — When adding new code to a file, follow the patterns already established in that file. If the existing pattern is `disabled={condition}` + plain `onClick={handler}`, don't introduce a new belt-and-suspenders variant. If the existing pattern is genuinely wrong, fix all instances — don't create a mix.
- **Dead schema fields and params are tech debt — remove them** — When a parameter, schema field, or prop is no longer consumed by any caller or downstream code, remove it in the same change. Dead fields mislead future developers into thinking they still have an effect.

## React Patterns

- **Verify all state reset paths** — When a `useState` variable is set in one handler, every other handler that logically exits or replaces that state must also reset it. The bug is reaching a stale / orphaned value because one exit path was missed. Example: a modal that sets `selectedId` on row click must also clear it on Cancel, on the ✕ button, and on click-outside. Check every path, not just the happy path.
- **Effect dependencies — no stale closures, no unnecessary deps** — Every value read inside `useEffect` must appear in the deps array. Omitting a value produces a stale closure that silently reads the initial value on every run. Conversely, deps that don't actually affect the effect's logic should be removed to avoid spurious re-runs. Inline callbacks should not be passed as deps — extract them with `useCallback` at the call site instead.
- **Effect infinite loops — flag unstable deps** — An effect re-runs whenever a dep reference changes. Common traps that cause infinite loops: inline object or array literals (`{ id }`, `[{ id }]`) create a new reference on every render; inline function expressions as deps do the same; setting state unconditionally inside an effect where that state value is also a dep. Stabilise with `useMemo` / `useCallback`, or restructure to remove the dep.
- **`useMemo` / `useCallback` — justify or inline** — Only wrap a value if it is either (a) a genuinely expensive computation that should not re-run on every render, or (b) a referentially stable dep required by a downstream `useEffect` or `React.memo`. If neither applies, inline the value — unnecessary memoisation adds noise and hides the real cost model.

## Storybook

- **New components require a story** — Any new component added to the components tree needs a Storybook story file alongside it. Follow the naming and structure patterns in existing `.stories.tsx` files.
- **New props and variants require a story** — Adding a prop or variant to an existing component is not covered by the existing default story. Add a story (or a new story within the existing file) that exercises the new path. "The component already has a story" is not sufficient if the new behaviour is not reachable from it.

## Accessibility

- **Use semantic HTML for interactive elements** — `<div onClick>` and `<span onClick>` without a `role` and `tabIndex` are inaccessible to keyboard and screen-reader users. Use `<button>` for actions and `<a>` for navigation. When a non-semantic element must be used, add `role`, `tabIndex={0}`, and keyboard handlers (`onKeyDown` for Enter / Space). Shadcn / Radix primitives handle this for standard controls — prefer them over custom implementations.
- **Label every interactive element** — Any interactive element whose purpose is not conveyed by visible text needs an `aria-label` or `aria-labelledby`. Common cases: icon-only buttons, close buttons, search inputs without a visible label.
- **Manage focus in modals and dialogs** — When a modal opens, focus must move inside it (Radix `Dialog` does this automatically). When it closes, focus must return to the element that triggered it. Custom overlay implementations that skip this break keyboard navigation.
- **Keyboard navigation for custom controls** — Custom menus, toggles, and list-selectors must respond to keyboard: Enter / Space to activate, arrow keys to navigate options, Escape to dismiss. Radix primitives include this — prefer them. Flag custom implementations that omit keyboard handling.
- **Don't convey information by colour alone** — Error states, status indicators, and disabled states communicated only through colour are inaccessible to colour-blind users. Pair colour with an icon, label, or pattern.

## Styling

- **Prefer Tailwind classes over inline styles** — `style={{ marginTop: 8 }}` should be `className="mt-2"`. Inline styles bypass Tailwind's constraint system, can't be purged, and make responsive / dark-mode variants harder. Only use `style` for values that are genuinely dynamic and have no Tailwind equivalent (e.g., a CSS variable set from JS).
- **Prefer design tokens over arbitrary Tailwind values** — `text-[14px]` and `bg-[#3b82f6]` bypass the design system. Use the closest Tailwind scale value or a design-system token. If the design calls for a value that doesn't exist in the scale, raise it with the design team rather than hardcoding an arbitrary value.
- **Use `cn()` for conditional class composition** — String concatenation (`className={"foo " + (active ? "bar" : "")}`) is error-prone and produces trailing spaces. Use the `cn()` utility (typically re-exported from `lib/utils`) for all conditional or merged class strings.

## Data Fetching

- **Prefer client-side TanStack over SSR loaders for new endpoints** — Implement new data fetching on the client using TanStack DB / TanStack Query. Avoid adding new React Router `loader` functions whose sole purpose is to serve data that could be fetched client-side. SSR loaders add server load, complicate caching, and tie data lifetime to navigation events. Existing SSR loaders are out of scope — this applies to new work only.
