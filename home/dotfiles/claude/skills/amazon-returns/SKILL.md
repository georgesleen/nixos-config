---
name: amazon-returns
description: Drive an amazon.ca return/refund end to end in a real browser (Playwright over a headed Chromium debug port), for George's own account. Covers finding the right order, the self-service return flow, the custom-dropdown and product-support-deflection gotchas, refund-vs-replacement handling, and the confirm-before-submit gate. Invoke when George wants to return an item bought on Amazon.
---

# Amazon.ca returns (browser-driven)

Submits a return/refund on **amazon.ca** for George's own account by driving a
real browser. This is account-affecting automation: **George logs in himself**
(2FA), and you **never click the final "Confirm your return" without explicit
go-ahead**. Marketplace assumed `.ca`; adjust the host if the order is on
another Amazon site.

DigiKey and other retailers are deliberately NOT covered here (different flows,
e.g. DigiKey needs an RMA request). Keep this skill Amazon-specific.

## Why headed Chromium over CDP (not the `playwright` MCP)

The nix `playwright` MCP (`home/dotfiles/claude.nix`) is **headless**, so it
can't do the interactive login/2FA Amazon requires, and a Playwright-launched
browser trips Amazon's bot detection more readily. Instead launch a **normal
headed Chromium with a remote-debugging port** and `connectOverCDP` to it. That
keeps a persistent, human-logged-in session you drive across steps, and looks
like a regular browser.

### Dependencies

- `chromium` (on PATH via the system profile) — the browser.
- `nodejs` + the `playwright` node library — the driver. Node is on PATH.
  Playwright ships in the nix store but ESM `import` ignores `NODE_PATH`, so
  resolve it and symlink a local `node_modules`:

  ```bash
  PW=$(find /nix/store -maxdepth 6 -type d -path '*/node_modules/playwright' 2>/dev/null | head -1)
  ln -sfn "$(dirname "$PW")" ./node_modules   # bare `import 'playwright'` now resolves
  ```

  (Alternatively `nix-shell -p nodejs playwright-test --run '<script>'`.)

## 1. Launch the browser and have George log in

Use a persistent `--user-data-dir` (in the scratchpad) so the login survives
across the many small scripts this flow needs. Do NOT use Playwright's launcher.

```bash
mkdir -p "$SCRATCH/amzn-profile"
export WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
nohup chromium --ozone-platform-hint=auto --remote-debugging-port=9222 \
  --user-data-dir="$SCRATCH/amzn-profile" --no-first-run --no-default-browser-check \
  "https://www.amazon.ca/gp/css/order-history" >/dev/null 2>&1 &
sleep 4
curl -s http://127.0.0.1:9222/json/version | head -c 120   # CDP up?
```

Tell George to **sign in (email/password + 2FA)** in that window. Never touch
credentials. Poll page state to detect when he lands on the orders page:

```js
import { chromium } from 'playwright';
const b = await chromium.connectOverCDP('http://127.0.0.1:9222');
const page = b.contexts()[0].pages().find(p => p.url().includes('amazon.')) || b.contexts()[0].pages()[0];
console.log(page.url(), '|', await page.title());
await b.close(); // detaches CDP; does NOT close the browser
```

All later scripts follow this connect/act/`b.close()` pattern.

## 2. Find the RIGHT order

Go to `https://www.amazon.ca/your-orders/orders?timeFilter=year-YYYY` and
enumerate `.js-order-card`. **Do not trust the first Flipper-ish match.** Real
accounts have traps:

- **Cancelled duplicates** (status "Cancelled", no return controls) — skip.
- **Accessories** (a case, a cable) ordered near the same date — skip.

For each card grab: order date, `ORDER #`, status (Delivered / In transit /
Cancelled), product title, and confirm a return control exists. Only a
**Delivered** order can be returned. Confirm the exact order number and product
before touching anything.

The return control is an anchor **"Return items"** →
`/spr/returns/cart?itemId=<id>&orderId=<order#>`. Navigate straight to that URL.

## 3. Reason + comment (the custom-dropdown gotcha)

On the return cart: the item checkbox is pre-checked. The "Why are you returning
this?" control is an Amazon **`a-native-dropdown`** — the real `<select>` is
`display:none`, so `selectOption` fails ("element is not visible") and clicking
the styled widget hits `aria-hidden` wrappers. **Set the native value and fire
`change`:**

```js
await page.evaluate(() => {
  const s = document.querySelector('select[name*="self_serviceable-questionSet"]');
  s.value = 'RO_CR-DEFECTIVE';                    // "Item defective or doesn't work"
  s.dispatchEvent(new Event('change', {bubbles:true}));
  s.dispatchEvent(new Event('input',  {bubbles:true}));
});
```

Verify the **visible** prompt updated (read the `[id*="native-dropdown-prompt"]`
text) before continuing — that proves the widget state, not just the DOM.

Common reason values: `RO_CR-DEFECTIVE` (defective/doesn't work). Enumerate the
`<option>`s to get others.

A **Comments (required)** textarea appears for defective. Fill it via
`textarea:visible` → `.fill(...)`. Keep it **under 200 chars, factual, no
personal info** (Amazon warns it's shared with external providers). Then click
**Continue**.

## 4. Get past the product-support deflection

The next page ("How can we make it right?") pushes a green **"Get product
support / Troubleshoot on your own"** block first. Click **"Continue to return
options"** to reach the actual resolution choice.

## 5. Resolution: refund vs replacement (enumerate, don't assume)

Enumerate `input[type=radio]` and their labels. **Amazon often offers refund
only** (e.g. "Refund to your Visa ending in XXXX") with no replacement/exchange
option. If George wanted a replacement and only a refund is offered, **stop and
ask** — don't silently take the refund. Select the chosen radio, click the
right-side **Continue**.

## 6. Return method (both usually free)

- **Intelcom Residential Pickup — No Box or Label Needed**: home pickup next
  business day, keep item in original packaging, an adult must be present. Most
  hands-off.
- **Canada Post Drop Off — Box and Label Required**: box it, print a label, drop
  off any time.

Note the **refund total includes tax** (BC 12%: a $285 item refunds $319.20).

## 7. Confirm — the submit gate

The final page's **"CONFIRM YOUR RETURN"** button is the real submission. **Get
George's explicit go-ahead first** (it affects his account/order). After
clicking, the URL becomes `/spr/returns/confirmation/...` and shows the refund
amount and the Initiated → Picked up → Refund issued → Refund credited timeline.
Screenshot it as the record. Refund posts after pickup, then up to ~7 days to
land.

## Tips

- When DOM `innerText` is swamped by the mega-menu, **screenshot** the page
  (`page.screenshot`) and read the image — fastest way to see the real state.
- One concern per script; re-`connectOverCDP` each time. `b.close()` only
  detaches — the headed browser and login persist.
- Kill the browser when done: `pkill -f 'remote-debugging-port=9222'`.

## Follow-on: monitoring

After a return is submitted, George may want a per-return daily monitor (see the
scheduling flow): one routine scoped to that order number, self-disabling when
the refund credits. That needs the Gmail connector attached to the cloud routine
and is separate from this skill.
