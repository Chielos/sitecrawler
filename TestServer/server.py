#!/usr/bin/env python3
"""
IndexPilot QA Test Server
Serves a mini-website for integration testing the crawler.

Usage:
    python3 TestServer/server.py

Then start a crawl against http://localhost:8765/

Includes:
- Normal pages with various SEO scenarios
- Pages with issues (missing titles, noindex, etc.)
- Redirect chains
- 404 and 500 pages
- robots.txt
- sitemap.xml
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import os
import time
import json

PAGES = {
    "/": """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>IndexPilot Test — Home</title>
<meta name="description" content="The homepage for IndexPilot crawler integration tests.">
<link rel="canonical" href="http://localhost:8765/">
</head>
<body>
<h1>IndexPilot Test Site</h1>
<p>This is a local test site for IndexPilot crawler integration testing.
It contains pages with various SEO characteristics so you can verify the crawler
correctly detects issues and extracts metadata.</p>
<h2>Navigation</h2>
<ul>
  <li><a href="/good-page/">Good Page</a> — well optimised, no issues</li>
  <li><a href="/missing-title/">Missing Title</a> — no title tag</li>
  <li><a href="/thin-content/">Thin Content</a> — very few words</li>
  <li><a href="/noindex/">Noindex Page</a> — noindex meta tag</li>
  <li><a href="/redirect-chain/">Redirect Chain Start</a> — 3 hops</li>
  <li><a href="/deep/1/2/3/4/5/6/7/8/">Deep Page</a> — 8 hops away</li>
  <li><a href="/broken-link/">Broken Link Target</a> — returns 404</li>
  <li><a href="/server-error/">Server Error</a> — returns 500</li>
</ul>
</body>
</html>""",

    "/good-page/": """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>A Well Optimised Page — IndexPilot Test</title>
<meta name="description" content="This page has a proper title, description, H1, and sufficient content for SEO testing purposes.">
<link rel="canonical" href="http://localhost:8765/good-page/">
<link rel="alternate" hreflang="en" href="http://localhost:8765/good-page/">
<script type="application/ld+json">{"@context":"https://schema.org","@type":"Article","name":"A Well Optimised Page"}</script>
</head>
<body>
<h1>A Well Optimised Page</h1>
<p>This page represents a well-structured web page with all the SEO elements in place.
It has a descriptive title, a meta description, a single H1, and sufficient body
content to avoid thin content penalties.</p>
<h2>Subheading One</h2>
<p>Content under subheading one. Lorem ipsum dolor sit amet, consectetur adipiscing elit.
Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
<h2>Subheading Two</h2>
<p>Content under subheading two. Ut enim ad minim veniam, quis nostrud exercitation ullamco
laboris nisi ut aliquip ex ea commodo consequat.</p>
<p><a href="/">Back to home</a> | <a href="/about/">About</a></p>
</body>
</html>""",

    "/missing-title/": """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<!-- Intentionally missing <title> tag -->
<meta name="description" content="This page is missing a title tag for testing.">
<link rel="canonical" href="http://localhost:8765/missing-title/">
</head>
<body>
<h1>Page With Missing Title</h1>
<p>This page deliberately has no title tag. IndexPilot should flag this with
a 'missing_title' error issue.</p>
<p><a href="/">Home</a></p>
</body>
</html>""",

    "/thin-content/": """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Thin Content Page</title>
<meta name="description" content="Only a few words.">
<link rel="canonical" href="http://localhost:8765/thin-content/">
</head>
<body>
<h1>Short Page</h1>
<p>Not much here.</p>
</body>
</html>""",

    "/noindex/": """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Noindex Page</title>
<meta name="robots" content="noindex, nofollow">
<link rel="canonical" href="http://localhost:8765/noindex/">
</head>
<body>
<h1>This Page Should Not Be Indexed</h1>
<p>The noindex meta tag tells search engines not to index this page.</p>
</body>
</html>""",

    "/about/": """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>About — IndexPilot Test</title>
<meta name="description" content="About the IndexPilot test site.">
</head>
<body>
<h1>About</h1>
<p>About page content. This is a supporting page.</p>
<p><a href="/">Home</a></p>
</body>
</html>""",
}

REDIRECTS = {
    "/redirect-chain/": "/redirect-step-2/",
    "/redirect-step-2/": "/redirect-step-3/",
    "/redirect-step-3/": "/good-page/",
    "/old-url/": "/good-page/",
}

# Deep path — just return the same page at each depth
def deep_page(path):
    depth = path.count("/") - 1
    return f"""<!DOCTYPE html>
<html><head><title>Deep Page Level {depth}</title></head>
<body><h1>Level {depth}</h1>
<a href="/">Home</a></body></html>"""


class Handler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        print(f"  {self.command} {self.path} → {args[1] if len(args) > 1 else '?'}")

    def do_GET(self):
        path = self.path.split("?")[0]  # strip query string

        # Robots
        if path == "/robots.txt":
            body = b"""User-agent: *
Disallow: /private/
Disallow: /admin/
Sitemap: http://localhost:8765/sitemap.xml
"""
            self.send_header_response(200, "text/plain", body)
            return

        # Sitemap
        if path == "/sitemap.xml":
            body = b"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>http://localhost:8765/</loc></url>
  <url><loc>http://localhost:8765/good-page/</loc></url>
  <url><loc>http://localhost:8765/about/</loc></url>
  <url><loc>http://localhost:8765/noindex/</loc></url>
</urlset>"""
            self.send_header_response(200, "application/xml", body)
            return

        # Redirects
        if path in REDIRECTS:
            self.send_response(301)
            self.send_header("Location", REDIRECTS[path])
            self.end_headers()
            return

        # 404
        if path == "/broken-link/":
            body = b"<html><body><h1>404 Not Found</h1></body></html>"
            self.send_header_response(404, "text/html", body)
            return

        # 500
        if path == "/server-error/":
            body = b"<html><body><h1>500 Internal Server Error</h1></body></html>"
            self.send_header_response(500, "text/html", body)
            return

        # Deep pages
        if path.startswith("/deep/"):
            body = deep_page(path).encode()
            self.send_header_response(200, "text/html", body)
            return

        # Known pages
        if path in PAGES:
            body = PAGES[path].encode()
            self.send_header_response(200, "text/html", body)
            return

        # Default 404
        body = b"<html><body><h1>404 Not Found</h1></body></html>"
        self.send_header_response(404, "text/html", body)

    def send_header_response(self, code, content_type, body):
        self.send_response(code)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    PORT = 8765
    server = HTTPServer(("localhost", PORT), Handler)
    print(f"IndexPilot QA Test Server listening on http://localhost:{PORT}/")
    print("Start a crawl in IndexPilot targeting: http://localhost:8765/")
    print("Press Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
