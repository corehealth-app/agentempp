# Conversation journal response latency

The native history transport has a 30-second request deadline. A connected QA
read on 15 November 2026, against server source `b68386ed`, returned a ten-entry
V3 page in 31,175 ms; the V1 read took 1,961 ms. Four entries were workouts. The
food registration and Nutrition facts were intact, but cold Flow could not expose
the saved item editor. This is one measured round, not a percentile benchmark.

V3 enriched each historical workout sequentially. Every enrichment runs the
existing typed workout reader, including its independent Auth, patient,
non-admin and current-clinical observations. The outer RPC and final page guards
also remain required. Raising the deadline, dropping feedback, returning partial
history or falling back to another journal protocol would hide the failure.

The request now overlaps at most four independent, read-only workout
enrichments. Each retains those original checks; no observation is cached or
fabricated. Results stay private until every enrichment finishes and the final
current-policy/clock fence passes. The original SQL page still determines event
order, pagination and byte limits. A scope failure refuses the entire response
and retains the service's existing closed state. No registration, reward,
provider inference, command admission or background retry is introduced.

Regression uses held SDK reconciliation reads through the actual typed service:
the sequential implementation cannot overlap the independent reads; the new
path does, under the four-read bound. Mid-flight admin revocation must reject the
whole page. Existing actual SQL golden packets continue to exercise completed
workouts, nullable energy and all six feedback sections.

Local tests and compilation do not qualify the hosted response time. Before
release, measure the real authenticated candidate and reopen the existing meal
on the native app, then verify direct editing and Day/Week parity. Preserve the
original registration instead of resending it to repeat the check.

A local-only diagnostic build then confirmed `mobile_api_timeout` in the native
history request after the first hosted repair. Actual stored V1/V3 packets still
decoded successfully. The replacement response remained close to 30 seconds:
28,635 ms followed by 25,866 ms in direct HTTP observations. Those two HTTP reads
do not establish a reliable native cold-open margin.

V3 now uses its own lane with parallel **read-only mapping** checks. Each
mapping first awaits fresh verified Auth and checks the original Auth identity. Its existing
non-admin and patient reads then overlap; both must finish successfully before
clinical state is read or authority is returned. Every pre/post mapping, typed
patient/admin decoder, owner/epoch comparison and serial monotonic clinical lane
remains. The protected shared scope source stays byte-exact; other callers keep
their original serial mapping. There is no cached Auth result, removed observation, longer client deadline or partial response.

The actual V3 service regression holds Auth, admin and patient boundaries: the
old code cannot enter the patient read while admin is held; the new code does,
only after Auth resolves. Neighboring cases retain sticky refusal on admin
transition, caller-scope changes and backwards clinical time in the journal lane
and unchanged shared lane. Hosted latency and native cold re-opening still require independent qualification.


A separate native cold-navigation failure happened before the journal started.
Switching to Nutrition while Flow was opening cancelled the originating view
`.task`. The shell coordinator forwarded that cancellation into its owned
factory, reported `unavailable`, and the returning root only automatically loads
from `idle`. The saved correction and historical HTTP/native decoder were valid.

Opening now belongs to the authenticated shell across transient tab navigation.
A cancelled view cannot start a new factory, but cancelling an existing waiter
does not cancel the shared opening. A returning view joins that same operation.
Explicit owner withdrawal still cancels the owned work, invalidates the bound
model synchronously and joins retirement; late publication remains forbidden by
the original owner/generation, authority and coordinator work-identity fences.
Genuine opening failures retain the existing explicit Retry action.

A real source/URLSession barrier regression failed on the former implementation.
It holds the opening request, cancels the view waiter, joins a fresh returning
waiter and requires one read-only request and one ready model. Neighboring tests
retain cancelled-entry admission, account withdrawal, retry and owned cleanup.

## Native read-only restoration and automatic history refresh

A mounted Flow root previously observed the neutral intake model's generic busy
flag. Its session restoration toggled that flag even though it only read state.
The busy-to-idle callback started a journal request before question origins had
finished restoring; the root's final explicit history load then replaced it.
A controlled URLSession test with the actual mounted view and an origins barrier
observed one premature request and two total journal requests.

The neutral model now emits a transient completion ID for user work, including
failed sends whose server outcome may require a fresh read. Read-only restoration
does not emit that signal. The view observes this ID for automatic history loads;
its busy flag, progress, dispatch, outbox, and deferred foreground refresh retain
their behavior. Explicit retry, pagination and root refresh still use their
existing fresh-read paths.

The same mounted-view regression now observes zero requests before releasing the
origins barrier and one afterwards. Native regression coverage also exercises
successful sends, lost responses, media restoration, origin cancellation and
owner withdrawal, read retries, historical commentary and shell ownership.
This is controlled native evidence, not a measured improvement in hosted latency,
a physical-device result or a distributed-build qualification.

Preserve native test results at an explicit task-owned `-resultBundlePath`.
The observed Xcode Logs/Test retention kept only the latest two runs and removed
the initial RED result bundle during later runs. Its observed failure and full
log remain evidence; a missing result bundle must not be reported as preserved.
The GREEN and regression bundles were copied to the qualification directory.


## Fresh observation waves

A later connected round still exposed intermittent cold-history refusal. One
instrumented native read completed in 24,434 ms with a single request, and the
same ten-entry HTTP page took 24,810 ms; other cold native rounds displayed
unavailable history. Their exact errors were not observed, so they are not
retrospectively classified as timeouts. Native reliability remains a release gate.

The journal lane previously queued a complete Auth/mapping/clinical observation
for every nested read-only caller, including concurrent enrichment operations.
It now admits concurrent callers to one **new** observation only until its
clinical capture starts. Every admitted caller precedes the actual snapshot and
waits for both its fresh pre- and post-capture verified Auth, non-admin and patient
mapping checks. Admission closes before invoking capture. A caller arriving during
capture or its post-checks queues a subsequent real observation; a completed
result is never reused. These batches are request-local and convey no write or
historical authority. Shared protected command scopes remain unchanged.

Barrier regressions distinguish calls before capture, calls during capture and
calls after completion. Concurrent post-capture admin revocation refuses every
waiting caller, and existing backwards-clock/owner/epoch/sticky-refusal tests
remain. The same native request deadline, four-workout bound, complete feedback,
immutable page order and final fresh policy fence remain. Test results establish
these semantics; they do not establish hosted timing or native reliability.
