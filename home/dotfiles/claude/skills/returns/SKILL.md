---
name: returns
description: Drive an online return/refund end to end in a real browser (Playwright over a headed Chromium debug port), for George's own accounts. Covers the shared browser-driving mechanics plus per-retailer flows for amazon.ca (self-service return) and DigiKey (guest RMA request with a defect questionnaire). Invoke when George wants to return something he bought online.
---

# Online returns (browser-driven)

Submits a return/refund on George's own accounts by driving a real browser.
This is **account-affecting automation**, so two rules hold everywhere:

1. **George authenticates himself.** Never touch credentials, never type a
   password, never accept a 2FA prompt on his behalf.
2. **Never click the final submit without explicit go-ahead.** Filling and
   navigating is fine; filing the return is his call.

Per-retailer flows live at the bottom. Read the shared mechanics first: they
are the same regardless of who you are returning to.

## Why headed Chromium over CDP (not the `playwright` MCP)

The nix `playwright` MCP (`home/dotfiles/claude.nix`) is **headless**, so it
cannot do the interactive login/2FA these sites require, and a
Playwright-*launched* browser trips bot detection more readily. Amazon flags it;
DigiKey sits behind Cloudflare and serves a "Just a moment..." interstitial.

Instead launch a **normal headed Chromium with a remote-debugging port** and
`connectOverCDP` to it. That keeps a persistent, human-logged-in session you
drive across steps, and looks like a regular browser. Empirically this walks
straight through Cloudflare where the Playwright launcher does not.

### Dependencies

- `chromium` (on PATH via the system profile), the browser.
- `nodejs` + the `playwright` node library, the driver. Node is on PATH.
  Playwright ships in the nix store but ESM `import` ignores `NODE_PATH`, so
  resolve it and symlink a local `node_modules`:

  ```bash
  PW=$(find /nix/store -maxdepth 6 -type d -path '*/node_modules/playwright' 2>/dev/null | head -1)
  ln -sfn "$(dirname "$PW")" ./node_modules   # bare `import 'playwright'` now resolves
  ```

  (`npm install playwright` in the scratchpad also works and gives CommonJS
  `require`. Either is fine; do not download browsers, use system chromium.)
- `imagemagick` for photo prep (crop, rotate, HEIC conversion) when a retailer
  demands product photos.

## 1. Launch the browser and have George sign in

Use a persistent `--user-data-dir` (in the scratchpad) so the login survives
across the many small scripts this flow needs. Do NOT use Playwright's launcher.

```bash
mkdir -p "$SCRATCH/ret-profile"
export WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0
nohup chromium --ozone-platform-hint=auto --remote-debugging-port=9222 \
  --user-data-dir="$SCRATCH/ret-profile" --no-first-run --no-default-browser-check \
  "<retailer start URL>" >/dev/null 2>&1 &
sleep 4
curl -s http://127.0.0.1:9222/json/version | head -c 120   # CDP up?
```

Then connect, act, detach:

```js
const { chromium } = require('playwright');
const b = await chromium.connectOverCDP('http://127.0.0.1:9222');
const page = b.contexts()[0].pages().find(p => p.url().includes('<host>'))
          || b.contexts()[0].pages()[0];
console.log(page.url(), '|', await page.title());
await b.close(); // detaches CDP; does NOT close the browser
```

All later scripts follow this connect/act/`b.close()` pattern.

## 2. Setting values on controlled inputs

Both sites use widgets where a plain `fill`/`selectOption` fails: the real
control is hidden, or a framework owns the value. The general fix is to set the
value through the **native setter** and fire `input` + `change` so the
framework notices:

```js
await page.evaluate(([sel, v]) => {
  const el = document.querySelector(sel);
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype
                                          : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
  el.dispatchEvent(new Event('input',  { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
}, [selector, value]);
```

For `<select>`, set `.value` to the option's value and dispatch `change`.
Always **verify the visible widget updated**, not just the DOM node.

## 3. Picking the right row (a real footgun)

When a page lists several order lines, do not select by "the element containing
the part number": that matches broad ancestors and can tick a **"Select Entire
Order"** checkbox, silently returning items George wants to keep. Walk up from
each checkbox to the **tightest** container that mentions the target item and
tick that one, then read back every checkbox state to confirm exactly one line
is selected.

## 4. Confirm, then submit

Screenshot the finished form and give George a field-by-field summary. Get his
explicit go-ahead before the final button. After submitting, screenshot the
confirmation (RMA number / refund amount / timeline) as the record.

## Tips

- When DOM `innerText` is swamped by nav chrome, **screenshot** the page and
  read the image. Fastest way to see real state.
- One concern per script; re-`connectOverCDP` each time. `b.close()` only
  detaches, so the headed browser and login persist.
- Kill the browser when done: `pkill -f 'remote-debugging-port=9222'`.
- Order details (invoice numbers, part numbers, prices, addresses) are usually
  in George's Gmail. Search `from:digikey`, `from:amazon`, etc. rather than
  asking him to dig them out.

---

# Retailer: amazon.ca

Self-service return, no RMA. Marketplace assumed `.ca`; adjust the host for
another Amazon site.

## Find the RIGHT order

Go to `https://www.amazon.ca/your-orders/orders?timeFilter=year-YYYY` and
enumerate `.js-order-card`. **Do not trust the first plausible match.** Real
accounts have traps:

- **Cancelled duplicates** (status "Cancelled", no return controls), skip.
- **Accessories** (a case, a cable) ordered near the same date, skip.

For each card grab: order date, `ORDER #`, status (Delivered / In transit /
Cancelled), product title, and confirm a return control exists. Only a
**Delivered** order can be returned. Confirm the exact order number and product
before touching anything.

The return control is an anchor **"Return items"** to
`/spr/returns/cart?itemId=<id>&orderId=<order#>`. Navigate straight there.

## Reason + comment (the custom-dropdown gotcha)

On the return cart the item checkbox is pre-checked. "Why are you returning
this?" is an Amazon **`a-native-dropdown`**: the real `<select>` is
`display:none`, so `selectOption` fails ("element is not visible") and clicking
the styled widget hits `aria-hidden` wrappers. Set the native value and fire
`change`:

```js
const s = document.querySelector('select[name*="self_serviceable-questionSet"]');
s.value = 'RO_CR-DEFECTIVE';                    // "Item defective or doesn't work"
s.dispatchEvent(new Event('change', {bubbles:true}));
```

Verify the **visible** prompt updated (read `[id*="native-dropdown-prompt"]`)
before continuing. Common reason value: `RO_CR-DEFECTIVE`. Enumerate the
`<option>`s for others.

A **Comments (required)** textarea appears for defective. Fill via
`textarea:visible`. Keep it **under 200 chars, factual, no personal info**
(Amazon warns it is shared with external providers). Then click **Continue**.

## Product-support deflection

The next page ("How can we make it right?") pushes a green **"Get product
support / Troubleshoot on your own"** block first. Click **"Continue to return
options"** to reach the actual resolution choice.

## Resolution: refund vs replacement (enumerate, do not assume)

Enumerate `input[type=radio]` and their labels. **Amazon often offers refund
only** (e.g. "Refund to your Visa ending in XXXX") with no replacement option.
If George wanted a replacement and only a refund is offered, **stop and ask**.

## Return method (both usually free)

- **Intelcom Residential Pickup, No Box or Label Needed**: home pickup next
  business day, keep item in original packaging, an adult must be present.
- **Canada Post Drop Off, Box and Label Required**: box it, print a label.

The **refund total includes tax** (BC 12%: a $285 item refunds $319.20).

## Submit

The final page's **"CONFIRM YOUR RETURN"** button is the real submission. After
clicking, the URL becomes `/spr/returns/confirmation/...` and shows the refund
amount and the Initiated / Picked up / Refund issued / Refund credited
timeline. Refund posts after pickup, then up to ~7 days to land.

---

# Retailer: DigiKey

**Not** a self-service return: DigiKey issues an **RMA** after reviewing a
defect questionnaire, and will not accept product shipped without one. Window
is **60 days** from invoice date (30 days for Marketplace-vendor items),
original packaging, unused and like-new.

## Guest path: no login required

Faster than the account route and avoids the sign-in entirely. Start at
`https://www.digikey.ca/mydigikey/returns` (use `.com` for a US order), scroll
to "Request a return or resolve an order Issue", and fill:

- `input[name="Email"]`, the address on the order
- `input[name="InvoiceId"]`, the **invoice** number (not the salesorder number)
- `select[name="Country"]`, e.g. CANADA
- `input[name="PostCode"]`, which **only appears after a country is selected**;
  use the postal code of the **shipping** address

Click **Continue** to land on `/MyDigiKey/ReturnsCenter/Guest?...` with the
invoice loaded.

The invoice number is in the shipment email, subject "DigiKey has shipped a
package for invoice NNNNNNNNN". The order confirmation email ("Thank you for
your DigiKey order!") lists every line item with DigiKey and manufacturer part
numbers, quantities and prices, plus both addresses.

## Select the line item

Each line is `Details[N]`, indexed in invoice order. Tick only the target row
(see the "tightest container" footgun above; the naive selector grabs **Select
Entire Order**). Then set the reason:

```js
const s = document.querySelector('select[name="Details[0].ReturnReason"]');
```

Options include "Product is defective", "Product is damaged", "Ordered wrong
product", "Received wrong product", "No longer need product", "Product does not
meet my requirements".

## Resolution radios

`input[name="Details[N].ResolutionChoice"]`:

- **value 1**, "Refund to your original payment method" (the default)
- **value 2**, "Ship replacement product(s)"
- **value 4**, "Evaluation"

**Avoid Evaluation unless George asks for it**: that is the RFE path the form
warns can take up to 6 weeks, with possible manufacturer test fees.

## The defect questionnaire (all required)

Textareas, all `Details[N].*`:

| Field | Content |
|---|---|
| `Issue` | The defect, with the isolation testing that proves it |
| `Application` | What the part was being used for |
| `MarkingsDescription` | Part markings: lead with what is **printed on the label**, then any firmware-reported identifier |
| `Detection` | When noticed (DOA, testing, field) |
| `FailureRate` | e.g. "100%, 1 of 1, fully reproducible" |
| `Damage` | Visible physical damage, and whether packaging was damaged |

Plus `Details[N].TechnicalContactDetails.{Name,Role,Phone,Email}`. **Phone is
`type=number`**, so pass digits only.

**Every textarea caps at 1000 characters.** Over that, submit silently fails:
the page does not navigate and a single "Message cannot exceed 1000 characters"
appears, with no indication of which field. Measure before submitting:

```js
[...document.querySelectorAll('textarea[name^="Details[0]"]')]
  .filter(t => t.value.length > 1000).map(t => t.name + '=' + t.value.length)
```

Write the `Issue` field like a bug report: symptom, then the swap tests that
isolate the fault, then the conclusion. A well-evidenced defect claim is the
difference between an approved RMA and a request for more information.

Beware of asserting facts you cannot see (physical damage, printed serials).
Fill the likely answer, then explicitly flag it for George to verify.

## Photos (four, all required)

`input[type=file]` named `Details[N].Image{Markings,Labels,Features,TestResults}`.
`setInputFiles` works directly on them.

- **Markings**: tight crop on the printed codes
- **Labels**: the product label, readable
- **Features**: the unit overall, showing whatever is relevant to the fault
- **TestResults**: evidence the part is faulty

**Generate the test-results image** rather than photographing a screen: write a
clean HTML summary, then screenshot it headless to PNG.

```js
const p = await b.newPage({ viewport: {width:1080, height:600}, deviceScaleFactor: 2 });
await p.goto('file://' + process.cwd() + '/test_results.html');
const h = await p.evaluate(() => document.body.scrollHeight);
await p.setViewportSize({ width: 1080, height: Math.ceil(h) + 20 });
await p.screenshot({ path: 'test_results.png' });
```

### Getting product photos off a phone

A laptop webcam is usually the wrong tool: **fixed-focus webcams (e.g. Brio 101,
no `focus_absolute` in `v4l2-ctl --list-ctrls`) physically cannot do this**.
Close enough to fill the frame is out of focus; far enough to focus leaves the
label too few pixels to read. Check for focus controls before trying.

iPhone over USB is also a trap here: usbmuxd may see the device yet fail with
`Could not connect to lockdownd ... lockdown error -8` and `idevice_id` may not
list it at all, even after tapping Trust. Do not sink time into it. Have George
upload to Google Drive (searchable via the Drive connector) or email it, then
have him download it locally; **do not** pull multi-MB images through a
connector as base64, it floods the context.

iPhone photos arrive as HEIC. Convert and derive both crops from one shot:

```bash
magick IMG_XXXX.HEIC -auto-orient -quality 92 photo.jpg
magick photo.jpg -rotate 270 -quality 88 part_label.jpg          # whole label upright
magick photo.jpg -crop 830x830+1270+1080 +repage -rotate 270 part_markings.jpg
```

Check the rotation by viewing the result; getting it 180 degrees out is easy.
Downscale big uploads (`-resize 2400x`) in case the form caps file size.

## Submit

The control is a plain **Submit** button at the bottom of the form. Success
lands on `/MyDigiKey/Returns/GuestSuccess` with "Your request has been sent to
Customer Service."

**No RMA number is issued at submit time** for a defect claim: DigiKey reviews
the questionnaire and contacts George. Nothing may be shipped back until that
RMA arrives. Tell him this explicitly, since it differs from Amazon where the
return is authorised immediately.

---

# Adding another retailer

Keep the shared mechanics above untouched and add a section with: the entry URL
and whether login is needed, how to identify the right order, the selector names
for reason/resolution, any hidden-widget gotchas, and where the real submit
button is. Note anything that would silently return the wrong item.
