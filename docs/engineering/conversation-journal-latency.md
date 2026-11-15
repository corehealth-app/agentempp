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
