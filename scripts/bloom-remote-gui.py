#!/usr/bin/env python3
"""A one-page control panel for the demo remote.

Opens http://localhost:8787 in your browser with buttons that show Bloom's
prompts on the phone: "Did you meet with…?", "How did your time… feel?",
"Name this new location?", notifications and Reset. It finds the phone over Bonjour, the same way bloom-remote.py does,
and lists the friends the phone has (on Celeste, real people from its
contacts), falling back to the comps' names.
Double-click "bloom-remote.command" to start it; close the Terminal window
to stop it.
"""
import importlib.util
import json
import pathlib
import time
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("bloom_remote", HERE / "bloom-remote.py")
remote = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remote)

PORT = 8787
FRIENDS = ["Ishan", "Manitej", "Ray", "Jadden", "Michelle", "Dev", "Theo", "Amara",
           "Nina", "Kenji", "Evan", "Sam"]
PLACES = ["Vienna Cafe, Lafayette", "Eleventh House, Lafayette", "Purdue Memorial Union, West Lafayette",
          "Hicks Library, West Lafayette", "Celery Bog, West Lafayette", "Circle K, West Lafayette",
          "Lafayette Farmers Market, Lafayette", "Climbing gym, Lafayette"]
ACTIVITIES = ["Coffee", "Lunch", "Dinner", "Walk", "Study session", "Bouldering", "Brunch"]

_phone = {"host": None, "found": 0.0}


def phone_host() -> str:
    """The phone's address, looked up again after a minute or on failure."""
    if _phone["host"] and time.time() - _phone["found"] < 60:
        return _phone["host"]
    try:
        host = remote.find_phone(timeout=5)
    except SystemExit as missing:
        raise LookupError(str(missing)) from None
    _phone.update(host=host, found=time.time())
    return host


def send(command: dict) -> tuple[bool, str]:
    try:
        host = phone_host()
    except LookupError as missing:
        return False, str(missing)
    request = urllib.request.Request(
        f"http://{host}/", data=json.dumps(command).encode(),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return True, response.read().decode().strip() or "ok"
    except urllib.error.HTTPError as error:
        return False, error.read().decode().strip()
    except OSError as error:
        _phone["host"] = None
        return False, f"Couldn't reach Bloom at {host}. Is it open on the phone? ({error})"


def options(values):
    return "".join(f"<option>{value}</option>" for value in values)


PAGE = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Bloom Remote</title>
<style>
  :root {{ --paper:#FDFAF5; --ink:#24211D; --muted:#716B62; --fill:#EEE5D8; --good:#18A165; --bad:#A04C46; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--paper); color:var(--ink);
         font:16px/1.45 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }}
  main {{ max-width:520px; margin:0 auto; padding:40px 20px 60px; display:grid; gap:20px; }}
  h1 {{ margin:0; font-size:28px; letter-spacing:-0.02em; }}
  p.lede {{ margin:4px 0 0; color:var(--muted); }}
  section {{ background:var(--fill); border-radius:16px; padding:20px; display:grid; gap:12px; }}
  h2 {{ margin:0; font-size:17px; }}
  h2 + p {{ margin:-6px 0 0; color:var(--muted); font-size:14px; }}
  label {{ display:grid; gap:4px; font-size:13px; color:var(--muted); }}
  select, input {{ font:inherit; color:var(--ink); background:var(--paper); border:0; border-radius:10px;
                  padding:10px 12px; }}
  .row {{ display:grid; grid-template-columns:1fr 1fr; gap:10px; }}
  button {{ font:inherit; font-weight:600; border:0; border-radius:999px; padding:12px 18px; cursor:pointer;
           background:var(--ink); color:var(--paper); }}
  button.quiet {{ background:transparent; color:var(--ink); box-shadow:inset 0 0 0 1px var(--muted); }}
  button:disabled {{ opacity:.5; cursor:default; }}
  button:focus-visible, select:focus-visible, input:focus-visible {{ outline:2px solid var(--ink); outline-offset:2px; }}
  #status {{ min-height:1.4em; font-size:14px; color:var(--muted); }}
  #status.ok {{ color:var(--good); }} #status.no {{ color:var(--bad); }}
  @media (max-width:440px) {{ .row {{ grid-template-columns:1fr; }} }}
</style></head>
<body><main>
  <div><h1>Bloom Remote</h1>
  <p class="lede">Shows Bloom's prompts on the phone, on cue. Keep Bloom open on the phone, on the same Wi-Fi as this Mac.</p></div>

  <section>
    <h2>Did you meet with…?</h2>
    <p>Bloom noticed you were near a friend and asks if it was a meetup.</p>
    <div class="row">
      <label>Friend<select id="s-friend">{options(FRIENDS)}</select></label>
      <label>Where<select id="s-place">{options(PLACES)}</select></label>
    </div>
    <label>When<input id="s-when" value="Just now"></label>
    <button data-kind="sighting">Show “Did you meet…?”</button>
  </section>

  <section>
    <h2>How did it feel?</h2>
    <p>A new hangout lands in Recent and asks how your time together felt.</p>
    <div class="row">
      <label>Friend<select id="r-friend">{options(FRIENDS[1:] + FRIENDS[:1])}</select></label>
      <label>What you did<select id="r-activity">{options(ACTIVITIES)}</select></label>
    </div>
    <label>Where<select id="r-place">{options(PLACES)}</select></label>
    <button data-kind="reflect">Show “How did it feel?”</button>
  </section>

  <section>
    <h2>Name this place?</h2>
    <p>Open a hangout on the phone first. Bloom notices you keep coming back and offers to name the spot.</p>
    <label>Times here this month<input id="n-visits" type="number" min="3" max="30" value="3"></label>
    <button data-kind="name">Show “Name this new location?”</button>
  </section>

  <section>
    <h2>Notification</h2>
    <p>Lands on the phone like a push. Give it a delay and you can lock the phone or leave Bloom first.</p>
    <div class="row">
      <label>Kind<select id="p-kind">
        <option value="nearby">Friend nearby</option>
        <option value="free">Good time to meet</option>
        <option value="reflect">How did it feel?</option>
        <option value="custom">Custom</option>
      </select></label>
      <label>Friend<select id="p-friend">{options(FRIENDS)}</select></label>
    </div>
    <label>Title<input id="p-title"></label>
    <label>Message<input id="p-body"></label>
    <label>When<select id="p-delay">
      <option value="0">Now</option>
      <option value="5" selected>In 5 seconds</option>
      <option value="10">In 10 seconds</option>
      <option value="30">In 30 seconds</option>
      <option value="60">In 1 minute</option>
    </select></label>
    <button data-kind="notify">Send Notification</button>
  </section>

  <section>
    <h2>Start over</h2>
    <p>Puts Home back the way it was when the app opened.</p>
    <button class="quiet" data-kind="reset">Reset Home</button>
  </section>

  <section>
    <h2>Friends</h2>
    <p>The names above come from the phone. Reload them after onboarding or a Reset.</p>
    <button class="quiet" id="reload">Reload Friends</button>
  </section>

  <div id="status" role="status" aria-live="polite"></div>
</main>
<script>
  const status = document.getElementById('status');
  const value = id => document.getElementById(id).value;
  // Fills the notification from its kind and friend; Custom leaves what you typed.
  function fillNotification() {{
    const first = value('p-friend').split(' ')[0];
    const words = {{
      nearby: [`${{first}} is nearby`, 'You’re both near Hicks Library. Say hi?'],
      free: ['A good time to meet', `You and ${{first}} are both free this afternoon.`],
      reflect: [`How was your time with ${{first}}?`, 'Tap to note how it felt.'],
    }}[value('p-kind')];
    if (!words) return;
    document.getElementById('p-title').value = words[0];
    document.getElementById('p-body').value = words[1];
  }}
  document.getElementById('p-kind').addEventListener('change', fillNotification);
  document.getElementById('p-friend').addEventListener('change', fillNotification);
  fillNotification();
  async function loadFriends() {{
    try {{
      const result = await (await fetch('/friends')).json();
      if (!result.ok || !result.friends.length) {{
        status.className = 'no'; status.textContent = result.message || 'The phone has no friends to list yet.';
        return;
      }}
      for (const [id, first] of [['s-friend', 0], ['r-friend', 1], ['p-friend', 0]]) {{
        const select = document.getElementById(id);
        const names = result.friends.slice(first).concat(result.friends.slice(0, first));
        select.replaceChildren(...names.map(name => new Option(name)));
      }}
      fillNotification();
      status.className = 'ok'; status.textContent = `Loaded ${{result.friends.length}} friends from the phone.`;
    }} catch (error) {{
      status.className = 'no'; status.textContent = 'The remote stopped. Double-click “bloom-remote.command” again.';
    }}
  }}
  document.getElementById('reload').addEventListener('click', loadFriends);
  loadFriends();
  document.querySelectorAll('button[data-kind]').forEach(button => button.addEventListener('click', async () => {{
    const kind = button.dataset.kind;
    const command = {{ kind }};
    if (kind === 'sighting') Object.assign(command, {{ friend: value('s-friend'), place: value('s-place'), when: value('s-when') }});
    if (kind === 'notify') Object.assign(command, {{ title: value('p-title'), body: value('p-body'), delay: Number(value('p-delay')) }});
    if (kind === 'name') command.visits = Math.max(3, parseInt(value('n-visits'), 10) || 3);
    if (kind === 'reflect') Object.assign(command, {{ friend: value('r-friend'), activity: value('r-activity'), place: value('r-place') }});
    document.querySelectorAll('button').forEach(b => b.disabled = true);
    status.className = ''; status.textContent = 'Sending…';
    try {{
      const response = await fetch('/send', {{ method: 'POST', headers: {{ 'Content-Type': 'application/json' }}, body: JSON.stringify(command) }});
      const result = await response.json();
      status.className = result.ok ? 'ok' : 'no';
      const later = kind === 'notify' && command.delay > 0;
      status.textContent = !result.ok ? result.message
        : later ? `Sent. It shows on the phone in ${{command.delay}} seconds.` : 'Sent. It’s on the phone now.';
    }} catch (error) {{
      status.className = 'no'; status.textContent = 'The remote stopped. Double-click “bloom-remote.command” again.';
    }} finally {{
      document.querySelectorAll('button').forEach(b => b.disabled = false);
    }}
  }}));
</script>
</body></html>"""


class Panel(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/friends":
            ok, message = send({"kind": "friends"})
            friends = [line for line in message.splitlines() if line.strip()] if ok else []
            self.reply_json({"ok": ok, "friends": friends, "message": "" if ok else message})
            return
        body = PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/send":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            command = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            command = {}
        ok, message = send(command)
        self.reply_json({"ok": ok, "message": message})

    def reply_json(self, value):
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Panel)
    print(f"Bloom Remote is running at http://localhost:{PORT}. Close this window to stop it.")
    webbrowser.open(f"http://localhost:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
