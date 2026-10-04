// Spend the loopback client's global AppView rate-limit budget (100 requests
// per 60-second window, keyed by client IP) through the Caddy proxy the app
// itself uses, so the app's next request gets the AppView's real 429
// plain-text rejection. Sets output.rateLimited only when the budget of a
// window that opened moments ago is spent, which leaves the flow almost the
// whole window to tap before the budget refills.
//
// The AppView limiter (coves internal/api/middleware/ratelimit.go) uses a fixed
// window that opens at the first request after the previous window expired. A
// rejected request neither counts nor moves the window. Stopping at the first
// 429 alone can leave only a moment of that window, so the script runs in
// three phases:
//   1. Spend until the first 429: the current window is exhausted.
//   2. Poll until the first non-429: that poll opened a fresh window.
//   3. Spend until 429 again: the fresh window is exhausted about a second in.
// Phase 2 waits out the rest of the current window, which is up to 60 seconds.
// A window reset in the middle of phase 1 can push it to about 200 requests.
var spendRequestLimit = 250;
var resetWaitLimitMs = 70000;
var resetPollIntervalMs = 200;
var lastStatus = null;

function isRateLimited() {
  lastStatus = http.get(PROXY_URL + '/xrpc/_health').status;
  return lastStatus === 429;
}

function spendUntilRateLimited() {
  for (var attempt = 0; attempt < spendRequestLimit; attempt++) {
    if (isRateLimited()) {
      return true;
    }
  }
  return false;
}

function waitForWindowReset() {
  var deadline = Date.now() + resetWaitLimitMs;
  while (Date.now() < deadline) {
    if (!isRateLimited()) {
      return true;
    }
    var nextPoll = Date.now() + resetPollIntervalMs;
    while (Date.now() < nextPoll) {
      // Busy-wait: Maestro's script engine has no sleep or setTimeout.
    }
  }
  return false;
}

output.rateLimited = false;
if (!spendUntilRateLimited()) {
  console.log('exhaust_appview_rate_limit: phase 1 got no 429 in ' +
      spendRequestLimit + ' requests; last status ' + lastStatus);
} else if (!waitForWindowReset()) {
  console.log('exhaust_appview_rate_limit: phase 2 saw no window reset in ' +
      resetWaitLimitMs + ' ms; last status ' + lastStatus);
} else if (!spendUntilRateLimited()) {
  console.log('exhaust_appview_rate_limit: phase 3 got no 429 in ' +
      spendRequestLimit + ' requests; last status ' + lastStatus);
} else {
  output.rateLimited = true;
}
