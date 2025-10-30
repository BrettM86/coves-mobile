/**
 * Cloudflare Worker for Coves OAuth
 * Handles client metadata and OAuth callbacks with Android Intent URL support
 */

export default {
  async fetch(request) {
    const url = new URL(request.url);

    // Serve client-metadata.json
    if (url.pathname === '/client-metadata.json') {
      return new Response(JSON.stringify({
        client_id: 'https://lingering-darkness-50a6.brettmay0212.workers.dev/client-metadata.json',
        client_name: 'Coves',
        client_uri: 'https://lingering-darkness-50a6.brettmay0212.workers.dev/client-metadata.json',
        redirect_uris: [
          'https://lingering-darkness-50a6.brettmay0212.workers.dev/oauth/callback',
          'dev.workers.brettmay0212.lingering-darkness-50a6:/oauth/callback'
        ],
        scope: 'atproto transition:generic',
        grant_types: ['authorization_code', 'refresh_token'],
        response_types: ['code'],
        application_type: 'native',
        token_endpoint_auth_method: 'none',
        dpop_bound_access_tokens: true
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Handle OAuth callback - redirect to app
    if (url.pathname === '/oauth/callback') {
      const params = url.search; // Preserve query params (e.g., ?state=xxx&code=xxx)
      const userAgent = request.headers.get('User-Agent') || '';
      const isAndroid = /Android/i.test(userAgent);

      // Build the appropriate deep link based on platform
      let deepLink;
      if (isAndroid) {
        // Android: Use Intent URL format (works reliably on all browsers)
        // Format: intent://path?query#Intent;scheme=SCHEME;package=PACKAGE;end
        const pathAndQuery = `/oauth/callback${params}`;
        deepLink = `intent:/${pathAndQuery}#Intent;scheme=dev.workers.brettmay0212.lingering-darkness-50a6;package=social.coves;end`;
      } else {
        // iOS: Use standard custom scheme
        deepLink = `dev.workers.brettmay0212.lingering-darkness-50a6:/oauth/callback${params}`;
      }

      return new Response(`
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Authorization Successful</title>
          <style>
            body {
              font-family: system-ui, -apple-system, sans-serif;
              display: flex;
              align-items: center;
              justify-content: center;
              min-height: 100vh;
              margin: 0;
              background: #f5f5f5;
            }
            .container {
              text-align: center;
              padding: 2rem;
              background: white;
              border-radius: 8px;
              box-shadow: 0 2px 8px rgba(0,0,0,0.1);
              max-width: 400px;
            }
            .success { color: #22c55e; font-size: 3rem; margin-bottom: 1rem; }
            h1 { margin: 0 0 0.5rem; color: #1f2937; font-size: 1.5rem; }
            p { color: #6b7280; margin: 0.5rem 0; }
            a {
              display: inline-block;
              margin-top: 1rem;
              padding: 0.75rem 1.5rem;
              background: #3b82f6;
              color: white;
              text-decoration: none;
              border-radius: 6px;
              font-weight: 500;
            }
            a:hover {
              background: #2563eb;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="success">\u2713</div>
            <h1>Authorization Successful!</h1>
            <p id="status">Returning to Coves...</p>
            <a href="${deepLink}" id="manualLink">Open Coves</a>
          </div>
          <script>
            // Attempt automatic redirect
            window.location.href = "${deepLink}";

            // Update status after 2 seconds if redirect didn't work
            setTimeout(() => {
              document.getElementById('status').textContent = 'Click the button above to continue';
            }, 2000);
          </script>
        </body>
        </html>
      `, {
        headers: { 'Content-Type': 'text/html' }
      });
    }

    return new Response('Not found', { status: 404 });
  }
};
