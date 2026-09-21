---
title: Hello, world
date: 2026-09-21
slug: hello-world
description: The first post, and a tour of what a post can contain.
published: true
---

## What this is

A post is a Markdown file in `content/`. The block at the top is the front matter: `title`, `date`, `slug` and `description` are required. `slug` becomes the URL, `posts/hello-world/` here.

Run `scripts/publish.sh` (or `scripts/publish.ps1` on Windows) and this file turns into a page, the landing page, feed and sitemap get updated, and a commit is proposed.

## Things a post can hold

Code blocks keep their whitespace:

```sh
$ scripts/publish.sh
publish hello-world
```

Lists, quotes and tables:

- One
- Two
  - Nested

> A quote.

| Key | Value |
|-----|-------|
| `published` | `false` keeps a draft off the site |

Images are picked up automatically. The one below was written as an ordinary Markdown image pointing at a URL on another site. On publish the script downloaded it into `assets/posts/hello-world/` as `01.png` and rewrote the link to point there. A local path such as `![alt](shot.png)`, relative to `content/`, is copied the same way.

![RunFridge](../assets/posts/hello-world/01.png)

Raw HTML passes through, so `<canvas>`, `<script>` and `<style>` tags work when a post needs them. The square below is drawn by a few lines of script at the end of this file.

<canvas id="demo" width="320" height="120" aria-label="A square bouncing left and right"></canvas>

<script>
(function () {
    var canvas = document.getElementById('demo'), c = canvas.getContext('2d');
    var x = 0, dx = 2, size = 40;
    function frame() {
        c.clearRect(0, 0, canvas.width, canvas.height);
        c.fillStyle = '#1a1a1a';
        c.fillRect(x, (canvas.height - size) / 2, size, size);
        x += dx;
        if (x <= 0 || x + size >= canvas.width) dx = -dx;
        requestAnimationFrame(frame);
    }
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) { x = (canvas.width - size) / 2; frame = function () {}; c.fillStyle = '#1a1a1a'; c.fillRect(x, (canvas.height - size) / 2, size, size); }
    else frame();
})();
</script>
